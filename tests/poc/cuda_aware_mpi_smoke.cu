// Transfer PoC — CUDA-aware MPI smoke test.
//
// Question: can MPI move a buffer directly from one GPU's memory to another
// GPU's memory on this node, without staging through host? The container's
// OpenMPI reports opal_built_with_cuda_support=false, but its UCX component
// lists a cuda_ipc transport, so the UCX path may still be CUDA-aware. This
// test answers it definitively: two ranks, one GPU each, exchange a device
// buffer via MPI_Sendrecv on device pointers, and verify the payload.
//
// Build (inside the container):
//   nvcc -ccbin mpicxx -O2 cuda_aware_mpi_smoke.cu -o cuda_aware_mpi_smoke
// Run (inside the container, 2 ranks):
//   mpirun -np 2 --mca pml ucx ./cuda_aware_mpi_smoke
//
// PASS  => device pointers work through MPI; Addition 2 = pass device buffers.
// crash/crash/FAIL => not CUDA-aware on this path; fall back to NCCL or staging.

#include <cstdio>
#include <cstdlib>
#include <vector>
#include <cmath>
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

    // Bind each rank to its own GPU, same scheme as the model overlay.
    int device_count = 0;
    CUDA_CHECK(cudaGetDeviceCount(&device_count));
    int local_rank = 0;
    if (const char* e = std::getenv("OMPI_COMM_WORLD_LOCAL_RANK")) {
        local_rank = std::atoi(e);
    }
    const int device = device_count > 0 ? local_rank % device_count : 0;
    CUDA_CHECK(cudaSetDevice(device));

    // Report whether the MPI runtime advertises CUDA awareness (informational).
#if defined(MPIX_CUDA_AWARE_SUPPORT) && MPIX_CUDA_AWARE_SUPPORT
    if (world_rank == 0) {
        std::printf("MPIX_Query_cuda_support() = %d\n", MPIX_Query_cuda_support());
    }
#else
    if (world_rank == 0) {
        std::printf("MPIX_CUDA_AWARE_SUPPORT macro not defined at compile time\n");
    }
#endif

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

    // The actual test: MPI_Sendrecv on DEVICE pointers, rank 0 -> rank 1.
    MPI_Status status;
    if (world_rank == 0) {
        MPI_Send(d_buf, n, MPI_DOUBLE, 1, 100, MPI_COMM_WORLD);
    } else {
        MPI_Recv(d_buf, n, MPI_DOUBLE, 0, 100, MPI_COMM_WORLD, &status);
    }

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
            std::printf("PASS: rank 1 received %d doubles device-to-device via MPI "
                        "(device %d)\n", n, device);
        }
    }

    CUDA_CHECK(cudaFree(d_buf));
    MPI_Bcast(&local_ok, 1, MPI_INT, 1, MPI_COMM_WORLD);
    MPI_Finalize();
    return local_ok ? 0 : 1;
}
