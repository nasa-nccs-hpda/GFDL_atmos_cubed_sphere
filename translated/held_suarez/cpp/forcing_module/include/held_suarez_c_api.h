/*
 * ============================================================================
 * Held-Suarez Forcing Module: C API
 *
 * This header provides C-compatible function declarations for calling
 * the C++ Held-Suarez forcing module from Fortran via iso_c_binding.
 *
 * Design principles:
 *   - Pure C interface (no C++ types)
 *   - Flat parameter lists (no structs in function signatures)
 *   - All arrays passed as pointers with explicit dimensions
 *   - Integer error codes instead of exceptions
 *
 * Array Layout:
 *   All arrays use Fortran column-major layout:
 *   - 2D: arr[i + nlon * j] for arr(i,j)
 *   - 3D: arr[i + nlon * (j + nlat * k)] for arr(i,j,k)
 *
 * Usage from Fortran:
 *   See hs_forcing_c_interface module in hs_forcing_c_interface.F90
 * ============================================================================
 */

#ifndef HELD_SUAREZ_C_API_H
#define HELD_SUAREZ_C_API_H

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * Error Codes
 * ============================================================================ */

#define HS_SUCCESS              0
#define HS_ERROR_NULL_POINTER  -1
#define HS_ERROR_INVALID_DIMS  -2
#define HS_ERROR_INVALID_CONFIG -3
#define HS_ERROR_TOPDOWN_MISSING -4

/* ============================================================================
 * Equilibrium Temperature Options
 *
 * Maps to Fortran equilibrium_t_option namelist variable.
 * ============================================================================ */

#define HS_EQUILIBRIUM_HELD_SUAREZ  0
#define HS_EQUILIBRIUM_TOP_DOWN     1

/* ============================================================================
 * Stratosphere Options (for top_down mode)
 *
 * Maps to Fortran stratosphere_t_option namelist variable.
 * ============================================================================ */

#define HS_STRATOSPHERE_DEFAULT        0
#define HS_STRATOSPHERE_C_ABOVE_TP     1
#define HS_STRATOSPHERE_HS_LIKE        2
#define HS_STRATOSPHERE_EXTEND_TP      3

/* ============================================================================
 * Main Driver Function
 *
 * Computes the complete Held-Suarez forcing (Rayleigh damping + thermal forcing).
 *
 * IMPORTANT: Tendency arrays (udt, vdt, tdt) are ACCUMULATED (added to),
 *            not overwritten. Initialize to zero before first call.
 *
 * Parameters:
 *   nlon, nlat, nlev - Grid dimensions
 *   current_time     - Time in seconds since epoch (int)
 *   dt               - Physics timestep in seconds
 *
 *   Coordinate arrays [nlon, nlat]:
 *   lon, lat         - Longitude, latitude in radians
 *
 *   Pressure fields:
 *   ps               - Surface pressure [Pa], array [nlon, nlat]
 *   p_full           - Pressure at full levels [Pa], array [nlon, nlat, nlev]
 *   p_half           - Pressure at half levels [Pa], array [nlon, nlat, nlev+1]
 *                      (NULL if !do_conserve_energy)
 *
 *   Prognostic variables [nlon, nlat, nlev]:
 *   u, v             - Zonal, meridional wind [m/s]
 *   t                - Temperature [K]
 *   um, vm           - Previous timestep winds (NULL if !do_conserve_energy)
 *
 *   Top-down specific (NULL if equilibrium_option != TOP_DOWN):
 *   zfull            - Height at full levels [m], array [nlon, nlat, nlev]
 *   tg_prev          - Previous ground temperature [K], array [nlon, nlat]
 *
 *   Configuration (flat parameters instead of struct for C interop):
 *   t_zero ... P00   - Equilibrium temperature parameters
 *   kappa            - R/cp ratio
 *   tka, tks, vkf    - Damping coefficients [1/s] (pre-converted from days)
 *   sigma_b          - Boundary layer top sigma
 *   orbital_period...ml_depth - Top-down parameters
 *   do_conserve_energy - 0 or 1
 *   equilibrium_option - HS_EQUILIBRIUM_* constant
 *   stratosphere_option - HS_STRATOSPHERE_* constant
 *
 *   Output arrays (tendency arrays are ACCUMULATED):
 *   udt, vdt         - Wind tendencies [m/s^2], array [nlon, nlat, nlev]
 *   tdt              - Temperature tendency [K/s], array [nlon, nlat, nlev]
 *   teq              - Equilibrium temperature [K], array [nlon, nlat, nlev]
 *   h_trop           - Tropopause height [km], array [nlon, nlat] (NULL if HS)
 *   tg_new           - New ground temp [K], array [nlon, nlat] (NULL if HS)
 *
 *   Optional:
 *   mask             - Mask array [nlon, nlat, nlev] (NULL if unused)
 *
 * Returns:
 *   HS_SUCCESS on success, error code on failure
 * ============================================================================ */

int hs_forcing_driver_c(
    /* Grid dimensions */
    int nlon, int nlat, int nlev,

    /* Time */
    int current_time,
    double dt,

    /* Coordinate arrays */
    const double* lon,
    const double* lat,

    /* Pressure fields */
    const double* ps,
    const double* p_full,
    const double* p_half,

    /* Prognostic variables */
    const double* u,
    const double* v,
    const double* t,

    /* Previous timestep (for energy conservation) */
    const double* um,
    const double* vm,

    /* Top-down specific inputs */
    const double* zfull,
    const double* tg_prev,

    /* Configuration parameters (flat, not struct) */
    double t_zero,
    double t_strat,
    double delh,
    double delv,
    double eps,
    double P00,
    double kappa,
    double tka,
    double tks,
    double vkf,
    double sigma_b,
    double orbital_period,
    double ecc,
    double obliq,
    double peri_time,
    double smaxis,
    double solar_const,
    double stefan,
    double albedo,
    double lapse,
    double h_a,
    double tau_s,
    double heat_capacity,
    double ml_depth,
    int do_conserve_energy,
    int equilibrium_option,
    int stratosphere_option,

    /* Output arrays */
    double* udt,
    double* vdt,
    double* tdt,
    double* teq,
    double* h_trop,
    double* tg_new,

    /* Optional mask */
    const double* mask
);

/* ============================================================================
 * Individual Kernel Wrappers
 *
 * These provide C access to individual kernels for testing or selective use.
 * ============================================================================ */

/* Rayleigh damping only */
int hs_rayleigh_damping_c(
    int nlon, int nlat, int nlev,
    const double* ps,
    const double* p_full,
    const double* u,
    const double* v,
    double vkf,
    double sigma_b,
    double* udt,
    double* vdt,
    const double* mask
);

/* Newtonian damping only (standard Held-Suarez) */
int hs_newtonian_damping_c(
    int nlon, int nlat, int nlev,
    const double* lat,
    const double* ps,
    const double* p_full,
    const double* t,
    double t_zero,
    double t_strat,
    double delh,
    double delv,
    double eps,
    double P00,
    double kappa,
    double tka,
    double tks,
    double sigma_b,
    double* tdt,
    double* teq,
    const double* mask
);

/* Top-down newtonian damping */
int hs_top_down_newtonian_damping_c(
    int nlon, int nlat, int nlev,
    int current_time,
    double dt,
    const double* lat,
    const double* ps,
    const double* p_full,
    const double* zfull,
    const double* t,
    const double* tg_prev,
    double t_strat,
    double eps,
    double sigma_b,
    double tka,
    double tks,
    double orbital_period,
    double ecc,
    double obliq,
    double peri_time,
    double smaxis,
    double solar_const,
    double stefan,
    double albedo,
    double lapse,
    double h_a,
    double tau_s,
    double heat_capacity,
    double ml_depth,
    int stratosphere_option,
    double* tdt,
    double* teq,
    double* h_trop,
    double* tg_new,
    const double* mask
);

/* ============================================================================
 * Utility Functions
 * ============================================================================ */

/* Convert damping timescales from days to 1/s */
void hs_convert_timescales_c(
    double ka_days,
    double ks_days,
    double kf_days,
    double* tka,
    double* tks,
    double* vkf
);

/* Get default configuration values */
void hs_get_defaults_c(
    double* t_zero,
    double* t_strat,
    double* delh,
    double* delv,
    double* eps,
    double* P00,
    double* kappa,
    double* tka,
    double* tks,
    double* vkf,
    double* sigma_b,
    double* orbital_period,
    double* ecc,
    double* obliq,
    double* peri_time,
    double* smaxis,
    double* solar_const,
    double* stefan,
    double* albedo,
    double* lapse,
    double* h_a,
    double* tau_s,
    double* heat_capacity,
    double* ml_depth
);

#ifdef __cplusplus
}
#endif

#endif /* HELD_SUAREZ_C_API_H */
