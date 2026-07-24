#include "fv_advection_kernels_cuda.h"
#include "fv_advection_kernel_profile.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cuda_runtime.h>

namespace {

namespace profile = fv_advection_kernels_profile;

profile::Counter semi_x_counter{"semi_x_3d", 0, 0.0};
profile::Counter slope_x_counter{"slope_x", 0, 0.0};
profile::Counter integer_flux_x_counter{"integer_flux_x", 0, 0.0};
profile::Counter vanleer_x_counter{"vanleer_x_3d", 0, 0.0};
profile::Counter slope_sphere_counter{"slope_sphere", 0, 0.0};
profile::Counter vanleer_sphere_counter{"vanleer_sphere_3d", 0, 0.0};
profile::Counter advection_predictor_counter{"advection_sphere_predictor", 0, 0.0};
profile::Counter advection_corrector_counter{"advection_sphere_corrector", 0, 0.0};
profile::Counter a_grid_stage1_counter{"a_grid_advection_stage1", 0, 0.0};
profile::Counter a_grid_stage2_counter{"a_grid_advection_stage2", 0, 0.0};
profile::Counter cuda_alloc_counter{"cuda_alloc_resize", 0, 0.0};
profile::Counter cuda_h2d_counter{"cuda_h2d", 0, 0.0};
profile::Counter cuda_d2h_counter{"cuda_d2h", 0, 0.0};
profile::Counter cuda_sync_counter{"cuda_sync", 0, 0.0};

void print_cuda_runtime_banner_once() {
    static bool printed = false;
    if (printed) {
        return;
    }
    std::fprintf(stdout,
                 "FV_CUDA_RUNTIME version=a_grid_stage_cuda_resident_20260724 "
                 "features=clean-build-required,a_grid_stage1,a_grid_stage2,resident_uc_vc_q2_dq\n");
    std::fflush(stdout);
    printed = true;
}

void print_cuda_profile() {
    profile::print_counter("cuda", semi_x_counter);
    profile::print_counter("cuda", slope_x_counter);
    profile::print_counter("cuda", integer_flux_x_counter);
    profile::print_counter("cuda", vanleer_x_counter);
    profile::print_counter("cuda", slope_sphere_counter);
    profile::print_counter("cuda", vanleer_sphere_counter);
    profile::print_counter("cuda", advection_predictor_counter);
    profile::print_counter("cuda", advection_corrector_counter);
    profile::print_counter("cuda", a_grid_stage1_counter);
    profile::print_counter("cuda", a_grid_stage2_counter);
    profile::print_counter("cuda", cuda_alloc_counter);
    profile::print_counter("cuda", cuda_h2d_counter);
    profile::print_counter("cuda", cuda_d2h_counter);
    profile::print_counter("cuda", cuda_sync_counter);
}

void register_cuda_profile_report() {
    print_cuda_runtime_banner_once();
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

struct DeviceBuffer {
    double* ptr = nullptr;
    std::size_t capacity = 0;
    const double* cached_host = nullptr;
    std::size_t cached_count = 0;

    ~DeviceBuffer() {
        if (ptr != nullptr) {
            cudaFree(ptr);
        }
    }

    int ensure(std::size_t count, const char* name) {
        if (count <= capacity) {
            return FV_CUDA_SUCCESS;
        }
        profile::ScopedTimer timer(cuda_alloc_counter);
        if (ptr != nullptr) {
            cudaFree(ptr);
            ptr = nullptr;
            capacity = 0;
            cached_host = nullptr;
            cached_count = 0;
        }
        const int ierr =
            check_cuda(cudaMalloc(reinterpret_cast<void**>(&ptr), count * sizeof(double)),
                       name);
        if (ierr == FV_CUDA_SUCCESS) {
            capacity = count;
        }
        return ierr;
    }

    int copy_from_host(const double* src, std::size_t count, const char* name) {
        if (src == nullptr) {
            std::fprintf(stderr, "fv_advection_kernels CUDA error: null input pointer %s\n", name);
            return FV_CUDA_INVALID_ARGUMENT;
        }
        int ierr = ensure(count, name);
        if (ierr != FV_CUDA_SUCCESS) {
            return ierr;
        }
        profile::ScopedTimer timer(cuda_h2d_counter);
        return check_cuda(cudaMemcpy(ptr, src, count * sizeof(double), cudaMemcpyHostToDevice),
                          name);
    }

    int copy_static_from_host(const double* src, std::size_t count, const char* name) {
        if (src == nullptr) {
            std::fprintf(stderr, "fv_advection_kernels CUDA error: null input pointer %s\n", name);
            return FV_CUDA_INVALID_ARGUMENT;
        }
        // Grid metrics are initialized once by the Fortran model and reused
        // for every timestep. Avoid recopying them when the same host storage
        // is passed repeatedly.
        if (src == cached_host && count == cached_count && count <= capacity) {
            return FV_CUDA_SUCCESS;
        }
        const int ierr = copy_from_host(src, count, name);
        if (ierr == FV_CUDA_SUCCESS) {
            cached_host = src;
            cached_count = count;
        }
        return ierr;
    }

    int copy_to_host(double* dst, std::size_t count, const char* name) {
        if (dst == nullptr) {
            std::fprintf(stderr, "fv_advection_kernels CUDA error: null output pointer %s\n", name);
            return FV_CUDA_INVALID_ARGUMENT;
        }
        profile::ScopedTimer timer(cuda_d2h_counter);
        return check_cuda(cudaMemcpy(dst, ptr, count * sizeof(double), cudaMemcpyDeviceToHost),
                          name);
    }
};

struct ResidentFusedAdvectionState {
    DeviceBuffer uc;
    DeviceBuffer vc;
    DeviceBuffer dq;
    DeviceBuffer q2;
    int nx = 0;
    int ny = 0;
    int nz = 0;
    bool q2_valid = false;
};

ResidentFusedAdvectionState& resident_fused_advection_state() {
    static thread_local ResidentFusedAdvectionState state;
    return state;
}

int check_device_available() {
    static int cached_status = -1;
    if (cached_status >= 0) {
        return cached_status;
    }
    int device_count = 0;
    int ierr = check_cuda(cudaGetDeviceCount(&device_count), "cudaGetDeviceCount");
    if (ierr != FV_CUDA_SUCCESS) {
        cached_status = ierr;
        return ierr;
    }
    if (device_count <= 0) {
        std::fprintf(stderr,
                     "fv_advection_kernels CUDA error: CUDA backend requested but no CUDA devices are available.\n");
        cached_status = FV_CUDA_ERROR;
        return FV_CUDA_ERROR;
    }
    cached_status = FV_CUDA_SUCCESS;
    return FV_CUDA_SUCCESS;
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

__global__ void advection_predictor_kernel(
    int nx,
    int ny,
    int nz,
    double half_dt,
    double dx,
    const double* c,
    const double* dyy,
    const double* ua,
    const double* va,
    const double* q,
    double* q1,
    double* q2) {
    const int size = nx * ny * nz;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= size) {
        return;
    }

    const int q_ny = ny + 4;
    const int plane = nx * ny;
    const int k0 = idx / plane;
    const int rem = idx - k0 * plane;
    const int j0 = rem / nx;
    const int i0 = rem - j0 * nx;
    const int qj = j0 + 2;
    const double q_center = q[idx3(i0, qj, k0, nx, q_ny)];

    const double bx = ua[idx] * half_dt / (dx * c[j0]);
    int ii = i0;
    ii -= static_cast<int>(floor(bx));
    if (ii > nx) {
        ii -= nx;
    }
    if (ii < 1) {
        ii += nx;
    }
    const int left = ii - 1;
    const int right = (left + 1 >= nx) ? 0 : left + 1;
    const double bb = bx - floor(bx);
    const double dq_x = bb * q[idx3(left, qj, k0, nx, q_ny)] +
                        (1.0 - bb) * q[idx3(right, qj, k0, nx, q_ny)] -
                        q_center;
    q1[idx3(i0, qj, k0, nx, q_ny)] = q_center + dq_x;

    const double va_val = va[idx];
    double dq_y;
    if (va_val >= 0.0) {
        dq_y = va_val * half_dt *
               (q[idx3(i0, qj - 1, k0, nx, q_ny)] - q_center) / dyy[j0];
    } else {
        dq_y = va_val * half_dt *
               (q_center - q[idx3(i0, qj + 1, k0, nx, q_ny)]) / dyy[j0 + 1];
    }
    q2[idx] = q_center + dq_y;
}

__global__ void a_grid_stage1_kernel(
    int nx,
    int ny,
    int nz,
    double half_dt,
    double dx,
    bool flux_only,
    const double* c,
    const double* cc,
    const double* dy,
    const double* dyy,
    const double* ua,
    const double* vx,
    const double* qx,
    double* uc,
    double* vc,
    double* dq_dt,
    double* q1,
    double* q2) {
    const int center_size = nx * ny * nz;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    const int halo_ny = ny + 4;
    if (idx >= center_size) {
        return;
    }

    const int center_plane = nx * ny;
    const int k0 = idx / center_plane;
    const int rem = idx - k0 * center_plane;
    const int j0 = rem / nx;
    const int i0 = rem - j0 * nx;
    const int im = (i0 == 0) ? nx - 1 : i0 - 1;
    const int ip = (i0 == nx - 1) ? 0 : i0 + 1;
    const int qj = j0 + 2;

    const double uc_val = 0.5 * (ua[idx3(im, j0, k0, nx, ny)] +
                                 ua[idx3(i0, j0, k0, nx, ny)]);
    uc[idx] = uc_val;

    const double q_center = qx[idx3(i0, qj, k0, nx, halo_ny)];
    if (!flux_only) {
        const double y_div =
            (vc[idx3(i0, j0 + 1, k0, nx, ny + 1)] * cc[j0 + 1] -
             vc[idx3(i0, j0, k0, nx, ny + 1)] * cc[j0]) /
            (c[j0] * dy[j0 + 1]);
        const double x_div =
            (0.5 * (ua[idx3(i0, j0, k0, nx, ny)] +
                    ua[idx3(ip, j0, k0, nx, ny)]) -
             uc_val) /
            (c[j0] * dx);
        dq_dt[idx] += q_center * (y_div + x_div);
    }

    const double bx = ua[idx] * half_dt / (dx * c[j0]);
    int ii = i0;
    ii -= static_cast<int>(floor(bx));
    if (ii > nx) {
        ii -= nx;
    }
    if (ii < 1) {
        ii += nx;
    }
    const int left = ii - 1;
    const int right = (left + 1 >= nx) ? 0 : left + 1;
    const double bb = bx - floor(bx);
    const double dq_x = bb * qx[idx3(left, qj, k0, nx, halo_ny)] +
                        (1.0 - bb) * qx[idx3(right, qj, k0, nx, halo_ny)] -
                        q_center;
    q1[idx3(i0, qj, k0, nx, halo_ny)] = q_center + dq_x;

    const double va_val = vx[idx3(i0, qj, k0, nx, halo_ny)];
    double dq_y;
    if (va_val >= 0.0) {
        dq_y = va_val * half_dt *
               (qx[idx3(i0, qj - 1, k0, nx, halo_ny)] - q_center) / dyy[j0];
    } else {
        dq_y = va_val * half_dt *
               (q_center - qx[idx3(i0, qj + 1, k0, nx, halo_ny)]) / dyy[j0 + 1];
    }
    q2[idx] = q_center + dq_y;
}

__global__ void a_grid_setup_vc_kernel(
    int nx,
    int ny,
    int nz,
    const double* vx,
    double* vc) {
    const int vc_size = nx * (ny + 1) * nz;
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= vc_size) {
        return;
    }
    const int halo_ny = ny + 4;
    const int vc_plane = nx * (ny + 1);
    const int k0 = idx / vc_plane;
    const int rem = idx - k0 * vc_plane;
    const int j0 = rem / nx;
    const int i0 = rem - j0 * nx;
    vc[idx] = 0.5 * (vx[idx3(i0, j0 + 1, k0, nx, halo_ny)] +
                     vx[idx3(i0, j0 + 2, k0, nx, halo_ny)]);
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

int launch_and_copy_back(
    double* host_out,
    DeviceBuffer& device_out,
    std::size_t count,
    const char* kernel_name) {
    int ierr = check_cuda(cudaGetLastError(), kernel_name);
    if (ierr == FV_CUDA_SUCCESS) {
        profile::ScopedTimer timer(cuda_sync_counter);
        ierr = check_cuda(cudaDeviceSynchronize(), kernel_name);
    }
    if (ierr == FV_CUDA_SUCCESS) {
        ierr = device_out.copy_to_host(host_out, count, "copy result to host");
    }
    return ierr;
}

int validate_common(int nx, int ny, int nz) {
    if (nx <= 0 || ny <= 0 || nz <= 0) {
        std::fprintf(stderr, "fv_advection_kernels CUDA error: invalid dimensions\n");
        return FV_CUDA_INVALID_ARGUMENT;
    }
    return check_device_available();
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
    int ierr = validate_common(nx, ny, nz);
    if (ierr != FV_CUDA_SUCCESS || c == nullptr || ua == nullptr || q == nullptr || dq == nullptr) {
        return ierr == FV_CUDA_SUCCESS ? FV_CUDA_INVALID_ARGUMENT : ierr;
    }
    const std::size_t count = static_cast<std::size_t>(nx) * ny * nz;
    static thread_local DeviceBuffer d_c;
    static thread_local DeviceBuffer d_ua;
    static thread_local DeviceBuffer d_q;
    static thread_local DeviceBuffer d_dq;
    if ((ierr = d_c.copy_static_from_host(c, ny, "c")) == FV_CUDA_SUCCESS &&
        (ierr = d_ua.copy_from_host(ua, count, "ua")) == FV_CUDA_SUCCESS &&
        (ierr = d_q.copy_from_host(q, count, "q")) == FV_CUDA_SUCCESS &&
        (ierr = d_dq.ensure(count, "dq")) == FV_CUDA_SUCCESS) {
        const int threads = 256;
        semi_x_kernel<<<static_cast<int>((count + threads - 1) / threads), threads>>>(
            nx, ny, nz, dt, dx, d_c.ptr, d_ua.ptr, d_q.ptr, d_dq.ptr);
        ierr = launch_and_copy_back(dq, d_dq, count, "semi_x_kernel");
    }
    return ierr;
}

int slope_x_cuda(int nx, int ny, int nz, bool monotone, const double* q, double* slope) {
    int ierr = validate_common(nx, ny, nz);
    if (ierr != FV_CUDA_SUCCESS || q == nullptr || slope == nullptr) {
        return ierr == FV_CUDA_SUCCESS ? FV_CUDA_INVALID_ARGUMENT : ierr;
    }
    const std::size_t count = static_cast<std::size_t>(nx) * ny * nz;
    static thread_local DeviceBuffer d_q;
    static thread_local DeviceBuffer d_slope;
    if ((ierr = d_q.copy_from_host(q, count, "q")) == FV_CUDA_SUCCESS &&
        (ierr = d_slope.ensure(count, "slope")) == FV_CUDA_SUCCESS) {
        const int threads = 256;
        slope_x_kernel<<<static_cast<int>((count + threads - 1) / threads), threads>>>(
            nx, ny, nz, monotone, d_q.ptr, d_slope.ptr);
        ierr = launch_and_copy_back(slope, d_slope, count, "slope_x_kernel");
    }
    return ierr;
}

int integer_flux_x_cuda(
    int nx,
    int ny,
    int nz,
    const double* courant,
    const double* q,
    double* flux) {
    int ierr = validate_common(nx, ny, nz);
    if (ierr != FV_CUDA_SUCCESS || courant == nullptr || q == nullptr || flux == nullptr) {
        return ierr == FV_CUDA_SUCCESS ? FV_CUDA_INVALID_ARGUMENT : ierr;
    }
    const std::size_t count = static_cast<std::size_t>(nx) * ny * nz;
    static thread_local DeviceBuffer d_courant;
    static thread_local DeviceBuffer d_q;
    static thread_local DeviceBuffer d_flux;
    if ((ierr = d_courant.copy_from_host(courant, count, "courant")) == FV_CUDA_SUCCESS &&
        (ierr = d_q.copy_from_host(q, count, "q")) == FV_CUDA_SUCCESS &&
        (ierr = d_flux.ensure(count, "flux")) == FV_CUDA_SUCCESS) {
        const int threads = 256;
        integer_flux_x_kernel<<<static_cast<int>((count + threads - 1) / threads), threads>>>(
            nx, ny, nz, d_courant.ptr, d_q.ptr, d_flux.ptr);
        ierr = launch_and_copy_back(flux, d_flux, count, "integer_flux_x_kernel");
    }
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
    int ierr = validate_common(nx, ny, nz);
    if (ierr != FV_CUDA_SUCCESS || c == nullptr || uc == nullptr || q == nullptr || dq_dt == nullptr) {
        return ierr == FV_CUDA_SUCCESS ? FV_CUDA_INVALID_ARGUMENT : ierr;
    }
    const std::size_t count = static_cast<std::size_t>(nx) * ny * nz;
    static thread_local DeviceBuffer d_c;
    static thread_local DeviceBuffer d_uc;
    static thread_local DeviceBuffer d_q;
    static thread_local DeviceBuffer d_dq;
    if ((ierr = d_c.copy_static_from_host(c, ny, "c")) == FV_CUDA_SUCCESS &&
        (ierr = d_uc.copy_from_host(uc, count, "uc")) == FV_CUDA_SUCCESS &&
        (ierr = d_q.copy_from_host(q, count, "q")) == FV_CUDA_SUCCESS &&
        (ierr = d_dq.copy_from_host(dq_dt, count, "dq_dt")) == FV_CUDA_SUCCESS) {
        const int threads = 256;
        vanleer_x_kernel<<<static_cast<int>((count + threads - 1) / threads), threads>>>(
            nx, ny, nz, dt, dx, d_c.ptr, monotone, d_uc.ptr, d_q.ptr, d_dq.ptr);
        ierr = launch_and_copy_back(dq_dt, d_dq, count, "vanleer_x_kernel");
    }
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
    int ierr = validate_common(nx, nys, nz);
    if (ierr != FV_CUDA_SUCCESS || dy_plus == nullptr || dy_minus == nullptr || q == nullptr || slope == nullptr) {
        return ierr == FV_CUDA_SUCCESS ? FV_CUDA_INVALID_ARGUMENT : ierr;
    }
    const std::size_t slope_count = static_cast<std::size_t>(nx) * nys * nz;
    const std::size_t q_count = static_cast<std::size_t>(nx) * (nys + 2) * nz;
    static thread_local DeviceBuffer d_dy_plus;
    static thread_local DeviceBuffer d_dy_minus;
    static thread_local DeviceBuffer d_q;
    static thread_local DeviceBuffer d_slope;
    if ((ierr = d_dy_plus.copy_static_from_host(dy_plus, nys, "dy_plus")) == FV_CUDA_SUCCESS &&
        (ierr = d_dy_minus.copy_static_from_host(dy_minus, nys, "dy_minus")) == FV_CUDA_SUCCESS &&
        (ierr = d_q.copy_from_host(q, q_count, "q")) == FV_CUDA_SUCCESS &&
        (ierr = d_slope.ensure(slope_count, "slope")) == FV_CUDA_SUCCESS) {
        const int threads = 256;
        slope_sphere_kernel<<<static_cast<int>((slope_count + threads - 1) / threads), threads>>>(
            nx, nys, nz, monotone, d_dy_plus.ptr, d_dy_minus.ptr, d_q.ptr, d_slope.ptr);
        ierr = launch_and_copy_back(slope, d_slope, slope_count, "slope_sphere_kernel");
    }
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
    int ierr = validate_common(nx, ny, nz);
    if (ierr != FV_CUDA_SUCCESS || c == nullptr || cc == nullptr || dy == nullptr ||
        dy_plus == nullptr || dy_minus == nullptr || vc == nullptr || q == nullptr || dq_dt == nullptr) {
        return ierr == FV_CUDA_SUCCESS ? FV_CUDA_INVALID_ARGUMENT : ierr;
    }
    const std::size_t dq_count = static_cast<std::size_t>(nx) * ny * nz;
    const std::size_t vc_count = static_cast<std::size_t>(nx) * (ny + 1) * nz;
    const std::size_t q_count = static_cast<std::size_t>(nx) * (ny + 4) * nz;
    static thread_local DeviceBuffer d_c;
    static thread_local DeviceBuffer d_cc;
    static thread_local DeviceBuffer d_dy;
    static thread_local DeviceBuffer d_dy_plus;
    static thread_local DeviceBuffer d_dy_minus;
    static thread_local DeviceBuffer d_vc;
    static thread_local DeviceBuffer d_q;
    static thread_local DeviceBuffer d_dq;
    if ((ierr = d_c.copy_static_from_host(c, ny, "c")) == FV_CUDA_SUCCESS &&
        (ierr = d_cc.copy_static_from_host(cc, ny + 1, "cc")) == FV_CUDA_SUCCESS &&
        (ierr = d_dy.copy_static_from_host(dy, ny + 2, "dy")) == FV_CUDA_SUCCESS &&
        (ierr = d_dy_plus.copy_static_from_host(dy_plus, ny + 2, "dy_plus")) == FV_CUDA_SUCCESS &&
        (ierr = d_dy_minus.copy_static_from_host(dy_minus, ny + 2, "dy_minus")) == FV_CUDA_SUCCESS &&
        (ierr = d_vc.copy_from_host(vc, vc_count, "vc")) == FV_CUDA_SUCCESS &&
        (ierr = d_q.copy_from_host(q, q_count, "q")) == FV_CUDA_SUCCESS &&
        (ierr = d_dq.copy_from_host(dq_dt, dq_count, "dq_dt")) == FV_CUDA_SUCCESS) {
        const int threads = 256;
        vanleer_sphere_kernel<<<static_cast<int>((dq_count + threads - 1) / threads), threads>>>(
            nx, ny, nz, dt, monotone, is_south_boundary, is_north_boundary, d_c.ptr,
            d_cc.ptr, d_dy.ptr, d_dy_plus.ptr, d_dy_minus.ptr, d_vc.ptr, d_q.ptr, d_dq.ptr);
        ierr = launch_and_copy_back(dq_dt, d_dq, dq_count, "vanleer_sphere_kernel");
    }
    return ierr;
}

int advection_sphere_predictor_cuda(
    int nx,
    int ny,
    int nz,
    double dt,
    double dx,
    const double* c,
    const double* dyy,
    const double* ua,
    const double* va,
    const double* q,
    double* q1,
    double* q2) {
    int ierr = validate_common(nx, ny, nz);
    if (ierr != FV_CUDA_SUCCESS || c == nullptr || dyy == nullptr || ua == nullptr ||
        va == nullptr || q == nullptr || q1 == nullptr || q2 == nullptr) {
        return ierr == FV_CUDA_SUCCESS ? FV_CUDA_INVALID_ARGUMENT : ierr;
    }
    const std::size_t center_count = static_cast<std::size_t>(nx) * ny * nz;
    const std::size_t halo_count = static_cast<std::size_t>(nx) * (ny + 4) * nz;
    static thread_local DeviceBuffer d_c;
    static thread_local DeviceBuffer d_dyy;
    static thread_local DeviceBuffer d_ua;
    static thread_local DeviceBuffer d_va;
    static thread_local DeviceBuffer d_q;
    static thread_local DeviceBuffer d_q1;
    ResidentFusedAdvectionState& resident = resident_fused_advection_state();
    if ((ierr = d_c.copy_static_from_host(c, ny, "c")) == FV_CUDA_SUCCESS &&
        (ierr = d_dyy.copy_static_from_host(dyy, ny + 1, "dyy")) == FV_CUDA_SUCCESS &&
        (ierr = d_ua.copy_from_host(ua, center_count, "ua")) == FV_CUDA_SUCCESS &&
        (ierr = d_va.copy_from_host(va, center_count, "va")) == FV_CUDA_SUCCESS &&
        (ierr = d_q.copy_from_host(q, halo_count, "q")) == FV_CUDA_SUCCESS &&
        (ierr = d_q1.ensure(halo_count, "q1")) == FV_CUDA_SUCCESS &&
        (ierr = resident.q2.ensure(center_count, "q2")) == FV_CUDA_SUCCESS) {
        ierr = check_cuda(cudaMemcpy(d_q1.ptr, d_q.ptr, halo_count * sizeof(double),
                                     cudaMemcpyDeviceToDevice),
                          "initialize q1 halos");
    }
    if (ierr == FV_CUDA_SUCCESS) {
        const int threads = 256;
        advection_predictor_kernel<<<static_cast<int>((center_count + threads - 1) / threads), threads>>>(
            nx, ny, nz, 0.5 * dt, dx, d_c.ptr, d_dyy.ptr, d_ua.ptr, d_va.ptr,
            d_q.ptr, d_q1.ptr, resident.q2.ptr);
        ierr = check_cuda(cudaGetLastError(), "advection_predictor_kernel");
        if (ierr == FV_CUDA_SUCCESS) {
            {
                profile::ScopedTimer timer(cuda_sync_counter);
                ierr = check_cuda(cudaDeviceSynchronize(), "advection_predictor_kernel");
            }
        }
        if (ierr == FV_CUDA_SUCCESS) {
            profile::ScopedTimer timer(cuda_d2h_counter);
            const std::size_t plane_count = static_cast<std::size_t>(nx) * (ny + 4);
            const std::size_t interior_offset = static_cast<std::size_t>(2) * nx;
            ierr = check_cuda(
                cudaMemcpy2D(q1 + interior_offset, plane_count * sizeof(double),
                             d_q1.ptr + interior_offset, plane_count * sizeof(double),
                             static_cast<std::size_t>(nx) * ny * sizeof(double),
                             static_cast<std::size_t>(nz), cudaMemcpyDeviceToHost),
                "copy q1 interior to host");
        }
        if (ierr == FV_CUDA_SUCCESS) {
            resident.nx = nx;
            resident.ny = ny;
            resident.nz = nz;
            resident.q2_valid = true;
        }
    }
    return ierr;
}

int advection_sphere_corrector_cuda(
    int nx,
    int ny_total,
    int ny,
    int nz,
    double dt,
    double dx,
    bool monotone,
    bool is_south_boundary,
    bool is_north_boundary,
    const double* c,
    const double* cc,
    const double* dy,
    const double* dy_plus,
    const double* dy_minus,
    const double* uc,
    const double* vc,
    const double* q1,
    const double* q2,
    double* dq_dt) {
    (void)ny_total;
    int ierr = validate_common(nx, ny, nz);
    if (ierr != FV_CUDA_SUCCESS || c == nullptr || cc == nullptr || dy == nullptr ||
        dy_plus == nullptr || dy_minus == nullptr || uc == nullptr || vc == nullptr ||
        q1 == nullptr || q2 == nullptr || dq_dt == nullptr) {
        return ierr == FV_CUDA_SUCCESS ? FV_CUDA_INVALID_ARGUMENT : ierr;
    }
    const std::size_t center_count = static_cast<std::size_t>(nx) * ny * nz;
    const std::size_t vc_count = static_cast<std::size_t>(nx) * (ny + 1) * nz;
    const std::size_t q1_count = static_cast<std::size_t>(nx) * (ny + 4) * nz;
    static thread_local DeviceBuffer d_c;
    static thread_local DeviceBuffer d_cc;
    static thread_local DeviceBuffer d_dy;
    static thread_local DeviceBuffer d_dy_plus;
    static thread_local DeviceBuffer d_dy_minus;
    static thread_local DeviceBuffer d_uc;
    static thread_local DeviceBuffer d_vc;
    static thread_local DeviceBuffer d_q1;
    static thread_local DeviceBuffer d_dq;
    ResidentFusedAdvectionState& resident = resident_fused_advection_state();
    const bool use_resident_q2 =
        resident.q2_valid && resident.nx == nx && resident.ny == ny && resident.nz == nz;
    if ((ierr = d_c.copy_static_from_host(c, ny, "c")) == FV_CUDA_SUCCESS &&
        (ierr = d_cc.copy_static_from_host(cc, ny + 1, "cc")) == FV_CUDA_SUCCESS &&
        (ierr = d_dy.copy_static_from_host(dy, ny + 2, "dy")) == FV_CUDA_SUCCESS &&
        (ierr = d_dy_plus.copy_static_from_host(dy_plus, ny + 2, "dy_plus")) == FV_CUDA_SUCCESS &&
        (ierr = d_dy_minus.copy_static_from_host(dy_minus, ny + 2, "dy_minus")) == FV_CUDA_SUCCESS &&
        (ierr = d_uc.copy_from_host(uc, center_count, "uc")) == FV_CUDA_SUCCESS &&
        (ierr = d_vc.copy_from_host(vc, vc_count, "vc")) == FV_CUDA_SUCCESS &&
        (ierr = d_q1.copy_from_host(q1, q1_count, "q1")) == FV_CUDA_SUCCESS &&
        (ierr = (use_resident_q2 ? FV_CUDA_SUCCESS : resident.q2.copy_from_host(q2, center_count, "q2"))) == FV_CUDA_SUCCESS &&
        (ierr = d_dq.copy_from_host(dq_dt, center_count, "dq_dt")) == FV_CUDA_SUCCESS) {
        const int threads = 256;
        const int blocks = static_cast<int>((center_count + threads - 1) / threads);
        vanleer_x_kernel<<<blocks, threads>>>(
            nx, ny, nz, dt, dx, d_c.ptr, monotone, d_uc.ptr, resident.q2.ptr, d_dq.ptr);
        ierr = check_cuda(cudaGetLastError(), "fused vanleer_x_kernel");
        if (ierr == FV_CUDA_SUCCESS) {
            vanleer_sphere_kernel<<<blocks, threads>>>(
                nx, ny, nz, dt, monotone, is_south_boundary, is_north_boundary,
                d_c.ptr, d_cc.ptr, d_dy.ptr, d_dy_plus.ptr, d_dy_minus.ptr,
                d_vc.ptr, d_q1.ptr, d_dq.ptr);
            ierr = check_cuda(cudaGetLastError(), "fused vanleer_sphere_kernel");
        }
        if (ierr == FV_CUDA_SUCCESS) {
            {
                profile::ScopedTimer timer(cuda_sync_counter);
                ierr = check_cuda(cudaDeviceSynchronize(), "advection_sphere_corrector");
            }
        }
        if (ierr == FV_CUDA_SUCCESS) {
            ierr = d_dq.copy_to_host(dq_dt, center_count, "copy dq_dt to host");
        }
    }
    return ierr;
}

int a_grid_advection_stage1_cuda(
    int nx,
    int ny,
    int nz,
    double dt,
    double dx,
    bool flux_only,
    const double* c,
    const double* cc,
    const double* dy,
    const double* dyy,
    const double* ua,
    const double* vx,
    const double* qx,
    double* dq_dt,
    double* q1) {
    int ierr = validate_common(nx, ny, nz);
    if (ierr != FV_CUDA_SUCCESS || c == nullptr || cc == nullptr || dy == nullptr ||
        dyy == nullptr || ua == nullptr || vx == nullptr || qx == nullptr ||
        dq_dt == nullptr || q1 == nullptr) {
        return ierr == FV_CUDA_SUCCESS ? FV_CUDA_INVALID_ARGUMENT : ierr;
    }
    const std::size_t center_count = static_cast<std::size_t>(nx) * ny * nz;
    const std::size_t vc_count = static_cast<std::size_t>(nx) * (ny + 1) * nz;
    const std::size_t halo_count = static_cast<std::size_t>(nx) * (ny + 4) * nz;
    ResidentFusedAdvectionState& resident = resident_fused_advection_state();
    static thread_local DeviceBuffer d_c;
    static thread_local DeviceBuffer d_cc;
    static thread_local DeviceBuffer d_dy;
    static thread_local DeviceBuffer d_dyy;
    static thread_local DeviceBuffer d_ua;
    static thread_local DeviceBuffer d_vx;
    static thread_local DeviceBuffer d_qx;
    static thread_local DeviceBuffer d_q1;
    if ((ierr = d_c.copy_static_from_host(c, ny, "c")) == FV_CUDA_SUCCESS &&
        (ierr = d_cc.copy_static_from_host(cc, ny + 1, "cc")) == FV_CUDA_SUCCESS &&
        (ierr = d_dy.copy_static_from_host(dy, ny + 2, "dy")) == FV_CUDA_SUCCESS &&
        (ierr = d_dyy.copy_static_from_host(dyy, ny + 1, "dyy")) == FV_CUDA_SUCCESS &&
        (ierr = d_ua.copy_from_host(ua, center_count, "ua")) == FV_CUDA_SUCCESS &&
        (ierr = d_vx.copy_from_host(vx, halo_count, "vx")) == FV_CUDA_SUCCESS &&
        (ierr = d_qx.copy_from_host(qx, halo_count, "qx")) == FV_CUDA_SUCCESS &&
        (ierr = resident.uc.ensure(center_count, "resident uc")) == FV_CUDA_SUCCESS &&
        (ierr = resident.vc.ensure(vc_count, "resident vc")) == FV_CUDA_SUCCESS &&
        (ierr = resident.dq.copy_from_host(dq_dt, center_count, "resident dq_dt")) == FV_CUDA_SUCCESS &&
        (ierr = resident.q2.ensure(center_count, "resident q2")) == FV_CUDA_SUCCESS &&
        (ierr = d_q1.ensure(halo_count, "q1")) == FV_CUDA_SUCCESS) {
        ierr = check_cuda(cudaMemcpy(d_q1.ptr, d_qx.ptr, halo_count * sizeof(double),
                                     cudaMemcpyDeviceToDevice),
                          "initialize q1 halos");
    }
    if (ierr == FV_CUDA_SUCCESS) {
        const int threads = 256;
        a_grid_setup_vc_kernel<<<static_cast<int>((vc_count + threads - 1) / threads), threads>>>(
            nx, ny, nz, d_vx.ptr, resident.vc.ptr);
        ierr = check_cuda(cudaGetLastError(), "a_grid_setup_vc_kernel");
    }
    if (ierr == FV_CUDA_SUCCESS) {
        const int threads = 256;
        a_grid_stage1_kernel<<<static_cast<int>((center_count + threads - 1) / threads), threads>>>(
            nx, ny, nz, 0.5 * dt, dx, flux_only, d_c.ptr, d_cc.ptr, d_dy.ptr,
            d_dyy.ptr, d_ua.ptr, d_vx.ptr, d_qx.ptr, resident.uc.ptr,
            resident.vc.ptr, resident.dq.ptr, d_q1.ptr, resident.q2.ptr);
        ierr = check_cuda(cudaGetLastError(), "a_grid_stage1_kernel");
    }
    if (ierr == FV_CUDA_SUCCESS) {
        {
            profile::ScopedTimer timer(cuda_sync_counter);
            ierr = check_cuda(cudaDeviceSynchronize(), "a_grid_advection_stage1");
        }
    }
    if (ierr == FV_CUDA_SUCCESS) {
        profile::ScopedTimer timer(cuda_d2h_counter);
        const std::size_t plane_count = static_cast<std::size_t>(nx) * (ny + 4);
        const std::size_t interior_offset = static_cast<std::size_t>(2) * nx;
        ierr = check_cuda(
            cudaMemcpy2D(q1 + interior_offset, plane_count * sizeof(double),
                         d_q1.ptr + interior_offset, plane_count * sizeof(double),
                         static_cast<std::size_t>(nx) * ny * sizeof(double),
                         static_cast<std::size_t>(nz), cudaMemcpyDeviceToHost),
            "copy q1 interior to host");
    }
    if (ierr == FV_CUDA_SUCCESS) {
        resident.nx = nx;
        resident.ny = ny;
        resident.nz = nz;
        resident.q2_valid = true;
    }
    return ierr;
}

int a_grid_advection_stage2_cuda(
    int nx,
    int ny_total,
    int ny,
    int nz,
    double dt,
    double dx,
    bool monotone,
    bool is_south_boundary,
    bool is_north_boundary,
    const double* c,
    const double* cc,
    const double* dy,
    const double* dy_plus,
    const double* dy_minus,
    const double* q1,
    double* dq_dt) {
    (void)ny_total;
    int ierr = validate_common(nx, ny, nz);
    ResidentFusedAdvectionState& resident = resident_fused_advection_state();
    const bool resident_valid =
        resident.q2_valid && resident.nx == nx && resident.ny == ny && resident.nz == nz;
    if (ierr != FV_CUDA_SUCCESS || !resident_valid || c == nullptr || cc == nullptr ||
        dy == nullptr || dy_plus == nullptr || dy_minus == nullptr || q1 == nullptr ||
        dq_dt == nullptr) {
        return ierr == FV_CUDA_SUCCESS ? FV_CUDA_INVALID_ARGUMENT : ierr;
    }
    const std::size_t center_count = static_cast<std::size_t>(nx) * ny * nz;
    const std::size_t q1_count = static_cast<std::size_t>(nx) * (ny + 4) * nz;
    static thread_local DeviceBuffer d_c;
    static thread_local DeviceBuffer d_cc;
    static thread_local DeviceBuffer d_dy;
    static thread_local DeviceBuffer d_dy_plus;
    static thread_local DeviceBuffer d_dy_minus;
    static thread_local DeviceBuffer d_q1;
    if ((ierr = d_c.copy_static_from_host(c, ny, "c")) == FV_CUDA_SUCCESS &&
        (ierr = d_cc.copy_static_from_host(cc, ny + 1, "cc")) == FV_CUDA_SUCCESS &&
        (ierr = d_dy.copy_static_from_host(dy, ny + 2, "dy")) == FV_CUDA_SUCCESS &&
        (ierr = d_dy_plus.copy_static_from_host(dy_plus, ny + 2, "dy_plus")) == FV_CUDA_SUCCESS &&
        (ierr = d_dy_minus.copy_static_from_host(dy_minus, ny + 2, "dy_minus")) == FV_CUDA_SUCCESS &&
        (ierr = d_q1.copy_from_host(q1, q1_count, "q1")) == FV_CUDA_SUCCESS) {
        const int threads = 256;
        const int blocks = static_cast<int>((center_count + threads - 1) / threads);
        vanleer_x_kernel<<<blocks, threads>>>(
            nx, ny, nz, dt, dx, d_c.ptr, monotone, resident.uc.ptr,
            resident.q2.ptr, resident.dq.ptr);
        ierr = check_cuda(cudaGetLastError(), "a_grid fused vanleer_x_kernel");
        if (ierr == FV_CUDA_SUCCESS) {
            vanleer_sphere_kernel<<<blocks, threads>>>(
                nx, ny, nz, dt, monotone, is_south_boundary, is_north_boundary,
                d_c.ptr, d_cc.ptr, d_dy.ptr, d_dy_plus.ptr, d_dy_minus.ptr,
                resident.vc.ptr, d_q1.ptr, resident.dq.ptr);
            ierr = check_cuda(cudaGetLastError(), "a_grid fused vanleer_sphere_kernel");
        }
        if (ierr == FV_CUDA_SUCCESS) {
            {
                profile::ScopedTimer timer(cuda_sync_counter);
                ierr = check_cuda(cudaDeviceSynchronize(), "a_grid_advection_stage2");
            }
        }
        if (ierr == FV_CUDA_SUCCESS) {
            ierr = resident.dq.copy_to_host(dq_dt, center_count, "copy resident dq_dt to host");
        }
    }
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

extern "C" int fv_advection_sphere_predictor_cuda_c(
    int nx,
    int js,
    int je,
    int nz,
    double dt,
    double dx,
    const double* c,
    const double* dyy,
    const double* ua,
    const double* va,
    const double* q,
    double* q1,
    double* q2) {
    register_cuda_profile_report();
    profile::ScopedTimer timer(advection_predictor_counter);
    return fv_advection_kernels::cuda_backend::advection_sphere_predictor_cuda(
        nx, je - js + 1, nz, dt, dx, c, dyy, ua, va, q, q1, q2);
}

extern "C" int fv_advection_sphere_corrector_cuda_c(
    int nx,
    int ny_total,
    int js,
    int je,
    int nz,
    double dt,
    double dx,
    int monotone,
    const double* c,
    const double* cc,
    const double* dy,
    const double* dy_plus,
    const double* dy_minus,
    const double* uc,
    const double* vc,
    const double* q1,
    const double* q2,
    double* dq_dt) {
    register_cuda_profile_report();
    profile::ScopedTimer timer(advection_corrector_counter);
    return fv_advection_kernels::cuda_backend::advection_sphere_corrector_cuda(
        nx, ny_total, je - js + 1, nz, dt, dx, monotone != 0, js == 1,
        je == ny_total, c, cc, dy, dy_plus, dy_minus, uc, vc, q1, q2, dq_dt);
}

extern "C" int fv_a_grid_advection_stage1_cuda_c(
    int nx,
    int js,
    int je,
    int nz,
    double dt,
    double dx,
    int flux_only,
    const double* c,
    const double* cc,
    const double* dy,
    const double* dyy,
    const double* ua,
    const double* vx,
    const double* qx,
    double* dq_dt,
    double* q1) {
    register_cuda_profile_report();
    profile::ScopedTimer timer(a_grid_stage1_counter);
    return fv_advection_kernels::cuda_backend::a_grid_advection_stage1_cuda(
        nx, je - js + 1, nz, dt, dx, flux_only != 0, c, cc, dy, dyy,
        ua, vx, qx, dq_dt, q1);
}

extern "C" int fv_a_grid_advection_stage2_cuda_c(
    int nx,
    int ny_total,
    int js,
    int je,
    int nz,
    double dt,
    double dx,
    int monotone,
    const double* c,
    const double* cc,
    const double* dy,
    const double* dy_plus,
    const double* dy_minus,
    const double* q1,
    double* dq_dt) {
    register_cuda_profile_report();
    profile::ScopedTimer timer(a_grid_stage2_counter);
    return fv_advection_kernels::cuda_backend::a_grid_advection_stage2_cuda(
        nx, ny_total, je - js + 1, nz, dt, dx, monotone != 0, js == 1,
        je == ny_total, c, cc, dy, dy_plus, dy_minus, q1, dq_dt);
}
