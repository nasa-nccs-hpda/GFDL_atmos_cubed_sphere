// ============================================================================
// Held-Suarez Forcing Module: C API Implementation
//
// This file implements the C-compatible wrapper functions declared in
// held_suarez_c_api.h. These wrappers convert flat C parameters to
// C++ structures and call the underlying C++ implementation.
// ============================================================================

#include "../include/held_suarez_c_api.h"
#include "../include/held_suarez_forcing.hpp"

// ============================================================================
// Main Driver Function
// ============================================================================

int hs_forcing_driver_c(
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
    double* udt,
    double* vdt,
    double* tdt,
    double* teq,
    double* h_trop,
    double* tg_new,
    const double* mask)
{
    // Validate required inputs
    if (nlon <= 0 || nlat <= 0 || nlev <= 0) {
        return HS_ERROR_INVALID_DIMS;
    }

    if (lat == nullptr || ps == nullptr || p_full == nullptr ||
        u == nullptr || v == nullptr || t == nullptr ||
        udt == nullptr || vdt == nullptr || tdt == nullptr || teq == nullptr) {
        return HS_ERROR_NULL_POINTER;
    }

    // Validate top_down requirements
    if (equilibrium_option == HS_EQUILIBRIUM_TOP_DOWN) {
        if (zfull == nullptr || tg_prev == nullptr ||
            h_trop == nullptr || tg_new == nullptr) {
            return HS_ERROR_TOPDOWN_MISSING;
        }
    }

    // Build configuration structure from flat parameters
    hs_forcing::Config config;
    config.t_zero = t_zero;
    config.t_strat = t_strat;
    config.delh = delh;
    config.delv = delv;
    config.eps = eps;
    config.P00 = P00;
    config.kappa = kappa;
    config.tka = tka;
    config.tks = tks;
    config.vkf = vkf;
    config.sigma_b = sigma_b;
    config.orbital_period = orbital_period;
    config.ecc = ecc;
    config.obliq = obliq;
    config.peri_time = peri_time;
    config.smaxis = smaxis;
    config.solar_const = solar_const;
    config.stefan = stefan;
    config.albedo = albedo;
    config.lapse = lapse;
    config.h_a = h_a;
    config.tau_s = tau_s;
    config.heat_capacity = heat_capacity;
    config.ml_depth = ml_depth;
    config.do_conserve_energy = do_conserve_energy;
    config.equilibrium_option = equilibrium_option;
    config.stratosphere_option = stratosphere_option;

    // Call C++ driver
    hs_forcing::hs_forcing_driver(
        nlon, nlat, nlev,
        current_time, dt,
        lon, lat,
        ps, p_full, p_half,
        u, v, t,
        um, vm,
        zfull, tg_prev,
        config,
        udt, vdt, tdt, teq,
        h_trop, tg_new,
        mask
    );

    return HS_SUCCESS;
}

// ============================================================================
// Individual Kernel Wrappers
// ============================================================================

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
    const double* mask)
{
    if (nlon <= 0 || nlat <= 0 || nlev <= 0) {
        return HS_ERROR_INVALID_DIMS;
    }

    if (ps == nullptr || p_full == nullptr ||
        u == nullptr || v == nullptr ||
        udt == nullptr || vdt == nullptr) {
        return HS_ERROR_NULL_POINTER;
    }

    hs_forcing::rayleigh_damping(
        nlon, nlat, nlev,
        ps, p_full, u, v,
        vkf, sigma_b,
        udt, vdt,
        mask
    );

    return HS_SUCCESS;
}

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
    const double* mask)
{
    if (nlon <= 0 || nlat <= 0 || nlev <= 0) {
        return HS_ERROR_INVALID_DIMS;
    }

    if (lat == nullptr || ps == nullptr || p_full == nullptr ||
        t == nullptr || tdt == nullptr || teq == nullptr) {
        return HS_ERROR_NULL_POINTER;
    }

    // Build minimal config for newtonian_damping
    hs_forcing::Config config;
    config.t_zero = t_zero;
    config.t_strat = t_strat;
    config.delh = delh;
    config.delv = delv;
    config.eps = eps;
    config.P00 = P00;
    config.kappa = kappa;
    config.tka = tka;
    config.tks = tks;
    config.sigma_b = sigma_b;

    hs_forcing::newtonian_damping(
        nlon, nlat, nlev,
        lat, ps, p_full, t,
        config,
        tdt, teq,
        mask
    );

    return HS_SUCCESS;
}

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
    const double* mask)
{
    if (nlon <= 0 || nlat <= 0 || nlev <= 0) {
        return HS_ERROR_INVALID_DIMS;
    }

    if (lat == nullptr || ps == nullptr || p_full == nullptr ||
        zfull == nullptr || t == nullptr || tg_prev == nullptr ||
        tdt == nullptr || teq == nullptr ||
        h_trop == nullptr || tg_new == nullptr) {
        return HS_ERROR_NULL_POINTER;
    }

    // Build config for top_down_newtonian_damping
    hs_forcing::Config config;
    config.t_strat = t_strat;
    config.eps = eps;
    config.sigma_b = sigma_b;
    config.tka = tka;
    config.tks = tks;
    config.orbital_period = orbital_period;
    config.ecc = ecc;
    config.obliq = obliq;
    config.peri_time = peri_time;
    config.smaxis = smaxis;
    config.solar_const = solar_const;
    config.stefan = stefan;
    config.albedo = albedo;
    config.lapse = lapse;
    config.h_a = h_a;
    config.tau_s = tau_s;
    config.heat_capacity = heat_capacity;
    config.ml_depth = ml_depth;
    config.stratosphere_option = stratosphere_option;

    hs_forcing::top_down_newtonian_damping(
        nlon, nlat, nlev,
        current_time, dt,
        lat, ps, p_full, zfull, t, tg_prev,
        config,
        tdt, teq, h_trop, tg_new,
        mask
    );

    return HS_SUCCESS;
}

// ============================================================================
// Utility Functions
// ============================================================================

void hs_convert_timescales_c(
    double ka_days,
    double ks_days,
    double kf_days,
    double* tka,
    double* tks,
    double* vkf)
{
    const double SECONDS_PER_DAY = 86400.0;

    if (tka != nullptr) {
        double ka_abs = (ka_days > 0) ? ka_days : -ka_days;
        *tka = 1.0 / (SECONDS_PER_DAY * ka_abs);
    }

    if (tks != nullptr) {
        double ks_abs = (ks_days > 0) ? ks_days : -ks_days;
        *tks = 1.0 / (SECONDS_PER_DAY * ks_abs);
    }

    if (vkf != nullptr) {
        double kf_abs = (kf_days > 0) ? kf_days : -kf_days;
        *vkf = 1.0 / (SECONDS_PER_DAY * kf_abs);
    }
}

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
    double* ml_depth)
{
    hs_forcing::Config cfg = hs_forcing::Config::defaults();

    if (t_zero != nullptr) *t_zero = cfg.t_zero;
    if (t_strat != nullptr) *t_strat = cfg.t_strat;
    if (delh != nullptr) *delh = cfg.delh;
    if (delv != nullptr) *delv = cfg.delv;
    if (eps != nullptr) *eps = cfg.eps;
    if (P00 != nullptr) *P00 = cfg.P00;
    if (kappa != nullptr) *kappa = cfg.kappa;
    if (tka != nullptr) *tka = cfg.tka;
    if (tks != nullptr) *tks = cfg.tks;
    if (vkf != nullptr) *vkf = cfg.vkf;
    if (sigma_b != nullptr) *sigma_b = cfg.sigma_b;
    if (orbital_period != nullptr) *orbital_period = cfg.orbital_period;
    if (ecc != nullptr) *ecc = cfg.ecc;
    if (obliq != nullptr) *obliq = cfg.obliq;
    if (peri_time != nullptr) *peri_time = cfg.peri_time;
    if (smaxis != nullptr) *smaxis = cfg.smaxis;
    if (solar_const != nullptr) *solar_const = cfg.solar_const;
    if (stefan != nullptr) *stefan = cfg.stefan;
    if (albedo != nullptr) *albedo = cfg.albedo;
    if (lapse != nullptr) *lapse = cfg.lapse;
    if (h_a != nullptr) *h_a = cfg.h_a;
    if (tau_s != nullptr) *tau_s = cfg.tau_s;
    if (heat_capacity != nullptr) *heat_capacity = cfg.heat_capacity;
    if (ml_depth != nullptr) *ml_depth = cfg.ml_depth;
}
