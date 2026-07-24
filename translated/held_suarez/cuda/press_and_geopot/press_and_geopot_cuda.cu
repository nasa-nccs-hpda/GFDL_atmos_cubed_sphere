#include "press_and_geopot_cuda.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cuda_runtime.h>

namespace {

constexpr int OPTION_SIMMONS_BURRIDGE = 1;
constexpr int OPTION_MCM = 2;
struct DeviceState {
    int nlev = 0;
    int columns = 0;
    int has_buffers = 0;
    int use_virtual_temperature = 0;
    int vert_difference_option = OPTION_SIMMONS_BURRIDGE;
    double rdgas = 287.04;
    double rvgas = 461.50;
    double* pk = nullptr;
    double* bk = nullptr;
    double* surface_p = nullptr;
    double* p_half = nullptr;
    double* ln_p_half = nullptr;
    double* p_full = nullptr;
    double* ln_p_full = nullptr;
    double* t_grid = nullptr;
    double* surf_geopotential = nullptr;
    double* geopot_full = nullptr;
    double* geopot_half = nullptr;
    double* q_grid = nullptr;
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
    if (g_state.surface_p != nullptr) cudaFree(g_state.surface_p);
    if (g_state.p_half != nullptr) cudaFree(g_state.p_half);
    if (g_state.ln_p_half != nullptr) cudaFree(g_state.ln_p_half);
    if (g_state.p_full != nullptr) cudaFree(g_state.p_full);
    if (g_state.ln_p_full != nullptr) cudaFree(g_state.ln_p_full);
    if (g_state.t_grid != nullptr) cudaFree(g_state.t_grid);
    if (g_state.surf_geopotential != nullptr) cudaFree(g_state.surf_geopotential);
    if (g_state.geopot_full != nullptr) cudaFree(g_state.geopot_full);
    if (g_state.geopot_half != nullptr) cudaFree(g_state.geopot_half);
    if (g_state.q_grid != nullptr) cudaFree(g_state.q_grid);
    g_state.surface_p = nullptr;
    g_state.p_half = nullptr;
    g_state.ln_p_half = nullptr;
    g_state.p_full = nullptr;
    g_state.ln_p_full = nullptr;
    g_state.t_grid = nullptr;
    g_state.surf_geopotential = nullptr;
    g_state.geopot_full = nullptr;
    g_state.geopot_half = nullptr;
    g_state.q_grid = nullptr;
    g_state.nlev = 0;
    g_state.columns = 0;
    g_state.has_buffers = 0;
}

int copy_to_device(double** dst, const double* src, std::size_t count, const char* name)
{
    int ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(dst), count * sizeof(double)), name);
    if (ierr != 0) {
        return ierr;
    }
    return check_cuda(cudaMemcpy(*dst, src, count * sizeof(double), cudaMemcpyHostToDevice), name);
}

int allocate_model_buffers(int columns, int nlev)
{
    if (g_state.has_buffers && g_state.columns == columns) {
        return 0;
    }

    if (g_state.surface_p != nullptr) cudaFree(g_state.surface_p);
    if (g_state.p_half != nullptr) cudaFree(g_state.p_half);
    if (g_state.ln_p_half != nullptr) cudaFree(g_state.ln_p_half);
    if (g_state.p_full != nullptr) cudaFree(g_state.p_full);
    if (g_state.ln_p_full != nullptr) cudaFree(g_state.ln_p_full);
    if (g_state.t_grid != nullptr) cudaFree(g_state.t_grid);
    if (g_state.surf_geopotential != nullptr) cudaFree(g_state.surf_geopotential);
    if (g_state.geopot_full != nullptr) cudaFree(g_state.geopot_full);
    if (g_state.geopot_half != nullptr) cudaFree(g_state.geopot_half);
    if (g_state.q_grid != nullptr) cudaFree(g_state.q_grid);
    g_state.surface_p = nullptr;
    g_state.p_half = nullptr;
    g_state.ln_p_half = nullptr;
    g_state.p_full = nullptr;
    g_state.ln_p_full = nullptr;
    g_state.t_grid = nullptr;
    g_state.surf_geopotential = nullptr;
    g_state.geopot_full = nullptr;
    g_state.geopot_half = nullptr;
    g_state.q_grid = nullptr;
    g_state.has_buffers = 0;

    const std::size_t count_2d = static_cast<std::size_t>(columns);
    const std::size_t count_full = count_2d * static_cast<std::size_t>(nlev);
    const std::size_t count_half = count_2d * static_cast<std::size_t>(nlev + 1);

    int ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(&g_state.surface_p), count_2d * sizeof(double)), "surface_p");
    if (ierr == 0) ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(&g_state.p_half), count_half * sizeof(double)), "p_half");
    if (ierr == 0) ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(&g_state.ln_p_half), count_half * sizeof(double)), "ln_p_half");
    if (ierr == 0) ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(&g_state.p_full), count_full * sizeof(double)), "p_full");
    if (ierr == 0) ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(&g_state.ln_p_full), count_full * sizeof(double)), "ln_p_full");
    if (ierr == 0) ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(&g_state.t_grid), count_full * sizeof(double)), "t_grid");
    if (ierr == 0) ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(&g_state.surf_geopotential), count_2d * sizeof(double)), "surf_geopotential");
    if (ierr == 0) ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(&g_state.geopot_full), count_full * sizeof(double)), "geopot_full");
    if (ierr == 0) ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(&g_state.geopot_half), count_half * sizeof(double)), "geopot_half");
    if (ierr == 0) ierr = check_cuda(cudaMalloc(reinterpret_cast<void**>(&g_state.q_grid), count_full * sizeof(double)), "q_grid");

    if (ierr != 0) {
        free_state();
        return ierr;
    }

    g_state.columns = columns;
    g_state.has_buffers = 1;
    return 0;
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
    if (!env_enabled("PRESS_GEOPOT_CUDA_ENABLE", false)) {
        std::fprintf(stderr,
                     "PRESS_GEOPOT_CUDA_RUNTIME version=column_cuda_20260724 disabled=1 set_PRESS_GEOPOT_CUDA_ENABLE=1_to_enable\n");
        return -10;
    }

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

    cudaEvent_t start{}, stop{};
    int ierr = start_timer(&start, &stop);
    if (ierr != 0) return ierr;

    ierr = allocate_model_buffers(columns, nlev);
    if (ierr == 0) {
        ierr = check_cuda(cudaMemcpy(g_state.surface_p, surface_p, count_2d * sizeof(double), cudaMemcpyHostToDevice), "copy surface_p");
    }

    if (ierr == 0) {
        const int block = 128;
        const int grid = (columns + block - 1) / block;
        pressure_variables_kernel<<<grid, block>>>(
            columns, nlev, g_state.vert_difference_option, g_state.pk, g_state.bk,
            g_state.surface_p, g_state.p_half, g_state.ln_p_half,
            g_state.p_full, g_state.ln_p_full);
        ierr = check_cuda(cudaGetLastError(), "pressure_variables_kernel");
    }

    if (ierr == 0) ierr = check_cuda(cudaMemcpy(p_half, g_state.p_half, count_half * sizeof(double), cudaMemcpyDeviceToHost), "copy p_half");
    if (ierr == 0) ierr = check_cuda(cudaMemcpy(ln_p_half, g_state.ln_p_half, count_half * sizeof(double), cudaMemcpyDeviceToHost), "copy ln_p_half");
    if (ierr == 0) ierr = check_cuda(cudaMemcpy(p_full, g_state.p_full, count_full * sizeof(double), cudaMemcpyDeviceToHost), "copy p_full");
    if (ierr == 0) ierr = check_cuda(cudaMemcpy(ln_p_full, g_state.ln_p_full, count_full * sizeof(double), cudaMemcpyDeviceToHost), "copy ln_p_full");

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

    cudaEvent_t start{}, stop{};
    int ierr = start_timer(&start, &stop);
    if (ierr != 0) return ierr;

    ierr = allocate_model_buffers(columns, nlev);
    if (ierr == 0) ierr = check_cuda(cudaMemcpy(g_state.t_grid, t_grid, count_full * sizeof(double), cudaMemcpyHostToDevice), "copy t_grid");
    if (ierr == 0) ierr = check_cuda(cudaMemcpy(g_state.ln_p_half, ln_p_half, count_half * sizeof(double), cudaMemcpyHostToDevice), "copy ln_p_half");
    if (ierr == 0) ierr = check_cuda(cudaMemcpy(g_state.ln_p_full, ln_p_full, count_full * sizeof(double), cudaMemcpyHostToDevice), "copy ln_p_full");
    if (ierr == 0) ierr = check_cuda(cudaMemcpy(g_state.surf_geopotential, surf_geopotential, count_2d * sizeof(double), cudaMemcpyHostToDevice), "copy surf_geopotential");
    if (ierr == 0 && has_q_grid) ierr = check_cuda(cudaMemcpy(g_state.q_grid, q_grid, count_full * sizeof(double), cudaMemcpyHostToDevice), "copy q_grid");

    if (ierr == 0) {
        const int block = 128;
        const int grid = (columns + block - 1) / block;
        compute_geopotential_kernel<<<grid, block>>>(
            columns, nlev, g_state.use_virtual_temperature, g_state.rdgas, g_state.rvgas, g_state.pk,
            g_state.t_grid, g_state.ln_p_half, g_state.ln_p_full,
            g_state.surf_geopotential, g_state.q_grid, has_q_grid,
            g_state.geopot_full, g_state.geopot_half);
        ierr = check_cuda(cudaGetLastError(), "compute_geopotential_kernel");
    }

    if (ierr == 0) ierr = check_cuda(cudaMemcpy(geopot_full, g_state.geopot_full, count_full * sizeof(double), cudaMemcpyDeviceToHost), "copy geopot_full");
    if (ierr == 0) ierr = check_cuda(cudaMemcpy(geopot_half, g_state.geopot_half, count_half * sizeof(double), cudaMemcpyDeviceToHost), "copy geopot_half");

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
