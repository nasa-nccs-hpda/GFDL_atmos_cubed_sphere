#ifndef RAYLEIGH_DAMPING_HPP
#define RAYLEIGH_DAMPING_HPP

//-----------------------------------------------------------------------
// Rayleigh Damping Kernel - C++ Translation
//
// Translated from: src/atmos_param/hs_forcing/hs_forcing.F90
// Original routine: rayleigh_damping (lines 615-679)
//
// This is a direct translation preserving the original algorithm.
// Array indexing uses Fortran column-major order for validation.
//-----------------------------------------------------------------------

#include <cmath>
#include <cstddef>

namespace hs_forcing {

//-----------------------------------------------------------------------
// Rayleigh damping of wind components near the surface
//
// Standard Held-Suarez (1994) formulation:
//   kv(sigma) = kf * max(0, (sigma - sigma_b) / (1 - sigma_b))
//   du/dt = -kv * u
//   dv/dt = -kv * v
//
// Arguments:
//   nlon, nlat, nlev - Grid dimensions
//   ps       - Surface pressure (Pa)              [nlon, nlat]
//   p_full   - Pressure at full levels (Pa)       [nlon, nlat, nlev]
//   u        - Zonal wind (m/s)                   [nlon, nlat, nlev]
//   v        - Meridional wind (m/s)              [nlon, nlat, nlev]
//   vkf      - Friction coefficient (1/s)
//   sigma_b  - Boundary layer top sigma level
//   udt      - Zonal wind tendency (m/s^2)        [nlon, nlat, nlev]
//   vdt      - Meridional wind tendency (m/s^2)   [nlon, nlat, nlev]
//   mask     - Optional mask (nullptr if not used) [nlon, nlat, nlev]
//
// Array layout: Fortran column-major order
//   Index as: arr[i + nlon * (j + nlat * k)]
//-----------------------------------------------------------------------

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
    const double* mask = nullptr)
{
    // Fortran: vcoeff = -vkf/(1.0-sigma_b)
    double vcoeff = -vkf / (1.0 - sigma_b);

    // Loop over levels (outer loop in Fortran)
    // Fortran: do k = 1, size(u,3)
    for (int k = 0; k < nlev; ++k) {

        // Loop over lat/lon (corresponds to Fortran array operations)
        for (int j = 0; j < nlat; ++j) {
            for (int i = 0; i < nlon; ++i) {

                // Fortran column-major index: (i,j) for 2D, (i,j,k) for 3D
                int idx_2d = i + nlon * j;
                int idx_3d = i + nlon * (j + nlat * k);

                // Fortran: rps = 1./ps
                double rps = 1.0 / ps[idx_2d];

                // Fortran: sigma(:,:) = p_full(:,:,k)*rps(:,:)
                double sigma = p_full[idx_3d] * rps;

                // Fortran: where (sigma(:,:) <= 1.0 .and. sigma(:,:) > sigma_b)
                //            vfactr(:,:) = vcoeff*(sigma(:,:)-sigma_b)
                //            udt(:,:,k)  = vfactr(:,:)*u(:,:,k)
                //            vdt(:,:,k)  = vfactr(:,:)*v(:,:,k)
                //          elsewhere
                //            udt(:,:,k) = 0.0
                //            vdt(:,:,k) = 0.0
                //          endwhere

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

    // Fortran: if (present(mask)) then
    //            udt = udt * mask
    //            vdt = vdt * mask
    //          endif
    if (mask != nullptr) {
        int total_size = nlon * nlat * nlev;
        for (int idx = 0; idx < total_size; ++idx) {
            udt[idx] = udt[idx] * mask[idx];
            vdt[idx] = vdt[idx] * mask[idx];
        }
    }
}

} // namespace hs_forcing

#endif // RAYLEIGH_DAMPING_HPP
