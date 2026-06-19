#ifndef SEMI_Y_3D_HPP
#define SEMI_Y_3D_HPP

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
    double* dq);

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
    double* dq);

#endif  // SEMI_Y_3D_HPP
