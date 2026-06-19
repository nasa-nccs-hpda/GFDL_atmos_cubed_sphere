#include "fv_advection_kernels.hpp"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

using Clock = std::chrono::steady_clock;

struct Problem {
    std::string label;
    int nx;
    int ny;
    int nz;
    double dt;
    double dx;
};

struct Metrics {
    double allocation_ms = 0.0;
    double h2d_ms = 0.0;
    double launch_ms = 0.0;
    double kernel_ms = 0.0;
    double synchronization_ms = 0.0;
    double d2h_ms = 0.0;
    double free_ms = 0.0;
    double total_ms = 0.0;
};

struct Inputs {
    std::vector<double> c;
    std::vector<double> cc;
    std::vector<double> dy;
    std::vector<double> dy_plus;
    std::vector<double> dy_minus;
    std::vector<double> ua;
    std::vector<double> uc;
    std::vector<double> vc;
    std::vector<double> q_x;
    std::vector<double> q_sphere;
    std::vector<double> dq_x;
    std::vector<double> dq_sphere;
};

double elapsed_ms(Clock::time_point start, Clock::time_point stop) {
    return std::chrono::duration<double, std::milli>(stop - start).count();
}

void check_cuda(cudaError_t status, const char* what) {
    if (status != cudaSuccess) {
        throw std::runtime_error(std::string(what) + ": " + cudaGetErrorString(status));
    }
}

__host__ __device__ inline std::size_t idx3(
    int i0, int j0, int k0, int nx, int ny) {
    return static_cast<std::size_t>(i0) +
           static_cast<std::size_t>(nx) *
               (static_cast<std::size_t>(j0) +
                static_cast<std::size_t>(ny) * static_cast<std::size_t>(k0));
}

__host__ __device__ inline double sign_with_magnitude(
    double magnitude, double sign_source) {
    return sign_source >= 0.0 ? fabs(magnitude) : -fabs(magnitude);
}

__host__ __device__ inline double min3(double a, double b, double c) {
    return fmin(a, fmin(b, c));
}

__host__ __device__ inline double max3(double a, double b, double c) {
    return fmax(a, fmax(b, c));
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
    const int index = blockIdx.x * blockDim.x + threadIdx.x;
    if (index >= size) {
        return;
    }

    const int plane = nx * ny;
    const int k0 = index / plane;
    const int rem = index - k0 * plane;
    const int j0 = rem / nx;
    const int i0 = rem - j0 * nx;
    const double b = ua[index] * dt / (dx * c[j0]);
    int ii = i0 - static_cast<int>(floor(b));
    if (ii > nx) {
        ii -= nx;
    }
    if (ii < 1) {
        ii += nx;
    }
    const int left = ii - 1;
    const int right = left + 1 >= nx ? 0 : left + 1;
    const double bb = b - floor(b);
    dq[index] = bb * q[idx3(left, j0, k0, nx, ny)] +
                (1.0 - bb) * q[idx3(right, j0, k0, nx, ny)] - q[index];
}

__device__ double slope_x_value(
    int nx,
    int ny,
    bool monotone,
    const double* q,
    int i0,
    int j0,
    int k0) {
    const int im = i0 == 0 ? nx - 1 : i0 - 1;
    const int ip = i0 == nx - 1 ? 0 : i0 + 1;
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
                               q[idx3(ip, j0, k0, nx, ny)]) - center))
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
    int ii = base_i - static_cast<int>(floor(b));
    if (ii > nx) {
        ii -= nx;
    }
    if (ii < 1) {
        ii += nx;
    }
    const int source = ii - 1;
    const double qq = q[idx3(source, j0, k0, nx, ny)];
    const double ss = slope_x_value(nx, ny, monotone, q, source, j0, k0);

    double integer_flux = 0.0;
    const int c_int = static_cast<int>(b);
    if (c_int >= 1) {
        for (int m = 1; m <= c_int; ++m) {
            int src = base_i - m;
            if (src < 0) {
                src += nx;
            }
            integer_flux += q[idx3(src, j0, k0, nx, ny)];
        }
    } else if (c_int <= -1) {
        for (int m = 0; m <= -c_int - 1; ++m) {
            int src = base_i + m;
            if (src >= nx) {
                src -= nx;
            }
            integer_flux -= q[idx3(src, j0, k0, nx, ny)];
        }
    }

    return integer_flux +
           bb * (qq + 0.5 * ss * (sign_with_magnitude(1.0, bb) - bb));
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
    const int index = blockIdx.x * blockDim.x + threadIdx.x;
    if (index >= size) {
        return;
    }
    const int plane = nx * ny;
    const int k0 = index / plane;
    const int rem = index - k0 * plane;
    const int j0 = rem / nx;
    const int i0 = rem - j0 * nx;
    dq_dt[index] -=
        (vanleer_x_flux_at(nx, ny, dt, dx, c, monotone, uc, q,
                           i0 + 1, j0, k0) -
         vanleer_x_flux_at(nx, ny, dt, dx, c, monotone, uc, q,
                           i0, j0, k0)) /
        dt;
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
         q[idx3(i0, j0 + 1, k0, nx, q_ny)]) * dy_plus[j0] +
        (q[idx3(i0, j0 + 1, k0, nx, q_ny)] -
         q[idx3(i0, j0, k0, nx, q_ny)]) * dy_minus[j0];
    const double center = q[idx3(i0, j0 + 1, k0, nx, q_ny)];
    if (monotone) {
        const double q_min = min3(q[idx3(i0, j0, k0, nx, q_ny)], center,
                                  q[idx3(i0, j0 + 2, k0, nx, q_ny)]);
        const double q_max = max3(q[idx3(i0, j0, k0, nx, q_ny)], center,
                                  q[idx3(i0, j0 + 2, k0, nx, q_ny)]);
        return sign_with_magnitude(
            min3(fabs(value), 2.0 * (center - q_min), 2.0 * (q_max - center)),
            value);
    }
    return sign_with_magnitude(fmin(fabs(value), 2.0 * center), value);
}

__device__ double vanleer_sphere_flux_at(
    int nx,
    int ny,
    double dt,
    bool monotone,
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
    const double vc_value = vc[idx3(i0, fj0, k0, nx, vc_ny)];
    if (vc_value >= 0.0) {
        return vc_value * cc[fj0] *
               (q[idx3(i0, fj0 + 1, k0, nx, q_ny)] +
                0.5 * slope_sphere_value(nx, slope_ny, monotone, dy_plus,
                                         dy_minus, q, i0, fj0, k0) *
                    (1.0 - vc_value * dt / dy[fj0]));
    }
    return vc_value * cc[fj0] *
           (q[idx3(i0, fj0 + 2, k0, nx, q_ny)] -
            0.5 * slope_sphere_value(nx, slope_ny, monotone, dy_plus,
                                     dy_minus, q, i0, fj0 + 1, k0) *
                (1.0 + vc_value * dt / dy[fj0 + 1]));
}

__global__ void vanleer_sphere_kernel(
    int nx,
    int ny,
    int nz,
    double dt,
    bool monotone,
    const double* c,
    const double* cc,
    const double* dy,
    const double* dy_plus,
    const double* dy_minus,
    const double* vc,
    const double* q,
    double* dq_dt) {
    const int size = nx * ny * nz;
    const int index = blockIdx.x * blockDim.x + threadIdx.x;
    if (index >= size) {
        return;
    }
    const int plane = nx * ny;
    const int k0 = index / plane;
    const int rem = index - k0 * plane;
    const int j0 = rem / nx;
    const int i0 = rem - j0 * nx;
    dq_dt[index] -=
        (vanleer_sphere_flux_at(nx, ny, dt, monotone, cc, dy, dy_plus,
                                dy_minus, vc, q, i0, j0 + 1, k0) -
         vanleer_sphere_flux_at(nx, ny, dt, monotone, cc, dy, dy_plus,
                                dy_minus, vc, q, i0, j0, k0)) /
        (dy[j0 + 1] * c[j0]);
}

Inputs make_inputs(const Problem& p) {
    const std::size_t x_count = static_cast<std::size_t>(p.nx) * p.ny * p.nz;
    const std::size_t vc_count =
        static_cast<std::size_t>(p.nx) * (p.ny + 1) * p.nz;
    const std::size_t sphere_q_count =
        static_cast<std::size_t>(p.nx) * (p.ny + 4) * p.nz;

    Inputs in;
    in.c.resize(p.ny);
    in.cc.resize(p.ny + 1);
    in.dy.resize(p.ny + 2, 1.0);
    in.dy_plus.resize(p.ny + 2, 0.5);
    in.dy_minus.resize(p.ny + 2, 0.5);
    in.ua.resize(x_count);
    in.uc.resize(x_count);
    in.vc.resize(vc_count);
    in.q_x.resize(x_count);
    in.q_sphere.resize(sphere_q_count);
    in.dq_x.assign(x_count, 0.0);
    in.dq_sphere.assign(x_count, 0.0);

    for (int j = 0; j < p.ny; ++j) {
        const double latitude = -1.2 + 2.4 * (j + 0.5) / p.ny;
        in.c[j] = 0.25 + 0.75 * std::cos(latitude);
    }
    for (int j = 0; j <= p.ny; ++j) {
        const int cj = std::min(j, p.ny - 1);
        in.cc[j] = in.c[cj];
    }
    for (std::size_t index = 0; index < x_count; ++index) {
        in.q_x[index] = 250.0 + 0.01 * static_cast<double>(index % 997);
        const double sign = index % 2 == 0 ? 1.0 : -1.0;
        in.ua[index] = sign * 2.0e-4;
        in.uc[index] = -sign * 1.5e-4;
    }
    for (std::size_t index = 0; index < sphere_q_count; ++index) {
        in.q_sphere[index] = 245.0 + 0.02 * static_cast<double>(index % 719);
    }
    for (std::size_t index = 0; index < vc_count; ++index) {
        in.vc[index] = index % 2 == 0 ? 1.0e-4 : -1.0e-4;
    }
    return in;
}

template <typename T>
void cuda_allocate(T** pointer, std::size_t count) {
    check_cuda(cudaMalloc(reinterpret_cast<void**>(pointer), count * sizeof(T)),
               "cudaMalloc");
}

void add_event_time(cudaEvent_t start, cudaEvent_t stop, double& total_ms) {
    float value = 0.0f;
    check_cuda(cudaEventElapsedTime(&value, start, stop), "cudaEventElapsedTime");
    total_ms += static_cast<double>(value);
}

void print_row(
    const Problem& p,
    const std::string& kernel,
    const std::string& mode,
    int iterations,
    const Metrics& m) {
    std::cout << p.label << ',' << p.nx << ',' << p.ny << ',' << p.nz << ','
              << kernel << ',' << mode << ',' << iterations << ','
              << std::fixed << std::setprecision(6)
              << m.allocation_ms << ',' << m.h2d_ms << ',' << m.launch_ms << ','
              << m.kernel_ms << ',' << m.synchronization_ms << ',' << m.d2h_ms
              << ',' << m.free_ms << ',' << m.total_ms << ','
              << m.total_ms / iterations << '\n';
}

Metrics run_cpu(
    const Problem& p,
    const Inputs& in,
    const std::string& kernel,
    int iterations) {
    Metrics m;
    std::vector<double> output =
        kernel == "vanleer_sphere_3d" ? in.dq_sphere : in.dq_x;
    const auto start = Clock::now();
    for (int n = 0; n < iterations; ++n) {
        if (kernel == "semi_x_3d") {
            fv_advection_kernels::semi_x_3d(
                p.nx, p.ny, p.nz, 0.5 * p.dt, p.dx, in.c.data(),
                in.ua.data(), in.q_x.data(), output.data());
        } else if (kernel == "vanleer_x_3d") {
            fv_advection_kernels::vanleer_x_3d(
                p.nx, p.ny, p.nz, p.dt, p.dx, in.c.data(), true,
                in.uc.data(), in.q_x.data(), output.data());
        } else {
            fv_advection_kernels::vanleer_sphere_3d(
                p.nx, p.ny, p.nz, p.dt, true, false, false, in.c.data(),
                in.cc.data(), in.dy.data(), in.dy_plus.data(),
                in.dy_minus.data(), in.vc.data(), in.q_sphere.data(),
                output.data());
        }
    }
    m.total_ms = elapsed_ms(start, Clock::now());
    m.kernel_ms = m.total_ms;
    volatile double checksum = output.empty() ? 0.0 : output[0];
    (void)checksum;
    return m;
}

Metrics run_cuda_semi(
    const Problem& p, const Inputs& in, int iterations, bool persistent) {
    Metrics m;
    const std::size_t count = static_cast<std::size_t>(p.nx) * p.ny * p.nz;
    const int threads = 256;
    const int blocks = static_cast<int>((count + threads - 1) / threads);
    std::vector<double> output(count);
    cudaEvent_t event_start, event_stop;
    check_cuda(cudaEventCreate(&event_start), "cudaEventCreate");
    check_cuda(cudaEventCreate(&event_stop), "cudaEventCreate");

    double *d_c = nullptr, *d_ua = nullptr, *d_q = nullptr, *d_dq = nullptr;
    const auto total_start = Clock::now();
    auto allocate = [&]() {
        const auto start = Clock::now();
        cuda_allocate(&d_c, in.c.size());
        cuda_allocate(&d_ua, count);
        cuda_allocate(&d_q, count);
        cuda_allocate(&d_dq, count);
        m.allocation_ms += elapsed_ms(start, Clock::now());
    };
    auto copy_in = [&]() {
        const auto start = Clock::now();
        check_cuda(cudaMemcpy(d_c, in.c.data(), in.c.size() * sizeof(double),
                              cudaMemcpyHostToDevice), "H2D c");
        check_cuda(cudaMemcpy(d_ua, in.ua.data(), count * sizeof(double),
                              cudaMemcpyHostToDevice), "H2D ua");
        check_cuda(cudaMemcpy(d_q, in.q_x.data(), count * sizeof(double),
                              cudaMemcpyHostToDevice), "H2D q");
        m.h2d_ms += elapsed_ms(start, Clock::now());
    };
    auto launch = [&]() {
        const auto start = Clock::now();
        semi_x_kernel<<<blocks, threads>>>(p.nx, p.ny, p.nz, 0.5 * p.dt,
                                           p.dx, d_c, d_ua, d_q, d_dq);
        check_cuda(cudaGetLastError(), "semi_x_kernel launch");
        m.launch_ms += elapsed_ms(start, Clock::now());
    };
    auto copy_out = [&]() {
        const auto start = Clock::now();
        check_cuda(cudaMemcpy(output.data(), d_dq, count * sizeof(double),
                              cudaMemcpyDeviceToHost), "D2H dq");
        m.d2h_ms += elapsed_ms(start, Clock::now());
    };
    auto release = [&]() {
        const auto start = Clock::now();
        check_cuda(cudaFree(d_c), "cudaFree c");
        check_cuda(cudaFree(d_ua), "cudaFree ua");
        check_cuda(cudaFree(d_q), "cudaFree q");
        check_cuda(cudaFree(d_dq), "cudaFree dq");
        d_c = d_ua = d_q = d_dq = nullptr;
        m.free_ms += elapsed_ms(start, Clock::now());
    };

    if (persistent) {
        allocate();
        copy_in();
        check_cuda(cudaEventRecord(event_start), "event start");
        for (int n = 0; n < iterations; ++n) {
            launch();
        }
        check_cuda(cudaEventRecord(event_stop), "event stop");
        const auto start = Clock::now();
        check_cuda(cudaEventSynchronize(event_stop), "event synchronize");
        m.synchronization_ms += elapsed_ms(start, Clock::now());
        add_event_time(event_start, event_stop, m.kernel_ms);
        copy_out();
        release();
    } else {
        for (int n = 0; n < iterations; ++n) {
            allocate();
            copy_in();
            check_cuda(cudaEventRecord(event_start), "event start");
            launch();
            check_cuda(cudaEventRecord(event_stop), "event stop");
            const auto start = Clock::now();
            check_cuda(cudaEventSynchronize(event_stop), "event synchronize");
            m.synchronization_ms += elapsed_ms(start, Clock::now());
            add_event_time(event_start, event_stop, m.kernel_ms);
            copy_out();
            release();
        }
    }
    m.total_ms = elapsed_ms(total_start, Clock::now());
    check_cuda(cudaEventDestroy(event_start), "cudaEventDestroy");
    check_cuda(cudaEventDestroy(event_stop), "cudaEventDestroy");
    return m;
}

Metrics run_cuda_vanleer_x(
    const Problem& p, const Inputs& in, int iterations, bool persistent) {
    Metrics m;
    const std::size_t count = static_cast<std::size_t>(p.nx) * p.ny * p.nz;
    const int threads = 256;
    const int blocks = static_cast<int>((count + threads - 1) / threads);
    std::vector<double> output(count);
    cudaEvent_t event_start, event_stop;
    check_cuda(cudaEventCreate(&event_start), "cudaEventCreate");
    check_cuda(cudaEventCreate(&event_stop), "cudaEventCreate");
    double *d_c = nullptr, *d_uc = nullptr, *d_q = nullptr, *d_dq = nullptr;
    const auto total_start = Clock::now();

    auto allocate = [&]() {
        const auto start = Clock::now();
        cuda_allocate(&d_c, in.c.size());
        cuda_allocate(&d_uc, count);
        cuda_allocate(&d_q, count);
        cuda_allocate(&d_dq, count);
        m.allocation_ms += elapsed_ms(start, Clock::now());
    };
    auto copy_in = [&]() {
        const auto start = Clock::now();
        check_cuda(cudaMemcpy(d_c, in.c.data(), in.c.size() * sizeof(double),
                              cudaMemcpyHostToDevice), "H2D c");
        check_cuda(cudaMemcpy(d_uc, in.uc.data(), count * sizeof(double),
                              cudaMemcpyHostToDevice), "H2D uc");
        check_cuda(cudaMemcpy(d_q, in.q_x.data(), count * sizeof(double),
                              cudaMemcpyHostToDevice), "H2D q");
        check_cuda(cudaMemcpy(d_dq, in.dq_x.data(), count * sizeof(double),
                              cudaMemcpyHostToDevice), "H2D dq");
        m.h2d_ms += elapsed_ms(start, Clock::now());
    };
    auto launch = [&]() {
        const auto start = Clock::now();
        vanleer_x_kernel<<<blocks, threads>>>(p.nx, p.ny, p.nz, p.dt, p.dx,
                                              d_c, true, d_uc, d_q, d_dq);
        check_cuda(cudaGetLastError(), "vanleer_x_kernel launch");
        m.launch_ms += elapsed_ms(start, Clock::now());
    };
    auto copy_out = [&]() {
        const auto start = Clock::now();
        check_cuda(cudaMemcpy(output.data(), d_dq, count * sizeof(double),
                              cudaMemcpyDeviceToHost), "D2H dq");
        m.d2h_ms += elapsed_ms(start, Clock::now());
    };
    auto release = [&]() {
        const auto start = Clock::now();
        check_cuda(cudaFree(d_c), "cudaFree c");
        check_cuda(cudaFree(d_uc), "cudaFree uc");
        check_cuda(cudaFree(d_q), "cudaFree q");
        check_cuda(cudaFree(d_dq), "cudaFree dq");
        d_c = d_uc = d_q = d_dq = nullptr;
        m.free_ms += elapsed_ms(start, Clock::now());
    };

    if (persistent) {
        allocate();
        copy_in();
        check_cuda(cudaEventRecord(event_start), "event start");
        for (int n = 0; n < iterations; ++n) {
            launch();
        }
        check_cuda(cudaEventRecord(event_stop), "event stop");
        const auto start = Clock::now();
        check_cuda(cudaEventSynchronize(event_stop), "event synchronize");
        m.synchronization_ms += elapsed_ms(start, Clock::now());
        add_event_time(event_start, event_stop, m.kernel_ms);
        copy_out();
        release();
    } else {
        for (int n = 0; n < iterations; ++n) {
            allocate();
            copy_in();
            check_cuda(cudaEventRecord(event_start), "event start");
            launch();
            check_cuda(cudaEventRecord(event_stop), "event stop");
            const auto start = Clock::now();
            check_cuda(cudaEventSynchronize(event_stop), "event synchronize");
            m.synchronization_ms += elapsed_ms(start, Clock::now());
            add_event_time(event_start, event_stop, m.kernel_ms);
            copy_out();
            release();
        }
    }
    m.total_ms = elapsed_ms(total_start, Clock::now());
    check_cuda(cudaEventDestroy(event_start), "cudaEventDestroy");
    check_cuda(cudaEventDestroy(event_stop), "cudaEventDestroy");
    return m;
}

Metrics run_cuda_vanleer_sphere(
    const Problem& p, const Inputs& in, int iterations, bool persistent) {
    Metrics m;
    const std::size_t count = static_cast<std::size_t>(p.nx) * p.ny * p.nz;
    const std::size_t vc_count =
        static_cast<std::size_t>(p.nx) * (p.ny + 1) * p.nz;
    const std::size_t q_count =
        static_cast<std::size_t>(p.nx) * (p.ny + 4) * p.nz;
    const int threads = 256;
    const int blocks = static_cast<int>((count + threads - 1) / threads);
    std::vector<double> output(count);
    cudaEvent_t event_start, event_stop;
    check_cuda(cudaEventCreate(&event_start), "cudaEventCreate");
    check_cuda(cudaEventCreate(&event_stop), "cudaEventCreate");
    double *d_c = nullptr, *d_cc = nullptr, *d_dy = nullptr;
    double *d_dy_plus = nullptr, *d_dy_minus = nullptr;
    double *d_vc = nullptr, *d_q = nullptr, *d_dq = nullptr;
    const auto total_start = Clock::now();

    auto allocate = [&]() {
        const auto start = Clock::now();
        cuda_allocate(&d_c, in.c.size());
        cuda_allocate(&d_cc, in.cc.size());
        cuda_allocate(&d_dy, in.dy.size());
        cuda_allocate(&d_dy_plus, in.dy_plus.size());
        cuda_allocate(&d_dy_minus, in.dy_minus.size());
        cuda_allocate(&d_vc, vc_count);
        cuda_allocate(&d_q, q_count);
        cuda_allocate(&d_dq, count);
        m.allocation_ms += elapsed_ms(start, Clock::now());
    };
    auto copy_in = [&]() {
        const auto start = Clock::now();
        check_cuda(cudaMemcpy(d_c, in.c.data(), in.c.size() * sizeof(double),
                              cudaMemcpyHostToDevice), "H2D c");
        check_cuda(cudaMemcpy(d_cc, in.cc.data(), in.cc.size() * sizeof(double),
                              cudaMemcpyHostToDevice), "H2D cc");
        check_cuda(cudaMemcpy(d_dy, in.dy.data(), in.dy.size() * sizeof(double),
                              cudaMemcpyHostToDevice), "H2D dy");
        check_cuda(cudaMemcpy(d_dy_plus, in.dy_plus.data(),
                              in.dy_plus.size() * sizeof(double),
                              cudaMemcpyHostToDevice), "H2D dy_plus");
        check_cuda(cudaMemcpy(d_dy_minus, in.dy_minus.data(),
                              in.dy_minus.size() * sizeof(double),
                              cudaMemcpyHostToDevice), "H2D dy_minus");
        check_cuda(cudaMemcpy(d_vc, in.vc.data(), vc_count * sizeof(double),
                              cudaMemcpyHostToDevice), "H2D vc");
        check_cuda(cudaMemcpy(d_q, in.q_sphere.data(), q_count * sizeof(double),
                              cudaMemcpyHostToDevice), "H2D q");
        check_cuda(cudaMemcpy(d_dq, in.dq_sphere.data(), count * sizeof(double),
                              cudaMemcpyHostToDevice), "H2D dq");
        m.h2d_ms += elapsed_ms(start, Clock::now());
    };
    auto launch = [&]() {
        const auto start = Clock::now();
        vanleer_sphere_kernel<<<blocks, threads>>>(
            p.nx, p.ny, p.nz, p.dt, true, d_c, d_cc, d_dy, d_dy_plus,
            d_dy_minus, d_vc, d_q, d_dq);
        check_cuda(cudaGetLastError(), "vanleer_sphere_kernel launch");
        m.launch_ms += elapsed_ms(start, Clock::now());
    };
    auto copy_out = [&]() {
        const auto start = Clock::now();
        check_cuda(cudaMemcpy(output.data(), d_dq, count * sizeof(double),
                              cudaMemcpyDeviceToHost), "D2H dq");
        m.d2h_ms += elapsed_ms(start, Clock::now());
    };
    auto release = [&]() {
        const auto start = Clock::now();
        check_cuda(cudaFree(d_c), "cudaFree c");
        check_cuda(cudaFree(d_cc), "cudaFree cc");
        check_cuda(cudaFree(d_dy), "cudaFree dy");
        check_cuda(cudaFree(d_dy_plus), "cudaFree dy_plus");
        check_cuda(cudaFree(d_dy_minus), "cudaFree dy_minus");
        check_cuda(cudaFree(d_vc), "cudaFree vc");
        check_cuda(cudaFree(d_q), "cudaFree q");
        check_cuda(cudaFree(d_dq), "cudaFree dq");
        d_c = d_cc = d_dy = d_dy_plus = d_dy_minus = nullptr;
        d_vc = d_q = d_dq = nullptr;
        m.free_ms += elapsed_ms(start, Clock::now());
    };

    if (persistent) {
        allocate();
        copy_in();
        check_cuda(cudaEventRecord(event_start), "event start");
        for (int n = 0; n < iterations; ++n) {
            launch();
        }
        check_cuda(cudaEventRecord(event_stop), "event stop");
        const auto start = Clock::now();
        check_cuda(cudaEventSynchronize(event_stop), "event synchronize");
        m.synchronization_ms += elapsed_ms(start, Clock::now());
        add_event_time(event_start, event_stop, m.kernel_ms);
        copy_out();
        release();
    } else {
        for (int n = 0; n < iterations; ++n) {
            allocate();
            copy_in();
            check_cuda(cudaEventRecord(event_start), "event start");
            launch();
            check_cuda(cudaEventRecord(event_stop), "event stop");
            const auto start = Clock::now();
            check_cuda(cudaEventSynchronize(event_stop), "event synchronize");
            m.synchronization_ms += elapsed_ms(start, Clock::now());
            add_event_time(event_start, event_stop, m.kernel_ms);
            copy_out();
            release();
        }
    }
    m.total_ms = elapsed_ms(total_start, Clock::now());
    check_cuda(cudaEventDestroy(event_start), "cudaEventDestroy");
    check_cuda(cudaEventDestroy(event_stop), "cudaEventDestroy");
    return m;
}

Problem resolution_problem(const std::string& label) {
    if (label == "T42") {
        return {label, 128, 4, 25, 600.0, 1.0};
    }
    if (label == "T85") {
        return {label, 256, 8, 25, 300.0, 1.0};
    }
    if (label == "T170") {
        return {label, 512, 16, 25, 150.0, 1.0};
    }
    throw std::runtime_error("Unknown resolution: " + label);
}

bool selected(const std::string& requested, const std::string& value) {
    return requested == "all" || requested == value;
}

}  // namespace

int main(int argc, char** argv) {
    try {
        std::string resolution = "T42";
        std::string mode = "all";
        std::string requested_kernel = "all";
        int iterations = 100;
        int nx_override = 0;
        int ny_override = 0;
        int nz_override = 0;

        for (int i = 1; i < argc; ++i) {
            const std::string arg = argv[i];
            if (arg == "--resolution" && i + 1 < argc) {
                resolution = argv[++i];
            } else if (arg == "--mode" && i + 1 < argc) {
                mode = argv[++i];
            } else if (arg == "--kernel" && i + 1 < argc) {
                requested_kernel = argv[++i];
            } else if (arg == "--iterations" && i + 1 < argc) {
                iterations = std::atoi(argv[++i]);
            } else if (arg == "--nx" && i + 1 < argc) {
                nx_override = std::atoi(argv[++i]);
            } else if (arg == "--ny" && i + 1 < argc) {
                ny_override = std::atoi(argv[++i]);
            } else if (arg == "--nz" && i + 1 < argc) {
                nz_override = std::atoi(argv[++i]);
            } else {
                throw std::runtime_error("Unknown or incomplete argument: " + arg);
            }
        }
        if (iterations <= 0) {
            throw std::runtime_error("--iterations must be positive");
        }

        Problem problem = resolution_problem(resolution);
        if (nx_override > 0) problem.nx = nx_override;
        if (ny_override > 0) problem.ny = ny_override;
        if (nz_override > 0) problem.nz = nz_override;
        Inputs inputs = make_inputs(problem);

        const bool cuda_requested =
            selected(mode, "cuda-current") || selected(mode, "cuda-persistent");
        if (cuda_requested) {
            int device_count = 0;
            check_cuda(cudaGetDeviceCount(&device_count), "cudaGetDeviceCount");
            if (device_count <= 0) {
                throw std::runtime_error("No CUDA device is available");
            }
            check_cuda(cudaSetDevice(0), "cudaSetDevice");
            check_cuda(cudaFree(nullptr), "CUDA context initialization");
        }

        std::cout << "resolution,nx,local_ny,nz,kernel,mode,iterations,"
                     "allocation_ms,h2d_ms,launch_ms,kernel_ms,sync_ms,"
                     "d2h_ms,free_ms,total_ms,total_ms_per_call\n";

        const std::vector<std::string> kernels = {
            "semi_x_3d", "vanleer_x_3d", "vanleer_sphere_3d"};
        for (const std::string& kernel : kernels) {
            if (!selected(requested_kernel, kernel)) {
                continue;
            }
            if (selected(mode, "cpu")) {
                print_row(problem, kernel, "cpu", iterations,
                          run_cpu(problem, inputs, kernel, iterations));
            }
            if (selected(mode, "cuda-current")) {
                Metrics result;
                if (kernel == "semi_x_3d") {
                    result = run_cuda_semi(problem, inputs, iterations, false);
                } else if (kernel == "vanleer_x_3d") {
                    result = run_cuda_vanleer_x(problem, inputs, iterations, false);
                } else {
                    result = run_cuda_vanleer_sphere(problem, inputs, iterations, false);
                }
                print_row(problem, kernel, "cuda-current", iterations, result);
            }
            if (selected(mode, "cuda-persistent")) {
                Metrics result;
                if (kernel == "semi_x_3d") {
                    result = run_cuda_semi(problem, inputs, iterations, true);
                } else if (kernel == "vanleer_x_3d") {
                    result = run_cuda_vanleer_x(problem, inputs, iterations, true);
                } else {
                    result = run_cuda_vanleer_sphere(problem, inputs, iterations, true);
                }
                print_row(problem, kernel, "cuda-persistent", iterations, result);
            }
        }
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "fv_advection_cuda_benchmark: " << error.what() << '\n';
        return 1;
    }
}
