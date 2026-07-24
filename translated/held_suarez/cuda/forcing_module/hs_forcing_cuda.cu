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

struct TransformBuffers {
    std::size_t size_3d = 0;
    std::size_t size_lat = 0;
    double* a = nullptr;
    double* b = nullptr;
    double* c = nullptr;
    double* d = nullptr;
    double* e = nullptr;
    double* cosm = nullptr;
};

TransformBuffers g_transform_buffers;
bool g_transform_banner_printed = false;

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

void free_transform_buffers()
{
    free_ptr(g_transform_buffers.a);
    free_ptr(g_transform_buffers.b);
    free_ptr(g_transform_buffers.c);
    free_ptr(g_transform_buffers.d);
    free_ptr(g_transform_buffers.e);
    free_ptr(g_transform_buffers.cosm);
    g_transform_buffers.size_3d = 0;
    g_transform_buffers.size_lat = 0;
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

int ensure_transform_buffers(std::size_t size_3d, std::size_t size_lat)
{
    if (g_transform_buffers.size_3d == size_3d &&
        g_transform_buffers.size_lat == size_lat) {
        return HS_SUCCESS;
    }

    free_transform_buffers();

    int ierr = alloc_ptr(g_transform_buffers.a, size_3d, "transform a");
    if (ierr == HS_SUCCESS) ierr = alloc_ptr(g_transform_buffers.b, size_3d, "transform b");
    if (ierr == HS_SUCCESS) ierr = alloc_ptr(g_transform_buffers.c, size_3d, "transform c");
    if (ierr == HS_SUCCESS) ierr = alloc_ptr(g_transform_buffers.d, size_3d, "transform d");
    if (ierr == HS_SUCCESS) ierr = alloc_ptr(g_transform_buffers.e, size_3d, "transform e");
    if (ierr == HS_SUCCESS) ierr = alloc_ptr(g_transform_buffers.cosm, size_lat, "transform cosm");

    if (ierr != HS_SUCCESS) {
        free_transform_buffers();
        return ierr;
    }

    g_transform_buffers.size_3d = size_3d;
    g_transform_buffers.size_lat = size_lat;
    return HS_SUCCESS;
}

__global__ void horizontal_advection_accumulate_kernel(
    int n, int ni, int nj,
    const double* u_grid,
    const double* v_grid,
    const double* cosm_lat,
    double* dx_grid,
    double* dy_grid,
    double* tendency)
{
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= n) {
        return;
    }
    const int j = (idx / ni) % nj;
    const double cosm = cosm_lat[j];
    const double dx = dx_grid[idx] * cosm;
    const double dy = dy_grid[idx] * cosm;
    tendency[idx] -= u_grid[idx] * dx + v_grid[idx] * dy;
    dx_grid[idx] = dx;
    dy_grid[idx] = dy;
}

__global__ void divide_two_by_cos_kernel(
    int n, int ni, int nj,
    const double* cosm_lat,
    double* a_grid,
    double* b_grid)
{
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= n) {
        return;
    }
    const int j = (idx / ni) % nj;
    const double cosm = cosm_lat[j];
    a_grid[idx] *= cosm;
    b_grid[idx] *= cosm;
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

extern "C" int transforms_horizontal_advection_cuda_c(
    const double* u_grid,
    const double* v_grid,
    const double* cosm_lat,
    double* dx_grid,
    double* dy_grid,
    double* tendency,
    int ni,
    int nj,
    int nk)
{
    if (u_grid == nullptr || v_grid == nullptr || cosm_lat == nullptr ||
        dx_grid == nullptr || dy_grid == nullptr || tendency == nullptr) {
        return HS_ERROR_NULL_POINTER;
    }
    if (ni <= 0 || nj <= 0 || nk <= 0) {
        return HS_ERROR_INVALID_CONFIG;
    }

    int device_count = 0;
    int ierr = check_cuda(cudaGetDeviceCount(&device_count), "cudaGetDeviceCount");
    if (ierr != HS_SUCCESS || device_count <= 0) {
        return HS_ERROR_INVALID_CONFIG;
    }

    const std::size_t size_3d =
        static_cast<std::size_t>(ni) * static_cast<std::size_t>(nj) * static_cast<std::size_t>(nk);
    ierr = ensure_transform_buffers(size_3d, static_cast<std::size_t>(nj));
    if (ierr != HS_SUCCESS) {
        return ierr;
    }

    if (!g_transform_banner_printed) {
        std::fprintf(stderr,
                     "TRANSFORMS_CUDA_RUNTIME version=horizontal_fused_20260724 sync=implicit size_3d=%zu\n",
                     size_3d);
        g_transform_banner_printed = true;
    }

    if (ierr == HS_SUCCESS) ierr = copy_h2d(g_transform_buffers.a, u_grid, size_3d, "transform copy u");
    if (ierr == HS_SUCCESS) ierr = copy_h2d(g_transform_buffers.b, v_grid, size_3d, "transform copy v");
    if (ierr == HS_SUCCESS) ierr = copy_h2d(g_transform_buffers.c, dx_grid, size_3d, "transform copy dx");
    if (ierr == HS_SUCCESS) ierr = copy_h2d(g_transform_buffers.d, dy_grid, size_3d, "transform copy dy");
    if (ierr == HS_SUCCESS) ierr = copy_h2d(g_transform_buffers.e, tendency, size_3d, "transform copy tendency");
    if (ierr == HS_SUCCESS) ierr = copy_h2d(g_transform_buffers.cosm, cosm_lat, static_cast<std::size_t>(nj), "transform copy cosm");
    if (ierr != HS_SUCCESS) {
        return ierr;
    }

    const int threads = 256;
    const int blocks = static_cast<int>((size_3d + threads - 1) / threads);
    horizontal_advection_accumulate_kernel<<<blocks, threads>>>(
        static_cast<int>(size_3d), ni, nj,
        g_transform_buffers.a, g_transform_buffers.b, g_transform_buffers.cosm,
        g_transform_buffers.c, g_transform_buffers.d, g_transform_buffers.e);
    ierr = check_cuda(cudaGetLastError(), "horizontal_advection_accumulate_kernel launch");
    if (ierr == HS_SUCCESS) ierr = check_cuda(cudaMemcpy(tendency, g_transform_buffers.e, size_3d * sizeof(double), cudaMemcpyDeviceToHost), "transform copy tendency to host");
    return ierr;
}

extern "C" int transforms_divide_two_by_cos_cuda_c(
    double* a_grid,
    double* b_grid,
    const double* cosm_lat,
    int ni,
    int nj,
    int nk)
{
    if (a_grid == nullptr || b_grid == nullptr || cosm_lat == nullptr) {
        return HS_ERROR_NULL_POINTER;
    }
    if (ni <= 0 || nj <= 0 || nk <= 0) {
        return HS_ERROR_INVALID_CONFIG;
    }

    int device_count = 0;
    int ierr = check_cuda(cudaGetDeviceCount(&device_count), "cudaGetDeviceCount");
    if (ierr != HS_SUCCESS || device_count <= 0) {
        return HS_ERROR_INVALID_CONFIG;
    }

    const std::size_t size_3d =
        static_cast<std::size_t>(ni) * static_cast<std::size_t>(nj) * static_cast<std::size_t>(nk);
    ierr = ensure_transform_buffers(size_3d, static_cast<std::size_t>(nj));
    if (ierr != HS_SUCCESS) {
        return ierr;
    }

    if (!g_transform_banner_printed) {
        std::fprintf(stderr,
                     "TRANSFORMS_CUDA_RUNTIME version=horizontal_fused_20260724 sync=implicit size_3d=%zu\n",
                     size_3d);
        g_transform_banner_printed = true;
    }

    if (ierr == HS_SUCCESS) ierr = copy_h2d(g_transform_buffers.a, a_grid, size_3d, "transform copy a");
    if (ierr == HS_SUCCESS) ierr = copy_h2d(g_transform_buffers.b, b_grid, size_3d, "transform copy b");
    if (ierr == HS_SUCCESS) ierr = copy_h2d(g_transform_buffers.cosm, cosm_lat, static_cast<std::size_t>(nj), "transform copy cosm");
    if (ierr != HS_SUCCESS) {
        return ierr;
    }

    const int threads = 256;
    const int blocks = static_cast<int>((size_3d + threads - 1) / threads);
    divide_two_by_cos_kernel<<<blocks, threads>>>(
        static_cast<int>(size_3d), ni, nj,
        g_transform_buffers.cosm, g_transform_buffers.a, g_transform_buffers.b);
    ierr = check_cuda(cudaGetLastError(), "divide_two_by_cos_kernel launch");
    if (ierr == HS_SUCCESS) ierr = check_cuda(cudaMemcpy(a_grid, g_transform_buffers.a, size_3d * sizeof(double), cudaMemcpyDeviceToHost), "transform copy a to host");
    if (ierr == HS_SUCCESS) ierr = check_cuda(cudaMemcpy(b_grid, g_transform_buffers.b, size_3d * sizeof(double), cudaMemcpyDeviceToHost), "transform copy b to host");
    return ierr;
}

} // namespace cuda_backend
} // namespace hs_forcing
