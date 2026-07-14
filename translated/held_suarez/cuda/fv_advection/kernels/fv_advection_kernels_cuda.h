#ifndef FV_ADVECTION_KERNELS_CUDA_H
#define FV_ADVECTION_KERNELS_CUDA_H

namespace fv_advection_kernels {
namespace cuda_backend {

int semi_x_3d_cuda(
    int nx,
    int ny,
    int nz,
    double dt,
    double dx,
    const double* c,
    const double* ua,
    const double* q,
    double* dq);

int slope_x_cuda(
    int nx,
    int ny,
    int nz,
    bool monotone,
    const double* q,
    double* slope);

int integer_flux_x_cuda(
    int nx,
    int ny,
    int nz,
    const double* courant,
    const double* q,
    double* flux);

int vanleer_x_3d_cuda(
    int nx,
    int ny,
    int nz,
    double dt,
    double dx,
    const double* c,
    bool monotone,
    const double* uc,
    const double* q,
    double* dq_dt);

int slope_sphere_cuda(
    int nx,
    int nys,
    int nz,
    bool monotone,
    const double* dy_plus,
    const double* dy_minus,
    const double* q,
    double* slope);

int vanleer_sphere_3d_cuda(
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
    double* dq_dt);

bool resident_boundary_enabled();

int resident_advection_begin(
    int nx,
    int ny,
    int nz,
    double half_dt,
    double dx,
    const double* c,
    const double* ua,
    const double* va,
    const double* q,
    const double* q_halo,
    const double* dyy,
    double* q1_interior);

int resident_advection_finish(
    int nx,
    int ny,
    int nz,
    double dt,
    double dx,
    bool monotone,
    bool is_south_boundary,
    bool is_north_boundary,
    const double* c,
    const double* cc,
    const double* dy,
    const double* dy_plus,
    const double* dy_minus,
    const double* uc,
    const double* vc,
    const double* q1,
    double* dq_dt);

}  // namespace cuda_backend
}  // namespace fv_advection_kernels

extern "C" int fv_semi_x_3d_cuda_c(
    int nx,
    int js,
    int je,
    int nz,
    double dt,
    double dx,
    const double* c,
    const double* ua,
    const double* q,
    double* dq);

extern "C" int fv_slope_x_cuda_c(
    int nx,
    int js,
    int je,
    int nz,
    int monotone,
    const double* q,
    double* slope);

extern "C" int fv_integer_flux_x_cuda_c(
    int nx,
    int js,
    int je,
    int nz,
    const double* courant,
    const double* q,
    double* flux);

extern "C" int fv_vanleer_x_3d_cuda_c(
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
    double* dq_dt);

extern "C" int fv_slope_sphere_cuda_c(
    int nx,
    int js,
    int je,
    int nz,
    int monotone,
    const double* dy_plus,
    const double* dy_minus,
    const double* q,
    double* slope);

extern "C" int fv_vanleer_sphere_3d_cuda_c(
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
    double* dq_dt);

extern "C" int fv_advection_resident_enabled_cuda_c();

extern "C" int fv_advection_resident_begin_cuda_c(
    int nx,
    int js,
    int je,
    int nz,
    double half_dt,
    double dx,
    const double* c,
    const double* ua,
    const double* va,
    const double* q,
    const double* q_halo,
    const double* dyy,
    double* q1_interior);

extern "C" int fv_advection_resident_finish_cuda_c(
    int nx,
    int ny_total,
    int js,
    int je,
    int nz,
    double dt,
    double dx,
    int monotone,
    const double* c,
    const double* cc,
    const double* dy,
    const double* dy_plus,
    const double* dy_minus,
    const double* uc,
    const double* vc,
    const double* q1,
    double* dq_dt);

#endif  // FV_ADVECTION_KERNELS_CUDA_H
