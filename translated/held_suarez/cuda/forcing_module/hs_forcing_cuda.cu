#include "hs_forcing_cuda.h"
#include "hs_forcing_cuda_kernels.cuh"

#include "../../cpp/forcing_module/include/held_suarez_c_api.h"

#include <cufft.h>
#include <algorithm>
#include <cstddef>
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

struct SphericalFourierBuffers {
    std::size_t spherical_size = 0;
    std::size_t fourier_size = 0;
    std::size_t legendre_size = 0;
    std::size_t jstart_size = 0;
    cufftDoubleComplex* spherical = nullptr;
    cufftDoubleComplex* fourier = nullptr;
    double* legendre = nullptr;
    double* legendre_wts = nullptr;
    int* jstart = nullptr;
    bool legendre_ready = false;
    bool legendre_wts_ready = false;
    bool jstart_ready = false;
};

SphericalFourierBuffers g_spherical_fourier_buffers;
bool g_spherical_fourier_banner_printed = false;

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

void free_complex_ptr(cufftDoubleComplex*& ptr)
{
    if (ptr != nullptr) {
        cudaFree(ptr);
        ptr = nullptr;
    }
}

void free_int_ptr(int*& ptr)
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

void free_spherical_fourier_buffers()
{
    free_complex_ptr(g_spherical_fourier_buffers.spherical);
    free_complex_ptr(g_spherical_fourier_buffers.fourier);
    free_ptr(g_spherical_fourier_buffers.legendre);
    free_ptr(g_spherical_fourier_buffers.legendre_wts);
    free_int_ptr(g_spherical_fourier_buffers.jstart);
    g_spherical_fourier_buffers.spherical_size = 0;
    g_spherical_fourier_buffers.fourier_size = 0;
    g_spherical_fourier_buffers.legendre_size = 0;
    g_spherical_fourier_buffers.jstart_size = 0;
    g_spherical_fourier_buffers.legendre_ready = false;
    g_spherical_fourier_buffers.legendre_wts_ready = false;
    g_spherical_fourier_buffers.jstart_ready = false;
}

int alloc_ptr(double*& ptr, std::size_t count, const char* name)
{
    return check_cuda(cudaMalloc(reinterpret_cast<void**>(&ptr), count * sizeof(double)), name);
}

int alloc_complex_ptr(cufftDoubleComplex*& ptr, std::size_t count, const char* name)
{
    return check_cuda(cudaMalloc(reinterpret_cast<void**>(&ptr), count * sizeof(cufftDoubleComplex)), name);
}

int alloc_int_ptr(int*& ptr, std::size_t count, const char* name)
{
    return check_cuda(cudaMalloc(reinterpret_cast<void**>(&ptr), count * sizeof(int)), name);
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

int ensure_spherical_fourier_buffers(
    std::size_t spherical_size,
    std::size_t fourier_size,
    std::size_t legendre_size,
    std::size_t jstart_size)
{
    if (g_spherical_fourier_buffers.spherical_size == spherical_size &&
        g_spherical_fourier_buffers.fourier_size == fourier_size &&
        g_spherical_fourier_buffers.legendre_size == legendre_size &&
        g_spherical_fourier_buffers.jstart_size == jstart_size) {
        return HS_SUCCESS;
    }

    free_spherical_fourier_buffers();

    int ierr = alloc_complex_ptr(g_spherical_fourier_buffers.spherical, spherical_size, "sf spherical");
    if (ierr == HS_SUCCESS) ierr = alloc_complex_ptr(g_spherical_fourier_buffers.fourier, fourier_size, "sf fourier");
    if (ierr == HS_SUCCESS) ierr = alloc_ptr(g_spherical_fourier_buffers.legendre, legendre_size, "sf legendre");
    if (ierr == HS_SUCCESS) ierr = alloc_ptr(g_spherical_fourier_buffers.legendre_wts, legendre_size, "sf legendre_wts");
    if (ierr == HS_SUCCESS) ierr = alloc_int_ptr(g_spherical_fourier_buffers.jstart, jstart_size, "sf jstart");

    if (ierr != HS_SUCCESS) {
        free_spherical_fourier_buffers();
        return ierr;
    }

    g_spherical_fourier_buffers.spherical_size = spherical_size;
    g_spherical_fourier_buffers.fourier_size = fourier_size;
    g_spherical_fourier_buffers.legendre_size = legendre_size;
    g_spherical_fourier_buffers.jstart_size = jstart_size;
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

__device__ inline cufftDoubleComplex cadd(cufftDoubleComplex a, cufftDoubleComplex b)
{
    return make_cuDoubleComplex(a.x + b.x, a.y + b.y);
}

__device__ inline cufftDoubleComplex csub(cufftDoubleComplex a, cufftDoubleComplex b)
{
    return make_cuDoubleComplex(a.x - b.x, a.y - b.y);
}

__device__ inline cufftDoubleComplex cmul_real(cufftDoubleComplex a, double b)
{
    return make_cuDoubleComplex(a.x * b, a.y * b);
}

__global__ void spherical_to_fourier_kernel(
    int total_tasks,
    const cufftDoubleComplex* spherical,
    cufftDoubleComplex* fourier,
    const double* legendre,
    const int* jstart,
    int nm,
    int nn,
    int nk,
    int nj,
    int nd,
    int ns,
    int ne,
    int neven,
    int nodd,
    int south_to_north)
{
    const int task = blockIdx.x * blockDim.x + threadIdx.x;
    if (task >= total_tasks) {
        return;
    }

    int t = task;
    const int m0 = t % nm;
    t /= nm;
    const int k0 = t % nk;
    t /= nk;
    const int j0 = t % nj;
    const int jd0 = t / nj;

    if ((nd % 2) == 0 && jd0 == nd / 2) {
        return;
    }
    if ((nd % 2) != 0 && jd0 == nd / 2 && j0 >= nj / 2) {
        return;
    }

    const int jhem0 = (jstart[jd0] - 1) + j0;
    cufftDoubleComplex x_even = make_cuDoubleComplex(0.0, 0.0);
    cufftDoubleComplex x_odd = make_cuDoubleComplex(0.0, 0.0);

    for (int n = neven; n <= ne; n += 2) {
        const int n0 = n - ns;
        const double leg = legendre[m0 + nm * (n0 + nn * jhem0)];
        x_even = cadd(x_even, cmul_real(spherical[m0 + nm * (n0 + nn * k0)], leg));
    }
    for (int n = nodd; n <= ne; n += 2) {
        const int n0 = n - ns;
        const double leg = legendre[m0 + nm * (n0 + nn * jhem0)];
        x_odd = cadd(x_odd, cmul_real(spherical[m0 + nm * (n0 + nn * k0)], leg));
    }

    const int mirror_j0 = nj - 1 - j0;
    const int mirror_jd0 = nd - 1 - jd0;
    const size_t left = static_cast<size_t>(m0) + static_cast<size_t>(nm) *
        (static_cast<size_t>(j0) + static_cast<size_t>(nj) *
        (static_cast<size_t>(k0) + static_cast<size_t>(nk) * static_cast<size_t>(jd0)));
    const size_t right = static_cast<size_t>(m0) + static_cast<size_t>(nm) *
        (static_cast<size_t>(mirror_j0) + static_cast<size_t>(nj) *
        (static_cast<size_t>(k0) + static_cast<size_t>(nk) * static_cast<size_t>(mirror_jd0)));

    if (south_to_north) {
        fourier[left] = csub(x_even, x_odd);
        fourier[right] = cadd(x_even, x_odd);
    } else {
        fourier[left] = cadd(x_even, x_odd);
        fourier[right] = csub(x_even, x_odd);
    }
}

__global__ void fourier_to_spherical_kernel(
    int total_tasks,
    const cufftDoubleComplex* fourier,
    cufftDoubleComplex* spherical,
    const double* legendre_wts,
    const int* jstart,
    int nm,
    int nn,
    int nk,
    int nj,
    int nd,
    int ns,
    int ne,
    int neven,
    int nodd,
    int south_to_north)
{
    const int task = blockIdx.x * blockDim.x + threadIdx.x;
    if (task >= total_tasks) {
        return;
    }

    int t = task;
    const int m0 = t % nm;
    t /= nm;
    const int k0 = t % nk;
    t /= nk;
    const int j0 = t % nj;
    const int jd0 = t / nj;

    if ((nd % 2) == 0 && jd0 == nd / 2) {
        return;
    }
    if ((nd % 2) != 0 && jd0 == nd / 2 && j0 >= nj / 2) {
        return;
    }

    const int mirror_j0 = nj - 1 - j0;
    const int mirror_jd0 = nd - 1 - jd0;
    const size_t left = static_cast<size_t>(m0) + static_cast<size_t>(nm) *
        (static_cast<size_t>(j0) + static_cast<size_t>(nj) *
        (static_cast<size_t>(k0) + static_cast<size_t>(nk) * static_cast<size_t>(jd0)));
    const size_t right = static_cast<size_t>(m0) + static_cast<size_t>(nm) *
        (static_cast<size_t>(mirror_j0) + static_cast<size_t>(nj) *
        (static_cast<size_t>(k0) + static_cast<size_t>(nk) * static_cast<size_t>(mirror_jd0)));

    cufftDoubleComplex x_even;
    cufftDoubleComplex x_odd;
    if (south_to_north) {
        x_even = cadd(fourier[right], fourier[left]);
        x_odd = csub(fourier[right], fourier[left]);
    } else {
        x_even = cadd(fourier[left], fourier[right]);
        x_odd = csub(fourier[left], fourier[right]);
    }

    const int jhem0 = (jstart[jd0] - 1) + j0;
    for (int n = neven; n <= ne; n += 2) {
        const int n0 = n - ns;
        const double leg = legendre_wts[m0 + nm * (n0 + nn * jhem0)];
        const size_t idx = static_cast<size_t>(m0) + static_cast<size_t>(nm) *
            (static_cast<size_t>(n0) + static_cast<size_t>(nn) * static_cast<size_t>(k0));
        atomicAdd(&spherical[idx].x, x_even.x * leg);
        atomicAdd(&spherical[idx].y, x_even.y * leg);
    }
    for (int n = nodd; n <= ne; n += 2) {
        const int n0 = n - ns;
        const double leg = legendre_wts[m0 + nm * (n0 + nn * jhem0)];
        const size_t idx = static_cast<size_t>(m0) + static_cast<size_t>(nm) *
            (static_cast<size_t>(n0) + static_cast<size_t>(nn) * static_cast<size_t>(k0));
        atomicAdd(&spherical[idx].x, x_odd.x * leg);
        atomicAdd(&spherical[idx].y, x_odd.y * leg);
    }
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

extern "C" int spherical_fourier_s2f_cuda_c(
    const cufftDoubleComplex* spherical,
    cufftDoubleComplex* fourier,
    const double* legendre,
    const int* jstart,
    int nm,
    int nn,
    int nk,
    int nj,
    int nd,
    int ns,
    int ne,
    int neven,
    int nodd,
    int south_to_north)
{
    if (spherical == nullptr || fourier == nullptr || legendre == nullptr || jstart == nullptr) {
        return HS_ERROR_NULL_POINTER;
    }
    if (nm <= 0 || nn <= 0 || nk <= 0 || nj <= 0 || nd <= 0 || ne < ns) {
        return HS_ERROR_INVALID_CONFIG;
    }

    int device_count = 0;
    int ierr = check_cuda(cudaGetDeviceCount(&device_count), "cudaGetDeviceCount");
    if (ierr != HS_SUCCESS || device_count <= 0) {
        return HS_ERROR_INVALID_CONFIG;
    }

    const std::size_t spherical_size =
        static_cast<std::size_t>(nm) * static_cast<std::size_t>(nn) * static_cast<std::size_t>(nk);
    const std::size_t fourier_size =
        static_cast<std::size_t>(nm) * static_cast<std::size_t>(nj) * static_cast<std::size_t>(nk) * static_cast<std::size_t>(nd);
    const std::size_t legendre_size =
        static_cast<std::size_t>(nm) * static_cast<std::size_t>(nn) * static_cast<std::size_t>((nj * nd + 1) / 2);

    ierr = ensure_spherical_fourier_buffers(spherical_size, fourier_size, legendre_size, static_cast<std::size_t>(nd));
    if (ierr != HS_SUCCESS) {
        return ierr;
    }

    if (!g_spherical_fourier_banner_printed) {
        std::fprintf(stderr,
                     "SPHERICAL_FOURIER_CUDA_RUNTIME version=legendre_parallel_20260724 sync=implicit nm=%d nn=%d nk=%d nj=%d nd=%d\n",
                     nm, nn, nk, nj, nd);
        g_spherical_fourier_banner_printed = true;
    }

    if (ierr == HS_SUCCESS) ierr = check_cuda(cudaMemcpy(g_spherical_fourier_buffers.spherical, spherical, spherical_size * sizeof(cufftDoubleComplex), cudaMemcpyHostToDevice), "sf copy spherical");
    if (ierr == HS_SUCCESS && !g_spherical_fourier_buffers.legendre_ready) {
        ierr = check_cuda(cudaMemcpy(g_spherical_fourier_buffers.legendre, legendre, legendre_size * sizeof(double), cudaMemcpyHostToDevice), "sf copy legendre");
        if (ierr == HS_SUCCESS) g_spherical_fourier_buffers.legendre_ready = true;
    }
    if (ierr == HS_SUCCESS && !g_spherical_fourier_buffers.jstart_ready) {
        ierr = check_cuda(cudaMemcpy(g_spherical_fourier_buffers.jstart, jstart, static_cast<std::size_t>(nd) * sizeof(int), cudaMemcpyHostToDevice), "sf copy jstart");
        if (ierr == HS_SUCCESS) g_spherical_fourier_buffers.jstart_ready = true;
    }
    if (ierr != HS_SUCCESS) {
        return ierr;
    }

    const int jd_count = nd / 2 + 1;
    const int total_tasks = nm * nk * nj * jd_count;
    const int threads = 128;
    const int blocks = (total_tasks + threads - 1) / threads;
    spherical_to_fourier_kernel<<<blocks, threads>>>(
        total_tasks,
        g_spherical_fourier_buffers.spherical,
        g_spherical_fourier_buffers.fourier,
        g_spherical_fourier_buffers.legendre,
        g_spherical_fourier_buffers.jstart,
        nm, nn, nk, nj, nd, ns, ne, neven, nodd, south_to_north);
    ierr = check_cuda(cudaGetLastError(), "spherical_to_fourier_kernel launch");
    if (ierr == HS_SUCCESS) {
        ierr = check_cuda(cudaMemcpy(fourier, g_spherical_fourier_buffers.fourier, fourier_size * sizeof(cufftDoubleComplex), cudaMemcpyDeviceToHost), "sf copy fourier to host");
    }
    return ierr;
}

extern "C" int spherical_fourier_f2s_cuda_c(
    const cufftDoubleComplex* fourier,
    cufftDoubleComplex* spherical,
    const double* legendre_wts,
    const int* jstart,
    int nm,
    int nn,
    int nk,
    int nj,
    int nd,
    int ns,
    int ne,
    int neven,
    int nodd,
    int south_to_north)
{
    if (spherical == nullptr || fourier == nullptr || legendre_wts == nullptr || jstart == nullptr) {
        return HS_ERROR_NULL_POINTER;
    }
    if (nm <= 0 || nn <= 0 || nk <= 0 || nj <= 0 || nd <= 0 || ne < ns) {
        return HS_ERROR_INVALID_CONFIG;
    }

    int device_count = 0;
    int ierr = check_cuda(cudaGetDeviceCount(&device_count), "cudaGetDeviceCount");
    if (ierr != HS_SUCCESS || device_count <= 0) {
        return HS_ERROR_INVALID_CONFIG;
    }

    const std::size_t spherical_size =
        static_cast<std::size_t>(nm) * static_cast<std::size_t>(nn) * static_cast<std::size_t>(nk);
    const std::size_t fourier_size =
        static_cast<std::size_t>(nm) * static_cast<std::size_t>(nj) * static_cast<std::size_t>(nk) * static_cast<std::size_t>(nd);
    const std::size_t legendre_size =
        static_cast<std::size_t>(nm) * static_cast<std::size_t>(nn) * static_cast<std::size_t>((nj * nd + 1) / 2);

    ierr = ensure_spherical_fourier_buffers(spherical_size, fourier_size, legendre_size, static_cast<std::size_t>(nd));
    if (ierr != HS_SUCCESS) {
        return ierr;
    }

    if (!g_spherical_fourier_banner_printed) {
        std::fprintf(stderr,
                     "SPHERICAL_FOURIER_CUDA_RUNTIME version=legendre_parallel_20260724 sync=implicit nm=%d nn=%d nk=%d nj=%d nd=%d\n",
                     nm, nn, nk, nj, nd);
        g_spherical_fourier_banner_printed = true;
    }

    if (ierr == HS_SUCCESS) ierr = check_cuda(cudaMemcpy(g_spherical_fourier_buffers.fourier, fourier, fourier_size * sizeof(cufftDoubleComplex), cudaMemcpyHostToDevice), "sf copy fourier");
    if (ierr == HS_SUCCESS && !g_spherical_fourier_buffers.legendre_wts_ready) {
        ierr = check_cuda(cudaMemcpy(g_spherical_fourier_buffers.legendre_wts, legendre_wts, legendre_size * sizeof(double), cudaMemcpyHostToDevice), "sf copy legendre_wts");
        if (ierr == HS_SUCCESS) g_spherical_fourier_buffers.legendre_wts_ready = true;
    }
    if (ierr == HS_SUCCESS && !g_spherical_fourier_buffers.jstart_ready) {
        ierr = check_cuda(cudaMemcpy(g_spherical_fourier_buffers.jstart, jstart, static_cast<std::size_t>(nd) * sizeof(int), cudaMemcpyHostToDevice), "sf copy jstart");
        if (ierr == HS_SUCCESS) g_spherical_fourier_buffers.jstart_ready = true;
    }
    if (ierr == HS_SUCCESS) ierr = check_cuda(cudaMemset(g_spherical_fourier_buffers.spherical, 0, spherical_size * sizeof(cufftDoubleComplex)), "sf clear spherical");
    if (ierr != HS_SUCCESS) {
        return ierr;
    }

    const int jd_count = nd / 2 + 1;
    const int total_tasks = nm * nk * nj * jd_count;
    const int threads = 128;
    const int blocks = (total_tasks + threads - 1) / threads;
    fourier_to_spherical_kernel<<<blocks, threads>>>(
        total_tasks,
        g_spherical_fourier_buffers.fourier,
        g_spherical_fourier_buffers.spherical,
        g_spherical_fourier_buffers.legendre_wts,
        g_spherical_fourier_buffers.jstart,
        nm, nn, nk, nj, nd, ns, ne, neven, nodd, south_to_north);
    ierr = check_cuda(cudaGetLastError(), "fourier_to_spherical_kernel launch");
    if (ierr == HS_SUCCESS) {
        ierr = check_cuda(cudaMemcpy(spherical, g_spherical_fourier_buffers.spherical, spherical_size * sizeof(cufftDoubleComplex), cudaMemcpyDeviceToHost), "sf copy spherical to host");
    }
    return ierr;
}

} // namespace cuda_backend
} // namespace hs_forcing
