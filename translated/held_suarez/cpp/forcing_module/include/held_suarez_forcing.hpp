#ifndef HELD_SUAREZ_FORCING_HPP
#define HELD_SUAREZ_FORCING_HPP

// ============================================================================
// Held-Suarez Forcing Module: Main Interface
//
// This header provides the unified C++ interface for the Held-Suarez forcing
// module. It aggregates the individual kernel translations and provides a
// single driver function that orchestrates the complete forcing calculation.
//
// Design principles:
//   - Stateless: all persistent state passed explicitly
//   - Fortran-compatible: arrays use column-major layout
//   - Tendency accumulation: outputs are ADDED to, not overwritten
//   - No dynamic allocation in hot path
//
// Original Fortran: src/atmos_param/hs_forcing/hs_forcing.F90
// ============================================================================

#include "held_suarez_config.hpp"

#include <algorithm>  // std::max, std::min
#include <cmath>      // std::sin, std::cos, std::tan, std::log, std::pow, etc.
#include <cstddef>    // size_t
#include <vector>     // std::vector for internal temporaries

namespace hs_forcing {

// ============================================================================
// Individual Kernel Functions
//
// These are the core computational kernels, translated from Fortran.
// Each has been validated independently against Fortran baseline.
// ============================================================================

// ----------------------------------------------------------------------------
// calc_ecc_anomaly
//
// Newton-Raphson solver for Kepler's equation: E - e*sin(E) = M
//
// Inputs:
//   mean_anomaly - Mean anomaly M [radians]
//   ecc          - Orbital eccentricity [dimensionless]
//
// Output:
//   ecc_anomaly  - Eccentric anomaly E [radians]
//
// Source: hs_forcing.F90:864-890
// ----------------------------------------------------------------------------
inline void calc_ecc_anomaly(double mean_anomaly, double ecc, double& ecc_anomaly) {
    const int maxiter = 30;
    const double tol = 1.0e-10;

    ecc_anomaly = mean_anomaly;
    double d = ecc_anomaly - ecc * std::sin(ecc_anomaly) - mean_anomaly;

    for (int k = 1; k <= maxiter; ++k) {
        double dE = d / (1.0 - ecc * std::cos(ecc_anomaly));
        ecc_anomaly = ecc_anomaly - dE;
        d = ecc_anomaly - ecc * std::sin(ecc_anomaly) - mean_anomaly;
        if (std::abs(d) < tol) {
            return;
        }
    }
    // Warning: eccentric anomaly has not converged (silent in C++ version)
}

// ----------------------------------------------------------------------------
// calc_hour_angle
//
// Compute solar hour angle from latitude and solar declination.
// Hour angle represents half the day length in radians.
//
// Inputs:
//   nlon, nlat - Grid dimensions
//   lat        - Latitude [radians], array [nlon, nlat]
//   dec        - Solar declination [radians], scalar
//
// Output:
//   hour_angle - Hour angle [radians], array [nlon, nlat]
//                Range: 0 (polar night) to PI (polar day)
//
// Source: hs_forcing.F90:842-860
// ----------------------------------------------------------------------------
inline void calc_hour_angle(
    int nlon, int nlat,
    const double* lat,
    double dec,
    double* hour_angle)
{
    double tan_dec = std::tan(dec);

    for (int j = 0; j < nlat; ++j) {
        for (int i = 0; i < nlon; ++i) {
            int idx = idx2(i, j, nlon);
            double inv_hour_angle = -std::tan(lat[idx]) * tan_dec;
            // Clamp to [-1, 1] for acos domain
            inv_hour_angle = std::max(-1.0, std::min(1.0, inv_hour_angle));
            hour_angle[idx] = std::acos(inv_hour_angle);
        }
    }
}

// ----------------------------------------------------------------------------
// update_orbit
//
// Compute solar declination and orbital distance from current time.
//
// Inputs:
//   current_time    - Time in seconds since epoch
//   orbital_period  - Orbital period [days]
//   ecc             - Orbital eccentricity
//   obliq           - Obliquity [degrees]
//   peri_time       - Perihelion time as fraction of orbital period
//   smaxis          - Semi-major axis [m]
//
// Outputs:
//   dec      - Solar declination [radians]
//   orb_dist - Orbital distance [m]
//
// Source: hs_forcing.F90:823-838
// ----------------------------------------------------------------------------
inline void update_orbit(
    int current_time,
    double orbital_period,
    double ecc,
    double obliq,
    double peri_time,
    double smaxis,
    double& dec,
    double& orb_dist)
{
    const double pi = constants::PI;
    const double sec_per_day = constants::SECONDS_PER_DAY;

    double mean_anomaly = 2.0 * pi / (orbital_period * sec_per_day) *
        (static_cast<double>(current_time) - peri_time * orbital_period * sec_per_day);

    double ecc_anomaly;
    calc_ecc_anomaly(mean_anomaly, ecc, ecc_anomaly);

    double true_anomaly = 2.0 * std::atan(
        std::sqrt((1.0 + ecc) / (1.0 - ecc)) * std::tan(ecc_anomaly / 2.0));

    orb_dist = smaxis * (1.0 - ecc * ecc) / (1.0 + ecc * std::cos(true_anomaly));

    double theta = 2.0 * pi * static_cast<double>(current_time) / (orbital_period * sec_per_day);
    dec = std::asin(std::sin(obliq * pi / 180.0) * std::sin(theta));
}

// ----------------------------------------------------------------------------
// rayleigh_damping
//
// Apply Rayleigh (linear) friction damping to horizontal wind components
// near the surface. Implements Held-Suarez (1994) Equation 3.
//
// Inputs:
//   nlon, nlat, nlev - Grid dimensions
//   ps               - Surface pressure [Pa], array [nlon, nlat]
//   p_full           - Pressure at full levels [Pa], array [nlon, nlat, nlev]
//   u                - Zonal wind [m/s], array [nlon, nlat, nlev]
//   v                - Meridional wind [m/s], array [nlon, nlat, nlev]
//   vkf              - Friction coefficient [1/s]
//   sigma_b          - Boundary layer top sigma level
//   mask             - Optional mask [nlon, nlat, nlev], nullptr if unused
//
// Outputs:
//   udt - Zonal wind tendency [m/s^2], array [nlon, nlat, nlev]
//   vdt - Meridional wind tendency [m/s^2], array [nlon, nlat, nlev]
//
// Note: Tendencies are WRITTEN (not accumulated) by this function.
//       The driver handles accumulation.
//
// Source: hs_forcing.F90:615-679
// ----------------------------------------------------------------------------
inline void rayleigh_damping(
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
    double vcoeff = -vkf / (1.0 - sigma_b);

    for (int k = 0; k < nlev; ++k) {
        for (int j = 0; j < nlat; ++j) {
            for (int i = 0; i < nlon; ++i) {
                int idx_2d = idx2(i, j, nlon);
                int idx_3d = idx3(i, j, k, nlon, nlat);

                double rps = 1.0 / ps[idx_2d];
                double sigma = p_full[idx_3d] * rps;

                if (sigma <= 1.0 && sigma > sigma_b) {
                    double vfactr = vcoeff * (sigma - sigma_b);
                    udt[idx_3d] = vfactr * u[idx_3d];
                    vdt[idx_3d] = vfactr * v[idx_3d];
                } else {
                    udt[idx_3d] = 0.0;
                    vdt[idx_3d] = 0.0;
                }
            }
        }
    }

    // Apply mask if present
    if (mask != nullptr) {
        int size_3d = nlon * nlat * nlev;
        for (int idx = 0; idx < size_3d; ++idx) {
            udt[idx] *= mask[idx];
            vdt[idx] *= mask[idx];
        }
    }
}

// ----------------------------------------------------------------------------
// newtonian_damping
//
// Compute Newtonian (linear) temperature relaxation toward an equilibrium
// temperature profile. Implements Held-Suarez (1994) Equations 1-2.
//
// Inputs:
//   nlon, nlat, nlev - Grid dimensions
//   lat              - Latitude [radians], array [nlon, nlat]
//   ps               - Surface pressure [Pa], array [nlon, nlat]
//   p_full           - Pressure at full levels [Pa], array [nlon, nlat, nlev]
//   t                - Temperature [K], array [nlon, nlat, nlev]
//   config           - Configuration parameters
//   mask             - Optional mask [nlon, nlat, nlev], nullptr if unused
//
// Outputs:
//   tdt - Temperature tendency [K/s], array [nlon, nlat, nlev]
//   teq - Equilibrium temperature [K], array [nlon, nlat, nlev]
//
// Note: Tendencies are WRITTEN (not accumulated) by this function.
//
// Source: hs_forcing.F90:508-611
// ----------------------------------------------------------------------------
inline void newtonian_damping(
    int nlon, int nlat, int nlev,
    const double* lat,
    const double* ps,
    const double* p_full,
    const double* t,
    const Config& config,
    double* tdt,
    double* teq,
    const double* mask)
{
    const int size_2d = nlon * nlat;

    // Allocate temporaries for latitude terms
    std::vector<double> sin_lat(size_2d);
    std::vector<double> sin_lat_2(size_2d);
    std::vector<double> cos_lat_2(size_2d);
    std::vector<double> cos_lat_4(size_2d);
    std::vector<double> t_star(size_2d);
    std::vector<double> tstr(size_2d);

    // Precompute latitude-dependent terms (2D)
    for (int j = 0; j < nlat; ++j) {
        for (int i = 0; i < nlon; ++i) {
            int idx = idx2(i, j, nlon);
            sin_lat[idx] = std::sin(lat[idx]);
            sin_lat_2[idx] = sin_lat[idx] * sin_lat[idx];
            cos_lat_2[idx] = 1.0 - sin_lat_2[idx];
            cos_lat_4[idx] = cos_lat_2[idx] * cos_lat_2[idx];

            t_star[idx] = config.t_zero - config.delh * sin_lat_2[idx]
                          - config.eps * sin_lat[idx];
            tstr[idx] = config.t_strat - config.eps * sin_lat[idx];
        }
    }

    // Damping coefficient
    double tcoeff = (config.tks - config.tka) / (1.0 - config.sigma_b);

    // Vertical loop
    for (int k = 0; k < nlev; ++k) {
        for (int j = 0; j < nlat; ++j) {
            for (int i = 0; i < nlon; ++i) {
                int idx_2d = idx2(i, j, nlon);
                int idx_3d = idx3(i, j, k, nlon, nlat);

                // Equilibrium temperature
                double p_norm = p_full[idx_3d] / config.P00;
                double the = t_star[idx_2d] - config.delv * cos_lat_2[idx_2d] * std::log(p_norm);
                teq[idx_3d] = std::max(the * std::pow(p_norm, config.kappa), tstr[idx_2d]);

                // Damping coefficient
                double rps = 1.0 / ps[idx_2d];
                double sigma = p_full[idx_3d] * rps;
                double tdamp;

                if (sigma <= 1.0 && sigma > config.sigma_b) {
                    double tfactr = tcoeff * (sigma - config.sigma_b);
                    tdamp = config.tka + cos_lat_4[idx_2d] * tfactr;
                } else {
                    tdamp = config.tka;
                }

                // Temperature tendency
                tdt[idx_3d] = -tdamp * (t[idx_3d] - teq[idx_3d]);
            }
        }
    }

    // Apply mask if present
    if (mask != nullptr) {
        int size_3d = nlon * nlat * nlev;
        for (int idx = 0; idx < size_3d; ++idx) {
            tdt[idx] *= mask[idx];
            teq[idx] *= mask[idx];
        }
    }
}

// ----------------------------------------------------------------------------
// top_down_newtonian_damping
//
// Temperature relaxation with tropopause-aware vertical structure.
// Uses radiative balance to compute tropopause height, applies heat
// capacity for surface temperature evolution.
//
// Inputs:
//   nlon, nlat, nlev - Grid dimensions
//   current_time     - Time in seconds since epoch
//   dt               - Timestep [s]
//   lat              - Latitude [radians], array [nlon, nlat]
//   ps               - Surface pressure [Pa], array [nlon, nlat]
//   p_full           - Pressure at full levels [Pa], array [nlon, nlat, nlev]
//   zfull            - Height at full levels [m], array [nlon, nlat, nlev]
//   t                - Temperature [K], array [nlon, nlat, nlev]
//   tg_prev          - Previous ground temperature [K], array [nlon, nlat]
//   config           - Configuration parameters
//   mask             - Optional mask [nlon, nlat, nlev], nullptr if unused
//
// Outputs:
//   tdt    - Temperature tendency [K/s], array [nlon, nlat, nlev]
//   teq    - Equilibrium temperature [K], array [nlon, nlat, nlev]
//   h_trop - Tropopause height [km], array [nlon, nlat]
//   tg_new - New ground temperature [K], array [nlon, nlat]
//
// Note: tg_new should be saved by caller for next timestep (replaces tg_prev)
//
// Source: hs_forcing.F90:894-1026
// ----------------------------------------------------------------------------
inline void top_down_newtonian_damping(
    int nlon, int nlat, int nlev,
    int current_time,
    double dt,
    const double* lat,
    const double* ps,
    const double* p_full,
    const double* zfull,
    const double* t,
    const double* tg_prev,
    const Config& config,
    double* tdt,
    double* teq,
    double* h_trop,
    double* tg_new,
    const double* mask)
{
    const int size_2d = nlon * nlat;
    const int size_3d = nlon * nlat * nlev;
    const double pi = constants::PI;

    // Allocate temporaries
    std::vector<double> sin_lat(size_2d);
    std::vector<double> cos_lat(size_2d);
    std::vector<double> cos_lat_4(size_2d);
    std::vector<double> hour_angle(size_2d);
    std::vector<double> s(size_2d);
    std::vector<double> t_radbal(size_2d);
    std::vector<double> t_trop(size_2d);
    std::vector<double> t_surf(size_2d);
    std::vector<double> tg(size_2d);
    std::vector<double> tstr(size_2d);
    std::vector<double> tdamp(size_3d);

    // Latitudinal constants
    for (int j = 0; j < nlat; ++j) {
        for (int i = 0; i < nlon; ++i) {
            int idx = idx2(i, j, nlon);
            sin_lat[idx] = std::sin(lat[idx]);
            cos_lat[idx] = std::cos(lat[idx]);
            double sin_lat_2 = sin_lat[idx] * sin_lat[idx];
            double cos_lat_2 = 1.0 - sin_lat_2;
            cos_lat_4[idx] = cos_lat_2 * cos_lat_2;
        }
    }

    // Orbital calculations
    double dec, orb_dist;
    update_orbit(current_time, config.orbital_period, config.ecc,
                 config.obliq, config.peri_time, config.smaxis,
                 dec, orb_dist);

    // Hour angle
    calc_hour_angle(nlon, nlat, lat, dec, hour_angle.data());

    // Solar insolation
    double sin_dec = std::sin(dec);
    double cos_dec = std::cos(dec);
    for (int idx = 0; idx < size_2d; ++idx) {
        s[idx] = config.solar_const / pi *
            (hour_angle[idx] * sin_lat[idx] * sin_dec +
             cos_lat[idx] * cos_dec * std::sin(hour_angle[idx]));
    }

    // Radiative balance temperature
    for (int idx = 0; idx < size_2d; ++idx) {
        double arg = (1.0 - config.albedo) * s[idx] / config.stefan;
        t_radbal[idx] = (arg > 0.0) ? std::pow(arg, 0.25) : 0.0;
    }

    // Tropopause height
    const double two_pow_025 = std::pow(2.0, 0.25);
    for (int idx = 0; idx < size_2d; ++idx) {
        t_trop[idx] = t_radbal[idx] / two_pow_025;
        double tt = t_trop[idx];
        if (tt > 0.0) {
            h_trop[idx] = 1.0 / (16.0 * config.lapse) *
                (1.3863 * tt + std::sqrt(1.3863 * tt * 1.3863 * tt +
                 32.0 * config.lapse * config.tau_s * config.h_a * tt));
        } else {
            h_trop[idx] = 0.0;
        }
    }

    // Surface temperature with heat capacity
    for (int idx = 0; idx < size_2d; ++idx) {
        t_surf[idx] = t_trop[idx] + h_trop[idx] * config.lapse;
        double t_surf_4 = t_surf[idx] * t_surf[idx] * t_surf[idx] * t_surf[idx];
        double tg_prev_4 = tg_prev[idx] * tg_prev[idx] * tg_prev[idx] * tg_prev[idx];
        tg[idx] = config.stefan * dt / (config.ml_depth * config.heat_capacity) *
                  (t_surf_4 - tg_prev_4) + tg_prev[idx];
        tg_new[idx] = tg[idx];
        t_trop[idx] = tg[idx] - h_trop[idx] * config.lapse;
    }

    // Stratosphere temperature
    for (int idx = 0; idx < size_2d; ++idx) {
        tstr[idx] = config.t_strat - config.eps * sin_lat[idx];
    }

    // Damping coefficient setup
    double tcoeff = (config.tks - config.tka) / (1.0 - config.sigma_b);

    // Vertical loop: equilibrium temperature and damping
    for (int k = 0; k < nlev; ++k) {
        for (int j = 0; j < nlat; ++j) {
            for (int i = 0; i < nlon; ++i) {
                int idx_2d = idx2(i, j, nlon);
                int idx_3d = idx3(i, j, k, nlon, nlat);

                // Equilibrium temperature
                teq[idx_3d] = t_trop[idx_2d] +
                    config.lapse * (h_trop[idx_2d] - zfull[idx_3d] / 1000.0);

                // Apply stratosphere option
                if (config.stratosphere_option == STRATOSPHERE_C_ABOVE_TP) {
                    if (zfull[idx_3d] / 1000.0 >= h_trop[idx_2d]) {
                        teq[idx_3d] = tstr[idx_2d];
                    }
                } else if (config.stratosphere_option == STRATOSPHERE_HS_LIKE) {
                    teq[idx_3d] = std::max(teq[idx_3d], tstr[idx_2d]);
                } else if (config.stratosphere_option == STRATOSPHERE_EXTEND_TP) {
                    if (zfull[idx_3d] / 1000.0 >= h_trop[idx_2d]) {
                        teq[idx_3d] = t_trop[idx_2d];
                    }
                } else {
                    teq[idx_3d] = std::max(teq[idx_3d], 0.0);
                }

                // Damping coefficient
                double rps = 1.0 / ps[idx_2d];
                double sigma = p_full[idx_3d] * rps;
                if (sigma <= 1.0 && sigma > config.sigma_b) {
                    double tfactr = tcoeff * (sigma - config.sigma_b);
                    tdamp[idx_3d] = config.tka + cos_lat_4[idx_2d] * tfactr;
                } else {
                    tdamp[idx_3d] = config.tka;
                }
            }
        }
    }

    // Temperature tendency
    for (int idx = 0; idx < size_3d; ++idx) {
        tdt[idx] = -tdamp[idx] * (t[idx] - teq[idx]);
    }

    // Apply mask if present
    if (mask != nullptr) {
        for (int idx = 0; idx < size_3d; ++idx) {
            tdt[idx] *= mask[idx];
            teq[idx] *= mask[idx];
        }
    }
}

// ============================================================================
// Module Driver Function
//
// This function orchestrates the complete Held-Suarez forcing calculation,
// matching the behavior of the Fortran hs_forcing subroutine.
//
// IMPORTANT: Tendency arrays (udt, vdt, tdt) are ACCUMULATED.
//            They must be initialized before calling this function.
// ============================================================================

// ----------------------------------------------------------------------------
// hs_forcing_driver
//
// Main driver function that combines all forcing components.
//
// Inputs:
//   nlon, nlat, nlev - Grid dimensions
//   current_time     - Time in seconds since epoch
//   dt               - Physics timestep [s]
//   lon              - Longitude [radians], array [nlon, nlat] (unused in HS)
//   lat              - Latitude [radians], array [nlon, nlat]
//   ps               - Surface pressure [Pa], array [nlon, nlat]
//   p_full           - Pressure at full levels [Pa], array [nlon, nlat, nlev]
//   p_half           - Pressure at half levels [Pa], array [nlon, nlat, nlev+1]
//                      (for energy conservation; nullptr if !do_conserve_energy)
//   u                - Zonal wind [m/s], array [nlon, nlat, nlev]
//   v                - Meridional wind [m/s], array [nlon, nlat, nlev]
//   t                - Temperature [K], array [nlon, nlat, nlev]
//   um, vm           - Previous timestep winds [m/s], array [nlon, nlat, nlev]
//                      (for energy conservation; nullptr if !do_conserve_energy)
//   zfull            - Height at full levels [m], array [nlon, nlat, nlev]
//                      (for top_down mode; nullptr if Held_Suarez)
//   tg_prev          - Previous ground temperature [K], array [nlon, nlat]
//                      (for top_down mode; nullptr if Held_Suarez)
//   config           - Configuration parameters
//   mask             - Optional mask [nlon, nlat, nlev], nullptr if unused
//
// Outputs (ACCUMULATED, not overwritten):
//   udt    - Zonal wind tendency [m/s^2], array [nlon, nlat, nlev]
//   vdt    - Meridional wind tendency [m/s^2], array [nlon, nlat, nlev]
//   tdt    - Temperature tendency [K/s], array [nlon, nlat, nlev]
//
// Outputs (diagnostic, overwritten):
//   teq    - Equilibrium temperature [K], array [nlon, nlat, nlev]
//   h_trop - Tropopause height [km], array [nlon, nlat]
//            (top_down only; nullptr if Held_Suarez)
//   tg_new - New ground temperature [K], array [nlon, nlat]
//            (top_down only; nullptr if Held_Suarez)
//
// Source: hs_forcing.F90:148-272
// ----------------------------------------------------------------------------
inline void hs_forcing_driver(
    int nlon, int nlat, int nlev,
    int current_time,
    double dt,
    const double* lon,          // unused in standard HS, kept for interface
    const double* lat,
    const double* ps,
    const double* p_full,
    const double* p_half,       // for energy conservation
    const double* u,
    const double* v,
    const double* t,
    const double* um,           // for energy conservation
    const double* vm,           // for energy conservation
    const double* zfull,        // for top_down
    const double* tg_prev,      // for top_down
    const Config& config,
    double* udt,
    double* vdt,
    double* tdt,
    double* teq,
    double* h_trop,             // for top_down
    double* tg_new,             // for top_down
    const double* mask)
{
    (void)lon;  // Suppress unused parameter warning

    const int size_3d = nlon * nlat * nlev;

    // Allocate temporary arrays for internal tendencies
    std::vector<double> utnd(size_3d);
    std::vector<double> vtnd(size_3d);
    std::vector<double> ttnd(size_3d);

    // ========================================================================
    // Step 1: Rayleigh damping of wind components
    // ========================================================================

    rayleigh_damping(
        nlon, nlat, nlev,
        ps, p_full, u, v,
        config.vkf, config.sigma_b,
        utnd.data(), vtnd.data(),
        mask
    );

    // ========================================================================
    // Step 2: Energy conservation (optional)
    //
    // Fortran: ttnd = -((um + 0.5*utnd*dt)*utnd + (vm + 0.5*vtnd*dt)*vtnd) / CP_AIR
    // ========================================================================

    if (config.do_conserve_energy && um != nullptr && vm != nullptr) {
        for (int idx = 0; idx < size_3d; ++idx) {
            double u_avg = um[idx] + 0.5 * utnd[idx] * dt;
            double v_avg = vm[idx] + 0.5 * vtnd[idx] * dt;
            double diss = -(u_avg * utnd[idx] + v_avg * vtnd[idx]) / constants::CP_AIR;
            tdt[idx] += diss;
        }
    }

    // Accumulate wind tendencies
    for (int idx = 0; idx < size_3d; ++idx) {
        udt[idx] += utnd[idx];
        vdt[idx] += vtnd[idx];
    }

    // ========================================================================
    // Step 3: Thermal forcing (branch on equilibrium_option)
    // ========================================================================

    if (config.equilibrium_option == EQUILIBRIUM_TOP_DOWN) {
        // Top-down newtonian damping with tropopause model
        if (zfull == nullptr || tg_prev == nullptr ||
            h_trop == nullptr || tg_new == nullptr) {
            // Error: missing required arrays for top_down mode
            // In a real implementation, would throw or return error code
            return;
        }

        top_down_newtonian_damping(
            nlon, nlat, nlev,
            current_time, dt,
            lat, ps, p_full, zfull, t, tg_prev,
            config,
            ttnd.data(), teq, h_trop, tg_new,
            mask
        );

    } else {
        // Standard Held-Suarez newtonian damping
        newtonian_damping(
            nlon, nlat, nlev,
            lat, ps, p_full, t,
            config,
            ttnd.data(), teq,
            mask
        );
    }

    // Accumulate temperature tendency
    for (int idx = 0; idx < size_3d; ++idx) {
        tdt[idx] += ttnd[idx];
    }
}

} // namespace hs_forcing

#endif // HELD_SUAREZ_FORCING_HPP
