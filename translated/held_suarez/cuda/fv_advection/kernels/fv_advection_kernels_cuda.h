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

int advection_sphere_predictor_cuda(
    int nx,
    int ny,
    int nz,
    double dt,
    double dx,
    const double* c,
    const double* dyy,
    const double* ua,
    const double* va,
    const double* q,
    double* q1,
    double* q2);

int advection_sphere_corrector_cuda(
    int nx,
    int ny_total,
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
    const double* q2,
    double* dq_dt);

int a_grid_advection_stage1_cuda(
    int nx,
    int ny,
    int nz,
    double dt,
    double dx,
    bool flux_only,
    const double* c,
    const double* cc,
    const double* dy,
    const double* dyy,
    const double* ua,
    const double* vx,
    const double* qx,
    double* dq_dt,
    double* q1);

int a_grid_advection_stage2_cuda(
    int nx,
    int ny_total,
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

extern "C" int fv_advection_sphere_predictor_cuda_c(
    int nx,
    int js,
    int je,
    int nz,
    double dt,
    double dx,
    const double* c,
    const double* dyy,
    const double* ua,
    const double* va,
    const double* q,
    double* q1,
    double* q2);

extern "C" int fv_advection_sphere_corrector_cuda_c(
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
    const double* q2,
    double* dq_dt);

extern "C" int fv_a_grid_advection_stage1_cuda_c(
    int nx,
    int js,
    int je,
    int nz,
    double dt,
    double dx,
    int flux_only,
    const double* c,
    const double* cc,
    const double* dy,
    const double* dyy,
    const double* ua,
    const double* vx,
    const double* qx,
    double* dq_dt,
    double* q1);

extern "C" int fv_a_grid_advection_stage2_cuda_c(
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
    const double* q1,
    double* dq_dt);

#endif  // FV_ADVECTION_KERNELS_CUDA_H
