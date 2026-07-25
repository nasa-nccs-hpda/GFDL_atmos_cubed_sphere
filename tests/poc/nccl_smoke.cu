// Transfer PoC — NCCL GPU-to-GPU smoke test.
//
// The container's MPI is not GPU-aware (UCX has no cuda_copy/cuda_ipc
// transports), so a device pointer handed to MPI_Recv crashes. NCCL moves
// data GPU-to-GPU directly (over NVLink here) and does not need GPU-aware
// MPI. This test confirms that path works before Addition 2 rewires the
// model's halo exchange onto it.
//
// MPI is used ONLY to bootstrap NCCL: rank 0 makes a unique id, broadcasts
// it (host bytes, so the non-GPU-aware MPI is fine), and every rank joins
// the NCCL communicator with it. The actual payload moves via ncclSend/Recv.
//
// Build (inside the container):
//   nvcc -ccbin mpicxx -O2 nccl_smoke.cu -o nccl_smoke -lnccl
// Run (inside the container, 2 ranks):
//   mpirun -np 2 --oversubscribe ./nccl_smoke
//
// PASS => GPU-to-GPU transfer works in this container; Addition 2 = NCCL.

#include <cstdio>
#include <cstdlib>
#include <vector>
#include <cmath>
#include <mpi.h>
#include <cuda_runtime.h>
#include <nccl.h>

#define CUDA_CHECK(call)                                                      \
    do {                                                                      \
        cudaError_t _e = (call);                                              \
        if (_e != cudaSuccess) {                                              \
            std::fprintf(stderr, "CUDA error %s at %s:%d\n",                  \
                         cudaGetErrorString(_e), __FILE__, __LINE__);         \
            MPI_Abort(MPI_COMM_WORLD, 1);                                     \
        }                                                                     \
    } while (0)

#define NCCL_CHECK(call)                                                      \
    do {                                                                      \
        ncclResult_t _r = (call);                                             \
        if (_r != ncclSuccess) {                                              \
            std::fprintf(stderr, "NCCL error %s at %s:%d\n",                  \
                         ncclGetErrorString(_r), __FILE__, __LINE__);         \
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

    // Bind each rank to its own GPU, same scheme as the model overlay.
    int device_count = 0;
    CUDA_CHECK(cudaGetDeviceCount(&device_count));
    int local_rank = 0;
    if (const char* e = std::getenv("OMPI_COMM_WORLD_LOCAL_RANK")) {
        local_rank = std::atoi(e);
    }
    const int device = device_count > 0 ? local_rank % device_count : 0;
    CUDA_CHECK(cudaSetDevice(device));

    // Bootstrap NCCL: rank 0 makes the id, everyone joins with it.
    ncclUniqueId id;
    if (world_rank == 0) NCCL_CHECK(ncclGetUniqueId(&id));
    MPI_Bcast(&id, sizeof(id), MPI_BYTE, 0, MPI_COMM_WORLD);

    ncclComm_t comm;
    NCCL_CHECK(ncclCommInitRank(&comm, world_size, id, world_rank));

    cudaStream_t stream;
    CUDA_CHECK(cudaStreamCreate(&stream));

    const int n = 1 << 20;                 // 1M doubles = 8 MiB payload
    double* d_buf = nullptr;
    CUDA_CHECK(cudaMalloc(&d_buf, n * sizeof(double)));

    const double sentinel = 3.14159265358979;
    std::vector<double> h(n);

    if (world_rank == 0) {
        for (int i = 0; i < n; ++i) h[i] = sentinel + i;
        CUDA_CHECK(cudaMemcpy(d_buf, h.data(), n * sizeof(double),
                              cudaMemcpyHostToDevice));
    } else {
        CUDA_CHECK(cudaMemset(d_buf, 0, n * sizeof(double)));
    }

    // The actual test: NCCL point-to-point, rank 0 -> rank 1, GPU-to-GPU.
    NCCL_CHECK(ncclGroupStart());
    if (world_rank == 0) {
        NCCL_CHECK(ncclSend(d_buf, n, ncclDouble, 1, comm, stream));
    } else {
        NCCL_CHECK(ncclRecv(d_buf, n, ncclDouble, 0, comm, stream));
    }
    NCCL_CHECK(ncclGroupEnd());
    CUDA_CHECK(cudaStreamSynchronize(stream));

    int local_ok = 1;
    if (world_rank == 1) {
        CUDA_CHECK(cudaMemcpy(h.data(), d_buf, n * sizeof(double),
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
            std::printf("PASS: rank 1 received %d doubles GPU-to-GPU via NCCL "
                        "(device %d)\n", n, device);
        }
    }

    CUDA_CHECK(cudaFree(d_buf));
    CUDA_CHECK(cudaStreamDestroy(stream));
    ncclCommDestroy(comm);
    MPI_Bcast(&local_ok, 1, MPI_INT, 1, MPI_COMM_WORLD);
    MPI_Finalize();
    return local_ok ? 0 : 1;
}
