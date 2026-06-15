#ifndef HS_FORCING_CUDA_KERNELS_CUH
#define HS_FORCING_CUDA_KERNELS_CUH

#include <cuda_runtime.h>

namespace hs_forcing {
namespace cuda_backend {

__global__ void rayleigh_accumulate_kernel(
    int size_3d,
    int nlon,
    int nlat,
    int nlev,
    const double* ps,
    const double* p_full,
    const double* u,
    const double* v,
    double vkf,
    double sigma_b,
    const double* mask,
    double* udt,
    double* vdt);

__global__ void newtonian_accumulate_kernel(
    int size_3d,
    int nlon,
    int nlat,
    int nlev,
    const double* lat,
    const double* ps,
    const double* p_full,
    const double* t,
    double t_zero,
    double t_strat,
    double delh,
    double delv,
    double eps,
    double p00,
    double kappa,
    double tka,
    double tks,
    double sigma_b,
    const double* mask,
    double* tdt,
    double* teq);

} // namespace cuda_backend
} // namespace hs_forcing

#endif // HS_FORCING_CUDA_KERNELS_CUH
