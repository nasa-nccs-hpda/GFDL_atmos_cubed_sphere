#ifndef NEWTONIAN_DAMPING_HPP
#define NEWTONIAN_DAMPING_HPP

//-----------------------------------------------------------------------
// Newtonian Damping Kernel - C++ Translation
//
// Translated from: src/atmos_param/hs_forcing/hs_forcing.F90
// Original routine: newtonian_damping (lines 508-611)
//
// This is a direct translation preserving the original algorithm.
// Array indexing uses Fortran column-major order for validation.
//-----------------------------------------------------------------------

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <vector>

namespace hs_forcing {

//-----------------------------------------------------------------------
// Newtonian damping (thermal relaxation) for Held-Suarez benchmark
//
// Implements Held-Suarez (1994) Equations 1-2:
//   Teq = max(T* - delv*cos^2(lat)*ln(p/P00)) * (p/P00)^kappa, T_strat)
//   dT/dt = -kT * (T - Teq)
//
// where kT varies with latitude and sigma level.
//
// Arguments:
//   nlon, nlat, nlev - Grid dimensions
//   lat      - Latitude (radians)                  [nlon, nlat]
//   ps       - Surface pressure (Pa)              [nlon, nlat]
//   p_full   - Pressure at full levels (Pa)       [nlon, nlat, nlev]
//   t        - Temperature (K)                    [nlon, nlat, nlev]
//
// Held-Suarez parameters:
//   t_zero   - Equatorial equilibrium temperature (K)
//   t_strat  - Stratospheric temperature (K)
//   delh     - Equator-pole temperature difference (K)
//   delv     - Static stability parameter (K)
//   eps      - Hemispheric asymmetry (K)
//   P00      - Reference pressure (Pa)
//   KAPPA    - R/cp (dimensionless)
//   tka      - Atmospheric damping rate (1/s)
//   tks      - Surface damping rate (1/s)
//   sigma_b  - Boundary layer top sigma level
//
// Outputs:
//   tdt      - Temperature tendency (K/s)         [nlon, nlat, nlev]
//   teq      - Equilibrium temperature (K)        [nlon, nlat, nlev]
//   mask     - Optional mask (nullptr if not used) [nlon, nlat, nlev]
//
// Array layout: Fortran column-major order
//   Index as: arr[i + nlon * (j + nlat * k)]
//-----------------------------------------------------------------------

inline void newtonian_damping(
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
    double KAPPA,
    double tka,
    double tks,
    double sigma_b,
    double* tdt,
    double* teq,
    const double* mask = nullptr)
{
    // Allocate temporary 2D arrays for latitude-dependent terms
    // These correspond to Fortran arrays: sin_lat, sin_lat_2, cos_lat_2, cos_lat_4, t_star, tstr
    std::vector<double> sin_lat(nlon * nlat);
    std::vector<double> sin_lat_2(nlon * nlat);
    std::vector<double> cos_lat_2(nlon * nlat);
    std::vector<double> cos_lat_4(nlon * nlat);
    std::vector<double> t_star(nlon * nlat);
    std::vector<double> tstr(nlon * nlat);
    std::vector<double> rps(nlon * nlat);

    // Allocate 3D array for damping coefficient
    std::vector<double> tdamp(nlon * nlat * nlev);

    //-----------------------------------------------------------------------
    // Precompute latitudinal constants (Fortran lines 539-546)
    //-----------------------------------------------------------------------

    for (int j = 0; j < nlat; ++j) {
        for (int i = 0; i < nlon; ++i) {
            int idx_2d = i + nlon * j;

            // Fortran: sin_lat(:,:) = sin(lat(:,:))
            sin_lat[idx_2d] = std::sin(lat[idx_2d]);

            // Fortran: sin_lat_2(:,:) = sin_lat(:,:)*sin_lat(:,:)
            sin_lat_2[idx_2d] = sin_lat[idx_2d] * sin_lat[idx_2d];

            // Fortran: cos_lat_2(:,:) = 1.0-sin_lat_2(:,:)
            cos_lat_2[idx_2d] = 1.0 - sin_lat_2[idx_2d];

            // Fortran: cos_lat_4(:,:) = cos_lat_2(:,:)*cos_lat_2(:,:)
            cos_lat_4[idx_2d] = cos_lat_2[idx_2d] * cos_lat_2[idx_2d];

            // Fortran: t_star(:,:) = t_zero - delh*sin_lat_2(:,:) - eps*sin_lat(:,:)
            t_star[idx_2d] = t_zero - delh * sin_lat_2[idx_2d] - eps * sin_lat[idx_2d];

            // Fortran: tstr(:,:) = t_strat - eps*sin_lat(:,:)
            tstr[idx_2d] = t_strat - eps * sin_lat[idx_2d];

            // Fortran: rps = 1./ps
            rps[idx_2d] = 1.0 / ps[idx_2d];
        }
    }

    //-----------------------------------------------------------------------
    // Compute coefficient (Fortran line 552)
    //-----------------------------------------------------------------------

    // Fortran: tcoeff = (tks-tka)/(1.0-sigma_b)
    double tcoeff = (tks - tka) / (1.0 - sigma_b);

    //-----------------------------------------------------------------------
    // Loop over levels (Fortran lines 556-598)
    //-----------------------------------------------------------------------

    for (int k = 0; k < nlev; ++k) {
        for (int j = 0; j < nlat; ++j) {
            for (int i = 0; i < nlon; ++i) {
                int idx_2d = i + nlon * j;
                int idx_3d = i + nlon * (j + nlat * k);

                //-------------------------------------------------------------
                // Compute equilibrium temperature (Held_Suarez option, lines 566-570)
                //-------------------------------------------------------------

                // Fortran: p_norm(:,:) = p_full(:,:,k)/pref
                double p_norm = p_full[idx_3d] / P00;

                // Fortran: the(:,:) = t_star(:,:) - delv*cos_lat_2(:,:)*log(p_norm(:,:))
                double the = t_star[idx_2d] - delv * cos_lat_2[idx_2d] * std::log(p_norm);

                // Fortran: teq(:,:,k) = the(:,:)*(p_norm(:,:))**KAPPA
                double teq_val = the * std::pow(p_norm, KAPPA);

                // Fortran: teq(:,:,k) = max( teq(:,:,k), tstr(:,:) )
                teq[idx_3d] = std::max(teq_val, tstr[idx_2d]);

                //-------------------------------------------------------------
                // Compute damping coefficient (Fortran lines 590-596)
                //-------------------------------------------------------------

                // Fortran: sigma(:,:) = p_full(:,:,k)*rps(:,:)
                double sigma = p_full[idx_3d] * rps[idx_2d];

                // Fortran: where (sigma(:,:) <= 1.0 .and. sigma(:,:) > sigma_b)
                //            tfactr(:,:) = tcoeff*(sigma(:,:)-sigma_b)
                //            tdamp(:,:,k) = tka + cos_lat_4(:,:)*tfactr(:,:)
                //          elsewhere
                //            tdamp(:,:,k) = tka
                //          endwhere

                if (sigma <= 1.0 && sigma > sigma_b) {
                    double tfactr = tcoeff * (sigma - sigma_b);
                    tdamp[idx_3d] = tka + cos_lat_4[idx_2d] * tfactr;
                } else {
                    tdamp[idx_3d] = tka;
                }
            }
        }
    }

    //-----------------------------------------------------------------------
    // Apply temperature tendency (Fortran lines 600-602)
    //-----------------------------------------------------------------------

    // Fortran: do k=1,size(t,3)
    //            tdt(:,:,k) = -tdamp(:,:,k)*(t(:,:,k)-teq(:,:,k))
    //          enddo

    for (int k = 0; k < nlev; ++k) {
        for (int j = 0; j < nlat; ++j) {
            for (int i = 0; i < nlon; ++i) {
                int idx_3d = i + nlon * (j + nlat * k);
                tdt[idx_3d] = -tdamp[idx_3d] * (t[idx_3d] - teq[idx_3d]);
            }
        }
    }

    //-----------------------------------------------------------------------
    // Apply mask if present (Fortran lines 604-607)
    //-----------------------------------------------------------------------

    // Fortran: if (present(mask)) then
    //            tdt = tdt * mask
    //            teq = teq * mask
    //          endif

    if (mask != nullptr) {
        int total_size = nlon * nlat * nlev;
        for (int idx = 0; idx < total_size; ++idx) {
            tdt[idx] = tdt[idx] * mask[idx];
            teq[idx] = teq[idx] * mask[idx];
        }
    }
}

} // namespace hs_forcing

#endif // NEWTONIAN_DAMPING_HPP
