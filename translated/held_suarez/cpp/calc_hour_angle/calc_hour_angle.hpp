#ifndef CALC_HOUR_ANGLE_HPP
#define CALC_HOUR_ANGLE_HPP

//-----------------------------------------------------------------------
// Calc Hour Angle Kernel - C++ Translation
//
// Translated from: src/atmos_param/hs_forcing/hs_forcing.F90
// Original routine: calc_hour_angle (lines 842-860)
//
// This is a direct translation preserving the original algorithm.
// Array indexing uses Fortran column-major order for validation.
//-----------------------------------------------------------------------

#include <algorithm>  // for std::min, std::max
#include <cmath>      // for std::tan, std::acos
#include <cstddef>    // for size_t

namespace hs_forcing {

//-----------------------------------------------------------------------
// calc_hour_angle
//
// Compute solar hour angle from latitude and solar declination.
//
// The hour angle H satisfies: cos(H) = -tan(lat) * tan(dec)
// The argument is clamped to [-1, 1] for polar night/day cases:
//   - cos(H) > 1  => polar night (H = 0)
//   - cos(H) < -1 => polar day   (H = π)
//
// Arguments:
//   nlon, nlat  - Grid dimensions
//   lat         - Latitude (radians)              [nlon, nlat]
//   dec         - Solar declination (radians)     scalar
//   hour_angle  - Output hour angle (radians)     [nlon, nlat]
//
// Array layout: Fortran column-major order
//   Index as: arr[i + nlon * j]
//-----------------------------------------------------------------------

inline void calc_hour_angle(
    int nlon,
    int nlat,
    const double* lat,
    double dec,
    double* hour_angle)
{
    // Fortran: tan(dec) is scalar, computed once
    double tan_dec = std::tan(dec);

    // Loop over lat/lon (corresponds to Fortran array operations)
    // Fortran: inv_hour_angle = -tan(lat(:,:))*tan(dec)
    for (int j = 0; j < nlat; ++j) {
        for (int i = 0; i < nlon; ++i) {

            // Fortran column-major index: (i,j)
            int idx = i + nlon * j;

            // Fortran: inv_hour_angle = -tan(lat(:,:))*tan(dec)
            double inv_hour_angle = -std::tan(lat[idx]) * tan_dec;

            // Fortran: where (inv_hour_angle > 1)
            //            inv_hour_angle = 1
            //          endwhere
            //          where (inv_hour_angle < -1)
            //            inv_hour_angle = -1
            //          endwhere
            inv_hour_angle = std::max(-1.0, std::min(1.0, inv_hour_angle));

            // Fortran: hour_angle = acos(inv_hour_angle)
            hour_angle[idx] = std::acos(inv_hour_angle);
        }
    }
}

} // namespace hs_forcing

#endif // CALC_HOUR_ANGLE_HPP
