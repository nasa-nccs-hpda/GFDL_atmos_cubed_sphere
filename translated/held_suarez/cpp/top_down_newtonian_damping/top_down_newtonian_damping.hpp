#ifndef TOP_DOWN_NEWTONIAN_DAMPING_HPP
#define TOP_DOWN_NEWTONIAN_DAMPING_HPP

//-----------------------------------------------------------------------
// Top-Down Newtonian Damping Kernel - C++ Translation
//
// Translated from: src/atmos_param/hs_forcing/hs_forcing.F90
// Original routine: top_down_newtonian_damping (lines 894-1026)
//
// This is a direct translation preserving the original algorithm.
// Array indexing uses Fortran column-major order for validation.
//
// Includes embedded translations of:
//   - calc_ecc_anomaly
//   - update_orbit
//   - calc_hour_angle
//-----------------------------------------------------------------------

#include <algorithm>  // for std::max, std::min
#include <cmath>      // for std::sin, std::cos, std::tan, std::acos, std::asin, std::atan, std::sqrt, std::log, std::pow, std::abs
#include <cstddef>    // for size_t
#include <vector>     // for std::vector

namespace hs_forcing {

//-----------------------------------------------------------------------
// Stratosphere temperature option enumeration
//-----------------------------------------------------------------------
enum StratosphereOption {
    STRAT_DEFAULT = 0,
    STRAT_C_ABOVE_TP = 1,
    STRAT_HS_LIKE = 2,
    STRAT_EXTEND_TP = 3
};

//-----------------------------------------------------------------------
// Parameters struct for top_down_newtonian_damping
//-----------------------------------------------------------------------
struct TopDownParams {
    // Physical constants
    double solar_const;
    double stefan;
    double pi;

    // Orbital parameters
    double orbital_period;  // days
    double ecc;             // eccentricity
    double obliq;           // obliquity (degrees)
    double peri_time;       // perihelion time fraction
    double smaxis;          // semi-major axis

    // Thermal parameters
    double albedo;
    double lapse;           // K/km
    double h_a;
    double tau_s;
    double heat_capacity;
    double ml_depth;

    // Held-Suarez parameters
    double t_strat;
    double eps;
    double sigma_b;
    double tka;             // 1/s
    double tks;             // 1/s
    double P00;

    // Stratosphere option
    int strat_option;
};

//-----------------------------------------------------------------------
// calc_ecc_anomaly (internal helper)
//
// Newton-Raphson solver for Kepler's equation: E - e*sin(E) = M
//-----------------------------------------------------------------------
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
            break;
        }
    }
}

//-----------------------------------------------------------------------
// update_orbit (internal helper)
//
// Compute solar declination and orbital distance from current time
//-----------------------------------------------------------------------
inline void update_orbit(
    int current_time,
    double orbital_period,
    double ecc,
    double obliq,
    double peri_time,
    double smaxis,
    double pi,
    double& dec,
    double& orb_dist)
{
    double mean_anomaly = 2.0 * pi / (orbital_period * 86400.0) *
                          (static_cast<double>(current_time) - peri_time * orbital_period * 86400.0);

    double ecc_anomaly;
    calc_ecc_anomaly(mean_anomaly, ecc, ecc_anomaly);

    double true_anomaly = 2.0 * std::atan(std::sqrt((1.0 + ecc) / (1.0 - ecc)) * std::tan(ecc_anomaly / 2.0));
    orb_dist = smaxis * (1.0 - ecc * ecc) / (1.0 + ecc * std::cos(true_anomaly));

    double theta = 2.0 * pi * static_cast<double>(current_time) / (orbital_period * 86400.0);
    dec = std::asin(std::sin(obliq * pi / 180.0) * std::sin(theta));
}

//-----------------------------------------------------------------------
// calc_hour_angle (internal helper)
//
// Compute solar hour angle from latitude and solar declination
//-----------------------------------------------------------------------
inline void calc_hour_angle_2d(
    int nlon, int nlat,
    const double* lat,
    double dec,
    double* hour_angle)
{
    double tan_dec = std::tan(dec);

    for (int j = 0; j < nlat; ++j) {
        for (int i = 0; i < nlon; ++i) {
            int idx = i + nlon * j;

            double inv_hour_angle = -std::tan(lat[idx]) * tan_dec;
            inv_hour_angle = std::max(-1.0, std::min(1.0, inv_hour_angle));
            hour_angle[idx] = std::acos(inv_hour_angle);
        }
    }
}

//-----------------------------------------------------------------------
// top_down_newtonian_damping
//
// Temperature relaxation with tropopause-aware vertical structure
//
// Arguments:
//   nlon, nlat, nlev - Grid dimensions
//   current_time     - Time in seconds since epoch
//   dt               - Timestep (seconds)
//   lat              - Latitude (radians)                [nlon, nlat]
//   ps               - Surface pressure (Pa)             [nlon, nlat]
//   p_full           - Pressure at full levels (Pa)      [nlon, nlat, nlev]
//   zfull            - Height at full levels (m)         [nlon, nlat, nlev]
//   t                - Temperature (K)                   [nlon, nlat, nlev]
//   tg_prev          - Previous ground temperature (K)   [nlon, nlat]
//   params           - Physical parameters struct
//   tdt              - Temperature tendency (K/s)        [nlon, nlat, nlev]
//   teq              - Equilibrium temperature (K)       [nlon, nlat, nlev]
//   h_trop           - Tropopause height (km)            [nlon, nlat]
//   tg_new           - New ground temperature (K)        [nlon, nlat]
//   mask             - Optional mask                     [nlon, nlat, nlev]
//
// Array layout: Fortran column-major order
//   2D index: arr[i + nlon * j]
//   3D index: arr[i + nlon * (j + nlat * k)]
//-----------------------------------------------------------------------
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
    const TopDownParams& params,
    double* tdt,
    double* teq,
    double* h_trop,
    double* tg_new,
    const double* mask = nullptr)
{
    const int size_2d = nlon * nlat;
    const int size_3d = nlon * nlat * nlev;

    // Allocate temporary arrays
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
    std::vector<double> rps(size_2d);
    std::vector<double> tdamp(size_3d);

    //-------------------------------------------------------------------
    // Latitudinal constants
    //-------------------------------------------------------------------
    for (int j = 0; j < nlat; ++j) {
        for (int i = 0; i < nlon; ++i) {
            int idx = i + nlon * j;
            sin_lat[idx] = std::sin(lat[idx]);
            cos_lat[idx] = std::cos(lat[idx]);
            double sin_lat_2 = sin_lat[idx] * sin_lat[idx];
            double cos_lat_2 = 1.0 - sin_lat_2;
            cos_lat_4[idx] = cos_lat_2 * cos_lat_2;
        }
    }

    //-------------------------------------------------------------------
    // Orbital calculations
    //-------------------------------------------------------------------
    double dec, orb_dist;
    update_orbit(current_time, params.orbital_period, params.ecc, params.obliq,
                 params.peri_time, params.smaxis, params.pi, dec, orb_dist);

    calc_hour_angle_2d(nlon, nlat, lat, dec, hour_angle.data());

    //-------------------------------------------------------------------
    // Solar insolation
    //-------------------------------------------------------------------
    double sin_dec = std::sin(dec);
    double cos_dec = std::cos(dec);
    for (int j = 0; j < nlat; ++j) {
        for (int i = 0; i < nlon; ++i) {
            int idx = i + nlon * j;
            s[idx] = params.solar_const / params.pi *
                     (hour_angle[idx] * sin_lat[idx] * sin_dec +
                      cos_lat[idx] * cos_dec * std::sin(hour_angle[idx]));
        }
    }

    //-------------------------------------------------------------------
    // Radiative balance temperature
    //-------------------------------------------------------------------
    for (int idx = 0; idx < size_2d; ++idx) {
        t_radbal[idx] = std::pow((1.0 - params.albedo) * s[idx] / params.stefan, 0.25);
    }

    //-------------------------------------------------------------------
    // Tropopause height
    //-------------------------------------------------------------------
    const double two_pow_025 = std::pow(2.0, 0.25);
    for (int idx = 0; idx < size_2d; ++idx) {
        t_trop[idx] = t_radbal[idx] / two_pow_025;
        double tt = t_trop[idx];
        h_trop[idx] = 1.0 / (16.0 * params.lapse) *
                      (1.3863 * tt +
                       std::sqrt(1.3863 * tt * 1.3863 * tt +
                                 32.0 * params.lapse * params.tau_s * params.h_a * tt));
    }

    //-------------------------------------------------------------------
    // Surface temperature with heat capacity
    //-------------------------------------------------------------------
    for (int idx = 0; idx < size_2d; ++idx) {
        t_surf[idx] = t_trop[idx] + h_trop[idx] * params.lapse;
        double t_surf_4 = t_surf[idx] * t_surf[idx] * t_surf[idx] * t_surf[idx];
        double tg_prev_4 = tg_prev[idx] * tg_prev[idx] * tg_prev[idx] * tg_prev[idx];
        tg[idx] = params.stefan * dt / (params.ml_depth * params.heat_capacity) *
                  (t_surf_4 - tg_prev_4) + tg_prev[idx];
        tg_new[idx] = tg[idx];
        t_trop[idx] = tg[idx] - h_trop[idx] * params.lapse;
    }

    //-------------------------------------------------------------------
    // Stratosphere temperature
    //-------------------------------------------------------------------
    for (int idx = 0; idx < size_2d; ++idx) {
        tstr[idx] = params.t_strat - params.eps * sin_lat[idx];
    }

    //-------------------------------------------------------------------
    // Damping coefficient setup
    //-------------------------------------------------------------------
    double tcoeff = (params.tks - params.tka) / (1.0 - params.sigma_b);
    for (int idx = 0; idx < size_2d; ++idx) {
        rps[idx] = 1.0 / ps[idx];
    }

    //-------------------------------------------------------------------
    // Vertical loop: equilibrium temperature and damping
    //-------------------------------------------------------------------
    for (int k = 0; k < nlev; ++k) {
        for (int j = 0; j < nlat; ++j) {
            for (int i = 0; i < nlon; ++i) {
                int idx_2d = i + nlon * j;
                int idx_3d = i + nlon * (j + nlat * k);

                // Equilibrium temperature
                teq[idx_3d] = t_trop[idx_2d] + params.lapse * (h_trop[idx_2d] - zfull[idx_3d] / 1000.0);

                // Apply stratosphere option
                if (params.strat_option == STRAT_C_ABOVE_TP) {
                    if (zfull[idx_3d] / 1000.0 >= h_trop[idx_2d]) {
                        teq[idx_3d] = tstr[idx_2d];
                    }
                } else if (params.strat_option == STRAT_HS_LIKE) {
                    teq[idx_3d] = std::max(teq[idx_3d], tstr[idx_2d]);
                } else if (params.strat_option == STRAT_EXTEND_TP) {
                    if (zfull[idx_3d] / 1000.0 >= h_trop[idx_2d]) {
                        teq[idx_3d] = t_trop[idx_2d];
                    }
                } else {
                    teq[idx_3d] = std::max(teq[idx_3d], 0.0);
                }

                // Damping coefficient
                double sigma = p_full[idx_3d] * rps[idx_2d];
                if (sigma <= 1.0 && sigma > params.sigma_b) {
                    double tfactr = tcoeff * (sigma - params.sigma_b);
                    tdamp[idx_3d] = params.tka + cos_lat_4[idx_2d] * tfactr;
                } else {
                    tdamp[idx_3d] = params.tka;
                }
            }
        }
    }

    //-------------------------------------------------------------------
    // Temperature tendency
    //-------------------------------------------------------------------
    for (int k = 0; k < nlev; ++k) {
        for (int j = 0; j < nlat; ++j) {
            for (int i = 0; i < nlon; ++i) {
                int idx_3d = i + nlon * (j + nlat * k);
                tdt[idx_3d] = -tdamp[idx_3d] * (t[idx_3d] - teq[idx_3d]);
            }
        }
    }

    //-------------------------------------------------------------------
    // Apply mask if present
    //-------------------------------------------------------------------
    if (mask != nullptr) {
        for (int idx = 0; idx < size_3d; ++idx) {
            tdt[idx] = tdt[idx] * mask[idx];
            teq[idx] = teq[idx] * mask[idx];
        }
    }
}

} // namespace hs_forcing

#endif // TOP_DOWN_NEWTONIAN_DAMPING_HPP
