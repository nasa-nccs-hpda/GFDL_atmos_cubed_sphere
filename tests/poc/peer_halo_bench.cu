// Transfer PoC — Phase 1: direct NVLink peer-copy halo benchmark.
//
// The NCCL halo benchmark (halo_exchange_bench.cu) packs the two edge rows into
// a staging buffer, ships them with ncclSend/ncclRecv, and unpacks them into the
// halo. On a single NVLinked node that machinery is the cost, not the ~200-330KB
// strip. This benchmark answers whether the exchange can instead be *one strided
// DMA* that reads the neighbor's interior edge rows straight into this rank's
// halo rows -- no packing, no send/recv, no unpacking, no staging buffer.
//
// It uses the same decomposition as halo_exchange_bench.cu / the model:
//   * split in Y only, one slab per rank (layout = 1 x npes);
//   * each rank owns full width nx, nyl = ny/npes interior rows, nz levels;
//   * halo = 2 rows north and south; no wrap in Y (rank 0 has only a north
//     neighbor, rank npes-1 only a south neighbor);
//   * field laid out like Fortran (nx, ytot, nz), ytot = nyl + 2*halo,
//     index = i + nx*j + nx*ytot*k.
//
// Because one rank per GPU means one process per GPU, a neighbor's device
// pointer is reached with CUDA IPC: each rank exports its field's base handle
// once (the grid is fixed for a run), neighbors import it (which enables peer
// access), and the exchange is a device-to-device strided copy
//   cudaMemcpy2DAsync(my_halo_band, pitch, neighbor_edge, pitch,
//                     nx*halo*8, nz, cudaMemcpyDefault, stream)
// that travels over NVLink and lands directly in my halo. Ordering that
// NCCL got implicitly from send/recv is supplied by interprocess CUDA events:
// each rank records "my edge is current"; a puller waits on its neighbor's event
// before reading. A per-iteration MPI_Barrier variant is also timed, to show the
// ordering cost rather than assume it.
//
// Pull geometry (matches the model's halo semantics):
//   my south halo rows [0, halo)          <- south neighbor interior rows [nyl, nyl+halo)
//   my north halo rows [halo+nyl, +halo)  <- north neighbor interior rows [halo, 2*halo)
// After one exchange every row satisfies cell(i,j,k) = encode(i, rank*nyl+j-halo, k),
// except the pole halos (no neighbor), which is the byte-verify invariant.
//
// Build (inside the container):
//   nvcc -ccbin mpicxx -O2 peer_halo_bench.cu -o peer_halo_bench
// Run (inside the container, npes ranks, one GPU each):
//   mpirun -np <npes> ./peer_halo_bench <nx> <ny> <nz> [halo=2] [iters=200]
//
// Compare head-to-head with halo_exchange_bench.cu at the same nx ny nz.

#include <cstdio>
#include <cstdlib>
#include <cstdint>
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

// Injective, exact-in-double encoding of a global cell coordinate.
static inline double encode(int i, long gj, int k, int nx, int nz) {
    return (double)((gj * (long)nx + i) * (long)nz + k);
}

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
    const int nx    = std::atoi(argv[1]);
    const int nyg   = std::atoi(argv[2]);
    const int nz    = std::atoi(argv[3]);
    const int halo  = argc > 4 ? std::atoi(argv[4]) : 2;
    const int iters = argc > 5 ? std::atoi(argv[5]) : 200;

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

    cudaStream_t stream;
    CUDA_CHECK(cudaStreamCreate(&stream));

    // Neighbors along the Y chain; -1 means "no neighbor" (a pole).
    const int north = (rank + 1 < npes) ? rank + 1 : -1;
    const int south = (rank - 1 >= 0)   ? rank - 1 : -1;

    const size_t field_elems = (size_t)nx * ytot * nz;
    const size_t face_elems  = (size_t)nx * halo * nz;
    const size_t dsize = sizeof(double);

    double* d_field = nullptr;
    CUDA_CHECK(cudaMalloc(&d_field, field_elems * dsize));

    // Fill the interior with the global-coordinate encoding and the halos with a
    // sentinel, so a correct pull overwrites the sentinel with the neighbor's
    // interior values and a wrong geometry is caught.
    std::vector<double> h(field_elems, -1.0);
    for (int k = 0; k < nz; ++k)
        for (int j = halo; j < halo + nyl; ++j) {
            const long gj = (long)rank * nyl + (j - halo);
            for (int i = 0; i < nx; ++i)
                h[(size_t)i + (size_t)nx * j + (size_t)nx * ytot * k] =
                    encode(i, gj, k, nx, nz);
        }
    CUDA_CHECK(cudaMemcpy(d_field, h.data(), field_elems * dsize, cudaMemcpyHostToDevice));

    // --- one-time CUDA IPC setup: share this field's base pointer and an
    // interprocess "edge current" event with each neighbor. -----------------
    cudaIpcMemHandle_t my_mem;
    CUDA_CHECK(cudaIpcGetMemHandle(&my_mem, d_field));

    cudaEvent_t my_event;
    CUDA_CHECK(cudaEventCreateWithFlags(
        &my_event, cudaEventInterprocess | cudaEventDisableTiming));
    cudaIpcEventHandle_t my_evt_h;
    CUDA_CHECK(cudaIpcGetEventHandle(&my_evt_h, my_event));

    // Per-neighbor imported resources.
    double* peer_field[2] = {nullptr, nullptr}; // [0]=south, [1]=north
    int     peer_device[2] = {-1, -1};
    cudaEvent_t peer_event[2] = {nullptr, nullptr};

    auto exchange_with = [&](int nbr, int slot) {
        if (nbr < 0) return;
        cudaIpcMemHandle_t nbr_mem;
        cudaIpcEventHandle_t nbr_evt_h;
        int nbr_dev = -1;
        MPI_Sendrecv(&my_mem, sizeof(my_mem), MPI_BYTE, nbr, 10,
                     &nbr_mem, sizeof(nbr_mem), MPI_BYTE, nbr, 10,
                     MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        MPI_Sendrecv(&my_evt_h, sizeof(my_evt_h), MPI_BYTE, nbr, 11,
                     &nbr_evt_h, sizeof(nbr_evt_h), MPI_BYTE, nbr, 11,
                     MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        MPI_Sendrecv(&device, 1, MPI_INT, nbr, 12,
                     &nbr_dev, 1, MPI_INT, nbr, 12,
                     MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        void* p = nullptr;
        CUDA_CHECK(cudaIpcOpenMemHandle(&p, nbr_mem, cudaIpcMemLazyEnablePeerAccess));
        peer_field[slot] = (double*)p;
        peer_device[slot] = nbr_dev;
        CUDA_CHECK(cudaIpcOpenEventHandle(&peer_event[slot], nbr_evt_h));
    };
    exchange_with(south, 0);
    exchange_with(north, 1);

    // cudaMemcpy2DPeer geometry: a `halo`-row band, contiguous nx*halo doubles
    // per level, strided by nx*ytot between levels, nz levels tall.
    const size_t row_bytes = (size_t)nx * halo * dsize;
    const size_t pitch     = (size_t)nx * ytot * dsize;
    const int j_recv_south = 0;                 // my south halo
    const int j_recv_north = halo + nyl;        // my north halo
    const int j_src_south  = nyl;               // south neighbor's top interior
    const int j_src_north  = halo;              // north neighbor's bottom interior

    // Peer access is already enabled by cudaIpcOpenMemHandle(LazyEnablePeerAccess),
    // so a device-to-device 2D copy from the imported neighbor pointer travels
    // directly over NVLink under unified addressing (there is no 2D "Peer"
    // variant in the runtime API; the 1D/3D Peer calls are the only ones, and
    // the model's own edge copies use cudaMemcpy2D the same way).
    auto pull_south = [&]() {
        CUDA_CHECK(cudaMemcpy2DAsync(
            d_field + (size_t)nx * j_recv_south, pitch,
            peer_field[0] + (size_t)nx * j_src_south, pitch,
            row_bytes, nz, cudaMemcpyDefault, stream));
    };
    auto pull_north = [&]() {
        CUDA_CHECK(cudaMemcpy2DAsync(
            d_field + (size_t)nx * j_recv_north, pitch,
            peer_field[1] + (size_t)nx * j_src_north, pitch,
            row_bytes, nz, cudaMemcpyDefault, stream));
    };

    // Event-ordered exchange: publish that my edge is current, wait for the
    // neighbor's edge to be current, then pull. For a static field this always
    // verifies; the waits are here so the timed cost reflects real ordering.
    auto exchange_event = [&]() {
        CUDA_CHECK(cudaEventRecord(my_event, stream));
        if (south >= 0) CUDA_CHECK(cudaStreamWaitEvent(stream, peer_event[0], 0));
        if (north >= 0) CUDA_CHECK(cudaStreamWaitEvent(stream, peer_event[1], 0));
        if (south >= 0) pull_south();
        if (north >= 0) pull_north();
    };

    // Barrier-ordered exchange: a host MPI_Barrier stands in for the ordering.
    // Correct but coarse; timed with wall clock since the barrier is host-side.
    auto exchange_barrier = [&]() {
        MPI_Barrier(MPI_COMM_WORLD);
        if (south >= 0) pull_south();
        if (north >= 0) pull_north();
        CUDA_CHECK(cudaStreamSynchronize(stream));
    };

    // --- correctness: one event-ordered exchange, then verify every row. -----
    exchange_event();
    CUDA_CHECK(cudaStreamSynchronize(stream));
    CUDA_CHECK(cudaMemcpy(h.data(), d_field, field_elems * dsize, cudaMemcpyDeviceToHost));

    int local_ok = 1;
    for (int k = 0; k < nz && local_ok; ++k)
        for (int j = 0; j < ytot && local_ok; ++j) {
            // Skip pole halos (no neighbor filled them).
            if (south < 0 && j < halo) continue;
            if (north < 0 && j >= halo + nyl) continue;
            const long gj = (long)rank * nyl + (j - halo);
            const double want = encode(0, gj, k, nx, nz); // i=0 column probe
            const double got  = h[(size_t)0 + (size_t)nx * j + (size_t)nx * ytot * k];
            if (got != want) {
                std::fprintf(stderr,
                    "FAIL rank %d: row j=%d k=%d got %.1f want %.1f\n",
                    rank, j, k, got, want);
                local_ok = 0;
            }
        }
    int all_ok = 0;
    MPI_Allreduce(&local_ok, &all_ok, 1, MPI_INT, MPI_MIN, MPI_COMM_WORLD);
    if (all_ok && rank == 0)
        std::printf("PEER_HALO verify: PASS (all ranks, geometry correct)\n");
    if (!all_ok) {
        MPI_Finalize();
        return 1;
    }

    // --- timing: event-ordered, GPU-stream timed (comparable to the NCCL bench).
    for (int w = 0; w < 20; ++w) exchange_event();
    CUDA_CHECK(cudaStreamSynchronize(stream));
    cudaEvent_t t0, t1;
    CUDA_CHECK(cudaEventCreate(&t0));
    CUDA_CHECK(cudaEventCreate(&t1));
    CUDA_CHECK(cudaEventRecord(t0, stream));
    for (int it = 0; it < iters; ++it) exchange_event();
    CUDA_CHECK(cudaEventRecord(t1, stream));
    CUDA_CHECK(cudaStreamSynchronize(stream));
    float ms_event = 0.0f;
    CUDA_CHECK(cudaEventElapsedTime(&ms_event, t0, t1));
    ms_event /= iters;

    // --- timing: barrier-ordered, wall-clock (host barrier not on the stream).
    for (int w = 0; w < 20; ++w) exchange_barrier();
    MPI_Barrier(MPI_COMM_WORLD);
    const double wall0 = MPI_Wtime();
    for (int it = 0; it < iters; ++it) exchange_barrier();
    const double wall1 = MPI_Wtime();
    double ms_barrier = (wall1 - wall0) * 1e3 / iters;

    // Bytes this rank pulls in per exchange (received into its halos).
    const int live = (north >= 0 ? 1 : 0) + (south >= 0 ? 1 : 0);
    const double bytes_per = (double)live * (double)face_elems * dsize;
    const double gbps = ms_event > 0 ? (bytes_per / (ms_event * 1e-3)) / 1e9 : 0.0;
    const double interior_elems = (double)nx * nyl * nz;
    const double halo_to_volume = ((double)live * (double)face_elems) / interior_elems;

    // Reduce for a single clean summary from rank 0.
    double max_event = ms_event, max_barrier = ms_barrier, sum_bytes = bytes_per;
    MPI_Reduce(rank == 0 ? MPI_IN_PLACE : &max_event,   &max_event,   1, MPI_DOUBLE, MPI_MAX, 0, MPI_COMM_WORLD);
    MPI_Reduce(rank == 0 ? MPI_IN_PLACE : &max_barrier, &max_barrier, 1, MPI_DOUBLE, MPI_MAX, 0, MPI_COMM_WORLD);
    MPI_Reduce(rank == 0 ? MPI_IN_PLACE : &sum_bytes,   &sum_bytes,   1, MPI_DOUBLE, MPI_SUM, 0, MPI_COMM_WORLD);

    if (rank == 0) {
        std::printf("PEER_HALO nx=%d ny=%d nz=%d ranks=%d halo=%d ny_local=%d\n",
                    nx, nyg, nz, npes, halo, nyl);
        std::printf("  per-exchange time, event-ordered (slowest rank): %.4f ms\n", max_event);
        std::printf("  per-exchange time, barrier-ordered (wall):       %.4f ms\n", max_barrier);
        std::printf("  per-exchange bytes received across all GPUs: %.3f MiB\n", sum_bytes / (1024.0*1024.0));
        std::printf("  interior-rank pull bandwidth (event): %.1f GB/s\n", gbps);
        std::printf("  halo-in / interior-volume ratio: %.4f  (halo/ny_local = %.4f)\n",
                    halo_to_volume, (double)halo / (double)nyl);
    }

    CUDA_CHECK(cudaEventDestroy(t0));
    CUDA_CHECK(cudaEventDestroy(t1));
    if (peer_event[0]) cudaEventDestroy(peer_event[0]);
    if (peer_event[1]) cudaEventDestroy(peer_event[1]);
    if (peer_field[0]) cudaIpcCloseMemHandle(peer_field[0]);
    if (peer_field[1]) cudaIpcCloseMemHandle(peer_field[1]);
    cudaEventDestroy(my_event);
    cudaFree(d_field);
    CUDA_CHECK(cudaStreamDestroy(stream));
    MPI_Finalize();
    return 0;
}
