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

void print_cuda_profile() {
    profile::print_counter("cuda", semi_x_counter);
    profile::print_counter("cuda", slope_x_counter);
    profile::print_counter("cuda", integer_flux_x_counter);
    profile::print_counter("cuda", vanleer_x_counter);
    profile::print_counter("cuda", slope_sphere_counter);
    profile::print_counter("cuda", vanleer_sphere_counter);
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
    return FV_CUDA_SUCCESS;
}

int copy_to_device(double** dst, const double* src, std::size_t count, const char* name) {
    if (src == nullptr) {
        std::fprintf(stderr, "fv_advection_kernels CUDA error: null input pointer %s\n", name);
        return FV_CUDA_INVALID_ARGUMENT;
    }
    int ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(dst), count * sizeof(double)), name);
    if (ierr != FV_CUDA_SUCCESS) {
        return ierr;
    }
    return check_cuda(cudaMemcpy(*dst, src, count * sizeof(double), cudaMemcpyHostToDevice), name);
}

int copy_inout_to_device(double** dst, const double* src, std::size_t count, const char* name) {
    return copy_to_device(dst, src, count, name);
}

void free_if_present(double* ptr) {
    if (ptr != nullptr) {
        cudaFree(ptr);
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
    double* device_out,
    std::size_t count,
    const char* kernel_name) {
    int ierr = check_cuda(cudaGetLastError(), kernel_name);
    if (ierr == FV_CUDA_SUCCESS) {
        ierr = check_cuda(cudaDeviceSynchronize(), kernel_name);
    }
    if (ierr == FV_CUDA_SUCCESS) {
        ierr = check_cuda(cudaMemcpy(host_out, device_out, count * sizeof(double),
                                     cudaMemcpyDeviceToHost),
                          "copy result to host");
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
    double *d_c = nullptr, *d_ua = nullptr, *d_q = nullptr, *d_dq = nullptr;
    if ((ierr = copy_to_device(&d_c, c, ny, "c")) == FV_CUDA_SUCCESS &&
        (ierr = copy_to_device(&d_ua, ua, count, "ua")) == FV_CUDA_SUCCESS &&
        (ierr = copy_to_device(&d_q, q, count, "q")) == FV_CUDA_SUCCESS &&
        (ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(&d_dq), count * sizeof(double)), "dq")) == FV_CUDA_SUCCESS) {
        const int threads = 256;
        semi_x_kernel<<<static_cast<int>((count + threads - 1) / threads), threads>>>(
            nx, ny, nz, dt, dx, d_c, d_ua, d_q, d_dq);
        ierr = launch_and_copy_back(dq, d_dq, count, "semi_x_kernel");
    }
    free_if_present(d_c); free_if_present(d_ua); free_if_present(d_q); free_if_present(d_dq);
    return ierr;
}

int slope_x_cuda(int nx, int ny, int nz, bool monotone, const double* q, double* slope) {
    int ierr = validate_common(nx, ny, nz);
    if (ierr != FV_CUDA_SUCCESS || q == nullptr || slope == nullptr) {
        return ierr == FV_CUDA_SUCCESS ? FV_CUDA_INVALID_ARGUMENT : ierr;
    }
    const std::size_t count = static_cast<std::size_t>(nx) * ny * nz;
    double *d_q = nullptr, *d_slope = nullptr;
    if ((ierr = copy_to_device(&d_q, q, count, "q")) == FV_CUDA_SUCCESS &&
        (ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(&d_slope), count * sizeof(double)), "slope")) == FV_CUDA_SUCCESS) {
        const int threads = 256;
        slope_x_kernel<<<static_cast<int>((count + threads - 1) / threads), threads>>>(
            nx, ny, nz, monotone, d_q, d_slope);
        ierr = launch_and_copy_back(slope, d_slope, count, "slope_x_kernel");
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
    int ierr = validate_common(nx, ny, nz);
    if (ierr != FV_CUDA_SUCCESS || courant == nullptr || q == nullptr || flux == nullptr) {
        return ierr == FV_CUDA_SUCCESS ? FV_CUDA_INVALID_ARGUMENT : ierr;
    }
    const std::size_t count = static_cast<std::size_t>(nx) * ny * nz;
    double *d_courant = nullptr, *d_q = nullptr, *d_flux = nullptr;
    if ((ierr = copy_to_device(&d_courant, courant, count, "courant")) == FV_CUDA_SUCCESS &&
        (ierr = copy_to_device(&d_q, q, count, "q")) == FV_CUDA_SUCCESS &&
        (ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(&d_flux), count * sizeof(double)), "flux")) == FV_CUDA_SUCCESS) {
        const int threads = 256;
        integer_flux_x_kernel<<<static_cast<int>((count + threads - 1) / threads), threads>>>(
            nx, ny, nz, d_courant, d_q, d_flux);
        ierr = launch_and_copy_back(flux, d_flux, count, "integer_flux_x_kernel");
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
    int ierr = validate_common(nx, ny, nz);
    if (ierr != FV_CUDA_SUCCESS || c == nullptr || uc == nullptr || q == nullptr || dq_dt == nullptr) {
        return ierr == FV_CUDA_SUCCESS ? FV_CUDA_INVALID_ARGUMENT : ierr;
    }
    const std::size_t count = static_cast<std::size_t>(nx) * ny * nz;
    double *d_c = nullptr, *d_uc = nullptr, *d_q = nullptr, *d_dq = nullptr;
    if ((ierr = copy_to_device(&d_c, c, ny, "c")) == FV_CUDA_SUCCESS &&
        (ierr = copy_to_device(&d_uc, uc, count, "uc")) == FV_CUDA_SUCCESS &&
        (ierr = copy_to_device(&d_q, q, count, "q")) == FV_CUDA_SUCCESS &&
        (ierr = copy_inout_to_device(&d_dq, dq_dt, count, "dq_dt")) == FV_CUDA_SUCCESS) {
        const int threads = 256;
        vanleer_x_kernel<<<static_cast<int>((count + threads - 1) / threads), threads>>>(
            nx, ny, nz, dt, dx, d_c, monotone, d_uc, d_q, d_dq);
        ierr = launch_and_copy_back(dq_dt, d_dq, count, "vanleer_x_kernel");
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
    int ierr = validate_common(nx, nys, nz);
    if (ierr != FV_CUDA_SUCCESS || dy_plus == nullptr || dy_minus == nullptr || q == nullptr || slope == nullptr) {
        return ierr == FV_CUDA_SUCCESS ? FV_CUDA_INVALID_ARGUMENT : ierr;
    }
    const std::size_t slope_count = static_cast<std::size_t>(nx) * nys * nz;
    const std::size_t q_count = static_cast<std::size_t>(nx) * (nys + 2) * nz;
    double *d_dy_plus = nullptr, *d_dy_minus = nullptr, *d_q = nullptr, *d_slope = nullptr;
    if ((ierr = copy_to_device(&d_dy_plus, dy_plus, nys, "dy_plus")) == FV_CUDA_SUCCESS &&
        (ierr = copy_to_device(&d_dy_minus, dy_minus, nys, "dy_minus")) == FV_CUDA_SUCCESS &&
        (ierr = copy_to_device(&d_q, q, q_count, "q")) == FV_CUDA_SUCCESS &&
        (ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(&d_slope), slope_count * sizeof(double)), "slope")) == FV_CUDA_SUCCESS) {
        const int threads = 256;
        slope_sphere_kernel<<<static_cast<int>((slope_count + threads - 1) / threads), threads>>>(
            nx, nys, nz, monotone, d_dy_plus, d_dy_minus, d_q, d_slope);
        ierr = launch_and_copy_back(slope, d_slope, slope_count, "slope_sphere_kernel");
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
    int ierr = validate_common(nx, ny, nz);
    if (ierr != FV_CUDA_SUCCESS || c == nullptr || cc == nullptr || dy == nullptr ||
        dy_plus == nullptr || dy_minus == nullptr || vc == nullptr || q == nullptr || dq_dt == nullptr) {
        return ierr == FV_CUDA_SUCCESS ? FV_CUDA_INVALID_ARGUMENT : ierr;
    }
    const std::size_t dq_count = static_cast<std::size_t>(nx) * ny * nz;
    const std::size_t vc_count = static_cast<std::size_t>(nx) * (ny + 1) * nz;
    const std::size_t q_count = static_cast<std::size_t>(nx) * (ny + 4) * nz;
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
        const int threads = 256;
        vanleer_sphere_kernel<<<static_cast<int>((dq_count + threads - 1) / threads), threads>>>(
            nx, ny, nz, dt, monotone, is_south_boundary, is_north_boundary, d_c,
            d_cc, d_dy, d_dy_plus, d_dy_minus, d_vc, d_q, d_dq);
        ierr = launch_and_copy_back(dq_dt, d_dq, dq_count, "vanleer_sphere_kernel");
    }
    free_if_present(d_c); free_if_present(d_cc); free_if_present(d_dy); free_if_present(d_dy_plus);
    free_if_present(d_dy_minus); free_if_present(d_vc); free_if_present(d_q); free_if_present(d_dq);
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
