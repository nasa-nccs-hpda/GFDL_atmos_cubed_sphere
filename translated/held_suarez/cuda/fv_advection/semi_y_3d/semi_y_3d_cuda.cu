#include "semi_y_3d_cuda.h"

#include <cstddef>
#include <cstdio>
#include <cuda_runtime.h>

namespace fv_advection {
namespace cuda_backend {

namespace {

constexpr int SEMI_Y_SUCCESS = 0;
constexpr int SEMI_Y_ERROR_CUDA = 1;
constexpr int SEMI_Y_ERROR_INVALID_ARGUMENT = 2;

__host__ __device__ inline int idx3(int i0, int j0, int k0, int nx, int ny) {
    return i0 + nx * (j0 + ny * k0);
}

int check_cuda(cudaError_t status, const char* what) {
    if (status == cudaSuccess) {
        return SEMI_Y_SUCCESS;
    }
    std::fprintf(stderr, "semi_y_3d CUDA error: %s failed: %s\n", what,
                 cudaGetErrorString(status));
    return SEMI_Y_ERROR_CUDA;
}

int copy_to_device(double** dst, const double* src, std::size_t count,
                   const char* name) {
    if (src == nullptr) {
        std::fprintf(stderr, "semi_y_3d CUDA error: null input pointer %s\n",
                     name);
        return SEMI_Y_ERROR_INVALID_ARGUMENT;
    }
    int ierr =
        check_cuda(cudaMalloc(reinterpret_cast<void**>(dst),
                              count * sizeof(double)),
                   name);
    if (ierr != SEMI_Y_SUCCESS) {
        return ierr;
    }
    return check_cuda(cudaMemcpy(*dst, src, count * sizeof(double),
                                 cudaMemcpyHostToDevice),
                      name);
}

void free_if_present(double* ptr) {
    if (ptr != nullptr) {
        cudaFree(ptr);
    }
}

__global__ void semi_y_3d_kernel(
    int nx,
    int ny,
    int nz,
    double dt,
    const double* va,
    const double* qx,
    const double* dyy,
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
    const int qx_ny = ny + 4;

    const double va_val = va[idx];
    const int qx_j_minus_1 = j0 + 1;
    const int qx_j = j0 + 2;
    const int qx_j_plus_1 = j0 + 3;

    if (va_val >= 0.0) {
        dq[idx] = va_val * dt *
                  (qx[idx3(i0, qx_j_minus_1, k0, nx, qx_ny)] -
                   qx[idx3(i0, qx_j, k0, nx, qx_ny)]) /
                  dyy[j0];
    } else {
        dq[idx] = va_val * dt *
                  (qx[idx3(i0, qx_j, k0, nx, qx_ny)] -
                   qx[idx3(i0, qx_j_plus_1, k0, nx, qx_ny)]) /
                  dyy[j0 + 1];
    }
}

}  // namespace

int semi_y_3d_cuda(
    int nx,
    int js,
    int je,
    int nz,
    double dt,
    const double* va,
    const double* qx,
    const double* dyy,
    double* dq) {
    (void)js;
    if (nx <= 0 || je < js || nz <= 0 || va == nullptr || qx == nullptr ||
        dyy == nullptr || dq == nullptr) {
        std::fprintf(stderr, "semi_y_3d CUDA error: invalid argument\n");
        return SEMI_Y_ERROR_INVALID_ARGUMENT;
    }

    int device_count = 0;
    int ierr = check_cuda(cudaGetDeviceCount(&device_count),
                          "cudaGetDeviceCount");
    if (ierr != SEMI_Y_SUCCESS) {
        return ierr;
    }
    if (device_count <= 0) {
        std::fprintf(stderr,
                     "semi_y_3d CUDA error: CUDA backend requested but no "
                     "CUDA devices are available.\n");
        return SEMI_Y_ERROR_CUDA;
    }

    const int ny = je - js + 1;
    const int qx_ny = ny + 4;
    const std::size_t va_count = static_cast<std::size_t>(nx) *
                                 static_cast<std::size_t>(ny) *
                                 static_cast<std::size_t>(nz);
    const std::size_t qx_count = static_cast<std::size_t>(nx) *
                                 static_cast<std::size_t>(qx_ny) *
                                 static_cast<std::size_t>(nz);
    const std::size_t dyy_count = static_cast<std::size_t>(ny + 1);

    double* d_va = nullptr;
    double* d_qx = nullptr;
    double* d_dyy = nullptr;
    double* d_dq = nullptr;

    ierr = copy_to_device(&d_va, va, va_count, "va");
    if (ierr == SEMI_Y_SUCCESS) {
        ierr = copy_to_device(&d_qx, qx, qx_count, "qx");
    }
    if (ierr == SEMI_Y_SUCCESS) {
        ierr = copy_to_device(&d_dyy, dyy, dyy_count, "dyy");
    }
    if (ierr == SEMI_Y_SUCCESS) {
        ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(&d_dq),
                                     va_count * sizeof(double)),
                          "dq");
    }

    if (ierr == SEMI_Y_SUCCESS) {
        const int threads = 256;
        const int blocks =
            static_cast<int>((va_count + threads - 1) / threads);
        semi_y_3d_kernel<<<blocks, threads>>>(nx, ny, nz, dt, d_va, d_qx,
                                              d_dyy, d_dq);
        ierr = check_cuda(cudaGetLastError(), "semi_y_3d_kernel launch");
        if (ierr == SEMI_Y_SUCCESS) {
            ierr = check_cuda(cudaDeviceSynchronize(),
                              "semi_y_3d_kernel synchronize");
        }
    }

    if (ierr == SEMI_Y_SUCCESS) {
        ierr = check_cuda(cudaMemcpy(dq, d_dq, va_count * sizeof(double),
                                     cudaMemcpyDeviceToHost),
                          "copy dq to host");
    }

    free_if_present(d_va);
    free_if_present(d_qx);
    free_if_present(d_dyy);
    free_if_present(d_dq);

    return ierr;
}

}  // namespace cuda_backend
}  // namespace fv_advection

extern "C" int fv_semi_y_3d_cuda_c(
    int nx,
    int js,
    int je,
    int nz,
    double dt,
    const double* va,
    const double* qx,
    const double* dyy,
    double* dq) {
    return fv_advection::cuda_backend::semi_y_3d_cuda(nx, js, je, nz, dt, va,
                                                      qx, dyy, dq);
}
