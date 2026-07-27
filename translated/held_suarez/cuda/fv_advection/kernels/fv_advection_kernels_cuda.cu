#include "fv_advection_kernels_cuda.h"
#include "fv_advection_kernel_profile.hpp"
#include "semi_y_3d_cuda.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cuda_runtime.h>
#include <utility>

// GPU-to-GPU halo exchange (FV transfer PoC, Level 1). The MPI and NCCL headers
// and every symbol that uses them are compiled only when the overlay build
// defines FV_ADVECTION_USE_NCCL (and adds the include/link flags). Without that
// define the file builds exactly as before, so the current model is unaffected.
#ifdef FV_ADVECTION_USE_NCCL
#include <mpi.h>
#include <nccl.h>
#endif

namespace {

namespace profile = fv_advection_kernels_profile;

profile::Counter semi_x_counter{"semi_x_3d", 0, 0.0};
profile::Counter slope_x_counter{"slope_x", 0, 0.0};
profile::Counter integer_flux_x_counter{"integer_flux_x", 0, 0.0};
profile::Counter vanleer_x_counter{"vanleer_x_3d", 0, 0.0};
profile::Counter slope_sphere_counter{"slope_sphere", 0, 0.0};
profile::Counter vanleer_sphere_counter{"vanleer_sphere_3d", 0, 0.0};
profile::Counter resident_begin_counter{"resident_advection_begin", 0, 0.0};
profile::Counter resident_finish_counter{"resident_advection_finish", 0, 0.0};

enum class CudaMode { stateless, persistent, resident, invalid };

struct CudaPhaseCounter {
    long long calls = 0;
    double allocation = 0.0;
    double h2d = 0.0;
    double kernel = 0.0;
    double sync = 0.0;
    double d2h = 0.0;
    double free = 0.0;
    double total = 0.0;
};

CudaPhaseCounter stateless_phases;
CudaPhaseCounter persistent_phases;
CudaPhaseCounter resident_phases;

CudaMode selected_cuda_mode() {
    const char* value = std::getenv("FV_KERNELS_CUDA_MODE");
    if (value == nullptr || value[0] == '\0' || std::strcmp(value, "stateless") == 0) {
        return CudaMode::stateless;
    }
    if (std::strcmp(value, "persistent") == 0) {
        return CudaMode::persistent;
    }
    if (std::strcmp(value, "resident") == 0) {
        return CudaMode::resident;
    }
    static bool reported = false;
    if (!reported) {
        std::fprintf(stderr,
                     "fv_advection_kernels CUDA error: invalid FV_KERNELS_CUDA_MODE='%s'; "
                     "expected stateless, persistent, or resident\n",
                     value);
        reported = true;
    }
    return CudaMode::invalid;
}

const char* cuda_backend_name(CudaMode mode) {
    if (mode == CudaMode::resident) return "cuda_resident";
    return mode == CudaMode::persistent ? "cuda_persistent" : "cuda_stateless";
}

bool uses_persistent_buffers(CudaMode mode) {
    return mode == CudaMode::persistent || mode == CudaMode::resident;
}

void print_phase_counter(const char* backend, const CudaPhaseCounter& counter) {
    if (!profile::enabled() || counter.calls <= 0) {
        return;
    }
    std::fprintf(
        stdout,
        "PROFILE_FV_ADVECTION_CUDA backend=%s rank=%s calls=%lld "
        "allocation=%.9f h2d=%.9f kernel=%.9f sync=%.9f d2h=%.9f "
        "free=%.9f total=%.9f\n",
        backend, profile::rank_string(), counter.calls, counter.allocation,
        counter.h2d, counter.kernel, counter.sync, counter.d2h, counter.free,
        counter.total);
}

void print_cuda_profile() {
    const char* backend = cuda_backend_name(selected_cuda_mode());
    profile::print_counter(backend, semi_x_counter);
    profile::print_counter(backend, slope_x_counter);
    profile::print_counter(backend, integer_flux_x_counter);
    profile::print_counter(backend, vanleer_x_counter);
    profile::print_counter(backend, slope_sphere_counter);
    profile::print_counter(backend, vanleer_sphere_counter);
    profile::print_counter(backend, resident_begin_counter);
    profile::print_counter(backend, resident_finish_counter);
    print_phase_counter("cuda_stateless", stateless_phases);
    print_phase_counter("cuda_persistent", persistent_phases);
    print_phase_counter("cuda_resident", resident_phases);
    std::fflush(stdout);
}

void register_cuda_profile_report() {
    static bool registered = false;
    if (!registered && profile::enabled()) {
        std::atexit(print_cuda_profile);
        registered = true;
    }
}

}  // namespace

namespace fv_advection_kernels {
namespace cuda_backend {

namespace {

constexpr int FV_CUDA_SUCCESS = 0;
constexpr int FV_CUDA_ERROR = 1;
constexpr int FV_CUDA_INVALID_ARGUMENT = 2;

using Clock = std::chrono::steady_clock;

double elapsed_seconds(Clock::time_point start) {
    return std::chrono::duration<double>(Clock::now() - start).count();
}

class PhaseCall {
  public:
    explicit PhaseCall(CudaMode mode)
        : counter_(mode == CudaMode::resident
                       ? resident_phases
                       : (mode == CudaMode::persistent ? persistent_phases
                                                       : stateless_phases)),
          active_(profile::enabled()),
          start_(Clock::now()) {}

    ~PhaseCall() {
        if (active_) {
            counter_.calls += 1;
            counter_.total += elapsed_seconds(start_);
        }
    }

    CudaPhaseCounter& counter() { return counter_; }

  private:
    CudaPhaseCounter& counter_;
    bool active_;
    Clock::time_point start_;
};

struct DeviceBuffer {
    double* data = nullptr;
    std::size_t capacity = 0;
};

// Resident scope-B slot map (no cross-phase aliasing for anything live across
// begin -> finish): 0 c, 1 ua, 2 q_int, 3 q1, 4 q2, 5 va_halo, 6 dyy, 7 dq,
// 8 cc, 9 dy, 10 dy_plus, 11 dy_minus, 12 uc, 13 vc, 14 q_halo,
// 15 va_int (semi_y interior), 16 semi scratch. 17..19 spare.
constexpr std::size_t kNumBuffers = 20;

struct PersistentContext {
    DeviceBuffer buffers[kNumBuffers];
    bool initialized = false;
    bool cleanup_registered = false;
    bool resident_stage_active = false;
    int resident_nx = 0;
    int resident_ny = 0;
    int resident_nz = 0;
    // The 6 grid metrics (c, dyy, cc, dy, dy_plus, dy_minus) are run-constant, so
    // begin uploads them once and reuses them; these track whether the resident
    // metric slots already hold the metrics for the current grid dimensions.
    bool metrics_resident = false;
    int metrics_nx = 0;
    int metrics_ny = 0;
    int metrics_nz = 0;
};

PersistentContext persistent_context;

struct TimingEvents {
    cudaEvent_t start = nullptr;
    cudaEvent_t stop = nullptr;
    bool initialized = false;
    bool cleanup_registered = false;
};

TimingEvents timing_events;

void release_persistent_context();
void release_timing_events();

__host__ __device__ inline int idx3(int i0, int j0, int k0, int nx, int ny) {
    return i0 + nx * (j0 + ny * k0);
}

__host__ __device__ inline double sign_with_magnitude(double magnitude, double sign_source) {
    return sign_source >= 0.0 ? fabs(magnitude) : -fabs(magnitude);
}

__host__ __device__ inline double min3(double a, double b, double c) {
    return fmin(a, fmin(b, c));
}

__host__ __device__ inline double max3(double a, double b, double c) {
    return fmax(a, fmax(b, c));
}

int check_cuda(cudaError_t status, const char* what) {
    if (status == cudaSuccess) {
        return FV_CUDA_SUCCESS;
    }
    std::fprintf(stderr, "fv_advection_kernels CUDA error: %s failed: %s\n", what,
                 cudaGetErrorString(status));
    return FV_CUDA_ERROR;
}

int check_device_available() {
    int device_count = 0;
    int ierr = check_cuda(cudaGetDeviceCount(&device_count), "cudaGetDeviceCount");
    if (ierr != FV_CUDA_SUCCESS) {
        return ierr;
    }
    if (device_count <= 0) {
        std::fprintf(stderr,
                     "fv_advection_kernels CUDA error: CUDA backend requested but no CUDA devices are available.\n");
        return FV_CUDA_ERROR;
    }
    // Transfer PoC (addition 1): fan MPI ranks across the node's GPUs instead of
    // piling every rank onto device 0. Keyed off the launcher's node-local rank
    // so ranks sharing a node spread over that node's devices. Done once/process.
    static bool device_selected = false;
    if (!device_selected) {
        int local_rank = 0;
        const char* env = std::getenv("OMPI_COMM_WORLD_LOCAL_RANK");
        if (env == nullptr) {
            env = std::getenv("SLURM_LOCALID");
        }
        if (env != nullptr) {
            local_rank = std::atoi(env);
        }
        const int device = local_rank % device_count;
        ierr = check_cuda(cudaSetDevice(device), "cudaSetDevice");
        if (ierr != FV_CUDA_SUCCESS) {
            return ierr;
        }
        if (profile::enabled()) {
            std::fprintf(stderr,
                         "PROFILE_FV_ADVECTION_CUDA device_select local_rank=%d device=%d device_count=%d\n",
                         local_rank, device, device_count);
        }
        device_selected = true;
    }
    return FV_CUDA_SUCCESS;
}

int ensure_persistent_context() {
    if (!persistent_context.initialized) {
        const int ierr = check_device_available();
        if (ierr != FV_CUDA_SUCCESS) {
            return ierr;
        }
        persistent_context.initialized = true;
    }
    if (!persistent_context.cleanup_registered) {
        std::atexit(release_persistent_context);
        persistent_context.cleanup_registered = true;
    }
    return FV_CUDA_SUCCESS;
}

#ifdef FV_ADVECTION_USE_NCCL
// One NCCL communicator per process, built once over the running MPI world and
// bound to this rank's GPU. Level 1 uses it to swap halo rows GPU-to-GPU instead
// of routing them through the host. Neighbors follow the Y-only decomposition
// (layout = 1 x npes): north = rank+1, south = rank-1; a -1 marks a pole, which
// has no neighbor on that side and reflects instead of exchanging.
struct NcclContext {
    ncclComm_t comm = nullptr;
    cudaStream_t stream = nullptr;
    int world_rank = -1;
    int world_size = 0;
    int north = -1;
    int south = -1;
    bool initialized = false;
    bool cleanup_registered = false;
    // Scratch for the GPU-to-GPU halo swap: one packed edge (two rows over all
    // levels) per direction, kept device-resident and reused across calls. Sized
    // lazily to the current tile; halo_capacity is elements per edge buffer.
    double* halo_send_south = nullptr;
    double* halo_recv_south = nullptr;
    double* halo_send_north = nullptr;
    double* halo_recv_north = nullptr;
    std::size_t halo_capacity = 0;
    // Recorded on `stream` after the unpack. The compute stream waits on this
    // instead of the host blocking on the exchange, so the fold and the flux
    // work can overlap the NCCL communication.
    cudaEvent_t halo_done = nullptr;
};

NcclContext nccl_context;

int check_nccl(ncclResult_t status, const char* what) {
    if (status == ncclSuccess) {
        return FV_CUDA_SUCCESS;
    }
    std::fprintf(stderr, "fv_advection_kernels NCCL error: %s failed: %s\n", what,
                 ncclGetErrorString(status));
    return FV_CUDA_ERROR;
}

void release_nccl_context() {
    double* halo_buffers[] = {nccl_context.halo_send_south, nccl_context.halo_recv_south,
                              nccl_context.halo_send_north, nccl_context.halo_recv_north};
    for (double* buffer : halo_buffers) {
        if (buffer != nullptr) {
            cudaFree(buffer);
        }
    }
    nccl_context.halo_send_south = nullptr;
    nccl_context.halo_recv_south = nullptr;
    nccl_context.halo_send_north = nullptr;
    nccl_context.halo_recv_north = nullptr;
    nccl_context.halo_capacity = 0;
    if (nccl_context.halo_done != nullptr) {
        cudaEventDestroy(nccl_context.halo_done);
        nccl_context.halo_done = nullptr;
    }
    if (nccl_context.stream != nullptr) {
        cudaStreamDestroy(nccl_context.stream);
        nccl_context.stream = nullptr;
    }
    if (nccl_context.comm != nullptr) {
        ncclCommDestroy(nccl_context.comm);
        nccl_context.comm = nullptr;
    }
    nccl_context.initialized = false;
}

// Build the NCCL communicator once. Safe to call repeatedly; only the first call
// does work. Returns FV_CUDA_SUCCESS once the communicator, stream, and neighbor
// ranks are ready.
int ensure_nccl_context() {
    if (nccl_context.initialized) {
        return FV_CUDA_SUCCESS;
    }

    // The device must be chosen before NCCL binds a communicator to it; this is
    // the same per-rank cudaSetDevice the resident path already relies on.
    int ierr = ensure_persistent_context();
    if (ierr != FV_CUDA_SUCCESS) {
        return ierr;
    }

    // FMS owns MPI and initializes it before any kernel runs; we only read the
    // existing world and use it to hand NCCL its bootstrap id.
    int mpi_ready = 0;
    if (MPI_Initialized(&mpi_ready) != MPI_SUCCESS || mpi_ready == 0) {
        std::fprintf(stderr,
                     "fv_advection_kernels NCCL error: MPI is not initialized; "
                     "cannot bootstrap the NCCL communicator.\n");
        return FV_CUDA_ERROR;
    }

    int world_rank = 0;
    int world_size = 0;
    MPI_Comm_rank(MPI_COMM_WORLD, &world_rank);
    MPI_Comm_size(MPI_COMM_WORLD, &world_size);

    // NCCL requires one rank per GPU. If more ranks share this node than it has
    // GPUs, the launcher's node-local rank runs past the device count; stop with
    // a clear message rather than letting NCCL fail with "invalid usage".
    int device_count = 0;
    ierr = check_cuda(cudaGetDeviceCount(&device_count), "cudaGetDeviceCount");
    if (ierr != FV_CUDA_SUCCESS) {
        return ierr;
    }
    int local_rank = 0;
    const char* env = std::getenv("OMPI_COMM_WORLD_LOCAL_RANK");
    if (env == nullptr) {
        env = std::getenv("SLURM_LOCALID");
    }
    if (env != nullptr) {
        local_rank = std::atoi(env);
    }
    if (local_rank >= device_count) {
        std::fprintf(stderr,
                     "fv_advection_kernels NCCL error: rank %d is node-local rank %d "
                     "but the node has only %d GPU(s). NCCL needs one MPI rank per "
                     "GPU; launch one rank per GPU (for example mpirun -np %d).\n",
                     world_rank, local_rank, device_count, device_count);
        return FV_CUDA_ERROR;
    }

    // Bootstrap: rank 0 makes the unique id and broadcasts it. Only host bytes
    // cross MPI here, so the container's non-GPU-aware MPI is fine; the payload
    // later moves through NCCL itself.
    ncclUniqueId id;
    if (world_rank == 0) {
        ierr = check_nccl(ncclGetUniqueId(&id), "ncclGetUniqueId");
        if (ierr != FV_CUDA_SUCCESS) {
            return ierr;
        }
    }
    if (MPI_Bcast(&id, sizeof(id), MPI_BYTE, 0, MPI_COMM_WORLD) != MPI_SUCCESS) {
        std::fprintf(stderr,
                     "fv_advection_kernels NCCL error: MPI_Bcast of the NCCL id failed.\n");
        return FV_CUDA_ERROR;
    }

    ncclComm_t comm = nullptr;
    ierr = check_nccl(ncclCommInitRank(&comm, world_size, id, world_rank),
                      "ncclCommInitRank");
    if (ierr != FV_CUDA_SUCCESS) {
        return ierr;
    }

    cudaStream_t stream = nullptr;
    ierr = check_cuda(cudaStreamCreate(&stream), "cudaStreamCreate");
    if (ierr != FV_CUDA_SUCCESS) {
        ncclCommDestroy(comm);
        return ierr;
    }

    // Ordering-only event (no timing) so the compute stream can wait for the
    // exchange without a host-side block.
    cudaEvent_t halo_done = nullptr;
    ierr = check_cuda(cudaEventCreateWithFlags(&halo_done, cudaEventDisableTiming),
                      "cudaEventCreate halo_done");
    if (ierr != FV_CUDA_SUCCESS) {
        cudaStreamDestroy(stream);
        ncclCommDestroy(comm);
        return ierr;
    }

    nccl_context.comm = comm;
    nccl_context.stream = stream;
    nccl_context.halo_done = halo_done;
    nccl_context.world_rank = world_rank;
    nccl_context.world_size = world_size;
    nccl_context.north = (world_rank + 1 < world_size) ? world_rank + 1 : -1;
    nccl_context.south = (world_rank - 1 >= 0) ? world_rank - 1 : -1;
    nccl_context.initialized = true;

    if (!nccl_context.cleanup_registered) {
        std::atexit(release_nccl_context);
        nccl_context.cleanup_registered = true;
    }

    if (profile::enabled()) {
        std::fprintf(stderr,
                     "PROFILE_FV_ADVECTION_CUDA nccl_init world_rank=%d world_size=%d "
                     "north=%d south=%d device_count=%d\n",
                     world_rank, world_size, nccl_context.north, nccl_context.south,
                     device_count);
    }
    return FV_CUDA_SUCCESS;
}

// Gather two rows of the haloed q1 (row0 and row0+1) across all levels into a
// contiguous [k][r][i] buffer, so a single NCCL send moves the whole edge.
__global__ void pack_halo_rows_kernel(const double* q1, double* buf, int nx, int ny,
                                      int nz, int row0) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int total = nx * 2 * nz;
    if (idx >= total) return;
    const int i = idx % nx;
    const int r = (idx / nx) % 2;
    const int k = idx / (nx * 2);
    buf[idx] = q1[i + (row0 + r) * nx + k * nx * (ny + 4)];
}

// Scatter a contiguous [k][r][i] buffer back into two rows of the haloed q1.
__global__ void unpack_halo_rows_kernel(double* q1, const double* buf, int nx, int ny,
                                        int nz, int row0) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int total = nx * 2 * nz;
    if (idx >= total) return;
    const int i = idx % nx;
    const int r = (idx / nx) % 2;
    const int k = idx / (nx * 2);
    q1[i + (row0 + r) * nx + k * nx * (ny + 4)] = buf[idx];
}

// Size the four packed-edge scratch buffers to the current tile, once. Reused
// across calls; grown (never shrunk) if a later call needs more.
int ensure_nccl_halo_buffers(std::size_t edge_count) {
    if (nccl_context.halo_capacity >= edge_count && nccl_context.halo_send_south != nullptr) {
        return FV_CUDA_SUCCESS;
    }
    double** slots[] = {&nccl_context.halo_send_south, &nccl_context.halo_recv_south,
                        &nccl_context.halo_send_north, &nccl_context.halo_recv_north};
    for (double** slot : slots) {
        if (*slot != nullptr) {
            cudaFree(*slot);
            *slot = nullptr;
        }
        int ierr = check_cuda(cudaMalloc(slot, edge_count * sizeof(double)),
                              "nccl halo scratch alloc");
        if (ierr != FV_CUDA_SUCCESS) {
            return ierr;
        }
    }
    nccl_context.halo_capacity = edge_count;
    return FV_CUDA_SUCCESS;
}

// Swap the q1 y-halo with the north/south neighbor ranks entirely on the GPU:
// pack the two interior edge rows, exchange them over NCCL (NVLink, no host
// round-trip), and unpack into the halo rows. A pole side (neighbor == -1) is
// left untouched here; the polar fold fills it. The device stream carries the
// pack, the exchange, and the unpack in order, and records nccl_context.halo_done
// when the unpack is queued. With synchronize == true the host waits for the
// stream (standalone test entry); with synchronize == false it returns without
// blocking and the caller orders the compute stream against halo_done.
int exchange_q1_halo_nccl(double* d_q1, int nx, int ny, int nz,
                          CudaPhaseCounter& phases, bool synchronize) {
    if (!nccl_context.initialized) {
        std::fprintf(stderr,
                     "fv_advection_kernels NCCL error: halo exchange requested before "
                     "the communicator was built.\n");
        return FV_CUDA_ERROR;
    }
    const bool has_south = nccl_context.south >= 0;
    const bool has_north = nccl_context.north >= 0;
    if (!has_south && !has_north) {
        return FV_CUDA_SUCCESS;  // single-rank column: nothing to exchange.
    }

    const std::size_t edge = static_cast<std::size_t>(nx) * 2 * nz;
    int ierr = ensure_nccl_halo_buffers(edge);
    if (ierr != FV_CUDA_SUCCESS) return ierr;

    cudaStream_t stream = nccl_context.stream;
    const int threads = 256;
    const int blocks = static_cast<int>((edge + threads - 1) / threads);
    const bool timing = profile::enabled();
    const auto exchange_start = Clock::now();

    // Pack the outbound interior edge rows: south {2,3}, north {ny,ny+1}.
    if (has_south) {
        pack_halo_rows_kernel<<<blocks, threads, 0, stream>>>(
            d_q1, nccl_context.halo_send_south, nx, ny, nz, 2);
    }
    if (has_north) {
        pack_halo_rows_kernel<<<blocks, threads, 0, stream>>>(
            d_q1, nccl_context.halo_send_north, nx, ny, nz, ny);
    }
    ierr = check_cuda(cudaGetLastError(), "nccl halo pack");
    if (ierr != FV_CUDA_SUCCESS) return ierr;

    // One grouped exchange so the paired send/recv cannot deadlock.
    if ((ierr = check_nccl(ncclGroupStart(), "ncclGroupStart")) != FV_CUDA_SUCCESS) {
        return ierr;
    }
    if (has_south) {
        if ((ierr = check_nccl(ncclSend(nccl_context.halo_send_south, edge, ncclDouble,
                                        nccl_context.south, nccl_context.comm, stream),
                               "ncclSend south")) != FV_CUDA_SUCCESS ||
            (ierr = check_nccl(ncclRecv(nccl_context.halo_recv_south, edge, ncclDouble,
                                        nccl_context.south, nccl_context.comm, stream),
                               "ncclRecv south")) != FV_CUDA_SUCCESS) {
            ncclGroupEnd();
            return ierr;
        }
    }
    if (has_north) {
        if ((ierr = check_nccl(ncclSend(nccl_context.halo_send_north, edge, ncclDouble,
                                        nccl_context.north, nccl_context.comm, stream),
                               "ncclSend north")) != FV_CUDA_SUCCESS ||
            (ierr = check_nccl(ncclRecv(nccl_context.halo_recv_north, edge, ncclDouble,
                                        nccl_context.north, nccl_context.comm, stream),
                               "ncclRecv north")) != FV_CUDA_SUCCESS) {
            ncclGroupEnd();
            return ierr;
        }
    }
    if ((ierr = check_nccl(ncclGroupEnd(), "ncclGroupEnd")) != FV_CUDA_SUCCESS) {
        return ierr;
    }

    // Unpack inbound halo rows: south halo {0,1}, north halo {ny+2,ny+3}.
    if (has_south) {
        unpack_halo_rows_kernel<<<blocks, threads, 0, stream>>>(
            d_q1, nccl_context.halo_recv_south, nx, ny, nz, 0);
    }
    if (has_north) {
        unpack_halo_rows_kernel<<<blocks, threads, 0, stream>>>(
            d_q1, nccl_context.halo_recv_north, nx, ny, nz, ny + 2);
    }
    ierr = check_cuda(cudaGetLastError(), "nccl halo unpack");
    if (ierr != FV_CUDA_SUCCESS) return ierr;

    // Mark the exchange complete on the NCCL stream so the compute stream can
    // wait for it without the host blocking here.
    ierr = check_cuda(cudaEventRecord(nccl_context.halo_done, stream),
                      "nccl halo event record");
    if (ierr != FV_CUDA_SUCCESS) return ierr;

    if (synchronize) {
        ierr = check_cuda(cudaStreamSynchronize(stream), "nccl halo exchange sync");
        if (timing) phases.kernel += elapsed_seconds(exchange_start);
    }
    return ierr;
}

// Fill a pole's q1 halo rows on the GPU by reflecting the interior across the
// pole, matching the host fold: the longitude opposite (src = c + nx/2, wrapped)
// supplies the value, and the two halo rows mirror the two nearest interior rows.
// A pole side has no neighbor, so NCCL leaves it untouched and this fills it.
// Reads touch only interior rows, writes only halo rows, so there is no race.
__global__ void polar_fold_q1_kernel(double* q1, int nx, int ny, int nz,
                                     bool fold_south, bool fold_north) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int total = nx * nz;
    if (idx >= total) return;
    const int c = idx % nx;
    const int k = idx / nx;
    const int src = (c + nx / 2) % nx;
    const int plane = nx * (ny + 4);
    const int base = k * plane;
    if (fold_south) {
        // South halo rows {1,0} reflect interior rows {2,3}.
        q1[base + 1 * nx + c] = q1[base + 2 * nx + src];
        q1[base + 0 * nx + c] = q1[base + 3 * nx + src];
    }
    if (fold_north) {
        // North halo rows {ny+2,ny+3} reflect interior rows {ny+1,ny}.
        q1[base + (ny + 2) * nx + c] = q1[base + (ny + 1) * nx + src];
        q1[base + (ny + 3) * nx + c] = q1[base + (ny) * nx + src];
    }
}

// Launch the pole fold for whichever sides this rank owns. No-op when the rank
// touches neither pole (both flags false), which is the interior-rank case. The
// fold runs on the default compute stream; it reads only interior rows and
// writes only pole halo rows, so it can run concurrently with the NCCL exchange
// (which touches the neighbor halo rows). With synchronize == false it returns
// without a host block and the caller's stream ordering covers completion.
int fold_q1_poles(double* d_q1, int nx, int ny, int nz, bool fold_south,
                  bool fold_north, CudaPhaseCounter& phases, bool synchronize) {
    if (!fold_south && !fold_north) {
        return FV_CUDA_SUCCESS;
    }
    const bool timing = profile::enabled();
    const auto fold_start = Clock::now();
    const int threads = 256;
    const int blocks = static_cast<int>((static_cast<std::size_t>(nx) * nz + threads - 1) / threads);
    polar_fold_q1_kernel<<<blocks, threads>>>(d_q1, nx, ny, nz, fold_south, fold_north);
    int ierr = check_cuda(cudaGetLastError(), "polar_fold_q1_kernel");
    if (ierr != FV_CUDA_SUCCESS) return ierr;
    if (synchronize) {
        ierr = check_cuda(cudaDeviceSynchronize(), "polar fold sync");
        if (timing) phases.kernel += elapsed_seconds(fold_start);
    }
    return ierr;
}

// Pole fold for the meridional wind vx (haloed va), matching the host fold at
// a_grid_horiz_advection: vx(i,0) = -vx(ii,1) and vx(i,ny+1) = -vx(ii,ny), where
// ii = i + nx/2 wrapped. The sign flips (a wind reflected across the pole
// reverses direction) and only the inner halo row on each pole side is filled,
// which is the single row compute_vc reads (device rows 1 and ny+2). Reads touch
// only interior rows, writes only halo rows, so it is race-free like the q1 fold.
__global__ void polar_fold_vx_kernel(double* vx, int nx, int ny, int nz,
                                     bool fold_south, bool fold_north) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int total = nx * nz;
    if (idx >= total) return;
    const int c = idx % nx;
    const int k = idx / nx;
    const int src = (c + nx / 2) % nx;
    const int plane = nx * (ny + 4);
    const int base = k * plane;
    if (fold_south) {
        // South inner halo row 1 (Fortran 0) reflects interior row 2 (Fortran 1).
        vx[base + 1 * nx + c] = -vx[base + 2 * nx + src];
    }
    if (fold_north) {
        // North inner halo row ny+2 (Fortran ny+1) reflects interior row ny+1
        // (Fortran ny).
        vx[base + (ny + 2) * nx + c] = -vx[base + (ny + 1) * nx + src];
    }
}

// Launch the vx pole fold for whichever sides this rank owns. Mirrors
// fold_q1_poles: no-op for an interior rank, runs on the default compute stream,
// and gates the host block on synchronize so the resident spine can overlap it.
int fold_vx_poles(double* d_vx, int nx, int ny, int nz, bool fold_south,
                  bool fold_north, CudaPhaseCounter& phases, bool synchronize) {
    if (!fold_south && !fold_north) {
        return FV_CUDA_SUCCESS;
    }
    const bool timing = profile::enabled();
    const auto fold_start = Clock::now();
    const int threads = 256;
    const int blocks = static_cast<int>((static_cast<std::size_t>(nx) * nz + threads - 1) / threads);
    polar_fold_vx_kernel<<<blocks, threads>>>(d_vx, nx, ny, nz, fold_south, fold_north);
    int ierr = check_cuda(cudaGetLastError(), "polar_fold_vx_kernel");
    if (ierr != FV_CUDA_SUCCESS) return ierr;
    if (synchronize) {
        ierr = check_cuda(cudaDeviceSynchronize(), "polar fold vx sync");
        if (timing) phases.kernel += elapsed_seconds(fold_start);
    }
    return ierr;
}
#endif  // FV_ADVECTION_USE_NCCL

int ensure_buffer(std::size_t slot, std::size_t count, CudaPhaseCounter& phases) {
    if (slot >= kNumBuffers) {
        return FV_CUDA_INVALID_ARGUMENT;
    }
    DeviceBuffer& buffer = persistent_context.buffers[slot];
    if (buffer.capacity >= count) {
        return FV_CUDA_SUCCESS;
    }

    if (buffer.data != nullptr) {
        const auto start = Clock::now();
        const int ierr = check_cuda(cudaFree(buffer.data), "persistent buffer resize free");
        if (profile::enabled()) {
            phases.free += elapsed_seconds(start);
        }
        buffer.data = nullptr;
        buffer.capacity = 0;
        if (ierr != FV_CUDA_SUCCESS) {
            return ierr;
        }
    }

    const auto start = Clock::now();
    const int ierr = check_cuda(
        cudaMalloc(reinterpret_cast<void**>(&buffer.data), count * sizeof(double)),
        "persistent buffer allocation");
    if (profile::enabled()) {
        phases.allocation += elapsed_seconds(start);
    }
    if (ierr == FV_CUDA_SUCCESS) {
        buffer.capacity = count;
    }
    return ierr;
}

void release_persistent_context() {
    const auto start = Clock::now();
    for (DeviceBuffer& buffer : persistent_context.buffers) {
        if (buffer.data != nullptr) {
            const cudaError_t status = cudaFree(buffer.data);
            if (status != cudaSuccess) {
                std::fprintf(stderr,
                             "fv_advection_kernels CUDA error: persistent finalize "
                             "failed: %s\n",
                             cudaGetErrorString(status));
            }
            buffer.data = nullptr;
            buffer.capacity = 0;
        }
    }
    if (profile::enabled() && persistent_context.initialized) {
        persistent_phases.free += elapsed_seconds(start);
    }
    persistent_context.initialized = false;
    persistent_context.resident_stage_active = false;
    persistent_context.metrics_resident = false;
    persistent_context.metrics_nx = 0;
    persistent_context.metrics_ny = 0;
    persistent_context.metrics_nz = 0;
}

int ensure_timing_events() {
    if (!timing_events.initialized) {
        int ierr = check_cuda(cudaEventCreate(&timing_events.start),
                              "cudaEventCreate start");
        if (ierr == FV_CUDA_SUCCESS) {
            ierr = check_cuda(cudaEventCreate(&timing_events.stop),
                              "cudaEventCreate stop");
        }
        if (ierr != FV_CUDA_SUCCESS) {
            release_timing_events();
            return ierr;
        }
        timing_events.initialized = true;
    }
    if (!timing_events.cleanup_registered) {
        std::atexit(release_timing_events);
        timing_events.cleanup_registered = true;
    }
    return FV_CUDA_SUCCESS;
}

void release_timing_events() {
    if (timing_events.start != nullptr) {
        cudaEventDestroy(timing_events.start);
        timing_events.start = nullptr;
    }
    if (timing_events.stop != nullptr) {
        cudaEventDestroy(timing_events.stop);
        timing_events.stop = nullptr;
    }
    timing_events.initialized = false;
}

int copy_to_existing_device(
    double* dst,
    const double* src,
    std::size_t count,
    const char* name,
    CudaPhaseCounter& phases) {
    if (src == nullptr || dst == nullptr) {
        std::fprintf(stderr, "fv_advection_kernels CUDA error: null pointer %s\n", name);
        return FV_CUDA_INVALID_ARGUMENT;
    }
    const auto start = Clock::now();
    const int ierr = check_cuda(
        cudaMemcpy(dst, src, count * sizeof(double), cudaMemcpyHostToDevice), name);
    if (profile::enabled()) {
        phases.h2d += elapsed_seconds(start);
    }
    return ierr;
}

int copy_to_device(double** dst, const double* src, std::size_t count, const char* name) {
    if (src == nullptr) {
        std::fprintf(stderr, "fv_advection_kernels CUDA error: null input pointer %s\n", name);
        return FV_CUDA_INVALID_ARGUMENT;
    }
    const auto allocation_start = Clock::now();
    int ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(dst), count * sizeof(double)), name);
    if (profile::enabled()) {
        stateless_phases.allocation += elapsed_seconds(allocation_start);
    }
    if (ierr != FV_CUDA_SUCCESS) {
        return ierr;
    }
    const auto copy_start = Clock::now();
    ierr = check_cuda(cudaMemcpy(*dst, src, count * sizeof(double), cudaMemcpyHostToDevice), name);
    if (profile::enabled()) {
        stateless_phases.h2d += elapsed_seconds(copy_start);
    }
    return ierr;
}

int copy_inout_to_device(double** dst, const double* src, std::size_t count, const char* name) {
    return copy_to_device(dst, src, count, name);
}

void free_if_present(double* ptr) {
    if (ptr != nullptr) {
        const auto start = Clock::now();
        const cudaError_t status = cudaFree(ptr);
        if (profile::enabled()) {
            stateless_phases.free += elapsed_seconds(start);
        }
        if (status != cudaSuccess) {
            std::fprintf(stderr, "fv_advection_kernels CUDA error: cudaFree failed: %s\n",
                         cudaGetErrorString(status));
        }
    }
}

__global__ void semi_x_kernel(
    int nx,
    int ny,
    int nz,
    double dt,
    double dx,
    const double* c,
    const double* ua,
    const double* q,
    double* dq) {
    const int size = nx * ny * nz;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= size) {
        return;
    }

    const int plane = nx * ny;
    const int k0 = idx / plane;
    const int rem = idx - k0 * plane;
    const int j0 = rem / nx;
    const int i0 = rem - j0 * nx;
    const double b = ua[idx] * dt / (dx * c[j0]);
    int ii = i0;
    ii -= static_cast<int>(floor(b));
    if (ii > nx) {
        ii -= nx;
    }
    if (ii < 1) {
        ii += nx;
    }
    const int left = ii - 1;
    const int right = (left + 1 >= nx) ? 0 : left + 1;
    const double bb = b - floor(b);
    dq[idx] = bb * q[idx3(left, j0, k0, nx, ny)] +
              (1.0 - bb) * q[idx3(right, j0, k0, nx, ny)] - q[idx];
}

__global__ void form_q1_with_halo_kernel(
    int nx,
    int ny,
    int nz,
    const double* q,
    const double* semi_x_dq,
    double* q1) {
    const int size = nx * ny * nz;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= size) return;
    const int plane = nx * ny;
    const int k0 = idx / plane;
    const int rem = idx - k0 * plane;
    const int j0 = rem / nx;
    const int i0 = rem - j0 * nx;
    q1[idx3(i0, j0 + 2, k0, nx, ny + 4)] = q[idx] + semi_x_dq[idx];
}

// q2 = q + semi_y(q), mirroring the Fortran cross term (interior layout).
__global__ void form_q2_kernel(
    int nx,
    int ny,
    int nz,
    const double* q,
    const double* semi_y_dq,
    double* q2) {
    const int size = nx * ny * nz;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= size) return;
    q2[idx] = q[idx] + semi_y_dq[idx];
}

// uc(i,j) = 0.5*(ua(i-1,j) + ua(i,j)), x-periodic (uc(1) = 0.5*(ua(nx) + ua(1))).
// Mirrors the host uc averaging in a_grid_horiz_advection_3d so the divergence
// pre-step can be folded into resident begin instead of crossing to the host.
__global__ void compute_uc_kernel(
    int nx,
    int ny,
    int nz,
    const double* ua,
    double* uc) {
    const int size = nx * ny * nz;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= size) return;
    const int plane = nx * ny;
    const int k0 = idx / plane;
    const int rem = idx - k0 * plane;
    const int j0 = rem / nx;
    const int i0 = rem - j0 * nx;
    const int im = (i0 == 0) ? nx - 1 : i0 - 1;
    uc[idx] = 0.5 * (ua[idx3(im, j0, k0, nx, ny)] + ua[idx]);
}

// vc(i,j) = 0.5*(vx(i,j-1) + vx(i,j)) for device rows r = 0..ny (global j = js+r),
// reading the haloed va (vx) at row offset 2. vc layout is nx*(ny+1)*nz.
__global__ void compute_vc_kernel(
    int nx,
    int ny,
    int nz,
    const double* va_halo,
    double* vc) {
    const int vc_ny = ny + 1;
    const int size = nx * vc_ny * nz;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= size) return;
    const int plane = nx * vc_ny;
    const int k0 = idx / plane;
    const int rem = idx - k0 * plane;
    const int r = rem / nx;
    const int i0 = rem - r * nx;
    const int q_ny = ny + 4;
    const double v_jm1 = va_halo[idx3(i0, r + 1, k0, nx, q_ny)];  // vx(j-1)
    const double v_j = va_halo[idx3(i0, r + 2, k0, nx, q_ny)];    // vx(j)
    vc[idx] = 0.5 * (v_jm1 + v_j);
}

// div from uc/vc and metrics, then dq = q*div. Folds the host
// `dq_dt = dq_dt + q*div` divergence term; dq is assumed zero on entry (the
// resident grid-tracer caller passes dt_tr = 0), so this overwrites it.
// Metric slices: c = c(js:je), cc = cc(js:je+1), dy = dy(js-1:je+1) (offset +1).
__global__ void div_qdiv_kernel(
    int nx,
    int ny,
    int nz,
    double dx,
    const double* c,
    const double* cc,
    const double* dy,
    const double* uc,
    const double* vc,
    const double* q,
    double* dq) {
    const int size = nx * ny * nz;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= size) return;
    const int plane = nx * ny;
    const int k0 = idx / plane;
    const int rem = idx - k0 * plane;
    const int j0 = rem / nx;
    const int i0 = rem - j0 * nx;
    const int vc_ny = ny + 1;
    const double vc_j = vc[idx3(i0, j0, k0, nx, vc_ny)];
    const double vc_jp = vc[idx3(i0, j0 + 1, k0, nx, vc_ny)];
    double div = (vc_jp * cc[j0 + 1] - vc_j * cc[j0]) / (c[j0] * dy[j0 + 1]);
    const int ip = (i0 == nx - 1) ? 0 : i0 + 1;
    div += (uc[idx3(ip, j0, k0, nx, ny)] - uc[idx]) / (c[j0] * dx);
    dq[idx] = q[idx] * div;
}

__global__ void slope_x_kernel(
    int nx,
    int ny,
    int nz,
    bool monotone,
    const double* q,
    double* slope) {
    const int size = nx * ny * nz;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= size) {
        return;
    }

    const int plane = nx * ny;
    const int k0 = idx / plane;
    const int rem = idx - k0 * plane;
    const int j0 = rem / nx;
    const int i0 = rem - j0 * nx;
    const int im = (i0 == 0) ? nx - 1 : i0 - 1;
    const int ip = (i0 == nx - 1) ? 0 : i0 + 1;
    const int ipp = (ip == nx - 1) ? 0 : ip + 1;

    const double grad_i = q[idx] - q[idx3(im, j0, k0, nx, ny)];
    const double grad_ip = q[idx3(ip, j0, k0, nx, ny)] - q[idx];
    double value = 0.5 * (grad_ip + grad_i);
    if (i0 == nx - 1) {
        const double grad_0 = q[idx3(0, j0, k0, nx, ny)] - q[idx3(nx - 1, j0, k0, nx, ny)];
        value = 0.5 * (grad_0 + grad_i);
    }
    (void)ipp;

    const double center = q[idx];
    const double limited =
        monotone
            ? min3(fabs(value),
                   2.0 * (center - min3(q[idx3(im, j0, k0, nx, ny)], center,
                                         q[idx3(ip, j0, k0, nx, ny)])),
                   2.0 * (max3(q[idx3(im, j0, k0, nx, ny)], center,
                               q[idx3(ip, j0, k0, nx, ny)]) -
                          center))
            : fmin(fabs(value), 2.0 * center);
    slope[idx] = sign_with_magnitude(limited, value);
}

__device__ double integer_flux_value(int nx, int ny, const double* courant, const double* q,
                                     int i0, int j0, int k0) {
    const int c_int = static_cast<int>(courant[idx3(i0, j0, k0, nx, ny)]);
    double sum = 0.0;
    if (c_int >= 1) {
        for (int m = 1; m <= c_int; ++m) {
            int src = i0 - m;
            if (src < 0) {
                src += nx;
            }
            sum += q[idx3(src, j0, k0, nx, ny)];
        }
    } else if (c_int <= -1) {
        for (int m = 0; m <= -c_int - 1; ++m) {
            int src = i0 + m;
            if (src >= nx) {
                src -= nx;
            }
            sum -= q[idx3(src, j0, k0, nx, ny)];
        }
    }
    return sum;
}

__global__ void integer_flux_x_kernel(
    int nx,
    int ny,
    int nz,
    const double* courant,
    const double* q,
    double* flux) {
    const int size = nx * ny * nz;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= size) {
        return;
    }
    const int plane = nx * ny;
    const int k0 = idx / plane;
    const int rem = idx - k0 * plane;
    const int j0 = rem / nx;
    const int i0 = rem - j0 * nx;
    flux[idx] = integer_flux_value(nx, ny, courant, q, i0, j0, k0);
}

__device__ double slope_x_value(
    int nx,
    int ny,
    bool monotone,
    const double* q,
    int i0,
    int j0,
    int k0) {
    const int im = (i0 == 0) ? nx - 1 : i0 - 1;
    const int ip = (i0 == nx - 1) ? 0 : i0 + 1;
    const double center = q[idx3(i0, j0, k0, nx, ny)];
    const double grad_i = center - q[idx3(im, j0, k0, nx, ny)];
    const double grad_ip = q[idx3(ip, j0, k0, nx, ny)] - center;
    const double value = 0.5 * (grad_ip + grad_i);
    const double limited =
        monotone
            ? min3(fabs(value),
                   2.0 * (center - min3(q[idx3(im, j0, k0, nx, ny)], center,
                                         q[idx3(ip, j0, k0, nx, ny)])),
                   2.0 * (max3(q[idx3(im, j0, k0, nx, ny)], center,
                               q[idx3(ip, j0, k0, nx, ny)]) -
                          center))
            : fmin(fabs(value), 2.0 * center);
    return sign_with_magnitude(limited, value);
}

__device__ double vanleer_x_flux_at(
    int nx,
    int ny,
    double dt,
    double dx,
    const double* c,
    bool monotone,
    const double* uc,
    const double* q,
    int flux_i,
    int j0,
    int k0) {
    const int base_i = flux_i == nx ? 0 : flux_i;
    const double b = uc[idx3(base_i, j0, k0, nx, ny)] * dt / (dx * c[j0]);
    const double bb = b - static_cast<int>(b);
    int ii = base_i;
    ii -= static_cast<int>(floor(b));
    if (ii > nx) {
        ii -= nx;
    }
    if (ii < 1) {
        ii += nx;
    }
    const int source = ii - 1;
    const double qq = q[idx3(source, j0, k0, nx, ny)];
    const double ss = slope_x_value(nx, ny, monotone, q, source, j0, k0);

    double int_flux = 0.0;
    const int c_int = static_cast<int>(b);
    if (c_int >= 1) {
        for (int m = 1; m <= c_int; ++m) {
            int src = base_i - m;
            if (src < 0) {
                src += nx;
            }
            int_flux += q[idx3(src, j0, k0, nx, ny)];
        }
    } else if (c_int <= -1) {
        for (int m = 0; m <= -c_int - 1; ++m) {
            int src = base_i + m;
            if (src >= nx) {
                src -= nx;
            }
            int_flux -= q[idx3(src, j0, k0, nx, ny)];
        }
    }

    return int_flux + bb * (qq + 0.5 * ss * (sign_with_magnitude(1.0, bb) - bb));
}

__global__ void vanleer_x_kernel(
    int nx,
    int ny,
    int nz,
    double dt,
    double dx,
    const double* c,
    bool monotone,
    const double* uc,
    const double* q,
    double* dq_dt) {
    const int size = nx * ny * nz;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= size) {
        return;
    }

    const int plane = nx * ny;
    const int k0 = idx / plane;
    const int rem = idx - k0 * plane;
    const int j0 = rem / nx;
    const int i0 = rem - j0 * nx;

    dq_dt[idx] -=
        (vanleer_x_flux_at(nx, ny, dt, dx, c, monotone, uc, q, i0 + 1, j0, k0) -
         vanleer_x_flux_at(nx, ny, dt, dx, c, monotone, uc, q, i0, j0, k0)) /
        dt;
}

__global__ void slope_sphere_kernel(
    int nx,
    int nys,
    int nz,
    bool monotone,
    const double* dy_plus,
    const double* dy_minus,
    const double* q,
    double* slope) {
    const int size = nx * nys * nz;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= size) {
        return;
    }
    const int q_ny = nys + 2;
    const int plane = nx * nys;
    const int k0 = idx / plane;
    const int rem = idx - k0 * plane;
    const int j0 = rem / nx;
    const int i0 = rem - j0 * nx;

    const double value =
        (q[idx3(i0, j0 + 2, k0, nx, q_ny)] -
         q[idx3(i0, j0 + 1, k0, nx, q_ny)]) *
            dy_plus[j0] +
        (q[idx3(i0, j0 + 1, k0, nx, q_ny)] -
         q[idx3(i0, j0, k0, nx, q_ny)]) *
            dy_minus[j0];

    if (monotone) {
        const double center = q[idx3(i0, j0 + 1, k0, nx, q_ny)];
        const double q_min = min3(q[idx3(i0, j0, k0, nx, q_ny)], center,
                                  q[idx3(i0, j0 + 2, k0, nx, q_ny)]);
        const double q_max = max3(q[idx3(i0, j0, k0, nx, q_ny)], center,
                                  q[idx3(i0, j0 + 2, k0, nx, q_ny)]);
        slope[idx] = sign_with_magnitude(
            min3(fabs(value), 2.0 * (center - q_min), 2.0 * (q_max - center)),
            value);
    } else {
        const double center = q[idx3(i0, j0 + 1, k0, nx, q_ny)];
        slope[idx] = sign_with_magnitude(fmin(fabs(value), 2.0 * center), value);
    }
}

__device__ double slope_sphere_value(
    int nx,
    int slope_ny,
    bool monotone,
    const double* dy_plus,
    const double* dy_minus,
    const double* q,
    int i0,
    int j0,
    int k0) {
    const int q_ny = slope_ny + 2;
    const double value =
        (q[idx3(i0, j0 + 2, k0, nx, q_ny)] -
         q[idx3(i0, j0 + 1, k0, nx, q_ny)]) *
            dy_plus[j0] +
        (q[idx3(i0, j0 + 1, k0, nx, q_ny)] -
         q[idx3(i0, j0, k0, nx, q_ny)]) *
            dy_minus[j0];
    if (monotone) {
        const double center = q[idx3(i0, j0 + 1, k0, nx, q_ny)];
        const double q_min = min3(q[idx3(i0, j0, k0, nx, q_ny)], center,
                                  q[idx3(i0, j0 + 2, k0, nx, q_ny)]);
        const double q_max = max3(q[idx3(i0, j0, k0, nx, q_ny)], center,
                                  q[idx3(i0, j0 + 2, k0, nx, q_ny)]);
        return sign_with_magnitude(
            min3(fabs(value), 2.0 * (center - q_min), 2.0 * (q_max - center)),
            value);
    }
    const double center = q[idx3(i0, j0 + 1, k0, nx, q_ny)];
    return sign_with_magnitude(fmin(fabs(value), 2.0 * center), value);
}

__device__ double vanleer_sphere_flux_at(
    int nx,
    int ny,
    double dt,
    bool monotone,
    bool is_south_boundary,
    bool is_north_boundary,
    const double* cc,
    const double* dy,
    const double* dy_plus,
    const double* dy_minus,
    const double* vc,
    const double* q,
    int i0,
    int fj0,
    int k0) {
    const int vc_ny = ny + 1;
    const int q_ny = ny + 4;
    const int slope_ny = ny + 2;
    if (fj0 == 0 && is_south_boundary) {
        return 0.0;
    }
    if (fj0 == ny && is_north_boundary) {
        return 0.0;
    }
    const double vc_val = vc[idx3(i0, fj0, k0, nx, vc_ny)];
    if (vc_val >= 0.0) {
        return vc_val * cc[fj0] *
               (q[idx3(i0, fj0 + 1, k0, nx, q_ny)] +
                0.5 * slope_sphere_value(nx, slope_ny, monotone, dy_plus,
                                         dy_minus, q, i0, fj0, k0) *
                    (1.0 - vc_val * dt / dy[fj0]));
    }
    return vc_val * cc[fj0] *
           (q[idx3(i0, fj0 + 2, k0, nx, q_ny)] -
            0.5 * slope_sphere_value(nx, slope_ny, monotone, dy_plus,
                                     dy_minus, q, i0, fj0 + 1, k0) *
                (1.0 + vc_val * dt / dy[fj0 + 1]));
}

__global__ void vanleer_sphere_kernel(
    int nx,
    int ny,
    int nz,
    double dt,
    bool monotone,
    bool is_south_boundary,
    bool is_north_boundary,
    const double* c,
    const double* cc,
    const double* dy,
    const double* dy_plus,
    const double* dy_minus,
    const double* vc,
    const double* q,
    double* dq_dt) {
    const int size = nx * ny * nz;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= size) {
        return;
    }
    const int plane = nx * ny;
    const int k0 = idx / plane;
    const int rem = idx - k0 * plane;
    const int j0 = rem / nx;
    const int i0 = rem - j0 * nx;

    dq_dt[idx] -=
        (vanleer_sphere_flux_at(nx, ny, dt, monotone, is_south_boundary,
                                is_north_boundary, cc, dy, dy_plus, dy_minus, vc, q,
                                i0, j0 + 1, k0) -
         vanleer_sphere_flux_at(nx, ny, dt, monotone, is_south_boundary,
                                is_north_boundary, cc, dy, dy_plus, dy_minus, vc, q,
                                i0, j0, k0)) *
        1.0 / (dy[j0 + 1] * c[j0]);
}

template <typename Launch>
int launch_and_copy_back(
    Launch launch,
    double* host_out,
    double* device_out,
    std::size_t count,
    const char* kernel_name,
    CudaPhaseCounter& phases) {
    const bool timing = profile::enabled();
    int ierr = FV_CUDA_SUCCESS;

    if (timing) {
        ierr = ensure_timing_events();
        if (ierr == FV_CUDA_SUCCESS) {
            ierr = check_cuda(cudaEventRecord(timing_events.start),
                              "cudaEventRecord start");
        }
    }
    if (ierr == FV_CUDA_SUCCESS) {
        launch();
        ierr = check_cuda(cudaGetLastError(), kernel_name);
    }
    if (ierr == FV_CUDA_SUCCESS && timing) {
        ierr = check_cuda(cudaEventRecord(timing_events.stop),
                          "cudaEventRecord stop");
    }

    const auto sync_start = Clock::now();
    if (ierr == FV_CUDA_SUCCESS) {
        ierr = timing
                   ? check_cuda(cudaEventSynchronize(timing_events.stop), kernel_name)
                   : check_cuda(cudaDeviceSynchronize(), kernel_name);
    }
    if (timing) {
        phases.sync += elapsed_seconds(sync_start);
        if (ierr == FV_CUDA_SUCCESS) {
            float milliseconds = 0.0f;
            ierr = check_cuda(
                cudaEventElapsedTime(&milliseconds, timing_events.start,
                                     timing_events.stop),
                "cudaEventElapsedTime");
            phases.kernel += static_cast<double>(milliseconds) * 1.0e-3;
        }
    }

    if (ierr == FV_CUDA_SUCCESS) {
        const auto copy_start = Clock::now();
        ierr = check_cuda(cudaMemcpy(host_out, device_out, count * sizeof(double),
                                     cudaMemcpyDeviceToHost),
                          "copy result to host");
        if (timing) {
            phases.d2h += elapsed_seconds(copy_start);
        }
    }
    return ierr;
}

int validate_common(int nx, int ny, int nz, CudaMode mode) {
    if (nx <= 0 || ny <= 0 || nz <= 0) {
        std::fprintf(stderr, "fv_advection_kernels CUDA error: invalid dimensions\n");
        return FV_CUDA_INVALID_ARGUMENT;
    }
    if (mode == CudaMode::invalid) {
        return FV_CUDA_INVALID_ARGUMENT;
    }
    return (mode == CudaMode::persistent || mode == CudaMode::resident)
               ? ensure_persistent_context()
               : check_device_available();
}

}  // namespace

int semi_x_3d_cuda(
    int nx,
    int ny,
    int nz,
    double dt,
    double dx,
    const double* c,
    const double* ua,
    const double* q,
    double* dq) {
    const CudaMode mode = selected_cuda_mode();
    PhaseCall phase_call(mode);
    CudaPhaseCounter& phases = phase_call.counter();
    int ierr = validate_common(nx, ny, nz, mode);
    if (ierr != FV_CUDA_SUCCESS || c == nullptr || ua == nullptr || q == nullptr || dq == nullptr) {
        return ierr == FV_CUDA_SUCCESS ? FV_CUDA_INVALID_ARGUMENT : ierr;
    }
    const std::size_t count = static_cast<std::size_t>(nx) * ny * nz;
    const int threads = 256;

    if (uses_persistent_buffers(mode)) {
        const std::pair<std::size_t, std::size_t> requests[] = {
            {0, static_cast<std::size_t>(ny)},
            {1, count},
            {2, count},
            {3, count}};
        for (const auto& request : requests) {
            ierr = ensure_buffer(request.first, request.second, phases);
            if (ierr != FV_CUDA_SUCCESS) return ierr;
        }
        double* d_c = persistent_context.buffers[0].data;
        double* d_ua = persistent_context.buffers[1].data;
        double* d_q = persistent_context.buffers[2].data;
        double* d_dq = persistent_context.buffers[3].data;
        if ((ierr = copy_to_existing_device(d_c, c, ny, "c", phases)) == FV_CUDA_SUCCESS &&
            (ierr = copy_to_existing_device(d_ua, ua, count, "ua", phases)) == FV_CUDA_SUCCESS &&
            (ierr = copy_to_existing_device(d_q, q, count, "q", phases)) == FV_CUDA_SUCCESS) {
            ierr = launch_and_copy_back(
                [&]() {
                    semi_x_kernel<<<static_cast<int>((count + threads - 1) / threads), threads>>>(
                        nx, ny, nz, dt, dx, d_c, d_ua, d_q, d_dq);
                },
                dq, d_dq, count, "semi_x_kernel", phases);
        }
        return ierr;
    }

    double *d_c = nullptr, *d_ua = nullptr, *d_q = nullptr, *d_dq = nullptr;
    if ((ierr = copy_to_device(&d_c, c, ny, "c")) == FV_CUDA_SUCCESS &&
        (ierr = copy_to_device(&d_ua, ua, count, "ua")) == FV_CUDA_SUCCESS &&
        (ierr = copy_to_device(&d_q, q, count, "q")) == FV_CUDA_SUCCESS &&
        (ierr = [&]() {
             const auto start = Clock::now();
             const int status = check_cuda(
                 cudaMalloc(reinterpret_cast<void**>(&d_dq), count * sizeof(double)), "dq");
             if (profile::enabled()) phases.allocation += elapsed_seconds(start);
             return status;
         }()) == FV_CUDA_SUCCESS) {
        ierr = launch_and_copy_back(
            [&]() {
                semi_x_kernel<<<static_cast<int>((count + threads - 1) / threads), threads>>>(
                    nx, ny, nz, dt, dx, d_c, d_ua, d_q, d_dq);
            },
            dq, d_dq, count, "semi_x_kernel", phases);
    }
    free_if_present(d_c); free_if_present(d_ua); free_if_present(d_q); free_if_present(d_dq);
    return ierr;
}

int slope_x_cuda(int nx, int ny, int nz, bool monotone, const double* q, double* slope) {
    const CudaMode mode = selected_cuda_mode();
    PhaseCall phase_call(mode);
    CudaPhaseCounter& phases = phase_call.counter();
    int ierr = validate_common(nx, ny, nz, mode);
    if (ierr != FV_CUDA_SUCCESS || q == nullptr || slope == nullptr) {
        return ierr == FV_CUDA_SUCCESS ? FV_CUDA_INVALID_ARGUMENT : ierr;
    }
    const std::size_t count = static_cast<std::size_t>(nx) * ny * nz;
    const int threads = 256;
    if (uses_persistent_buffers(mode)) {
        if ((ierr = ensure_buffer(0, count, phases)) != FV_CUDA_SUCCESS ||
            (ierr = ensure_buffer(1, count, phases)) != FV_CUDA_SUCCESS) {
            return ierr;
        }
        double* d_q = persistent_context.buffers[0].data;
        double* d_slope = persistent_context.buffers[1].data;
        if ((ierr = copy_to_existing_device(d_q, q, count, "q", phases)) == FV_CUDA_SUCCESS) {
            ierr = launch_and_copy_back(
                [&]() {
                    slope_x_kernel<<<static_cast<int>((count + threads - 1) / threads), threads>>>(
                        nx, ny, nz, monotone, d_q, d_slope);
                },
                slope, d_slope, count, "slope_x_kernel", phases);
        }
        return ierr;
    }
    double *d_q = nullptr, *d_slope = nullptr;
    if ((ierr = copy_to_device(&d_q, q, count, "q")) == FV_CUDA_SUCCESS &&
        (ierr = [&]() {
             const auto start = Clock::now();
             const int status = check_cuda(
                 cudaMalloc(reinterpret_cast<void**>(&d_slope), count * sizeof(double)), "slope");
             if (profile::enabled()) phases.allocation += elapsed_seconds(start);
             return status;
         }()) == FV_CUDA_SUCCESS) {
        ierr = launch_and_copy_back(
            [&]() {
                slope_x_kernel<<<static_cast<int>((count + threads - 1) / threads), threads>>>(
                    nx, ny, nz, monotone, d_q, d_slope);
            },
            slope, d_slope, count, "slope_x_kernel", phases);
    }
    free_if_present(d_q); free_if_present(d_slope);
    return ierr;
}

int integer_flux_x_cuda(
    int nx,
    int ny,
    int nz,
    const double* courant,
    const double* q,
    double* flux) {
    const CudaMode mode = selected_cuda_mode();
    PhaseCall phase_call(mode);
    CudaPhaseCounter& phases = phase_call.counter();
    int ierr = validate_common(nx, ny, nz, mode);
    if (ierr != FV_CUDA_SUCCESS || courant == nullptr || q == nullptr || flux == nullptr) {
        return ierr == FV_CUDA_SUCCESS ? FV_CUDA_INVALID_ARGUMENT : ierr;
    }
    const std::size_t count = static_cast<std::size_t>(nx) * ny * nz;
    const int threads = 256;
    if (uses_persistent_buffers(mode)) {
        if ((ierr = ensure_buffer(0, count, phases)) != FV_CUDA_SUCCESS ||
            (ierr = ensure_buffer(1, count, phases)) != FV_CUDA_SUCCESS ||
            (ierr = ensure_buffer(2, count, phases)) != FV_CUDA_SUCCESS) {
            return ierr;
        }
        double* d_courant = persistent_context.buffers[0].data;
        double* d_q = persistent_context.buffers[1].data;
        double* d_flux = persistent_context.buffers[2].data;
        if ((ierr = copy_to_existing_device(d_courant, courant, count, "courant", phases)) == FV_CUDA_SUCCESS &&
            (ierr = copy_to_existing_device(d_q, q, count, "q", phases)) == FV_CUDA_SUCCESS) {
            ierr = launch_and_copy_back(
                [&]() {
                    integer_flux_x_kernel<<<static_cast<int>((count + threads - 1) / threads), threads>>>(
                        nx, ny, nz, d_courant, d_q, d_flux);
                },
                flux, d_flux, count, "integer_flux_x_kernel", phases);
        }
        return ierr;
    }
    double *d_courant = nullptr, *d_q = nullptr, *d_flux = nullptr;
    if ((ierr = copy_to_device(&d_courant, courant, count, "courant")) == FV_CUDA_SUCCESS &&
        (ierr = copy_to_device(&d_q, q, count, "q")) == FV_CUDA_SUCCESS &&
        (ierr = [&]() {
             const auto start = Clock::now();
             const int status = check_cuda(
                 cudaMalloc(reinterpret_cast<void**>(&d_flux), count * sizeof(double)), "flux");
             if (profile::enabled()) phases.allocation += elapsed_seconds(start);
             return status;
         }()) == FV_CUDA_SUCCESS) {
        ierr = launch_and_copy_back(
            [&]() {
                integer_flux_x_kernel<<<static_cast<int>((count + threads - 1) / threads), threads>>>(
                    nx, ny, nz, d_courant, d_q, d_flux);
            },
            flux, d_flux, count, "integer_flux_x_kernel", phases);
    }
    free_if_present(d_courant); free_if_present(d_q); free_if_present(d_flux);
    return ierr;
}

int vanleer_x_3d_cuda(
    int nx,
    int ny,
    int nz,
    double dt,
    double dx,
    const double* c,
    bool monotone,
    const double* uc,
    const double* q,
    double* dq_dt) {
    const CudaMode mode = selected_cuda_mode();
    PhaseCall phase_call(mode);
    CudaPhaseCounter& phases = phase_call.counter();
    int ierr = validate_common(nx, ny, nz, mode);
    if (ierr != FV_CUDA_SUCCESS || c == nullptr || uc == nullptr || q == nullptr || dq_dt == nullptr) {
        return ierr == FV_CUDA_SUCCESS ? FV_CUDA_INVALID_ARGUMENT : ierr;
    }
    const std::size_t count = static_cast<std::size_t>(nx) * ny * nz;
    const int threads = 256;
    if (uses_persistent_buffers(mode)) {
        const std::pair<std::size_t, std::size_t> requests[] = {
            {0, static_cast<std::size_t>(ny)},
            {1, count},
            {2, count},
            {3, count}};
        for (const auto& request : requests) {
            ierr = ensure_buffer(request.first, request.second, phases);
            if (ierr != FV_CUDA_SUCCESS) return ierr;
        }
        double* d_c = persistent_context.buffers[0].data;
        double* d_uc = persistent_context.buffers[1].data;
        double* d_q = persistent_context.buffers[2].data;
        double* d_dq = persistent_context.buffers[3].data;
        if ((ierr = copy_to_existing_device(d_c, c, ny, "c", phases)) == FV_CUDA_SUCCESS &&
            (ierr = copy_to_existing_device(d_uc, uc, count, "uc", phases)) == FV_CUDA_SUCCESS &&
            (ierr = copy_to_existing_device(d_q, q, count, "q", phases)) == FV_CUDA_SUCCESS &&
            (ierr = copy_to_existing_device(d_dq, dq_dt, count, "dq_dt", phases)) == FV_CUDA_SUCCESS) {
            ierr = launch_and_copy_back(
                [&]() {
                    vanleer_x_kernel<<<static_cast<int>((count + threads - 1) / threads), threads>>>(
                        nx, ny, nz, dt, dx, d_c, monotone, d_uc, d_q, d_dq);
                },
                dq_dt, d_dq, count, "vanleer_x_kernel", phases);
        }
        return ierr;
    }
    double *d_c = nullptr, *d_uc = nullptr, *d_q = nullptr, *d_dq = nullptr;
    if ((ierr = copy_to_device(&d_c, c, ny, "c")) == FV_CUDA_SUCCESS &&
        (ierr = copy_to_device(&d_uc, uc, count, "uc")) == FV_CUDA_SUCCESS &&
        (ierr = copy_to_device(&d_q, q, count, "q")) == FV_CUDA_SUCCESS &&
        (ierr = copy_inout_to_device(&d_dq, dq_dt, count, "dq_dt")) == FV_CUDA_SUCCESS) {
        ierr = launch_and_copy_back(
            [&]() {
                vanleer_x_kernel<<<static_cast<int>((count + threads - 1) / threads), threads>>>(
                    nx, ny, nz, dt, dx, d_c, monotone, d_uc, d_q, d_dq);
            },
            dq_dt, d_dq, count, "vanleer_x_kernel", phases);
    }
    free_if_present(d_c); free_if_present(d_uc); free_if_present(d_q); free_if_present(d_dq);
    return ierr;
}

int slope_sphere_cuda(
    int nx,
    int nys,
    int nz,
    bool monotone,
    const double* dy_plus,
    const double* dy_minus,
    const double* q,
    double* slope) {
    const CudaMode mode = selected_cuda_mode();
    PhaseCall phase_call(mode);
    CudaPhaseCounter& phases = phase_call.counter();
    int ierr = validate_common(nx, nys, nz, mode);
    if (ierr != FV_CUDA_SUCCESS || dy_plus == nullptr || dy_minus == nullptr || q == nullptr || slope == nullptr) {
        return ierr == FV_CUDA_SUCCESS ? FV_CUDA_INVALID_ARGUMENT : ierr;
    }
    const std::size_t slope_count = static_cast<std::size_t>(nx) * nys * nz;
    const std::size_t q_count = static_cast<std::size_t>(nx) * (nys + 2) * nz;
    const int threads = 256;
    if (uses_persistent_buffers(mode)) {
        const std::pair<std::size_t, std::size_t> requests[] = {
            {0, static_cast<std::size_t>(nys)},
            {1, static_cast<std::size_t>(nys)},
            {2, q_count},
            {3, slope_count}};
        for (const auto& request : requests) {
            ierr = ensure_buffer(request.first, request.second, phases);
            if (ierr != FV_CUDA_SUCCESS) return ierr;
        }
        double* d_dy_plus = persistent_context.buffers[0].data;
        double* d_dy_minus = persistent_context.buffers[1].data;
        double* d_q = persistent_context.buffers[2].data;
        double* d_slope = persistent_context.buffers[3].data;
        if ((ierr = copy_to_existing_device(d_dy_plus, dy_plus, nys, "dy_plus", phases)) == FV_CUDA_SUCCESS &&
            (ierr = copy_to_existing_device(d_dy_minus, dy_minus, nys, "dy_minus", phases)) == FV_CUDA_SUCCESS &&
            (ierr = copy_to_existing_device(d_q, q, q_count, "q", phases)) == FV_CUDA_SUCCESS) {
            ierr = launch_and_copy_back(
                [&]() {
                    slope_sphere_kernel<<<static_cast<int>((slope_count + threads - 1) / threads), threads>>>(
                        nx, nys, nz, monotone, d_dy_plus, d_dy_minus, d_q, d_slope);
                },
                slope, d_slope, slope_count, "slope_sphere_kernel", phases);
        }
        return ierr;
    }
    double *d_dy_plus = nullptr, *d_dy_minus = nullptr, *d_q = nullptr, *d_slope = nullptr;
    if ((ierr = copy_to_device(&d_dy_plus, dy_plus, nys, "dy_plus")) == FV_CUDA_SUCCESS &&
        (ierr = copy_to_device(&d_dy_minus, dy_minus, nys, "dy_minus")) == FV_CUDA_SUCCESS &&
        (ierr = copy_to_device(&d_q, q, q_count, "q")) == FV_CUDA_SUCCESS &&
        (ierr = [&]() {
             const auto start = Clock::now();
             const int status = check_cuda(
                 cudaMalloc(reinterpret_cast<void**>(&d_slope), slope_count * sizeof(double)), "slope");
             if (profile::enabled()) phases.allocation += elapsed_seconds(start);
             return status;
         }()) == FV_CUDA_SUCCESS) {
        ierr = launch_and_copy_back(
            [&]() {
                slope_sphere_kernel<<<static_cast<int>((slope_count + threads - 1) / threads), threads>>>(
                    nx, nys, nz, monotone, d_dy_plus, d_dy_minus, d_q, d_slope);
            },
            slope, d_slope, slope_count, "slope_sphere_kernel", phases);
    }
    free_if_present(d_dy_plus); free_if_present(d_dy_minus); free_if_present(d_q); free_if_present(d_slope);
    return ierr;
}

int vanleer_sphere_3d_cuda(
    int nx,
    int ny,
    int nz,
    double dt,
    bool monotone,
    bool is_south_boundary,
    bool is_north_boundary,
    const double* c,
    const double* cc,
    const double* dy,
    const double* dy_plus,
    const double* dy_minus,
    const double* vc,
    const double* q,
    double* dq_dt) {
    const CudaMode mode = selected_cuda_mode();
    PhaseCall phase_call(mode);
    CudaPhaseCounter& phases = phase_call.counter();
    int ierr = validate_common(nx, ny, nz, mode);
    if (ierr != FV_CUDA_SUCCESS || c == nullptr || cc == nullptr || dy == nullptr ||
        dy_plus == nullptr || dy_minus == nullptr || vc == nullptr || q == nullptr || dq_dt == nullptr) {
        return ierr == FV_CUDA_SUCCESS ? FV_CUDA_INVALID_ARGUMENT : ierr;
    }
    const std::size_t dq_count = static_cast<std::size_t>(nx) * ny * nz;
    const std::size_t vc_count = static_cast<std::size_t>(nx) * (ny + 1) * nz;
    const std::size_t q_count = static_cast<std::size_t>(nx) * (ny + 4) * nz;
    const int threads = 256;
    if (uses_persistent_buffers(mode)) {
        const std::size_t metric_count = static_cast<std::size_t>(ny + 2);
        const std::pair<std::size_t, std::size_t> requests[] = {
            {0, static_cast<std::size_t>(ny)},
            {1, static_cast<std::size_t>(ny + 1)},
            {2, metric_count}, {3, metric_count}, {4, metric_count},
            {5, vc_count}, {6, q_count}, {7, dq_count}};
        for (const auto& request : requests) {
            ierr = ensure_buffer(request.first, request.second, phases);
            if (ierr != FV_CUDA_SUCCESS) return ierr;
        }
        double* d_c = persistent_context.buffers[0].data;
        double* d_cc = persistent_context.buffers[1].data;
        double* d_dy = persistent_context.buffers[2].data;
        double* d_dy_plus = persistent_context.buffers[3].data;
        double* d_dy_minus = persistent_context.buffers[4].data;
        double* d_vc = persistent_context.buffers[5].data;
        double* d_q = persistent_context.buffers[6].data;
        double* d_dq = persistent_context.buffers[7].data;
        if ((ierr = copy_to_existing_device(d_c, c, ny, "c", phases)) == FV_CUDA_SUCCESS &&
            (ierr = copy_to_existing_device(d_cc, cc, ny + 1, "cc", phases)) == FV_CUDA_SUCCESS &&
            (ierr = copy_to_existing_device(d_dy, dy, ny + 2, "dy", phases)) == FV_CUDA_SUCCESS &&
            (ierr = copy_to_existing_device(d_dy_plus, dy_plus, ny + 2, "dy_plus", phases)) == FV_CUDA_SUCCESS &&
            (ierr = copy_to_existing_device(d_dy_minus, dy_minus, ny + 2, "dy_minus", phases)) == FV_CUDA_SUCCESS &&
            (ierr = copy_to_existing_device(d_vc, vc, vc_count, "vc", phases)) == FV_CUDA_SUCCESS &&
            (ierr = copy_to_existing_device(d_q, q, q_count, "q", phases)) == FV_CUDA_SUCCESS &&
            (ierr = copy_to_existing_device(d_dq, dq_dt, dq_count, "dq_dt", phases)) == FV_CUDA_SUCCESS) {
            ierr = launch_and_copy_back(
                [&]() {
                    vanleer_sphere_kernel<<<static_cast<int>((dq_count + threads - 1) / threads), threads>>>(
                        nx, ny, nz, dt, monotone, is_south_boundary, is_north_boundary,
                        d_c, d_cc, d_dy, d_dy_plus, d_dy_minus, d_vc, d_q, d_dq);
                },
                dq_dt, d_dq, dq_count, "vanleer_sphere_kernel", phases);
        }
        return ierr;
    }
    double *d_c = nullptr, *d_cc = nullptr, *d_dy = nullptr, *d_dy_plus = nullptr, *d_dy_minus = nullptr;
    double *d_vc = nullptr, *d_q = nullptr, *d_dq = nullptr;
    if ((ierr = copy_to_device(&d_c, c, ny, "c")) == FV_CUDA_SUCCESS &&
        (ierr = copy_to_device(&d_cc, cc, ny + 1, "cc")) == FV_CUDA_SUCCESS &&
        (ierr = copy_to_device(&d_dy, dy, ny + 2, "dy")) == FV_CUDA_SUCCESS &&
        (ierr = copy_to_device(&d_dy_plus, dy_plus, ny + 2, "dy_plus")) == FV_CUDA_SUCCESS &&
        (ierr = copy_to_device(&d_dy_minus, dy_minus, ny + 2, "dy_minus")) == FV_CUDA_SUCCESS &&
        (ierr = copy_to_device(&d_vc, vc, vc_count, "vc")) == FV_CUDA_SUCCESS &&
        (ierr = copy_to_device(&d_q, q, q_count, "q")) == FV_CUDA_SUCCESS &&
        (ierr = copy_inout_to_device(&d_dq, dq_dt, dq_count, "dq_dt")) == FV_CUDA_SUCCESS) {
        ierr = launch_and_copy_back(
            [&]() {
                vanleer_sphere_kernel<<<static_cast<int>((dq_count + threads - 1) / threads), threads>>>(
                    nx, ny, nz, dt, monotone, is_south_boundary, is_north_boundary,
                    d_c, d_cc, d_dy, d_dy_plus, d_dy_minus, d_vc, d_q, d_dq);
            },
            dq_dt, d_dq, dq_count, "vanleer_sphere_kernel", phases);
    }
    free_if_present(d_c); free_if_present(d_cc); free_if_present(d_dy); free_if_present(d_dy_plus);
    free_if_present(d_dy_minus); free_if_present(d_vc); free_if_present(d_q); free_if_present(d_dq);
    return ierr;
}

bool resident_boundary_enabled() {
    return selected_cuda_mode() == CudaMode::resident;
}

// Runtime switch (env FV_ADVECTION_NCCL_HALO) for the GPU-to-GPU q1 halo path.
// Off by default, so the host-routed halo stays the reference and the same binary
// can run both for a bit-for-bit A/B. Only takes effect in resident mode built
// with FV_ADVECTION_USE_NCCL. Read once and cached.
bool nccl_halo_enabled() {
#ifdef FV_ADVECTION_USE_NCCL
    static const bool enabled = [] {
        const char* value = std::getenv("FV_ADVECTION_NCCL_HALO");
        return value != nullptr &&
               (value[0] == '1' || value[0] == 't' || value[0] == 'T' ||
                value[0] == 'y' || value[0] == 'Y');
    }();
    return enabled;
#else
    return false;
#endif
}

// Build (or confirm) the process's NCCL communicator. Returns FV_CUDA_SUCCESS on
// success. When the overlay is built without FV_ADVECTION_USE_NCCL this reports
// that GPU-to-GPU halo support was not compiled in, so a misconfigured run fails
// loudly instead of silently skipping the device exchange.
int nccl_init() {
#ifdef FV_ADVECTION_USE_NCCL
    return ensure_nccl_context();
#else
    std::fprintf(stderr,
                 "fv_advection_kernels NCCL error: this overlay was built without "
                 "FV_ADVECTION_USE_NCCL; rebuild with NCCL support to use the "
                 "GPU-to-GPU halo exchange.\n");
    return FV_CUDA_ERROR;
#endif
}

// Swap the resident q1 y-halo (buffers[3]) with the neighbor ranks on the GPU.
// Requires an active resident stage matching nx/ny/nz. This is the device-side
// stand-in for the host mpp_update_domains(q1) of the neighbor rows; the pole
// side is left for the fold. Step 4 calls this from the resident spine.
int nccl_exchange_resident_q1_halo(int nx, int ny, int nz) {
#ifdef FV_ADVECTION_USE_NCCL
    const CudaMode mode = selected_cuda_mode();
    PhaseCall phase_call(mode);
    CudaPhaseCounter& phases = phase_call.counter();
    if (mode != CudaMode::resident || !persistent_context.resident_stage_active ||
        nx != persistent_context.resident_nx || ny != persistent_context.resident_ny ||
        nz != persistent_context.resident_nz) {
        std::fprintf(stderr,
                     "fv_advection_kernels NCCL error: q1 halo exchange needs an active "
                     "resident stage matching nx/ny/nz.\n");
        return FV_CUDA_INVALID_ARGUMENT;
    }
    double* d_q1 = persistent_context.buffers[3].data;
    if (d_q1 == nullptr) {
        return FV_CUDA_INVALID_ARGUMENT;
    }
    // Standalone entry: block until the exchange is done so callers get a
    // completed halo.
    return exchange_q1_halo_nccl(d_q1, nx, ny, nz, phases, /*synchronize=*/true);
#else
    (void)nx;
    (void)ny;
    (void)nz;
    std::fprintf(stderr,
                 "fv_advection_kernels NCCL error: this overlay was built without "
                 "FV_ADVECTION_USE_NCCL; rebuild with NCCL support to use the "
                 "GPU-to-GPU halo exchange.\n");
    return FV_CUDA_ERROR;
#endif
}

// Fill this rank's pole q1 halo rows on the GPU (device-side stand-in for the
// host polar fold). is_south_boundary/is_north_boundary come from the model
// (js==1 / je==ny) and mark which poles this rank owns. Needs an active resident
// stage matching nx/ny/nz. Step 4 calls this from the resident spine.
int fold_resident_q1_poles(int nx, int ny, int nz, bool is_south_boundary,
                           bool is_north_boundary) {
#ifdef FV_ADVECTION_USE_NCCL
    const CudaMode mode = selected_cuda_mode();
    PhaseCall phase_call(mode);
    CudaPhaseCounter& phases = phase_call.counter();
    if (mode != CudaMode::resident || !persistent_context.resident_stage_active ||
        nx != persistent_context.resident_nx || ny != persistent_context.resident_ny ||
        nz != persistent_context.resident_nz) {
        std::fprintf(stderr,
                     "fv_advection_kernels NCCL error: q1 polar fold needs an active "
                     "resident stage matching nx/ny/nz.\n");
        return FV_CUDA_INVALID_ARGUMENT;
    }
    double* d_q1 = persistent_context.buffers[3].data;
    if (d_q1 == nullptr) {
        return FV_CUDA_INVALID_ARGUMENT;
    }
    // Standalone entry: block until the fold is done.
    return fold_q1_poles(d_q1, nx, ny, nz, is_south_boundary, is_north_boundary, phases,
                         /*synchronize=*/true);
#else
    (void)nx;
    (void)ny;
    (void)nz;
    (void)is_south_boundary;
    (void)is_north_boundary;
    std::fprintf(stderr,
                 "fv_advection_kernels NCCL error: this overlay was built without "
                 "FV_ADVECTION_USE_NCCL; rebuild with NCCL support to use the "
                 "GPU-to-GPU halo exchange.\n");
    return FV_CUDA_ERROR;
#endif
}

int resident_advection_begin(
    int nx,
    int ny,
    int nz,
    double half_dt,
    double dx,
    bool fold_div,
    const double* c,
    const double* cc,
    const double* dy,
    const double* dy_plus,
    const double* dy_minus,
    const double* dyy,
    const double* ua,
    const double* q,
    const double* va,
    double* q1_interior) {
    const CudaMode mode = selected_cuda_mode();
    PhaseCall phase_call(mode);
    CudaPhaseCounter& phases = phase_call.counter();
    if (mode != CudaMode::resident) return FV_CUDA_INVALID_ARGUMENT;
    int ierr = validate_common(nx, ny, nz, mode);
    if (ierr != FV_CUDA_SUCCESS || c == nullptr || cc == nullptr || dy == nullptr ||
        dy_plus == nullptr || dy_minus == nullptr || dyy == nullptr || ua == nullptr ||
        q == nullptr || va == nullptr || q1_interior == nullptr ||
        persistent_context.resident_stage_active) {
        return ierr == FV_CUDA_SUCCESS ? FV_CUDA_INVALID_ARGUMENT : ierr;
    }

    const std::size_t count = static_cast<std::size_t>(nx) * ny * nz;
    const std::size_t q1_count = static_cast<std::size_t>(nx) * (ny + 4) * nz;
    const std::size_t vc_count = static_cast<std::size_t>(nx) * (ny + 1) * nz;
    const std::size_t metric_count = static_cast<std::size_t>(ny + 2);

    // Begin uploads every metric finish needs (none re-uploaded in finish) plus
    // the haloed q and va, and produces all fields that must stay resident across
    // the boundary: q1 (interior), q2, uc, vc, and dq = q*div.
    const std::pair<std::size_t, std::size_t> requests[] = {
        {0, static_cast<std::size_t>(ny)}, {1, count}, {2, count}, {3, q1_count},
        {4, count}, {5, q1_count}, {6, static_cast<std::size_t>(ny + 1)}, {7, count},
        {8, static_cast<std::size_t>(ny + 1)}, {9, metric_count}, {10, metric_count},
        {11, metric_count}, {12, count}, {13, vc_count}, {14, q1_count}, {15, count},
        {16, count}};
    for (const auto& request : requests) {
        ierr = ensure_buffer(request.first, request.second, phases);
        if (ierr != FV_CUDA_SUCCESS) return ierr;
    }

    double* d_c = persistent_context.buffers[0].data;
    double* d_ua = persistent_context.buffers[1].data;
    double* d_q = persistent_context.buffers[2].data;
    double* d_q1 = persistent_context.buffers[3].data;
    double* d_q2 = persistent_context.buffers[4].data;
    double* d_va_halo = persistent_context.buffers[5].data;
    double* d_dyy = persistent_context.buffers[6].data;
    double* d_dq = persistent_context.buffers[7].data;
    double* d_cc = persistent_context.buffers[8].data;
    double* d_dy = persistent_context.buffers[9].data;
    double* d_dy_plus = persistent_context.buffers[10].data;
    double* d_dy_minus = persistent_context.buffers[11].data;
    double* d_uc = persistent_context.buffers[12].data;
    double* d_vc = persistent_context.buffers[13].data;
    double* d_q_halo = persistent_context.buffers[14].data;
    double* d_va = persistent_context.buffers[15].data;
    double* d_semi_dq = persistent_context.buffers[16].data;

    // The 6 grid metrics are run-constant (computed once in fv_advection_init and
    // passed as the same js:je slice every call). Nothing but begin/finish touches
    // their slots in resident mode, so upload them once and reuse across all calls;
    // re-upload only when the grid dimensions change (ensure_buffer would have
    // reallocated the slots, dropping their contents). This removes the per-call
    // H2D of the constant metrics, the residency headroom task-4 identified.
    const bool metrics_current =
        persistent_context.metrics_resident && persistent_context.metrics_nx == nx &&
        persistent_context.metrics_ny == ny && persistent_context.metrics_nz == nz;
    if (!metrics_current) {
        persistent_context.metrics_resident = false;
        if ((ierr = copy_to_existing_device(d_c, c, ny, "resident c", phases)) != FV_CUDA_SUCCESS ||
            (ierr = copy_to_existing_device(d_cc, cc, ny + 1, "resident cc", phases)) != FV_CUDA_SUCCESS ||
            (ierr = copy_to_existing_device(d_dy, dy, metric_count, "resident dy", phases)) != FV_CUDA_SUCCESS ||
            (ierr = copy_to_existing_device(d_dy_plus, dy_plus, metric_count, "resident dy_plus", phases)) != FV_CUDA_SUCCESS ||
            (ierr = copy_to_existing_device(d_dy_minus, dy_minus, metric_count, "resident dy_minus", phases)) != FV_CUDA_SUCCESS ||
            (ierr = copy_to_existing_device(d_dyy, dyy, ny + 1, "resident dyy", phases)) != FV_CUDA_SUCCESS) {
            return ierr;
        }
        persistent_context.metrics_resident = true;
        persistent_context.metrics_nx = nx;
        persistent_context.metrics_ny = ny;
        persistent_context.metrics_nz = nz;
    }

    // q and va arrive haloed (nx*(ny+4)*nz). semi_y and vc read the y-halo; the
    // x-direction kernels and uc/div use the interior, stripped device-side (D2D,
    // no extra host transfer). These fields are time-varying, so upload every call.
    if ((ierr = copy_to_existing_device(d_q_halo, q, q1_count, "resident q halo", phases)) != FV_CUDA_SUCCESS ||
        (ierr = copy_to_existing_device(d_va_halo, va, q1_count, "resident va halo", phases)) != FV_CUDA_SUCCESS ||
        (ierr = copy_to_existing_device(d_ua, ua, count, "resident ua", phases)) != FV_CUDA_SUCCESS) {
        return ierr;
    }
    // Strip the ny interior rows {2..ny+1} of the haloed q and va into d_q / d_va.
    const std::size_t int_pitch = static_cast<std::size_t>(nx) * ny * sizeof(double);
    const std::size_t halo_pitch = static_cast<std::size_t>(nx) * (ny + 4) * sizeof(double);
    ierr = check_cuda(
        cudaMemcpy2D(d_q, int_pitch, d_q_halo + 2 * nx, halo_pitch,
                     static_cast<std::size_t>(nx) * ny * sizeof(double), nz,
                     cudaMemcpyDeviceToDevice),
        "resident q interior strip");
    if (ierr == FV_CUDA_SUCCESS) {
        ierr = check_cuda(
            cudaMemcpy2D(d_va, int_pitch, d_va_halo + 2 * nx, halo_pitch,
                         static_cast<std::size_t>(nx) * ny * sizeof(double), nz,
                         cudaMemcpyDeviceToDevice),
            "resident va interior strip");
    }
    if (ierr != FV_CUDA_SUCCESS) return ierr;

    const bool timing = profile::enabled();
    if (timing && (ierr = ensure_timing_events()) == FV_CUDA_SUCCESS) {
        ierr = check_cuda(cudaEventRecord(timing_events.start), "resident begin event start");
    }

    // Phase B: swap the qx (q) and vx (va) y-halos GPU-to-GPU over NCCL and fold
    // the poles on the device, so the host skips mpp_update_domains(vx)/(qx) and
    // their polar folds in a_grid_horiz_advection. Both fields share the resident
    // q1 slot layout (nx*(ny+4)*nz), so the same exchange serves them. semi_x and
    // form_q1 read only the stripped interior, so they run without waiting; the
    // compute stream waits on halo_done just before semi_y (reads the q halo) and
    // compute_vc (reads the va halo). Pole sides come from the NCCL neighbors:
    // south/north < 0 marks a pole, which reflects instead of exchanging. qx folds
    // symmetrically (same as q1); vx flips sign (a wind reflected across the pole).
#ifdef FV_ADVECTION_USE_NCCL
    const bool device_halo = nccl_halo_enabled();
    if (ierr == FV_CUDA_SUCCESS && device_halo) {
        const bool fold_south = nccl_context.south < 0;
        const bool fold_north = nccl_context.north < 0;
        ierr = exchange_q1_halo_nccl(d_q_halo, nx, ny, nz, phases, /*synchronize=*/false);
        if (ierr == FV_CUDA_SUCCESS) {
            ierr = exchange_q1_halo_nccl(d_va_halo, nx, ny, nz, phases, /*synchronize=*/false);
        }
        if (ierr == FV_CUDA_SUCCESS) {
            ierr = fold_q1_poles(d_q_halo, nx, ny, nz, fold_south, fold_north, phases,
                                 /*synchronize=*/false);
        }
        if (ierr == FV_CUDA_SUCCESS) {
            ierr = fold_vx_poles(d_va_halo, nx, ny, nz, fold_south, fold_north, phases,
                                 /*synchronize=*/false);
        }
    }
#endif

    const int threads = 256;
    const int blocks = static_cast<int>((count + threads - 1) / threads);
    if (ierr == FV_CUDA_SUCCESS) {
        semi_x_kernel<<<blocks, threads>>>(nx, ny, nz, half_dt, dx, d_c, d_ua, d_q,
                                           d_semi_dq);
        ierr = check_cuda(cudaGetLastError(), "resident semi_x_kernel");
    }
    if (ierr == FV_CUDA_SUCCESS) {
        form_q1_with_halo_kernel<<<blocks, threads>>>(nx, ny, nz, d_q, d_semi_dq, d_q1);
        ierr = check_cuda(cudaGetLastError(), "resident form_q1_with_halo_kernel");
    }

#ifdef FV_ADVECTION_USE_NCCL
    // The q/va halos feed semi_y and compute_vc below; wait for the GPU-to-GPU
    // exchange to land before the first kernel that reads them. The folds already
    // ran on the compute stream, so only the NCCL exchange needs the cross-stream
    // wait (halo_done was recorded after the last unpack).
    if (ierr == FV_CUDA_SUCCESS && device_halo &&
        (nccl_context.south >= 0 || nccl_context.north >= 0)) {
        ierr = check_cuda(cudaStreamWaitEvent(0, nccl_context.halo_done, 0),
                          "resident begin wait halo");
    }
#endif

    // q2 = q + semi_y(q): semi_y reads the haloed q (not q1), matching the
    // Fortran cross term; form_q2 adds the field back.
    if (ierr == FV_CUDA_SUCCESS) {
        ierr = fv_advection::cuda_backend::semi_y_3d_cuda(nx, 1, ny, nz, half_dt, d_va, d_q_halo, d_dyy, d_semi_dq);
    }
    if (ierr == FV_CUDA_SUCCESS) {
        form_q2_kernel<<<blocks, threads>>>(nx, ny, nz, d_q, d_semi_dq, d_q2);
        ierr = check_cuda(cudaGetLastError(), "resident form_q2_kernel");
    }

    // Divergence pre-step, folded onto the device: uc (x-avg of ua), vc (y-avg of
    // the haloed va), then dq = q*div. With flux mode (fold_div false) the host
    // skips the div term, so dq starts at zero.
    if (ierr == FV_CUDA_SUCCESS) {
        compute_uc_kernel<<<blocks, threads>>>(nx, ny, nz, d_ua, d_uc);
        ierr = check_cuda(cudaGetLastError(), "resident compute_uc_kernel");
    }
    if (ierr == FV_CUDA_SUCCESS) {
        const int vc_blocks = static_cast<int>((vc_count + threads - 1) / threads);
        compute_vc_kernel<<<vc_blocks, threads>>>(nx, ny, nz, d_va_halo, d_vc);
        ierr = check_cuda(cudaGetLastError(), "resident compute_vc_kernel");
    }
    if (ierr == FV_CUDA_SUCCESS) {
        if (fold_div) {
            div_qdiv_kernel<<<blocks, threads>>>(nx, ny, nz, dx, d_c, d_cc, d_dy,
                                                 d_uc, d_vc, d_q, d_dq);
            ierr = check_cuda(cudaGetLastError(), "resident div_qdiv_kernel");
        } else {
            ierr = check_cuda(cudaMemset(d_dq, 0, count * sizeof(double)),
                              "resident dq zero");
        }
    }

    if (ierr == FV_CUDA_SUCCESS && timing) {
        ierr = check_cuda(cudaEventRecord(timing_events.stop), "resident begin event stop");
    }
    const auto sync_start = Clock::now();
    if (ierr == FV_CUDA_SUCCESS) {
        ierr = timing ? check_cuda(cudaEventSynchronize(timing_events.stop), "resident begin sync")
                      : check_cuda(cudaDeviceSynchronize(), "resident begin sync");
    }
    if (timing) {
        phases.sync += elapsed_seconds(sync_start);
        if (ierr == FV_CUDA_SUCCESS) {
            float milliseconds = 0.0f;
            ierr = check_cuda(cudaEventElapsedTime(&milliseconds, timing_events.start,
                                                   timing_events.stop),
                              "resident begin elapsed");
            phases.kernel += static_cast<double>(milliseconds) * 1.0e-3;
        }
    }
    // Halo-only residency: the device interior of q1 stays authoritative across
    // begin -> finish, so only the two edge interior rows per side need to reach
    // the host. mpp_update_domains sends those rows to neighbors and the polar
    // fold reads rows {1,2} / {ny-1,ny} from them; the deep interior is never
    // touched host-side before resident_advection_finish uploads the halo back.
    // With the GPU-to-GPU halo path on, the neighbor swap and fold happen on the
    // device in finish, so these edge rows never need to reach the host.
    if (ierr == FV_CUDA_SUCCESS && !nccl_halo_enabled()) {
        const std::size_t host_pitch = static_cast<std::size_t>(nx) * ny * sizeof(double);
        const std::size_t dev_pitch = static_cast<std::size_t>(nx) * (ny + 4) * sizeof(double);
        const std::size_t edge_width = static_cast<std::size_t>(nx) * 2 * sizeof(double);
        const auto copy_start = Clock::now();
        // South edge: host rows {0,1} <- device interior rows {2,3}.
        ierr = check_cuda(
            cudaMemcpy2D(q1_interior, host_pitch, d_q1 + 2 * nx, dev_pitch,
                         edge_width, nz, cudaMemcpyDeviceToHost),
            "resident q1 south edge to host");
        if (ierr == FV_CUDA_SUCCESS) {
            // North edge: host rows {ny-2,ny-1} <- device interior rows {ny,ny+1}.
            ierr = check_cuda(
                cudaMemcpy2D(q1_interior + static_cast<std::size_t>(ny - 2) * nx, host_pitch,
                             d_q1 + static_cast<std::size_t>(ny) * nx, dev_pitch,
                             edge_width, nz, cudaMemcpyDeviceToHost),
                "resident q1 north edge to host");
        }
        if (timing) phases.d2h += elapsed_seconds(copy_start);
    }
    if (ierr == FV_CUDA_SUCCESS) {
        persistent_context.resident_stage_active = true;
        persistent_context.resident_nx = nx;
        persistent_context.resident_ny = ny;
        persistent_context.resident_nz = nz;
    }
    return ierr;
}

int resident_advection_finish(
    int nx,
    int ny,
    int nz,
    double dt,
    double dx,
    bool monotone,
    bool is_south_boundary,
    bool is_north_boundary,
    const double* q1,
    double* dq_dt) {
    const CudaMode mode = selected_cuda_mode();
    PhaseCall phase_call(mode);
    CudaPhaseCounter& phases = phase_call.counter();
    if (mode != CudaMode::resident || !persistent_context.resident_stage_active ||
        nx != persistent_context.resident_nx || ny != persistent_context.resident_ny ||
        nz != persistent_context.resident_nz) {
        return FV_CUDA_INVALID_ARGUMENT;
    }
    int ierr = validate_common(nx, ny, nz, mode);
    if (ierr != FV_CUDA_SUCCESS || q1 == nullptr || dq_dt == nullptr) {
        persistent_context.resident_stage_active = false;
        return ierr == FV_CUDA_SUCCESS ? FV_CUDA_INVALID_ARGUMENT : ierr;
    }

    const std::size_t count = static_cast<std::size_t>(nx) * ny * nz;

    // c, cc, dy, dy_plus, dy_minus, uc, vc, and dq are all resident from begin;
    // finish uploads nothing but the q1 halo rows and reads the rest from device.
    double* d_c = persistent_context.buffers[0].data;
    double* d_q1 = persistent_context.buffers[3].data;
    double* d_q2 = persistent_context.buffers[4].data;
    double* d_dq = persistent_context.buffers[7].data;
    double* d_cc = persistent_context.buffers[8].data;
    double* d_dy = persistent_context.buffers[9].data;
    double* d_dy_plus = persistent_context.buffers[10].data;
    double* d_dy_minus = persistent_context.buffers[11].data;
    double* d_uc = persistent_context.buffers[12].data;
    double* d_vc = persistent_context.buffers[13].data;

    const bool device_halo = nccl_halo_enabled();
    const bool timing = profile::enabled();
    if (ierr == FV_CUDA_SUCCESS && timing) {
        ierr = ensure_timing_events();
    }
    // Device path: open the timing window before the halo work so the event
    // window covers the NCCL exchange and the fold as well as the flux kernels.
    // The host path opens it after the upload (below) so the h2d cost stays in
    // the h2d counter, not the kernel window.
    if (ierr == FV_CUDA_SUCCESS && timing && device_halo) {
        ierr = check_cuda(cudaEventRecord(timing_events.start, 0),
                          "resident finish event start");
    }

    // Halo-only residency: d_q1's interior is still valid from resident_begin, so
    // only the two halo rows per side need to be filled before the sphere flux
    // kernel reads them.
    if (ierr == FV_CUDA_SUCCESS && device_halo) {
#ifdef FV_ADVECTION_USE_NCCL
        // GPU-to-GPU path: swap the neighbor rows over NCCL and fold the poles,
        // all on the device. No host round-trip; the host q1 argument is unused.
        // Neither call blocks the host: the exchange records halo_done on the
        // NCCL stream, the fold runs on the compute stream (overlapping the
        // exchange), and the compute stream waits on halo_done just before the
        // sphere flux kernel reads the halo (below).
        ierr = exchange_q1_halo_nccl(d_q1, nx, ny, nz, phases, /*synchronize=*/false);
        if (ierr == FV_CUDA_SUCCESS) {
            ierr = fold_q1_poles(d_q1, nx, ny, nz, is_south_boundary, is_north_boundary,
                                 phases, /*synchronize=*/false);
        }
#endif
    } else if (ierr == FV_CUDA_SUCCESS) {
        // Host path: the halo rows were filled host-side by mpp_update_domains and
        // the polar fold; upload them. Layout matches device d_q1 (halo offset 2),
        // so rows map 1:1.
        const std::size_t pitch = static_cast<std::size_t>(nx) * (ny + 4) * sizeof(double);
        const std::size_t halo_width = static_cast<std::size_t>(nx) * 2 * sizeof(double);
        const auto copy_start = Clock::now();
        // South halo: device/host rows {0,1}.
        ierr = check_cuda(
            cudaMemcpy2D(d_q1, pitch, q1, pitch, halo_width, nz, cudaMemcpyHostToDevice),
            "resident q1 south halo to device");
        if (ierr == FV_CUDA_SUCCESS) {
            // North halo: device/host rows {ny+2,ny+3}.
            ierr = check_cuda(
                cudaMemcpy2D(d_q1 + static_cast<std::size_t>(ny + 2) * nx, pitch,
                             q1 + static_cast<std::size_t>(ny + 2) * nx, pitch,
                             halo_width, nz, cudaMemcpyHostToDevice),
                "resident q1 north halo to device");
        }
        if (profile::enabled()) phases.h2d += elapsed_seconds(copy_start);
    }

    // Host path: open the timing window after the upload (the device path
    // already opened it before the halo work).
    if (ierr == FV_CUDA_SUCCESS && timing && !device_halo) {
        ierr = check_cuda(cudaEventRecord(timing_events.start), "resident finish event start");
    }
    const int threads = 256;
    const int blocks = static_cast<int>((count + threads - 1) / threads);
    if (ierr == FV_CUDA_SUCCESS) {
        // vanleer_x reads d_q2/d_uc/d_dq, not the q1 halo, so it can run on the
        // compute stream while the NCCL exchange is still in flight.
        vanleer_x_kernel<<<blocks, threads>>>(nx, ny, nz, dt, dx, d_c, monotone,
                                              d_uc, d_q2, d_dq);
        ierr = check_cuda(cudaGetLastError(), "resident vanleer_x_kernel");
    }
#ifdef FV_ADVECTION_USE_NCCL
    // The sphere flux kernel below reads the neighbor halo rows filled on the
    // NCCL stream, so the compute stream must wait for the exchange first. Only
    // needed when this rank actually exchanged (has a neighbor).
    if (ierr == FV_CUDA_SUCCESS && device_halo &&
        (nccl_context.south >= 0 || nccl_context.north >= 0)) {
        ierr = check_cuda(cudaStreamWaitEvent(0, nccl_context.halo_done, 0),
                          "resident finish wait halo");
    }
#endif
    if (ierr == FV_CUDA_SUCCESS) {
        vanleer_sphere_kernel<<<blocks, threads>>>(
            nx, ny, nz, dt, monotone, is_south_boundary, is_north_boundary,
            d_c, d_cc, d_dy, d_dy_plus, d_dy_minus, d_vc, d_q1, d_dq);
        ierr = check_cuda(cudaGetLastError(), "resident vanleer_sphere_kernel");
    }
    if (ierr == FV_CUDA_SUCCESS && timing) {
        ierr = check_cuda(cudaEventRecord(timing_events.stop), "resident finish event stop");
    }
    const auto sync_start = Clock::now();
    if (ierr == FV_CUDA_SUCCESS) {
        ierr = timing ? check_cuda(cudaEventSynchronize(timing_events.stop), "resident finish sync")
                      : check_cuda(cudaDeviceSynchronize(), "resident finish sync");
    }
    if (timing) {
        phases.sync += elapsed_seconds(sync_start);
        if (ierr == FV_CUDA_SUCCESS) {
            float milliseconds = 0.0f;
            ierr = check_cuda(cudaEventElapsedTime(&milliseconds, timing_events.start,
                                                   timing_events.stop),
                              "resident finish elapsed");
            phases.kernel += static_cast<double>(milliseconds) * 1.0e-3;
        }
    }
    if (ierr == FV_CUDA_SUCCESS) {
        const auto copy_start = Clock::now();
        ierr = check_cuda(cudaMemcpy(dq_dt, d_dq, count * sizeof(double),
                                     cudaMemcpyDeviceToHost),
                          "resident dq_dt to host");
        if (timing) phases.d2h += elapsed_seconds(copy_start);
    }
    persistent_context.resident_stage_active = false;
    return ierr;
}

}  // namespace cuda_backend
}  // namespace fv_advection_kernels

extern "C" int fv_semi_x_3d_cuda_c(
    int nx,
    int js,
    int je,
    int nz,
    double dt,
    double dx,
    const double* c,
    const double* ua,
    const double* q,
    double* dq) {
    register_cuda_profile_report();
    profile::ScopedTimer timer(semi_x_counter);
    return fv_advection_kernels::cuda_backend::semi_x_3d_cuda(
        nx, je - js + 1, nz, dt, dx, c, ua, q, dq);
}

extern "C" int fv_slope_x_cuda_c(
    int nx,
    int js,
    int je,
    int nz,
    int monotone,
    const double* q,
    double* slope) {
    register_cuda_profile_report();
    profile::ScopedTimer timer(slope_x_counter);
    return fv_advection_kernels::cuda_backend::slope_x_cuda(
        nx, je - js + 1, nz, monotone != 0, q, slope);
}

extern "C" int fv_integer_flux_x_cuda_c(
    int nx,
    int js,
    int je,
    int nz,
    const double* courant,
    const double* q,
    double* flux) {
    register_cuda_profile_report();
    profile::ScopedTimer timer(integer_flux_x_counter);
    return fv_advection_kernels::cuda_backend::integer_flux_x_cuda(
        nx, je - js + 1, nz, courant, q, flux);
}

extern "C" int fv_vanleer_x_3d_cuda_c(
    int nx,
    int js,
    int je,
    int nz,
    double dt,
    double dx,
    const double* c,
    int monotone,
    const double* uc,
    const double* q,
    double* dq_dt) {
    register_cuda_profile_report();
    profile::ScopedTimer timer(vanleer_x_counter);
    return fv_advection_kernels::cuda_backend::vanleer_x_3d_cuda(
        nx, je - js + 1, nz, dt, dx, c, monotone != 0, uc, q, dq_dt);
}

extern "C" int fv_slope_sphere_cuda_c(
    int nx,
    int js,
    int je,
    int nz,
    int monotone,
    const double* dy_plus,
    const double* dy_minus,
    const double* q,
    double* slope) {
    register_cuda_profile_report();
    profile::ScopedTimer timer(slope_sphere_counter);
    return fv_advection_kernels::cuda_backend::slope_sphere_cuda(
        nx, je - js + 3, nz, monotone != 0, dy_plus, dy_minus, q, slope);
}

extern "C" int fv_vanleer_sphere_3d_cuda_c(
    int nx,
    int ny_total,
    int js,
    int je,
    int nz,
    double dt,
    int monotone,
    const double* c,
    const double* cc,
    const double* dy,
    const double* dy_plus,
    const double* dy_minus,
    const double* vc,
    const double* q,
    double* dq_dt) {
    register_cuda_profile_report();
    profile::ScopedTimer timer(vanleer_sphere_counter);
    return fv_advection_kernels::cuda_backend::vanleer_sphere_3d_cuda(
        nx, je - js + 1, nz, dt, monotone != 0, js == 1,
        je == ny_total, c, cc, dy, dy_plus, dy_minus, vc, q, dq_dt);
}

extern "C" int fv_advection_resident_enabled_cuda_c() {
    return fv_advection_kernels::cuda_backend::resident_boundary_enabled() ? 1 : 0;
}

extern "C" int fv_advection_resident_begin_cuda_c(
    int nx,
    int js,
    int je,
    int nz,
    double half_dt,
    double dx,
    int fold_div,
    const double* c,
    const double* cc,
    const double* dy,
    const double* dy_plus,
    const double* dy_minus,
    const double* dyy,
    const double* ua,
    const double* q,
    const double* va,
    double* q1_interior) {
    register_cuda_profile_report();
    profile::ScopedTimer timer(resident_begin_counter);
    return fv_advection_kernels::cuda_backend::resident_advection_begin(
        nx, je - js + 1, nz, half_dt, dx, fold_div != 0, c, cc, dy, dy_plus,
        dy_minus, dyy, ua, q, va, q1_interior);
}

extern "C" int fv_advection_resident_finish_cuda_c(
    int nx,
    int ny_total,
    int js,
    int je,
    int nz,
    double dt,
    double dx,
    int monotone,
    const double* q1,
    double* dq_dt) {
    register_cuda_profile_report();
    profile::ScopedTimer timer(resident_finish_counter);
    return fv_advection_kernels::cuda_backend::resident_advection_finish(
        nx, je - js + 1, nz, dt, dx, monotone != 0, js == 1,
        je == ny_total, q1, dq_dt);
}

extern "C" int fv_advection_nccl_init_cuda_c() {
    register_cuda_profile_report();
    return fv_advection_kernels::cuda_backend::nccl_init();
}

extern "C" int fv_advection_nccl_exchange_q1_halo_cuda_c(int nx, int ny, int nz) {
    register_cuda_profile_report();
    return fv_advection_kernels::cuda_backend::nccl_exchange_resident_q1_halo(nx, ny, nz);
}

extern "C" int fv_advection_nccl_fold_q1_poles_cuda_c(int nx, int ny, int nz,
                                                      int is_south_boundary,
                                                      int is_north_boundary) {
    register_cuda_profile_report();
    return fv_advection_kernels::cuda_backend::fold_resident_q1_poles(
        nx, ny, nz, is_south_boundary != 0, is_north_boundary != 0);
}

extern "C" int fv_advection_nccl_halo_enabled_cuda_c() {
    return fv_advection_kernels::cuda_backend::nccl_halo_enabled() ? 1 : 0;
}
