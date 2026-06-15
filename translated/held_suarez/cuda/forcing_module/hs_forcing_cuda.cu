#include "hs_forcing_cuda.h"
#include "hs_forcing_cuda_kernels.cuh"

#include "../../cpp/forcing_module/include/held_suarez_c_api.h"

#include <algorithm>
#include <cstdio>

namespace hs_forcing {
namespace cuda_backend {

namespace {

int check_cuda(cudaError_t status, const char* what)
{
    if (status == cudaSuccess) {
        return HS_SUCCESS;
    }
    std::fprintf(stderr, "HS CUDA backend error: %s failed: %s\n",
                 what, cudaGetErrorString(status));
    return HS_ERROR_INVALID_CONFIG;
}

int copy_to_device(double** dst, const double* src, std::size_t count, const char* name)
{
    if (src == nullptr) {
        *dst = nullptr;
        return HS_SUCCESS;
    }

    int ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(dst), count * sizeof(double)), name);
    if (ierr != HS_SUCCESS) {
        return ierr;
    }
    return check_cuda(cudaMemcpy(*dst, src, count * sizeof(double), cudaMemcpyHostToDevice), name);
}

int alloc_and_copy_inout(double** dst, double* src, std::size_t count, const char* name)
{
    if (src == nullptr) {
        *dst = nullptr;
        return HS_ERROR_NULL_POINTER;
    }

    int ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(dst), count * sizeof(double)), name);
    if (ierr != HS_SUCCESS) {
        return ierr;
    }
    return check_cuda(cudaMemcpy(*dst, src, count * sizeof(double), cudaMemcpyHostToDevice), name);
}

void free_if_present(double* ptr)
{
    if (ptr != nullptr) {
        cudaFree(ptr);
    }
}

} // namespace

__global__ void rayleigh_accumulate_kernel(
    int size_3d,
    int nlon,
    int nlat,
    int nlev,
    const double* ps,
    const double* p_full,
    const double* u,
    const double* v,
    double vkf,
    double sigma_b,
    const double* mask,
    double* udt,
    double* vdt)
{
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= size_3d) {
        return;
    }

    const int plane = nlon * nlat;
    const int k = idx / plane;
    if (k >= nlev) {
        return;
    }
    const int idx_2d = idx - k * plane;
    const double sigma = p_full[idx] / ps[idx_2d];
    double utnd = 0.0;
    double vtnd = 0.0;

    if (sigma <= 1.0 && sigma > sigma_b) {
        const double vcoeff = -vkf / (1.0 - sigma_b);
        const double vfactr = vcoeff * (sigma - sigma_b);
        utnd = vfactr * u[idx];
        vtnd = vfactr * v[idx];
    }

    if (mask != nullptr) {
        utnd *= mask[idx];
        vtnd *= mask[idx];
    }

    udt[idx] += utnd;
    vdt[idx] += vtnd;
}

__global__ void newtonian_accumulate_kernel(
    int size_3d,
    int nlon,
    int nlat,
    int nlev,
    const double* lat,
    const double* ps,
    const double* p_full,
    const double* t,
    double t_zero,
    double t_strat,
    double delh,
    double delv,
    double eps,
    double p00,
    double kappa,
    double tka,
    double tks,
    double sigma_b,
    const double* mask,
    double* tdt,
    double* teq)
{
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= size_3d) {
        return;
    }

    const int plane = nlon * nlat;
    const int k = idx / plane;
    if (k >= nlev) {
        return;
    }
    const int idx_2d = idx - k * plane;

    const double sin_lat = sin(lat[idx_2d]);
    const double sin_lat_2 = sin_lat * sin_lat;
    const double cos_lat_2 = 1.0 - sin_lat_2;
    const double cos_lat_4 = cos_lat_2 * cos_lat_2;
    const double t_star = t_zero - delh * sin_lat_2 - eps * sin_lat;
    const double tstr = t_strat - eps * sin_lat;

    const double p_norm = p_full[idx] / p00;
    const double the = t_star - delv * cos_lat_2 * log(p_norm);
    double teq_value = fmax(the * pow(p_norm, kappa), tstr);

    const double sigma = p_full[idx] / ps[idx_2d];
    double tdamp = tka;
    if (sigma <= 1.0 && sigma > sigma_b) {
        const double tcoeff = (tks - tka) / (1.0 - sigma_b);
        const double tfactr = tcoeff * (sigma - sigma_b);
        tdamp = tka + cos_lat_4 * tfactr;
    }

    double ttnd = -tdamp * (t[idx] - teq_value);
    if (mask != nullptr) {
        ttnd *= mask[idx];
        teq_value *= mask[idx];
    }

    tdt[idx] += ttnd;
    teq[idx] = teq_value;
}

int hs_forcing_driver_cuda(
    int nlon, int nlat, int nlev,
    int current_time,
    double dt,
    const double* lon,
    const double* lat,
    const double* ps,
    const double* p_full,
    const double* p_half,
    const double* u,
    const double* v,
    const double* t,
    const double* um,
    const double* vm,
    const double* zfull,
    const double* tg_prev,
    const Config& config,
    double* udt,
    double* vdt,
    double* tdt,
    double* teq,
    double* h_trop,
    double* tg_new,
    const double* mask)
{
    (void)current_time;
    (void)dt;
    (void)lon;
    (void)p_half;
    (void)um;
    (void)vm;
    (void)zfull;
    (void)tg_prev;
    (void)h_trop;
    (void)tg_new;

    if (config.equilibrium_option != EQUILIBRIUM_HELD_SUAREZ) {
        std::fprintf(stderr, "HS CUDA backend error: only standard Held-Suarez equilibrium is supported in the CUDA POC.\n");
        return HS_ERROR_INVALID_CONFIG;
    }
    if (config.do_conserve_energy) {
        std::fprintf(stderr, "HS CUDA backend error: energy-conserving forcing is not supported in the CUDA POC.\n");
        return HS_ERROR_INVALID_CONFIG;
    }

    int device_count = 0;
    int ierr = check_cuda(cudaGetDeviceCount(&device_count), "cudaGetDeviceCount");
    if (ierr != HS_SUCCESS) {
        return ierr;
    }
    if (device_count <= 0) {
        std::fprintf(stderr, "HS CUDA backend error: HS_FORCE_BACKEND=cuda requested but no CUDA devices are available.\n");
        return HS_ERROR_INVALID_CONFIG;
    }

    const std::size_t size_2d = static_cast<std::size_t>(nlon) * static_cast<std::size_t>(nlat);
    const std::size_t size_3d = size_2d * static_cast<std::size_t>(nlev);

    double* d_lat = nullptr;
    double* d_ps = nullptr;
    double* d_p_full = nullptr;
    double* d_u = nullptr;
    double* d_v = nullptr;
    double* d_t = nullptr;
    double* d_udt = nullptr;
    double* d_vdt = nullptr;
    double* d_tdt = nullptr;
    double* d_teq = nullptr;
    double* d_mask = nullptr;

    ierr = copy_to_device(&d_lat, lat, size_2d, "lat");
    if (ierr == HS_SUCCESS) ierr = copy_to_device(&d_ps, ps, size_2d, "ps");
    if (ierr == HS_SUCCESS) ierr = copy_to_device(&d_p_full, p_full, size_3d, "p_full");
    if (ierr == HS_SUCCESS) ierr = copy_to_device(&d_u, u, size_3d, "u");
    if (ierr == HS_SUCCESS) ierr = copy_to_device(&d_v, v, size_3d, "v");
    if (ierr == HS_SUCCESS) ierr = copy_to_device(&d_t, t, size_3d, "t");
    if (ierr == HS_SUCCESS) ierr = alloc_and_copy_inout(&d_udt, udt, size_3d, "udt");
    if (ierr == HS_SUCCESS) ierr = alloc_and_copy_inout(&d_vdt, vdt, size_3d, "vdt");
    if (ierr == HS_SUCCESS) ierr = alloc_and_copy_inout(&d_tdt, tdt, size_3d, "tdt");
    if (ierr == HS_SUCCESS) ierr = alloc_and_copy_inout(&d_teq, teq, size_3d, "teq");
    if (ierr == HS_SUCCESS && mask != nullptr) ierr = copy_to_device(&d_mask, mask, size_3d, "mask");

    if (ierr != HS_SUCCESS) {
        free_if_present(d_lat);
        free_if_present(d_ps);
        free_if_present(d_p_full);
        free_if_present(d_u);
        free_if_present(d_v);
        free_if_present(d_t);
        free_if_present(d_udt);
        free_if_present(d_vdt);
        free_if_present(d_tdt);
        free_if_present(d_teq);
        free_if_present(d_mask);
        return ierr;
    }

    const int threads = 256;
    const int blocks = static_cast<int>((size_3d + threads - 1) / threads);

    rayleigh_accumulate_kernel<<<blocks, threads>>>(
        static_cast<int>(size_3d), nlon, nlat, nlev,
        d_ps, d_p_full, d_u, d_v,
        config.vkf, config.sigma_b, d_mask,
        d_udt, d_vdt);
    ierr = check_cuda(cudaGetLastError(), "rayleigh_accumulate_kernel launch");
    if (ierr == HS_SUCCESS) ierr = check_cuda(cudaDeviceSynchronize(), "rayleigh_accumulate_kernel synchronize");

    if (ierr == HS_SUCCESS) {
        newtonian_accumulate_kernel<<<blocks, threads>>>(
            static_cast<int>(size_3d), nlon, nlat, nlev,
            d_lat, d_ps, d_p_full, d_t,
            config.t_zero, config.t_strat, config.delh, config.delv, config.eps,
            config.P00, config.kappa, config.tka, config.tks, config.sigma_b,
            d_mask, d_tdt, d_teq);
        ierr = check_cuda(cudaGetLastError(), "newtonian_accumulate_kernel launch");
    }
    if (ierr == HS_SUCCESS) ierr = check_cuda(cudaDeviceSynchronize(), "newtonian_accumulate_kernel synchronize");

    if (ierr == HS_SUCCESS) ierr = check_cuda(cudaMemcpy(udt, d_udt, size_3d * sizeof(double), cudaMemcpyDeviceToHost), "copy udt to host");
    if (ierr == HS_SUCCESS) ierr = check_cuda(cudaMemcpy(vdt, d_vdt, size_3d * sizeof(double), cudaMemcpyDeviceToHost), "copy vdt to host");
    if (ierr == HS_SUCCESS) ierr = check_cuda(cudaMemcpy(tdt, d_tdt, size_3d * sizeof(double), cudaMemcpyDeviceToHost), "copy tdt to host");
    if (ierr == HS_SUCCESS) ierr = check_cuda(cudaMemcpy(teq, d_teq, size_3d * sizeof(double), cudaMemcpyDeviceToHost), "copy teq to host");

    free_if_present(d_lat);
    free_if_present(d_ps);
    free_if_present(d_p_full);
    free_if_present(d_u);
    free_if_present(d_v);
    free_if_present(d_t);
    free_if_present(d_udt);
    free_if_present(d_vdt);
    free_if_present(d_tdt);
    free_if_present(d_teq);
    free_if_present(d_mask);

    return ierr;
}

} // namespace cuda_backend
} // namespace hs_forcing
