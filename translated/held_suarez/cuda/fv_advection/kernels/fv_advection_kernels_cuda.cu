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
    if (ierr == FV_CUDA_SUCCESS) {
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

    // Halo-only residency: d_q1's interior is still valid from resident_begin, so
    // only the two halo rows per side (filled host-side by mpp_update_domains and
    // the polar fold) need to be uploaded. Layout matches device d_q1 (halo
    // offset 2), so rows map 1:1.
    if (ierr == FV_CUDA_SUCCESS) {
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

    const bool timing = profile::enabled();
    if (ierr == FV_CUDA_SUCCESS && timing && (ierr = ensure_timing_events()) == FV_CUDA_SUCCESS) {
        ierr = check_cuda(cudaEventRecord(timing_events.start), "resident finish event start");
    }
    const int threads = 256;
    const int blocks = static_cast<int>((count + threads - 1) / threads);
    if (ierr == FV_CUDA_SUCCESS) {
        vanleer_x_kernel<<<blocks, threads>>>(nx, ny, nz, dt, dx, d_c, monotone,
                                              d_uc, d_q2, d_dq);
        ierr = check_cuda(cudaGetLastError(), "resident vanleer_x_kernel");
    }
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
