#ifndef SEMI_Y_3D_CUDA_H
#define SEMI_Y_3D_CUDA_H

namespace fv_advection {
namespace cuda_backend {

int semi_y_3d_cuda(
    int nx,
    int js,
    int je,
    int nz,
    double dt,
    const double* va,
    const double* qx,
    const double* dyy,
    double* dq);

}  // namespace cuda_backend
}  // namespace fv_advection

extern "C" int fv_semi_y_3d_cuda_c(
    int nx,
    int js,
    int je,
    int nz,
    double dt,
    const double* va,
    const double* qx,
    const double* dyy,
    double* dq);

#endif  // SEMI_Y_3D_CUDA_H
