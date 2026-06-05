// calc_ecc_anomaly.hpp
// C++ translation of calc_ecc_anomaly from hs_forcing_mod
// Original: src/atmos_param/hs_forcing/hs_forcing.F90:864-890

#ifndef CALC_ECC_ANOMALY_HPP
#define CALC_ECC_ANOMALY_HPP

#include <cmath>
#include <iostream>

namespace hs_forcing {

// Result struct with convergence information
// (Enhanced interface compared to original Fortran)
struct EccAnomalyResult {
    double ecc_anomaly;  // Eccentric anomaly E (radians)
    bool converged;      // True if iteration converged within tolerance
    int iterations;      // Number of iterations performed
};

// ----------------------------------------------------------------------------
// calc_ecc_anomaly
//
// Solves Kepler's equation: E - e*sin(E) = M
// Using Newton-Raphson iteration
//
// Inputs:
//   mean_anomaly - Mean anomaly M (radians)
//   ecc          - Orbital eccentricity e (dimensionless, 0 <= e < 1)
//
// Outputs:
//   EccAnomalyResult containing:
//     - ecc_anomaly: Eccentric anomaly E (radians)
//     - converged: whether iteration converged
//     - iterations: number of iterations used
//
// Algorithm mapping to Fortran (hs_forcing.F90:864-890):
//   - maxiter = 30        -> max_iter parameter (default 30)
//   - tol = 1.d-10        -> tol parameter (default 1.0e-10)
//   - Newton-Raphson:     dE = d / (1 - ecc*cos(ecc_anomaly))
//                         ecc_anomaly = ecc_anomaly - dE
// ----------------------------------------------------------------------------
inline EccAnomalyResult calc_ecc_anomaly(
    double mean_anomaly,
    double ecc,
    int max_iter = 30,
    double tol = 1.0e-10)
{
    EccAnomalyResult result;
    result.converged = false;
    result.iterations = 0;

    // Fortran: ecc_anomaly = mean_anomaly
    double ecc_anomaly = mean_anomaly;

    // Fortran: d = ecc_anomaly - ecc*sin(ecc_anomaly) - mean_anomaly
    double d = ecc_anomaly - ecc * std::sin(ecc_anomaly) - mean_anomaly;

    // Fortran: do k=1,maxiter
    for (int k = 1; k <= max_iter; ++k) {
        result.iterations = k;

        // Fortran: dE = d/(1 - ecc*cos(ecc_anomaly))
        double dE = d / (1.0 - ecc * std::cos(ecc_anomaly));

        // Fortran: ecc_anomaly = ecc_anomaly - dE
        ecc_anomaly = ecc_anomaly - dE;

        // Fortran: d = ecc_anomaly - ecc*sin(ecc_anomaly) - mean_anomaly
        d = ecc_anomaly - ecc * std::sin(ecc_anomaly) - mean_anomaly;

        // Fortran: if (abs(d) < tol) then exit endif
        if (std::abs(d) < tol) {
            result.converged = true;
            break;
        }
    }

    // Fortran: if (k > maxiter) then
    //            if (abs(d) > tol) then
    //              print *, '*** Warning: eccentric anomaly has not converged'
    //            endif
    //          endif
    if (!result.converged && std::abs(d) > tol) {
        std::cerr << "*** Warning: eccentric anomaly has not converged" << std::endl;
    }

    result.ecc_anomaly = ecc_anomaly;
    return result;
}

// Simple interface matching Fortran signature exactly
// (for direct comparison testing)
inline void calc_ecc_anomaly_fortran_interface(
    double mean_anomaly,
    double ecc,
    double& ecc_anomaly)
{
    auto result = calc_ecc_anomaly(mean_anomaly, ecc);
    ecc_anomaly = result.ecc_anomaly;
}

} // namespace hs_forcing

#endif // CALC_ECC_ANOMALY_HPP
