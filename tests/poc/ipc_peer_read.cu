// Transfer PoC — Phase 0 gate: CUDA IPC cross-process peer read.
//
// The earlier NCCL check proved GPU-to-GPU *messaging* works in this container.
// The peer-copy experiment needs something stronger and distinct: one process
// must read another process's device memory *directly*, with no send/recv and
// no staging — a strided cudaMemcpy2D whose source is a neighbor rank's buffer.
//
// One rank per GPU means one process per GPU, so a raw device pointer from a
// neighbor is meaningless across the process boundary. CUDA IPC bridges it:
// the owner calls cudaIpcGetMemHandle on its allocation, ships the ~64-byte
// handle over host MPI, and the neighbor calls cudaIpcOpenMemHandle to obtain a
// pointer valid in its own address space (lazily enabling peer access from its
// current device). This is a separate driver/container capability from the P2P
// that NCCL exercises — some container or driver configs disable it. This test
// decides whether the whole peer-copy approach is possible on this host.
//
// Rank 0 allocates and fills a buffer and exports its IPC handle. Rank 1 opens
// the handle and pulls the bytes over NVLink with cudaMemcpy (device-to-device,
// reading rank 0's memory), then verifies them. It also reports
// cudaDeviceCanAccessPeer for the rank-1 -> rank-0 device pair.
//
// Build (inside the container):
//   nvcc -ccbin mpicxx -O2 ipc_peer_read.cu -o ipc_peer_read
// Run (inside the container, 2 ranks, ideally on two distinct GPUs):
//   mpirun -np 2 --oversubscribe ./ipc_peer_read
//
// PASS => cross-process peer read works here; the peer-copy halo is feasible.
// FAIL on cudaIpcOpenMemHandle => the container blocks CUDA IPC; STOP (the plan
//   does not proceed to Phase 1 on this host).

#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <vector>
#include <mpi.h>
#include <cuda_runtime.h>

#define CUDA_CHECK(call)                                                      \
    do {                                                                      \
        cudaError_t _e = (call);                                              \
        if (_e != cudaSuccess) {                                              \
            std::fprintf(stderr, "CUDA error %s at %s:%d\n",                  \
                         cudaGetErrorString(_e), __FILE__, __LINE__);         \
            MPI_Abort(MPI_COMM_WORLD, 1);                                     \
        }                                                                     \
    } while (0)

int main(int argc, char** argv) {
    MPI_Init(&argc, &argv);

    int world_rank = 0, world_size = 0;
    MPI_Comm_rank(MPI_COMM_WORLD, &world_rank);
    MPI_Comm_size(MPI_COMM_WORLD, &world_size);

    if (world_size != 2) {
        if (world_rank == 0) {
            std::fprintf(stderr, "This test needs exactly 2 ranks (got %d).\n",
                         world_size);
        }
        MPI_Finalize();
        return 2;
    }

    // Bind each rank to its own GPU, same scheme as the model overlay. With two
    // ranks this puts rank 0 on device 0 and rank 1 on device 1, so the read
    // crosses devices over NVLink — the case the halo copy actually uses.
    int device_count = 0;
    CUDA_CHECK(cudaGetDeviceCount(&device_count));
    int local_rank = 0;
    if (const char* e = std::getenv("OMPI_COMM_WORLD_LOCAL_RANK")) {
        local_rank = std::atoi(e);
    }
    const int device = device_count > 0 ? local_rank % device_count : 0;
    CUDA_CHECK(cudaSetDevice(device));

    // Report peer capability for the rank-1 -> rank-0 device pair. Exchange the
    // bound device ordinals first; canAccessPeer is only meaningful across two
    // distinct devices.
    int peer_device = -1;
    MPI_Sendrecv(&device, 1, MPI_INT, world_rank ^ 1, 0,
                 &peer_device, 1, MPI_INT, world_rank ^ 1, 0,
                 MPI_COMM_WORLD, MPI_STATUS_IGNORE);
    if (world_rank == 1) {
        int can_peer = 0;
        if (peer_device != device) {
            CUDA_CHECK(cudaDeviceCanAccessPeer(&can_peer, device, peer_device));
        }
        std::printf("PEER: rank 1 device %d -> rank 0 device %d canAccessPeer=%d%s\n",
                    device, peer_device, can_peer,
                    peer_device == device ? " (same device)" : "");
    }

    const int n = 1 << 20;                 // 1M doubles = 8 MiB payload
    const double sentinel = 3.14159265358979;

    int local_ok = 1;

    if (world_rank == 0) {
        // Owner: allocate, fill, export the IPC handle to rank 1.
        double* d_buf = nullptr;
        CUDA_CHECK(cudaMalloc(&d_buf, n * sizeof(double)));
        std::vector<double> h(n);
        for (int i = 0; i < n; ++i) h[i] = sentinel + i;
        CUDA_CHECK(cudaMemcpy(d_buf, h.data(), n * sizeof(double),
                              cudaMemcpyHostToDevice));

        cudaIpcMemHandle_t handle;
        CUDA_CHECK(cudaIpcGetMemHandle(&handle, d_buf));
        MPI_Send(&handle, sizeof(handle), MPI_BYTE, 1, 1, MPI_COMM_WORLD);

        // Wait until rank 1 has finished reading before freeing the buffer.
        MPI_Barrier(MPI_COMM_WORLD);
        CUDA_CHECK(cudaFree(d_buf));
    } else {
        // Neighbor: import the handle, pull the bytes over NVLink, verify.
        cudaIpcMemHandle_t handle;
        MPI_Recv(&handle, sizeof(handle), MPI_BYTE, 0, 1, MPI_COMM_WORLD,
                 MPI_STATUS_IGNORE);

        void* peer_ptr = nullptr;
        cudaError_t open_err =
            cudaIpcOpenMemHandle(&peer_ptr, handle, cudaIpcMemLazyEnablePeerAccess);
        if (open_err != cudaSuccess) {
            std::fprintf(stderr,
                         "FAIL: cudaIpcOpenMemHandle: %s. The container blocks "
                         "CUDA IPC; the peer-copy halo is infeasible on this "
                         "host. STOP.\n",
                         cudaGetErrorString(open_err));
            local_ok = 0;
            // Let rank 0 out of its barrier so both processes exit cleanly.
            MPI_Barrier(MPI_COMM_WORLD);
            MPI_Bcast(&local_ok, 1, MPI_INT, 1, MPI_COMM_WORLD);
            MPI_Finalize();
            return 1;
        }

        double* d_local = nullptr;
        CUDA_CHECK(cudaMalloc(&d_local, n * sizeof(double)));
        // The actual test: read rank 0's device memory directly into ours.
        CUDA_CHECK(cudaMemcpy(d_local, peer_ptr, n * sizeof(double),
                              cudaMemcpyDeviceToDevice));
        CUDA_CHECK(cudaDeviceSynchronize());

        std::vector<double> h(n);
        CUDA_CHECK(cudaMemcpy(h.data(), d_local, n * sizeof(double),
                              cudaMemcpyDeviceToHost));
        for (int i = 0; i < n; ++i) {
            if (std::fabs(h[i] - (sentinel + i)) > 1e-9) {
                std::fprintf(stderr,
                             "FAIL: element %d = %.12f, expected %.12f\n",
                             i, h[i], sentinel + i);
                local_ok = 0;
                break;
            }
        }
        if (local_ok) {
            std::printf("PASS: rank 1 read %d doubles from rank 0's GPU directly "
                        "via CUDA IPC peer copy (device %d <- %d)\n",
                        n, device, peer_device);
        }

        CUDA_CHECK(cudaIpcCloseMemHandle(peer_ptr));
        CUDA_CHECK(cudaFree(d_local));
        MPI_Barrier(MPI_COMM_WORLD);
    }

    MPI_Bcast(&local_ok, 1, MPI_INT, 1, MPI_COMM_WORLD);
    MPI_Finalize();
    return local_ok ? 0 : 1;
}
