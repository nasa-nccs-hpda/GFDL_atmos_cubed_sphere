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

// Build (or confirm) the process's NCCL communicator for GPU-to-GPU halo
// exchange. Returns 0 on success. Fails when built without FV_ADVECTION_USE_NCCL.
int nccl_init();

// Swap the resident q1 y-halo with the neighbor ranks on the GPU (pack, NCCL
// send/recv, unpack). Needs an active resident stage matching nx/ny/nz. The pole
// side is left for the fold. Returns 0 on success.
int nccl_exchange_resident_q1_halo(int nx, int ny, int nz);

// Fill this rank's pole q1 halo rows on the GPU by reflecting the interior across
// the pole (device-side stand-in for the host polar fold). is_south_boundary /
// is_north_boundary mark which poles this rank owns. Needs an active resident
// stage matching nx/ny/nz. Returns 0 on success.
int fold_resident_q1_poles(int nx, int ny, int nz, bool is_south_boundary,
                           bool is_north_boundary);

// True when the GPU-to-GPU q1 halo path is on (env FV_ADVECTION_NCCL_HALO). Off
// by default; only meaningful in resident mode built with FV_ADVECTION_USE_NCCL.
bool nccl_halo_enabled();

// Build (or confirm) the process's CUDA IPC peer context for the direct NVLink
// peer-copy halo. Returns 0 on success. Fails when built without
// FV_ADVECTION_USE_PEER.
int peer_init();

// True when the direct peer-copy halo path is on (env FV_ADVECTION_PEER_HALO).
// Off by default; only meaningful in resident mode built with FV_ADVECTION_USE_PEER.
bool peer_halo_enabled();

int resident_advection_begin(
    int nx,
    int ny,
    int nz,
    double half_dt,
    double dx,
    bool fold_div,
    const double* c,
    const double* cc,
    const double* dy,
    const double* dy_plus,
    const double* dy_minus,
    const double* dyy,
    const double* ua,
    const double* q,
    const double* va,
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
    int fold_div,
    const double* c,
    const double* cc,
    const double* dy,
    const double* dy_plus,
    const double* dy_minus,
    const double* dyy,
    const double* ua,
    const double* q,
    const double* va,
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
    const double* q1,
    double* dq_dt);

// Bootstrap the NCCL communicator once, over the running MPI world. Returns 0 on
// success. Callable from Fortran to force setup (and surface any misconfiguration)
// before the first halo exchange.
extern "C" int fv_advection_nccl_init_cuda_c();

// Swap the resident q1 y-halo with the neighbor ranks on the GPU. Needs an active
// resident stage matching nx/ny/nz. Returns 0 on success.
extern "C" int fv_advection_nccl_exchange_q1_halo_cuda_c(int nx, int ny, int nz);

// Fill this rank's pole q1 halo rows on the GPU. is_south_boundary /
// is_north_boundary are nonzero for the poles this rank owns. Needs an active
// resident stage matching nx/ny/nz. Returns 0 on success.
extern "C" int fv_advection_nccl_fold_q1_poles_cuda_c(int nx, int ny, int nz,
                                                      int is_south_boundary,
                                                      int is_north_boundary);

// Returns 1 when the GPU-to-GPU q1 halo path is on (env FV_ADVECTION_NCCL_HALO),
// else 0. Lets the Fortran side skip the host halo exchange and fold.
extern "C" int fv_advection_nccl_halo_enabled_cuda_c();

// Bootstrap the CUDA IPC peer context once, over the running MPI world. Returns 0
// on success. Callable from Fortran to force setup (and surface any
// misconfiguration, such as a GPU pair without peer access) before the first
// peer-copy halo.
extern "C" int fv_advection_peer_init_cuda_c();

// Returns 1 when the direct peer-copy halo path is on (env FV_ADVECTION_PEER_HALO),
// else 0. Lets the Fortran side skip the host halo exchange and fold.
extern "C" int fv_advection_peer_halo_enabled_cuda_c();

#endif  // FV_ADVECTION_KERNELS_CUDA_H
