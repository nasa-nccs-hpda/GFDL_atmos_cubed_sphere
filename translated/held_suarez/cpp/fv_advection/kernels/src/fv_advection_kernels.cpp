#include "fv_advection_kernels.hpp"
#include "fv_advection_kernel_profile.hpp"

#include <algorithm>
#include <cstdlib>
#include <cmath>
#include <cstddef>
#include <vector>

namespace {

inline std::size_t idx3(int i0, int j0, int k0, int nx, int ny) {
    return static_cast<std::size_t>(i0) +
           static_cast<std::size_t>(nx) *
               (static_cast<std::size_t>(j0) +
                static_cast<std::size_t>(ny) * static_cast<std::size_t>(k0));
}

inline double sign_with_magnitude(double magnitude, double sign_source) {
    return sign_source >= 0.0 ? std::abs(magnitude) : -std::abs(magnitude);
}

template <typename T>
inline T min3(T a, T b, T c) {
    return std::min(a, std::min(b, c));
}

template <typename T>
inline T max3(T a, T b, T c) {
    return std::max(a, std::max(b, c));
}

namespace profile = fv_advection_kernels_profile;

profile::Counter semi_x_counter{"semi_x_3d", 0, 0.0};
profile::Counter slope_x_counter{"slope_x", 0, 0.0};
profile::Counter integer_flux_x_counter{"integer_flux_x", 0, 0.0};
profile::Counter vanleer_x_counter{"vanleer_x_3d", 0, 0.0};
profile::Counter slope_sphere_counter{"slope_sphere", 0, 0.0};
profile::Counter vanleer_sphere_counter{"vanleer_sphere_3d", 0, 0.0};

void print_cpu_profile() {
    profile::print_counter("cpu", semi_x_counter);
    profile::print_counter("cpu", slope_x_counter);
    profile::print_counter("cpu", integer_flux_x_counter);
    profile::print_counter("cpu", vanleer_x_counter);
    profile::print_counter("cpu", slope_sphere_counter);
    profile::print_counter("cpu", vanleer_sphere_counter);
}

void register_cpu_profile_report() {
    static bool registered = false;
    if (!registered && profile::enabled()) {
        std::atexit(print_cpu_profile);
        registered = true;
    }
}

}  // namespace

namespace fv_advection_kernels {

void find_cell_x(int nx, int ny, int nz, const double* b, int* ii) {
    for (int k0 = 0; k0 < nz; ++k0) {
        for (int j0 = 0; j0 < ny; ++j0) {
            for (int i0 = 0; i0 < nx; ++i0) {
                const std::size_t idx = idx3(i0, j0, k0, nx, ny);
                int value = (i0 + 1) - 1;
                value -= static_cast<int>(std::floor(b[idx]));
                if (value > nx) {
                    value -= nx;
                }
                if (value < 1) {
                    value += nx;
                }
                ii[idx] = value;
            }
        }
    }
}

void slope_x(
    int nx,
    int ny,
    int nz,
    bool monotone,
    const double* q,
    double* slope) {
    std::vector<double> grad(static_cast<std::size_t>(nx) * ny * nz);

    for (int k0 = 0; k0 < nz; ++k0) {
        for (int j0 = 0; j0 < ny; ++j0) {
            for (int i0 = 1; i0 < nx; ++i0) {
                grad[idx3(i0, j0, k0, nx, ny)] =
                    q[idx3(i0, j0, k0, nx, ny)] -
                    q[idx3(i0 - 1, j0, k0, nx, ny)];
            }
            grad[idx3(0, j0, k0, nx, ny)] =
                q[idx3(0, j0, k0, nx, ny)] -
                q[idx3(nx - 1, j0, k0, nx, ny)];

            for (int i0 = 0; i0 < nx - 1; ++i0) {
                slope[idx3(i0, j0, k0, nx, ny)] =
                    0.5 * (grad[idx3(i0 + 1, j0, k0, nx, ny)] +
                           grad[idx3(i0, j0, k0, nx, ny)]);
            }
            slope[idx3(nx - 1, j0, k0, nx, ny)] =
                0.5 * (grad[idx3(0, j0, k0, nx, ny)] +
                       grad[idx3(nx - 1, j0, k0, nx, ny)]);
        }
    }

    for (int k0 = 0; k0 < nz; ++k0) {
        for (int j0 = 0; j0 < ny; ++j0) {
            for (int i0 = 0; i0 < nx; ++i0) {
                const int im = (i0 == 0) ? nx - 1 : i0 - 1;
                const int ip = (i0 == nx - 1) ? 0 : i0 + 1;
                const std::size_t idx = idx3(i0, j0, k0, nx, ny);
                const double val = q[idx];
                const double limited =
                    monotone
                        ? min3(std::abs(slope[idx]),
                               2.0 * (val - min3(q[idx3(im, j0, k0, nx, ny)],
                                                 val,
                                                 q[idx3(ip, j0, k0, nx, ny)])),
                               2.0 * (max3(q[idx3(im, j0, k0, nx, ny)],
                                           val,
                                           q[idx3(ip, j0, k0, nx, ny)]) -
                                      val))
                        : std::min(std::abs(slope[idx]), 2.0 * val);
                slope[idx] = sign_with_magnitude(limited, slope[idx]);
            }
        }
    }
}

void integer_flux_x(
    int nx,
    int ny,
    int nz,
    const double* courant,
    const double* q,
    double* flux) {
    std::fill(flux, flux + static_cast<std::size_t>(nx) * ny * nz, 0.0);

    for (int k0 = 0; k0 < nz; ++k0) {
        for (int j0 = 0; j0 < ny; ++j0) {
            for (int i0 = 0; i0 < nx; ++i0) {
                const int c_int =
                    static_cast<int>(courant[idx3(i0, j0, k0, nx, ny)]);
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

                flux[idx3(i0, j0, k0, nx, ny)] = sum;
            }
        }
    }
}

void semi_x_3d(
    int nx,
    int ny,
    int nz,
    double dt,
    double dx,
    const double* c,
    const double* ua,
    const double* q,
    double* dq) {
    std::vector<double> b(static_cast<std::size_t>(nx) * ny * nz);
    std::vector<int> ii(static_cast<std::size_t>(nx) * ny * nz);

    for (int k0 = 0; k0 < nz; ++k0) {
        for (int j0 = 0; j0 < ny; ++j0) {
            for (int i0 = 0; i0 < nx; ++i0) {
                const std::size_t idx = idx3(i0, j0, k0, nx, ny);
                b[idx] = ua[idx] * dt / (dx * c[j0]);
            }
        }
    }

    find_cell_x(nx, ny, nz, b.data(), ii.data());

    for (int k0 = 0; k0 < nz; ++k0) {
        for (int j0 = 0; j0 < ny; ++j0) {
            for (int i0 = 0; i0 < nx; ++i0) {
                const std::size_t idx = idx3(i0, j0, k0, nx, ny);
                const int left = ii[idx] - 1;
                const int right = (left + 1 >= nx) ? 0 : left + 1;
                const double bb = b[idx] - std::floor(b[idx]);
                dq[idx] = bb * q[idx3(left, j0, k0, nx, ny)] +
                          (1.0 - bb) * q[idx3(right, j0, k0, nx, ny)] -
                          q[idx];
            }
        }
    }
}

void slope_sphere(
    int nx,
    int nys,
    int nz,
    bool monotone,
    const double* dy_plus,
    const double* dy_minus,
    const double* q,
    double* slope) {
    const int q_ny = nys + 2;

    for (int k0 = 0; k0 < nz; ++k0) {
        for (int j0 = 0; j0 < nys; ++j0) {
            for (int i0 = 0; i0 < nx; ++i0) {
                const std::size_t out = idx3(i0, j0, k0, nx, nys);
                const double val =
                    (q[idx3(i0, j0 + 2, k0, nx, q_ny)] -
                     q[idx3(i0, j0 + 1, k0, nx, q_ny)]) *
                        dy_plus[j0] +
                    (q[idx3(i0, j0 + 1, k0, nx, q_ny)] -
                     q[idx3(i0, j0, k0, nx, q_ny)]) *
                        dy_minus[j0];

                if (monotone) {
                    const double center = q[idx3(i0, j0 + 1, k0, nx, q_ny)];
                    const double q_min =
                        min3(q[idx3(i0, j0, k0, nx, q_ny)], center,
                             q[idx3(i0, j0 + 2, k0, nx, q_ny)]);
                    const double q_max =
                        max3(q[idx3(i0, j0, k0, nx, q_ny)], center,
                             q[idx3(i0, j0 + 2, k0, nx, q_ny)]);
                    const double limited =
                        min3(std::abs(val), 2.0 * (center - q_min),
                             2.0 * (q_max - center));
                    slope[out] = sign_with_magnitude(limited, val);
                } else {
                    const double center = q[idx3(i0, j0 + 1, k0, nx, q_ny)];
                    slope[out] =
                        sign_with_magnitude(std::min(std::abs(val), 2.0 * center),
                                            val);
                }
            }
        }
    }
}

void vanleer_x_3d(
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
    const std::size_t count = static_cast<std::size_t>(nx) * ny * nz;
    std::vector<double> b(count);
    std::vector<double> bb(count);
    std::vector<double> slope(count);
    std::vector<double> int_flux(count, 0.0);
    std::vector<int> ii(count);
    std::vector<double> flux(static_cast<std::size_t>(nx + 1) * ny * nz, 0.0);

    double max_abs_b = 0.0;
    for (int k0 = 0; k0 < nz; ++k0) {
        for (int j0 = 0; j0 < ny; ++j0) {
            for (int i0 = 0; i0 < nx; ++i0) {
                const std::size_t idx = idx3(i0, j0, k0, nx, ny);
                b[idx] = uc[idx] * dt / (dx * c[j0]);
                bb[idx] = b[idx] - static_cast<int>(b[idx]);
                max_abs_b = std::max(max_abs_b, std::abs(b[idx]));
            }
        }
    }

    if (max_abs_b > 1.0) {
        integer_flux_x(nx, ny, nz, b.data(), q, int_flux.data());
    }
    slope_x(nx, ny, nz, monotone, q, slope.data());
    find_cell_x(nx, ny, nz, b.data(), ii.data());

    for (int k0 = 0; k0 < nz; ++k0) {
        for (int j0 = 0; j0 < ny; ++j0) {
            for (int i0 = 0; i0 < nx; ++i0) {
                const std::size_t idx = idx3(i0, j0, k0, nx, ny);
                const int source = ii[idx] - 1;
                const double qq = q[idx3(source, j0, k0, nx, ny)];
                const double ss = slope[idx3(source, j0, k0, nx, ny)];
                flux[idx3(i0, j0, k0, nx + 1, ny)] =
                    int_flux[idx] +
                    bb[idx] * (qq + 0.5 * ss * (sign_with_magnitude(1.0, bb[idx]) -
                                                bb[idx]));
            }
            flux[idx3(nx, j0, k0, nx + 1, ny)] =
                flux[idx3(0, j0, k0, nx + 1, ny)];
        }
    }

    for (int k0 = 0; k0 < nz; ++k0) {
        for (int j0 = 0; j0 < ny; ++j0) {
            for (int i0 = 0; i0 < nx; ++i0) {
                dq_dt[idx3(i0, j0, k0, nx, ny)] -=
                    (flux[idx3(i0 + 1, j0, k0, nx + 1, ny)] -
                     flux[idx3(i0, j0, k0, nx + 1, ny)]) /
                    dt;
            }
        }
    }
}

void vanleer_sphere_3d(
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
    const int slope_ny = ny + 2;
    const int q_ny = ny + 4;
    const int vc_ny = ny + 1;
    std::vector<double> slope(static_cast<std::size_t>(nx) * slope_ny * nz);
    std::vector<double> flux(static_cast<std::size_t>(nx) * vc_ny * nz, 0.0);

    slope_sphere(nx, slope_ny, nz, monotone, dy_plus, dy_minus, q, slope.data());

    for (int k0 = 0; k0 < nz; ++k0) {
        for (int j0 = 0; j0 < vc_ny; ++j0) {
            for (int i0 = 0; i0 < nx; ++i0) {
                const std::size_t vc_idx = idx3(i0, j0, k0, nx, vc_ny);
                const double vc_val = vc[vc_idx];
                if (vc_val >= 0.0) {
                    flux[vc_idx] =
                        vc_val * cc[j0] *
                        (q[idx3(i0, j0 + 1, k0, nx, q_ny)] +
                         0.5 * slope[idx3(i0, j0, k0, nx, slope_ny)] *
                             (1.0 - vc_val * dt / dy[j0]));
                } else {
                    flux[vc_idx] =
                        vc_val * cc[j0] *
                        (q[idx3(i0, j0 + 2, k0, nx, q_ny)] -
                         0.5 * slope[idx3(i0, j0 + 1, k0, nx, slope_ny)] *
                             (1.0 + vc_val * dt / dy[j0 + 1]));
                }
            }
        }
    }

    if (is_south_boundary) {
        for (int k0 = 0; k0 < nz; ++k0) {
            for (int i0 = 0; i0 < nx; ++i0) {
                flux[idx3(i0, 0, k0, nx, vc_ny)] = 0.0;
            }
        }
    }
    if (is_north_boundary) {
        for (int k0 = 0; k0 < nz; ++k0) {
            for (int i0 = 0; i0 < nx; ++i0) {
                flux[idx3(i0, ny, k0, nx, vc_ny)] = 0.0;
            }
        }
    }

    for (int k0 = 0; k0 < nz; ++k0) {
        for (int j0 = 0; j0 < ny; ++j0) {
            for (int i0 = 0; i0 < nx; ++i0) {
                dq_dt[idx3(i0, j0, k0, nx, ny)] -=
                    (flux[idx3(i0, j0 + 1, k0, nx, vc_ny)] -
                     flux[idx3(i0, j0, k0, nx, vc_ny)]) /
                    (dy[j0 + 1] * c[j0]);
            }
        }
    }
}

}  // namespace fv_advection_kernels

extern "C" void fv_semi_x_3d_c(
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
    register_cpu_profile_report();
    profile::ScopedTimer timer(semi_x_counter);
    fv_advection_kernels::semi_x_3d(
        nx, je - js + 1, nz, dt, dx, c, ua, q, dq);
}

extern "C" void fv_slope_x_c(
    int nx,
    int js,
    int je,
    int nz,
    int monotone,
    const double* q,
    double* slope) {
    register_cpu_profile_report();
    profile::ScopedTimer timer(slope_x_counter);
    fv_advection_kernels::slope_x(
        nx, je - js + 1, nz, monotone != 0, q, slope);
}

extern "C" void fv_integer_flux_x_c(
    int nx,
    int js,
    int je,
    int nz,
    const double* courant,
    const double* q,
    double* flux) {
    register_cpu_profile_report();
    profile::ScopedTimer timer(integer_flux_x_counter);
    fv_advection_kernels::integer_flux_x(
        nx, je - js + 1, nz, courant, q, flux);
}

extern "C" void fv_vanleer_x_3d_c(
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
    register_cpu_profile_report();
    profile::ScopedTimer timer(vanleer_x_counter);
    fv_advection_kernels::vanleer_x_3d(
        nx, je - js + 1, nz, dt, dx, c, monotone != 0, uc, q, dq_dt);
}

extern "C" void fv_slope_sphere_c(
    int nx,
    int js,
    int je,
    int nz,
    int monotone,
    const double* dy_plus,
    const double* dy_minus,
    const double* q,
    double* slope) {
    register_cpu_profile_report();
    profile::ScopedTimer timer(slope_sphere_counter);
    fv_advection_kernels::slope_sphere(
        nx, je - js + 3, nz, monotone != 0, dy_plus, dy_minus, q, slope);
}

extern "C" void fv_vanleer_sphere_3d_c(
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
    register_cpu_profile_report();
    profile::ScopedTimer timer(vanleer_sphere_counter);
    fv_advection_kernels::vanleer_sphere_3d(
        nx, je - js + 1, nz, dt, monotone != 0, js == 1,
        je == ny_total, c, cc, dy, dy_plus, dy_minus, vc, q, dq_dt);
}
