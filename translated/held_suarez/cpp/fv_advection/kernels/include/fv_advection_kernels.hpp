#ifndef FV_ADVECTION_KERNELS_HPP
#define FV_ADVECTION_KERNELS_HPP

namespace fv_advection_kernels {

void find_cell_x(int nx, int ny, int nz, const double* b, int* ii);

void slope_x(
    int nx,
    int ny,
    int nz,
    bool monotone,
    const double* q,
    double* slope);

void integer_flux_x(
    int nx,
    int ny,
    int nz,
    const double* courant,
    const double* q,
    double* flux);

void semi_x_3d(
    int nx,
    int ny,
    int nz,
    double dt,
    double dx,
    const double* c,
    const double* ua,
    const double* q,
    double* dq);

void slope_sphere(
    int nx,
    int nys,
    int nz,
    bool monotone,
    const double* dy_plus,
    const double* dy_minus,
    const double* q,
    double* slope);

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
    double* dq_dt);

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
    double* dq_dt);

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
    double* dq);

extern "C" void fv_slope_x_c(
    int nx,
    int js,
    int je,
    int nz,
    int monotone,
    const double* q,
    double* slope);

extern "C" void fv_integer_flux_x_c(
    int nx,
    int js,
    int je,
    int nz,
    const double* courant,
    const double* q,
    double* flux);

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
    double* dq_dt);

extern "C" void fv_slope_sphere_c(
    int nx,
    int js,
    int je,
    int nz,
    int monotone,
    const double* dy_plus,
    const double* dy_minus,
    const double* q,
    double* slope);

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
    double* dq_dt);

#endif  // FV_ADVECTION_KERNELS_HPP
