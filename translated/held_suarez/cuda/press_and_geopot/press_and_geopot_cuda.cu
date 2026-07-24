#include "press_and_geopot_cuda.h"

#include <cmath>
#include <cstdio>
#include <cuda_runtime.h>

namespace {

constexpr int OPTION_SIMMONS_BURRIDGE = 1;
constexpr int OPTION_MCM = 2;
struct DeviceState {
    int nlev = 0;
    int use_virtual_temperature = 0;
    int vert_difference_option = OPTION_SIMMONS_BURRIDGE;
    double rdgas = 287.04;
    double rvgas = 461.50;
    double* pk = nullptr;
    double* bk = nullptr;
};

DeviceState g_state;
long long g_pressure_calls = 0;
long long g_geopot_calls = 0;
double g_pressure_seconds = 0.0;
double g_geopot_seconds = 0.0;

int check_cuda(cudaError_t status, const char* what)
{
    if (status == cudaSuccess) {
        return 0;
    }
    std::fprintf(stderr, "PRESS_GEOPOT CUDA error: %s failed: %s\n",
                 what, cudaGetErrorString(status));
    return -1;
}

void free_state()
{
    if (g_state.pk != nullptr) {
        cudaFree(g_state.pk);
        g_state.pk = nullptr;
    }
    if (g_state.bk != nullptr) {
        cudaFree(g_state.bk);
        g_state.bk = nullptr;
    }
    g_state.nlev = 0;
}

int copy_to_device(double** dst, const double* src, std::size_t count, const char* name)
{
    int ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(dst), count * sizeof(double)), name);
    if (ierr != 0) {
        return ierr;
    }
    return check_cuda(cudaMemcpy(*dst, src, count * sizeof(double), cudaMemcpyHostToDevice), name);
}

double elapsed_seconds(cudaEvent_t start, cudaEvent_t stop)
{
    float ms = 0.0f;
    cudaEventElapsedTime(&ms, start, stop);
    return static_cast<double>(ms) * 1.0e-3;
}

int start_timer(cudaEvent_t* start, cudaEvent_t* stop)
{
    int ierr = check_cuda(cudaEventCreate(start), "cudaEventCreate(start)");
    if (ierr != 0) {
        return ierr;
    }
    ierr = check_cuda(cudaEventCreate(stop), "cudaEventCreate(stop)");
    if (ierr != 0) {
        cudaEventDestroy(*start);
        return ierr;
    }
    return check_cuda(cudaEventRecord(*start), "cudaEventRecord(start)");
}

int stop_timer(cudaEvent_t start, cudaEvent_t stop, double* accumulator)
{
    int ierr = check_cuda(cudaEventRecord(stop), "cudaEventRecord(stop)");
    if (ierr == 0) {
        ierr = check_cuda(cudaEventSynchronize(stop), "cudaEventSynchronize(stop)");
    }
    if (ierr == 0) {
        *accumulator += elapsed_seconds(start, stop);
    }
    cudaEventDestroy(start);
    cudaEventDestroy(stop);
    return ierr;
}

__global__ void pressure_variables_kernel(
    int columns,
    int nlev,
    int option,
    const double* pk,
    const double* bk,
    const double* surface_p,
    double* p_half,
    double* ln_p_half,
    double* p_full,
    double* ln_p_full)
{
    const int col = blockIdx.x * blockDim.x + threadIdx.x;
    if (col >= columns) {
        return;
    }

    const int half_stride = columns;
    const int full_stride = columns;
    const double ps = surface_p[col];
    const bool top_zero = (pk[0] == 0.0 && bk[0] == 0.0);

    for (int k = 0; k <= nlev; ++k) {
        p_half[col + k * half_stride] = pk[k] + bk[k] * ps;
    }

    if (option == OPTION_MCM) {
        for (int k = 0; k < nlev; ++k) {
            const double ph0 = p_half[col + k * half_stride];
            const double ph1 = p_half[col + (k + 1) * half_stride];
            const double pf = 0.5 * (ph0 + ph1);
            p_full[col + k * full_stride] = pf;
            ln_p_full[col + k * full_stride] = log(pf);
        }
        if (top_zero) {
            ln_p_half[col] = 0.0;
            for (int k = 1; k <= nlev; ++k) {
                ln_p_half[col + k * half_stride] = log(p_half[col + k * half_stride]);
            }
        } else {
            for (int k = 0; k <= nlev; ++k) {
                ln_p_half[col + k * half_stride] = log(p_half[col + k * half_stride]);
            }
        }
        return;
    }

    if (top_zero) {
        ln_p_half[col] = 0.0;
        for (int k = 1; k <= nlev; ++k) {
            ln_p_half[col + k * half_stride] = log(p_half[col + k * half_stride]);
        }
        ln_p_full[col] = ln_p_half[col + half_stride] - 1.0;
        for (int k = 1; k < nlev; ++k) {
            const double ph0 = p_half[col + k * half_stride];
            const double ph1 = p_half[col + (k + 1) * half_stride];
            const double l0 = ln_p_half[col + k * half_stride];
            const double l1 = ln_p_half[col + (k + 1) * half_stride];
            const double alpha = 1.0 - ph0 * (l1 - l0) / (ph1 - ph0);
            ln_p_full[col + k * full_stride] = l1 - alpha;
        }
    } else {
        for (int k = 0; k <= nlev; ++k) {
            ln_p_half[col + k * half_stride] = log(p_half[col + k * half_stride]);
        }
        for (int k = 0; k < nlev; ++k) {
            const double ph0 = p_half[col + k * half_stride];
            const double ph1 = p_half[col + (k + 1) * half_stride];
            const double l0 = ln_p_half[col + k * half_stride];
            const double l1 = ln_p_half[col + (k + 1) * half_stride];
            const double alpha = 1.0 - ph0 * (l1 - l0) / (ph1 - ph0);
            ln_p_full[col + k * full_stride] = l1 - alpha;
        }
    }

    for (int k = 0; k < nlev; ++k) {
        p_full[col + k * full_stride] = exp(ln_p_full[col + k * full_stride]);
    }
}

__global__ void compute_geopotential_kernel(
    int columns,
    int nlev,
    int use_virtual_temperature,
    double rdgas,
    double rvgas,
    const double* pk,
    const double* t_grid,
    const double* ln_p_half,
    const double* ln_p_full,
    const double* surf_geopotential,
    const double* q_grid,
    int has_q_grid,
    double* geopot_full,
    double* geopot_half)
{
    const int col = blockIdx.x * blockDim.x + threadIdx.x;
    if (col >= columns) {
        return;
    }

    const int half_stride = columns;
    const int full_stride = columns;
    const int ktop = (pk[0] == 0.0) ? 1 : 0;
    const double virtual_coeff = rvgas / rdgas - 1.0;

    geopot_half[col + nlev * half_stride] = surf_geopotential[col];
    if (ktop == 1) {
        geopot_half[col] = 0.0;
    }

    for (int k = nlev - 1; k >= ktop; --k) {
        double virtual_t = t_grid[col + k * full_stride];
        if (use_virtual_temperature && has_q_grid) {
            virtual_t *= 1.0 + virtual_coeff * q_grid[col + k * full_stride];
        }
        const double delta_ln =
            ln_p_half[col + (k + 1) * half_stride] - ln_p_half[col + k * half_stride];
        geopot_half[col + k * half_stride] =
            geopot_half[col + (k + 1) * half_stride] + rdgas * virtual_t * delta_ln;
    }

    for (int k = 0; k < nlev; ++k) {
        double virtual_t = t_grid[col + k * full_stride];
        if (use_virtual_temperature && has_q_grid) {
            virtual_t *= 1.0 + virtual_coeff * q_grid[col + k * full_stride];
        }
        const double delta_ln =
            ln_p_half[col + (k + 1) * half_stride] - ln_p_full[col + k * full_stride];
        geopot_full[col + k * full_stride] =
            geopot_half[col + (k + 1) * half_stride] + rdgas * virtual_t * delta_ln;
    }
}

} // namespace

extern "C" int press_geopot_cuda_init_c(
    int nlev,
    const double* pk,
    const double* bk,
    double rdgas,
    double rvgas,
    int use_virtual_temperature,
    int vert_difference_option)
{
    int device_count = 0;
    int ierr = check_cuda(cudaGetDeviceCount(&device_count), "cudaGetDeviceCount");
    if (ierr != 0 || device_count <= 0) {
        return -1;
    }

    free_state();
    g_state.nlev = nlev;
    g_state.use_virtual_temperature = use_virtual_temperature;
    g_state.vert_difference_option = vert_difference_option;
    g_state.rdgas = rdgas;
    g_state.rvgas = rvgas;
    ierr = copy_to_device(&g_state.pk, pk, static_cast<std::size_t>(nlev + 1), "pk");
    if (ierr != 0) {
        free_state();
        return ierr;
    }
    ierr = copy_to_device(&g_state.bk, bk, static_cast<std::size_t>(nlev + 1), "bk");
    if (ierr != 0) {
        free_state();
        return ierr;
    }

    std::fprintf(stderr,
                 "PRESS_GEOPOT_CUDA_RUNTIME version=column_cuda_20260724 nlev=%d option=%d virtual_t=%d\n",
                 nlev, vert_difference_option, use_virtual_temperature);
    return 0;
}

extern "C" int press_geopot_pressure_variables_cuda_c(
    int ni,
    int nj,
    int nlev,
    double* p_half,
    double* ln_p_half,
    double* p_full,
    double* ln_p_full,
    const double* surface_p)
{
    if (g_state.pk == nullptr || g_state.bk == nullptr || nlev != g_state.nlev) {
        return -2;
    }

    const int columns = ni * nj;
    const std::size_t count_2d = static_cast<std::size_t>(columns);
    const std::size_t count_full = static_cast<std::size_t>(columns) * static_cast<std::size_t>(nlev);
    const std::size_t count_half = static_cast<std::size_t>(columns) * static_cast<std::size_t>(nlev + 1);

    double *d_surface_p = nullptr, *d_p_half = nullptr, *d_ln_p_half = nullptr;
    double *d_p_full = nullptr, *d_ln_p_full = nullptr;
    cudaEvent_t start{}, stop{};
    int ierr = start_timer(&start, &stop);
    if (ierr != 0) return ierr;

    ierr = copy_to_device(&d_surface_p, surface_p, count_2d, "surface_p");
    if (ierr == 0) ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(&d_p_half), count_half * sizeof(double)), "p_half");
    if (ierr == 0) ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(&d_ln_p_half), count_half * sizeof(double)), "ln_p_half");
    if (ierr == 0) ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(&d_p_full), count_full * sizeof(double)), "p_full");
    if (ierr == 0) ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(&d_ln_p_full), count_full * sizeof(double)), "ln_p_full");

    if (ierr == 0) {
        const int block = 128;
        const int grid = (columns + block - 1) / block;
        pressure_variables_kernel<<<grid, block>>>(
            columns, nlev, g_state.vert_difference_option, g_state.pk, g_state.bk,
            d_surface_p, d_p_half, d_ln_p_half, d_p_full, d_ln_p_full);
        ierr = check_cuda(cudaGetLastError(), "pressure_variables_kernel");
    }

    if (ierr == 0) ierr = check_cuda(cudaMemcpy(p_half, d_p_half, count_half * sizeof(double), cudaMemcpyDeviceToHost), "copy p_half");
    if (ierr == 0) ierr = check_cuda(cudaMemcpy(ln_p_half, d_ln_p_half, count_half * sizeof(double), cudaMemcpyDeviceToHost), "copy ln_p_half");
    if (ierr == 0) ierr = check_cuda(cudaMemcpy(p_full, d_p_full, count_full * sizeof(double), cudaMemcpyDeviceToHost), "copy p_full");
    if (ierr == 0) ierr = check_cuda(cudaMemcpy(ln_p_full, d_ln_p_full, count_full * sizeof(double), cudaMemcpyDeviceToHost), "copy ln_p_full");

    cudaFree(d_surface_p);
    cudaFree(d_p_half);
    cudaFree(d_ln_p_half);
    cudaFree(d_p_full);
    cudaFree(d_ln_p_full);

    if (ierr == 0) {
        ++g_pressure_calls;
    }
    stop_timer(start, stop, &g_pressure_seconds);
    return ierr;
}

extern "C" int press_geopot_compute_geopotential_cuda_c(
    int ni,
    int nj,
    int nlev,
    const double* t_grid,
    const double* ln_p_half,
    const double* ln_p_full,
    const double* surf_geopotential,
    double* geopot_full,
    double* geopot_half,
    const double* q_grid,
    int has_q_grid)
{
    if (g_state.pk == nullptr || nlev != g_state.nlev) {
        return -2;
    }
    if (g_state.use_virtual_temperature && !has_q_grid) {
        return -3;
    }

    const int columns = ni * nj;
    const std::size_t count_2d = static_cast<std::size_t>(columns);
    const std::size_t count_full = static_cast<std::size_t>(columns) * static_cast<std::size_t>(nlev);
    const std::size_t count_half = static_cast<std::size_t>(columns) * static_cast<std::size_t>(nlev + 1);

    double *d_t_grid = nullptr, *d_ln_p_half = nullptr, *d_ln_p_full = nullptr;
    double *d_surf_geopotential = nullptr, *d_geopot_full = nullptr, *d_geopot_half = nullptr;
    double* d_q_grid = nullptr;
    cudaEvent_t start{}, stop{};
    int ierr = start_timer(&start, &stop);
    if (ierr != 0) return ierr;

    ierr = copy_to_device(&d_t_grid, t_grid, count_full, "t_grid");
    if (ierr == 0) ierr = copy_to_device(&d_ln_p_half, ln_p_half, count_half, "ln_p_half");
    if (ierr == 0) ierr = copy_to_device(&d_ln_p_full, ln_p_full, count_full, "ln_p_full");
    if (ierr == 0) ierr = copy_to_device(&d_surf_geopotential, surf_geopotential, count_2d, "surf_geopotential");
    if (ierr == 0 && has_q_grid) ierr = copy_to_device(&d_q_grid, q_grid, count_full, "q_grid");
    if (ierr == 0) ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(&d_geopot_full), count_full * sizeof(double)), "geopot_full");
    if (ierr == 0) ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(&d_geopot_half), count_half * sizeof(double)), "geopot_half");

    if (ierr == 0) {
        const int block = 128;
        const int grid = (columns + block - 1) / block;
        compute_geopotential_kernel<<<grid, block>>>(
            columns, nlev, g_state.use_virtual_temperature, g_state.rdgas, g_state.rvgas, g_state.pk,
            d_t_grid, d_ln_p_half, d_ln_p_full, d_surf_geopotential,
            d_q_grid, has_q_grid, d_geopot_full, d_geopot_half);
        ierr = check_cuda(cudaGetLastError(), "compute_geopotential_kernel");
    }

    if (ierr == 0) ierr = check_cuda(cudaMemcpy(geopot_full, d_geopot_full, count_full * sizeof(double), cudaMemcpyDeviceToHost), "copy geopot_full");
    if (ierr == 0) ierr = check_cuda(cudaMemcpy(geopot_half, d_geopot_half, count_half * sizeof(double), cudaMemcpyDeviceToHost), "copy geopot_half");

    cudaFree(d_t_grid);
    cudaFree(d_ln_p_half);
    cudaFree(d_ln_p_full);
    cudaFree(d_surf_geopotential);
    cudaFree(d_q_grid);
    cudaFree(d_geopot_full);
    cudaFree(d_geopot_half);

    if (ierr == 0) {
        ++g_geopot_calls;
    }
    stop_timer(start, stop, &g_geopot_seconds);
    return ierr;
}

extern "C" void press_geopot_cuda_finalize_c(void)
{
    free_state();
}

extern "C" void press_geopot_cuda_profile_print_c(void)
{
    if (g_pressure_calls > 0) {
        std::fprintf(stderr,
                     "PROFILE_PRESS_GEOPOT backend=cuda name=pressure_variables calls=%lld total_s=%.9f avg_s=%.9e\n",
                     g_pressure_calls, g_pressure_seconds,
                     g_pressure_seconds / static_cast<double>(g_pressure_calls));
    }
    if (g_geopot_calls > 0) {
        std::fprintf(stderr,
                     "PROFILE_PRESS_GEOPOT backend=cuda name=compute_geopotential calls=%lld total_s=%.9f avg_s=%.9e\n",
                     g_geopot_calls, g_geopot_seconds,
                     g_geopot_seconds / static_cast<double>(g_geopot_calls));
    }
}
