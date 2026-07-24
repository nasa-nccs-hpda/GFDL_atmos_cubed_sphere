#include "hs_forcing_cuda.h"
#include "hs_forcing_cuda_kernels.cuh"

#include "../../cpp/forcing_module/include/held_suarez_c_api.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>

namespace hs_forcing {
namespace cuda_backend {

namespace {

struct DeviceBuffers {
    std::size_t size_2d = 0;
    std::size_t size_3d = 0;
    bool static_fields_ready = false;
    double* lat = nullptr;
    double* ps = nullptr;
    double* p_full = nullptr;
    double* u = nullptr;
    double* v = nullptr;
    double* t = nullptr;
    double* udt = nullptr;
    double* vdt = nullptr;
    double* tdt = nullptr;
    double* teq = nullptr;
    double* mask = nullptr;
};

DeviceBuffers g_buffers;
bool g_banner_printed = false;

int check_cuda(cudaError_t status, const char* what)
{
    if (status == cudaSuccess) {
        return HS_SUCCESS;
    }
    std::fprintf(stderr, "HS CUDA backend error: %s failed: %s\n",
                 what, cudaGetErrorString(status));
    return HS_ERROR_INVALID_CONFIG;
}

void free_ptr(double*& ptr)
{
    if (ptr != nullptr) {
        cudaFree(ptr);
        ptr = nullptr;
    }
}

void free_buffers()
{
    free_ptr(g_buffers.lat);
    free_ptr(g_buffers.ps);
    free_ptr(g_buffers.p_full);
    free_ptr(g_buffers.u);
    free_ptr(g_buffers.v);
    free_ptr(g_buffers.t);
    free_ptr(g_buffers.udt);
    free_ptr(g_buffers.vdt);
    free_ptr(g_buffers.tdt);
    free_ptr(g_buffers.teq);
    free_ptr(g_buffers.mask);
    g_buffers.size_2d = 0;
    g_buffers.size_3d = 0;
    g_buffers.static_fields_ready = false;
}

int alloc_ptr(double*& ptr, std::size_t count, const char* name)
{
    return check_cuda(cudaMalloc(reinterpret_cast<void**>(&ptr), count * sizeof(double)), name);
}

int ensure_buffers(std::size_t size_2d, std::size_t size_3d)
{
    if (g_buffers.size_2d == size_2d && g_buffers.size_3d == size_3d) {
        return HS_SUCCESS;
    }

    free_buffers();

    int ierr = alloc_ptr(g_buffers.lat, size_2d, "lat");
    if (ierr == HS_SUCCESS) ierr = alloc_ptr(g_buffers.ps, size_2d, "ps");
    if (ierr == HS_SUCCESS) ierr = alloc_ptr(g_buffers.p_full, size_3d, "p_full");
    if (ierr == HS_SUCCESS) ierr = alloc_ptr(g_buffers.u, size_3d, "u");
    if (ierr == HS_SUCCESS) ierr = alloc_ptr(g_buffers.v, size_3d, "v");
    if (ierr == HS_SUCCESS) ierr = alloc_ptr(g_buffers.t, size_3d, "t");
    if (ierr == HS_SUCCESS) ierr = alloc_ptr(g_buffers.udt, size_3d, "udt");
    if (ierr == HS_SUCCESS) ierr = alloc_ptr(g_buffers.vdt, size_3d, "vdt");
    if (ierr == HS_SUCCESS) ierr = alloc_ptr(g_buffers.tdt, size_3d, "tdt");
    if (ierr == HS_SUCCESS) ierr = alloc_ptr(g_buffers.teq, size_3d, "teq");
    if (ierr == HS_SUCCESS) ierr = alloc_ptr(g_buffers.mask, size_3d, "mask");

    if (ierr != HS_SUCCESS) {
        free_buffers();
        return ierr;
    }

    g_buffers.size_2d = size_2d;
    g_buffers.size_3d = size_3d;
    return HS_SUCCESS;
}

int copy_h2d(double* dst, const double* src, std::size_t count, const char* name)
{
    if (src == nullptr) {
        return HS_SUCCESS;
    }
    return check_cuda(cudaMemcpy(dst, src, count * sizeof(double), cudaMemcpyHostToDevice), name);
}

bool env_enabled(const char* name, bool default_value)
{
    const char* value = std::getenv(name);
    if (value == nullptr || value[0] == '\0') {
        return default_value;
    }
    return !(value[0] == '0' || value[0] == 'f' || value[0] == 'F' ||
             value[0] == 'n' || value[0] == 'N');
}

} // namespace

__global__ void hs_forcing_accumulate_kernel(
    int size_3d,
    int nlon,
    int nlat,
    int nlev,
    const double* lat,
    const double* ps,
    const double* p_full,
    const double* u,
    const double* v,
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
    double vkf,
    double sigma_b,
    const double* mask,
    double* udt,
    double* vdt,
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
    const double sigma = p_full[idx] / ps[idx_2d];

    double utnd = 0.0;
    double vtnd = 0.0;
    if (sigma <= 1.0 && sigma > sigma_b) {
        const double vcoeff = -vkf / (1.0 - sigma_b);
        const double vfactr = vcoeff * (sigma - sigma_b);
        utnd = vfactr * u[idx];
        vtnd = vfactr * v[idx];
    }

    const double sin_lat = sin(lat[idx_2d]);
    const double sin_lat_2 = sin_lat * sin_lat;
    const double cos_lat_2 = 1.0 - sin_lat_2;
    const double cos_lat_4 = cos_lat_2 * cos_lat_2;
    const double t_star = t_zero - delh * sin_lat_2 - eps * sin_lat;
    const double tstr = t_strat - eps * sin_lat;

    const double p_norm = p_full[idx] / p00;
    const double the = t_star - delv * cos_lat_2 * log(p_norm);
    double teq_value = fmax(the * pow(p_norm, kappa), tstr);

    double tdamp = tka;
    if (sigma <= 1.0 && sigma > sigma_b) {
        const double tcoeff = (tks - tka) / (1.0 - sigma_b);
        const double tfactr = tcoeff * (sigma - sigma_b);
        tdamp = tka + cos_lat_4 * tfactr;
    }

    double ttnd = -tdamp * (t[idx] - teq_value);
    if (mask != nullptr) {
        utnd *= mask[idx];
        vtnd *= mask[idx];
        ttnd *= mask[idx];
        teq_value *= mask[idx];
    }

    udt[idx] += utnd;
    vdt[idx] += vtnd;
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

    const bool copy_teq = env_enabled("HS_FORCE_COPY_TEQ", false);
    if (copy_teq && teq == nullptr) {
        std::fprintf(stderr,
                     "HS CUDA backend error: HS_FORCE_COPY_TEQ=1 requires a host teq array.\n");
        return HS_ERROR_NULL_POINTER;
    }

    if (!g_banner_printed) {
        std::fprintf(stderr,
                     "HS_FORCE_CUDA_RUNTIME version=fused_persistent_20260724 sync=implicit copy_teq=%d size_3d=%zu\n",
                     copy_teq ? 1 : 0, size_3d);
        g_banner_printed = true;
    }

    ierr = ensure_buffers(size_2d, size_3d);
    if (ierr == HS_SUCCESS && !g_buffers.static_fields_ready) {
        ierr = copy_h2d(g_buffers.lat, lat, size_2d, "copy lat");
        if (ierr == HS_SUCCESS) {
            g_buffers.static_fields_ready = true;
        }
    }
    if (ierr == HS_SUCCESS) ierr = copy_h2d(g_buffers.ps, ps, size_2d, "copy ps");
    if (ierr == HS_SUCCESS) ierr = copy_h2d(g_buffers.p_full, p_full, size_3d, "copy p_full");
    if (ierr == HS_SUCCESS) ierr = copy_h2d(g_buffers.u, u, size_3d, "copy u");
    if (ierr == HS_SUCCESS) ierr = copy_h2d(g_buffers.v, v, size_3d, "copy v");
    if (ierr == HS_SUCCESS) ierr = copy_h2d(g_buffers.t, t, size_3d, "copy t");
    if (ierr == HS_SUCCESS) ierr = copy_h2d(g_buffers.udt, udt, size_3d, "copy udt");
    if (ierr == HS_SUCCESS) ierr = copy_h2d(g_buffers.vdt, vdt, size_3d, "copy vdt");
    if (ierr == HS_SUCCESS) ierr = copy_h2d(g_buffers.tdt, tdt, size_3d, "copy tdt");
    if (ierr == HS_SUCCESS && mask != nullptr) ierr = copy_h2d(g_buffers.mask, mask, size_3d, "copy mask");
    if (ierr != HS_SUCCESS) {
        return ierr;
    }

    const int threads = 256;
    const int blocks = static_cast<int>((size_3d + threads - 1) / threads);

    hs_forcing_accumulate_kernel<<<blocks, threads>>>(
        static_cast<int>(size_3d), nlon, nlat, nlev, g_buffers.lat,
        g_buffers.ps, g_buffers.p_full, g_buffers.u, g_buffers.v,
        g_buffers.t, config.t_zero, config.t_strat, config.delh, config.delv,
        config.eps, config.P00, config.kappa, config.tka, config.tks,
        config.vkf, config.sigma_b, mask != nullptr ? g_buffers.mask : nullptr,
        g_buffers.udt, g_buffers.vdt, g_buffers.tdt, g_buffers.teq);
    ierr = check_cuda(cudaGetLastError(), "hs_forcing_accumulate_kernel launch");

    if (ierr == HS_SUCCESS) ierr = check_cuda(cudaMemcpy(udt, g_buffers.udt, size_3d * sizeof(double), cudaMemcpyDeviceToHost), "copy udt to host");
    if (ierr == HS_SUCCESS) ierr = check_cuda(cudaMemcpy(vdt, g_buffers.vdt, size_3d * sizeof(double), cudaMemcpyDeviceToHost), "copy vdt to host");
    if (ierr == HS_SUCCESS) ierr = check_cuda(cudaMemcpy(tdt, g_buffers.tdt, size_3d * sizeof(double), cudaMemcpyDeviceToHost), "copy tdt to host");
    if (ierr == HS_SUCCESS && copy_teq) {
        ierr = check_cuda(cudaMemcpy(teq, g_buffers.teq, size_3d * sizeof(double), cudaMemcpyDeviceToHost), "copy teq to host");
    }

    return ierr;
}

} // namespace cuda_backend
} // namespace hs_forcing
