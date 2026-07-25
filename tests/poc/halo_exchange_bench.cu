// Transfer PoC — Addition 2: NCCL nearest-neighbor halo-exchange benchmark.
//
// This is the standalone benchmark that answers the PoC question directly:
// how much data does the FV neighbor exchange move between GPUs, does it stay
// on the GPUs, and does its share shrink as resolution rises? It replicates
// the real model's decomposition (see fv_advection.F90):
//
//   * the grid is split in Y only, one slab per rank (layout = 1 x npes);
//   * each rank owns the full width nx and ny/npes interior rows, nz levels;
//   * halo = 2 rows on the north and south edges (yhalo=2);
//   * fields are 8-byte reals (-r8);
//   * no wrap in Y (the poles reflect, they do not exchange), so rank 0 has
//     only a north neighbor and rank npes-1 only a south neighbor.
//
// One "exchange" = send the 2 top interior rows to the north neighbor and the
// 2 bottom interior rows to the south neighbor, and receive their rows into
// this rank's halos. The rows are strided in memory (layout matches Fortran
// (nx, y, nz) column-major), so they are packed into contiguous buffers with
// cudaMemcpy2D, moved GPU-to-GPU by NCCL, and unpacked — exactly the work a
// real device-resident halo exchange must do. All buffers stay on the GPU;
// nothing is staged through the host.
//
// Build (inside the container):
//   nvcc -ccbin mpicxx -O2 halo_exchange_bench.cu -o halo_exchange_bench -lnccl
// Run (inside the container, npes ranks):
//   mpirun -np <npes> --oversubscribe ./halo_exchange_bench <nx> <ny> <nz> [halo] [iters]
//
// Baseline (T85L25, 16 ranks):  ... 256 128 25
// Doubled  (T170L25, 16 ranks): ... 512 256 25
// Quad     (T340L25, 16 ranks): ... 1024 512 25

#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <vector>
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
    int rank = 0, npes = 0;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &npes);

    if (argc < 4) {
        if (rank == 0)
            std::fprintf(stderr,
                "usage: %s <nx> <ny_global> <nz> [halo=2] [iters=200]\n", argv[0]);
        MPI_Finalize();
        return 2;
    }
    const int nx   = std::atoi(argv[1]);
    const int nyg  = std::atoi(argv[2]);
    const int nz   = std::atoi(argv[3]);
    const int halo = argc > 4 ? std::atoi(argv[4]) : 2;
    const int iters= argc > 5 ? std::atoi(argv[5]) : 200;

    if (nyg % npes != 0) {
        if (rank == 0)
            std::fprintf(stderr, "ny_global (%d) must divide evenly by ranks (%d)\n",
                         nyg, npes);
        MPI_Finalize();
        return 2;
    }
    const int nyl  = nyg / npes;           // interior rows this rank owns
    const int ytot = nyl + 2 * halo;       // interior + north/south halos

    // Bind each rank to its own GPU (same scheme as the model overlay).
    int device_count = 0;
    CUDA_CHECK(cudaGetDeviceCount(&device_count));
    int local_rank = 0;
    if (const char* e = std::getenv("OMPI_COMM_WORLD_LOCAL_RANK")) local_rank = std::atoi(e);
    const int device = device_count > 0 ? local_rank % device_count : 0;
    CUDA_CHECK(cudaSetDevice(device));

    // Bootstrap NCCL over MPI (host bytes only).
    ncclUniqueId id;
    if (rank == 0) NCCL_CHECK(ncclGetUniqueId(&id));
    MPI_Bcast(&id, sizeof(id), MPI_BYTE, 0, MPI_COMM_WORLD);
    ncclComm_t comm;
    NCCL_CHECK(ncclCommInitRank(&comm, npes, id, rank));

    cudaStream_t stream;
    CUDA_CHECK(cudaStreamCreate(&stream));

    // Neighbors along the Y chain; -1 means "no neighbor" (a pole).
    const int north = (rank + 1 < npes) ? rank + 1 : -1;
    const int south = (rank - 1 >= 0)   ? rank - 1 : -1;

    // Field laid out like Fortran (nx, ytot, nz): index = i + nx*j + nx*ytot*k.
    // A block of `halo` consecutive y-rows at fixed k is a contiguous run of
    // nx*halo doubles; across k it is strided by nx*ytot. cudaMemcpy2D moves
    // that with width = nx*halo doubles, height = nz.
    const size_t field_elems = (size_t)nx * ytot * nz;
    const size_t face_elems  = (size_t)nx * halo * nz;   // one face, all levels
    const size_t dsize = sizeof(double);

    double *d_field = nullptr;
    double *d_send_n = nullptr, *d_send_s = nullptr;     // packed outgoing faces
    double *d_recv_n = nullptr, *d_recv_s = nullptr;     // packed incoming faces
    CUDA_CHECK(cudaMalloc(&d_field,  field_elems * dsize));
    CUDA_CHECK(cudaMalloc(&d_send_n, face_elems  * dsize));
    CUDA_CHECK(cudaMalloc(&d_send_s, face_elems  * dsize));
    CUDA_CHECK(cudaMalloc(&d_recv_n, face_elems  * dsize));
    CUDA_CHECK(cudaMalloc(&d_recv_s, face_elems  * dsize));
    CUDA_CHECK(cudaMemset(d_field, 0, field_elems * dsize));

    // Row offsets (in y) of the interior rows we send and the halos we fill.
    const int j_send_north = halo + nyl - halo;   // top `halo` interior rows
    const int j_send_south = halo;                // bottom `halo` interior rows
    const int j_recv_north = halo + nyl;          // north halo region
    const int j_recv_south = 0;                   // south halo region

    // cudaMemcpy2D geometry for a `halo`-row face across all nz levels.
    const size_t row_bytes   = (size_t)nx * halo * dsize;  // contiguous per level
    const size_t field_pitch = (size_t)nx * ytot * dsize;  // stride between levels
    auto pack = [&](double* dst, int j0) {
        CUDA_CHECK(cudaMemcpy2DAsync(
            dst, row_bytes,
            d_field + (size_t)nx * j0, field_pitch,
            row_bytes, nz, cudaMemcpyDeviceToDevice, stream));
    };
    auto unpack = [&](const double* src, int j0) {
        CUDA_CHECK(cudaMemcpy2DAsync(
            d_field + (size_t)nx * j0, field_pitch,
            src, row_bytes,
            row_bytes, nz, cudaMemcpyDeviceToDevice, stream));
    };

    auto one_exchange = [&]() {
        if (north >= 0) pack(d_send_n, j_send_north);
        if (south >= 0) pack(d_send_s, j_send_south);
        NCCL_CHECK(ncclGroupStart());
        if (north >= 0) {
            NCCL_CHECK(ncclSend(d_send_n, face_elems, ncclDouble, north, comm, stream));
            NCCL_CHECK(ncclRecv(d_recv_n, face_elems, ncclDouble, north, comm, stream));
        }
        if (south >= 0) {
            NCCL_CHECK(ncclSend(d_send_s, face_elems, ncclDouble, south, comm, stream));
            NCCL_CHECK(ncclRecv(d_recv_s, face_elems, ncclDouble, south, comm, stream));
        }
        NCCL_CHECK(ncclGroupEnd());
        if (north >= 0) unpack(d_recv_n, j_recv_north);
        if (south >= 0) unpack(d_recv_s, j_recv_south);
    };

    // Warm up (NCCL sets up its channels on first use).
    for (int w = 0; w < 20; ++w) one_exchange();
    CUDA_CHECK(cudaStreamSynchronize(stream));

    cudaEvent_t t0, t1;
    CUDA_CHECK(cudaEventCreate(&t0));
    CUDA_CHECK(cudaEventCreate(&t1));
    CUDA_CHECK(cudaEventRecord(t0, stream));
    for (int it = 0; it < iters; ++it) one_exchange();
    CUDA_CHECK(cudaEventRecord(t1, stream));
    CUDA_CHECK(cudaStreamSynchronize(stream));

    float ms_total = 0.0f;
    CUDA_CHECK(cudaEventElapsedTime(&ms_total, t0, t1));
    const double ms_per = ms_total / iters;

    // Bytes this rank moves per exchange (sent + received on live neighbors).
    const int live = (north >= 0 ? 1 : 0) + (south >= 0 ? 1 : 0);
    const double bytes_per = (double)live * 2.0 * (double)face_elems * dsize; // send+recv
    const double gbps = ms_per > 0 ? (bytes_per / (ms_per * 1e-3)) / 1e9 : 0.0;

    // On-device interior work this rank holds, for the edge-vs-volume ratio.
    const double interior_elems = (double)nx * nyl * nz;
    const double face_out_elems = (double)live * (double)face_elems; // rows sent out
    const double halo_to_volume = face_out_elems / interior_elems;

    // Reduce to rank 0 for a single clean summary line per resolution.
    double max_ms = ms_per, sum_bytes = bytes_per;
    MPI_Reduce(rank == 0 ? MPI_IN_PLACE : &max_ms,  &max_ms,  1, MPI_DOUBLE, MPI_MAX, 0, MPI_COMM_WORLD);
    MPI_Reduce(rank == 0 ? MPI_IN_PLACE : &sum_bytes,&sum_bytes,1, MPI_DOUBLE, MPI_SUM, 0, MPI_COMM_WORLD);

    if (rank == 0) {
        std::printf("HALO_BENCH nx=%d ny=%d nz=%d ranks=%d halo=%d ny_local=%d\n",
                    nx, nyg, nz, npes, halo, nyl);
        std::printf("  per-exchange time (slowest rank): %.4f ms\n", max_ms);
        std::printf("  per-exchange bytes across all GPUs: %.3f MiB\n", sum_bytes / (1024.0*1024.0));
        std::printf("  interior-rank bandwidth: %.1f GB/s\n", gbps);
        std::printf("  halo-out / interior-volume ratio: %.4f  (2*halo/ny_local = %.4f)\n",
                    halo_to_volume, 2.0 * halo / (double)nyl);
    }

    CUDA_CHECK(cudaEventDestroy(t0));
    CUDA_CHECK(cudaEventDestroy(t1));
    cudaFree(d_field); cudaFree(d_send_n); cudaFree(d_send_s);
    cudaFree(d_recv_n); cudaFree(d_recv_s);
    CUDA_CHECK(cudaStreamDestroy(stream));
    ncclCommDestroy(comm);
    MPI_Finalize();
    return 0;
}
