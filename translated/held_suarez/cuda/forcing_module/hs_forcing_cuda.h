#ifndef HS_FORCING_CUDA_H
#define HS_FORCING_CUDA_H

#include "../../cpp/forcing_module/include/held_suarez_config.hpp"

namespace hs_forcing {
namespace cuda_backend {

int hs_forcing_driver_cuda(
    int nlon, int nlat, int nlev,
    int current_time,
    double dt,
    const double* lon,
    const double* lat,
    const double* ps,
    const double* p_full,
    const double* p_half,
    const double* u,
    const double* v,
    const double* t,
    const double* um,
    const double* vm,
    const double* zfull,
    const double* tg_prev,
    const Config& config,
    double* udt,
    double* vdt,
    double* tdt,
    double* teq,
    double* h_trop,
    double* tg_new,
    const double* mask);

} // namespace cuda_backend
} // namespace hs_forcing

#endif // HS_FORCING_CUDA_H
