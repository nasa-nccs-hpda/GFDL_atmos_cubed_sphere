#ifndef PRESS_AND_GEOPOT_CUDA_H
#define PRESS_AND_GEOPOT_CUDA_H

#ifdef __cplusplus
extern "C" {
#endif

int press_geopot_cuda_init_c(
    int nlev,
    const double* pk,
    const double* bk,
    double rdgas,
    double rvgas,
    int use_virtual_temperature,
    int vert_difference_option);

int press_geopot_pressure_variables_cuda_c(
    int ni,
    int nj,
    int nlev,
    double* p_half,
    double* ln_p_half,
    double* p_full,
    double* ln_p_full,
    const double* surface_p);

int press_geopot_compute_geopotential_cuda_c(
    int ni,
    int nj,
    int nlev,
    const double* t_grid,
    const double* ln_p_half,
    const double* ln_p_full,
    const double* surf_geopotential,
    double* geopot_full,
    double* geopot_half,
    const double* q_grid,
    int has_q_grid);

void press_geopot_cuda_finalize_c(void);
void press_geopot_cuda_profile_print_c(void);

#ifdef __cplusplus
}
#endif

#endif
