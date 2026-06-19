#include "semi_y_3d.hpp"

#include <cstddef>

namespace {

inline std::size_t idx3(int i0, int j0, int k0, int nx, int ny) {
    return static_cast<std::size_t>(i0) +
           static_cast<std::size_t>(nx) *
               (static_cast<std::size_t>(j0) +
                static_cast<std::size_t>(ny) * static_cast<std::size_t>(k0));
}

}  // namespace

namespace fv_advection {

void semi_y_3d(
    int nx,
    int js,
    int je,
    int nz,
    double dt,
    const double* va,
    const double* qx,
    const double* dyy,
    double* dq) {
    const int ny = je - js + 1;
    const int qx_ny = ny + 4;  // qx lower bound is js-2 and upper bound is je+2.

    for (int k0 = 0; k0 < nz; ++k0) {
        for (int j = js; j <= je; ++j) {
            const int j0 = j - js;
            const int qx_j_minus_1 = j - (js - 2) - 1;
            const int qx_j = j - (js - 2);
            const int qx_j_plus_1 = j - (js - 2) + 1;
            for (int i0 = 0; i0 < nx; ++i0) {
                const std::size_t out_idx = idx3(i0, j0, k0, nx, ny);
                const double va_val = va[out_idx];
                if (va_val >= 0.0) {
                    dq[out_idx] =
                        va_val * dt *
                        (qx[idx3(i0, qx_j_minus_1, k0, nx, qx_ny)] -
                         qx[idx3(i0, qx_j, k0, nx, qx_ny)]) /
                        dyy[j - js];
                } else {
                    dq[out_idx] =
                        va_val * dt *
                        (qx[idx3(i0, qx_j, k0, nx, qx_ny)] -
                         qx[idx3(i0, qx_j_plus_1, k0, nx, qx_ny)]) /
                        dyy[j + 1 - js];
                }
            }
        }
    }
}

}  // namespace fv_advection

extern "C" void fv_semi_y_3d_c(
    int nx,
    int js,
    int je,
    int nz,
    double dt,
    const double* va,
    const double* qx,
    const double* dyy,
    double* dq) {
    fv_advection::semi_y_3d(nx, js, je, nz, dt, va, qx, dyy, dq);
}
