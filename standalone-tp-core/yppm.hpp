// yppm.hpp — C++ port of the yppm subroutine from tp_core.F90
//
// Design goals:
//   - Header-only: suitable for later annotation as __host__ __device__
//   - No heap allocation: all scratch lives in caller-supplied ScratchYPPM
//   - Template on Real (float/double) for future GPU float usage
//   - No STL containers inside function bodies
//
// Usage (single column, as in tests):
//   ScratchYPPM<float, 20> scratch;
//   yppm_col<float,20>(flux_col, q_col, cry_col, jord, js, je, jsd, jed,
//                      npx, npy, dya_col, nested, grid_type, lim_fac, scratch);
//
// Usage (multi-column wrapper, matching Fortran yppm signature):
//   yppm<float,20>(flux, q, cry, jord, ifirst, ilast, isd, ied, js, je,
//                  jsd, jed, npx, npy, dya, nested, grid_type, lim_fac, scratch);
//
// Note for GPU porting:
//   Replace std::abs/std::copysign with fabsf/copysignf (or __device__ equivalents).
//   Replace std::min/std::max with explicit ternary expressions.
//   Annotate pert_ppm, yppm_col with __host__ __device__.
//   Provide scratch from shared memory instead of the stack.
#pragma once
#include <cmath>

namespace fv3 {

// ---------------------------------------------------------------------------
// Module-level constants (from tp_core_mod, lines 61-98)
// ---------------------------------------------------------------------------
namespace detail {

template <typename Real>
struct Const {
    static constexpr Real p1       = Real(7.0  / 12.0);
    static constexpr Real p2       = Real(-1.0 / 12.0);
    static constexpr Real r3       = Real(1.0  /  3.0);
    static constexpr Real near_zero = Real(1.e-25);
    static constexpr Real r12      = Real(1.0  / 12.0);
    static constexpr Real ppm_fac  = Real(3.0  /  2.0);
    static constexpr Real s11      = Real(11.0 / 14.0);
    static constexpr Real s14      = Real(4.0  /  7.0);
    static constexpr Real s15      = Real(3.0  / 14.0);
    static constexpr Real c1       = Real(-2.0 / 14.0);
    static constexpr Real c2       = Real(11.0 / 14.0);
    static constexpr Real c3       = Real(5.0  / 14.0);
};

template <typename Real>
inline Real fmin3(Real a, Real b, Real c) {
    Real ab = a < b ? a : b;
    return ab < c ? ab : c;
}

template <typename Real>
inline Real fmax3(Real a, Real b, Real c) {
    Real ab = a > b ? a : b;
    return ab > c ? ab : c;
}

template <typename Real>
inline Real fmin4(Real a, Real b, Real c, Real d) {
    return fmin3(a < b ? a : b, c, d);
}

template <typename Real>
inline Real fmax4(Real a, Real b, Real c, Real d) {
    return fmax3(a > b ? a : b, c, d);
}

} // namespace detail

// ---------------------------------------------------------------------------
// Scratch memory for one y-column of yppm.
// NMAX must satisfy NMAX >= (je - js + 1).
// Array sizes have a small margin beyond the theoretical minimum.
// ---------------------------------------------------------------------------
template <typename Real, int NMAX>
struct ScratchYPPM {
    Real dm   [NMAX + 6];   // j in [js-2, je+2], needs NMAX+4
    Real al   [NMAX + 6];   // j in [js-1, je+2], needs NMAX+3
    Real bl   [NMAX + 5];   // j in [js-1, je+1], needs NMAX+2
    Real br   [NMAX + 5];
    Real b0   [NMAX + 5];
    Real dq   [NMAX + 8];   // j in [js-3, je+2], needs NMAX+5
    bool smt5 [NMAX + 5];   // j in [js-1, je+1], needs NMAX+2
    bool smt6 [NMAX + 5];
};

// ---------------------------------------------------------------------------
// pert_ppm: optimized PPM limiter on a 1-D array of length im.
//   iv=0: positive-definite constraint
//   iv=1: standard PPM monotone constraint
//
// Arrays are 0-indexed: a0[0..im-1], al[0..im-1], ar[0..im-1].
// This matches calling with offset pointers into the scratch j-arrays.
// ---------------------------------------------------------------------------
template <typename Real>
void pert_ppm(int im, const Real* a0, Real* al, Real* ar, int iv)
{
    using C = detail::Const<Real>;

    if (iv == 0) {
        // Positive-definite constraint
        for (int i = 0; i < im; ++i) {
            if (a0[i] <= Real(0)) {
                al[i] = Real(0);
                ar[i] = Real(0);
            } else {
                const Real a4  = -Real(3) * (ar[i] + al[i]);
                const Real da1 = ar[i] - al[i];
                if (std::abs(da1) < -a4) {
                    const Real fmin = a0[i] + Real(0.25)/a4 * da1*da1 + a4*C::r12;
                    if (fmin < Real(0)) {
                        if (ar[i] > Real(0) && al[i] > Real(0)) {
                            ar[i] = Real(0);
                            al[i] = Real(0);
                        } else if (da1 > Real(0)) {
                            ar[i] = -Real(2) * al[i];
                        } else {
                            al[i] = -Real(2) * ar[i];
                        }
                    }
                }
            }
        }
    } else {
        // Standard PPM monotone constraint
        for (int i = 0; i < im; ++i) {
            if (al[i] * ar[i] < Real(0)) {
                const Real da1  = al[i] - ar[i];
                const Real da2  = da1 * da1;
                const Real a6da = Real(3) * (al[i] + ar[i]) * da1;
                if      (a6da < -da2) ar[i] = -Real(2) * al[i];
                else if (a6da >  da2) al[i] = -Real(2) * ar[i];
            } else {
                al[i] = Real(0);
                ar[i] = Real(0);
            }
        }
    }
}

// ---------------------------------------------------------------------------
// yppm_col: Y-direction PPM flux for a single x-column.
//
// Array arguments are 0-indexed from their lower Fortran bounds:
//   flux_col[j - js],  j in [js, je+1]          (output)
//   q_col[j - jsd],    j in [jsd, jed]           (input)
//   cry_col[j - js],   j in [js, je+1]           (Courant number, input)
//   dya_col[j - jsd],  j in [jsd, jed]           (grid spacing, input)
//
// NMAX must satisfy NMAX >= (je - js + 1).
// ---------------------------------------------------------------------------
template <typename Real, int NMAX>
void yppm_col(
    Real*       flux_col,
    const Real* q_col,
    const Real* cry_col,
    int jord,
    int js, int je,
    int jsd, int jed,
    int npx, int npy,
    const Real* dya_col,
    bool nested,
    int grid_type,
    Real lim_fac,
    ScratchYPPM<Real, NMAX>& s)
{
    using C = detail::Const<Real>;

    // Build offset pointers so that arr[j] corresponds to Fortran arr(j).
    Real*       flux = flux_col - js;
    const Real* q    = q_col    - jsd;
    const Real* cry  = cry_col  - js;
    const Real* dya  = dya_col  - jsd;

    Real* dm   = s.dm   - (js - 2);
    Real* al_s = s.al   - (js - 1);
    Real* bl   = s.bl   - (js - 1);
    Real* br   = s.br   - (js - 1);
    Real* b0   = s.b0   - (js - 1);
    Real* dq   = s.dq   - (js - 3);
    bool* smt5 = s.smt5 - (js - 1);
    bool* smt6 = s.smt6 - (js - 1);

    // Single-column temporaries (Fortran's dimension(ifirst:ilast) arrays
    // collapse to scalars when ifirst==ilast).
    Real fx1, xt1, a4_val;
    bool hi5, hi6;

    // Compute stencil loop bounds (Fortran lines 735-743)
    int js1, je3, je1;
    if (!nested && grid_type < 3) {
        js1 = (js - 1) > 3 ? (js - 1) : 3;           // max(3, js-1)
        je3 = (npy - 2) < (je + 2) ? (npy - 2) : (je + 2); // min(npy-2, je+2)
        je1 = (npy - 3) < (je + 1) ? (npy - 3) : (je + 1); // min(npy-3, je+1)
    } else {
        js1 = js - 1;
        je3 = je + 2;
        je1 = je + 1;
    }

    const int mord = jord >= 0 ? jord : -jord;

    // =========================================================================
    if (jord < 7) {
    // =========================================================================
    // Low-order schemes (|jord| = 1..6)
    // =========================================================================

        // Compute interior edge values al_s (Fortran lines 749-753)
        for (int j = js1; j <= je3; ++j)
            al_s[j] = C::p1*(q[j-1] + q[j]) + C::p2*(q[j-2] + q[j+1]);

        // Cubed-sphere boundary fixups for al_s (Fortran lines 755-772)
        if (!nested && grid_type < 3) {
            if (js == 1) {
                al_s[0] = C::c1*q[-2] + C::c2*q[-1] + C::c3*q[0];
                al_s[1] = Real(0.5) * (
                    ((Real(2)*dya[0] + dya[-1])*q[0]  - dya[0]*q[-1])  / (dya[-1] + dya[0])
                  + ((Real(2)*dya[1] + dya[ 2])*q[1]  - dya[1]*q[ 2])  / (dya[ 1] + dya[2]));
                al_s[2] = C::c3*q[1] + C::c2*q[2] + C::c1*q[3];
            }
            if ((je + 1) == npy) {
                al_s[npy-1] = C::c1*q[npy-3] + C::c2*q[npy-2] + C::c3*q[npy-1];
                al_s[npy]   = Real(0.5) * (
                    ((Real(2)*dya[npy-1] + dya[npy-2])*q[npy-1] - dya[npy-1]*q[npy-2]) / (dya[npy-2] + dya[npy-1])
                  + ((Real(2)*dya[npy  ] + dya[npy+1])*q[npy  ] - dya[npy  ]*q[npy+1]) / (dya[npy  ] + dya[npy+1]));
                al_s[npy+1] = C::c3*q[npy] + C::c2*q[npy+1] + C::c1*q[npy+2];
            }
        }

        // Clamp al_s >= 0 for negative jord (positive-definite, Fortran lines 774-780)
        if (jord < 0) {
            for (int j = js - 1; j <= je + 2; ++j)
                if (al_s[j] < Real(0)) al_s[j] = Real(0);
        }

        // Dispatch on mord (Fortran lines 782-969)
        if (mord == 1) {
            for (int j = js - 1; j <= je + 1; ++j) {
                bl[j]   = al_s[j]   - q[j];
                br[j]   = al_s[j+1] - q[j];
                b0[j]   = bl[j] + br[j];
                smt5[j] = std::abs(lim_fac * b0[j]) < std::abs(bl[j] - br[j]);
            }
            for (int j = js; j <= je + 1; ++j) {
                if (cry[j] > Real(0)) {
                    fx1 = (Real(1) - cry[j]) * (br[j-1] - cry[j] * b0[j-1]);
                    flux[j] = q[j-1];
                } else {
                    fx1 = (Real(1) + cry[j]) * (bl[j] + cry[j] * b0[j]);
                    flux[j] = q[j];
                }
                if (smt5[j-1] || smt5[j]) flux[j] += fx1;
            }

        } else if (mord == 2) {
            // Perfectly linear scheme (Fortran lines 805-820)
            for (int j = js; j <= je + 1; ++j) {
                const Real xt = cry[j];
                Real qtmp;
                if (xt > Real(0)) {
                    qtmp    = q[j-1];
                    flux[j] = qtmp + (Real(1) - xt) * (al_s[j] - qtmp - xt*(al_s[j-1] + al_s[j] - Real(2)*qtmp));
                } else {
                    qtmp    = q[j];
                    flux[j] = qtmp + (Real(1) + xt) * (al_s[j] - qtmp + xt*(al_s[j] + al_s[j+1] - Real(2)*qtmp));
                }
            }

        } else if (mord == 3) {
            for (int j = js - 1; j <= je + 1; ++j) {
                bl[j] = al_s[j]   - q[j];
                br[j] = al_s[j+1] - q[j];
                b0[j] = bl[j] + br[j];
                const Real x0 = std::abs(b0[j]);
                const Real xt = std::abs(bl[j] - br[j]);
                smt5[j] =         x0 < xt;
                smt6[j] = Real(3)*x0 < xt;
            }
            for (int j = js; j <= je + 1; ++j) {
                xt1 = cry[j];
                if (xt1 > Real(0)) {
                    if (smt5[j-1] || smt6[j])
                        flux[j] = q[j-1] + (Real(1) - xt1) * (br[j-1] - xt1 * b0[j-1]);
                    else
                        flux[j] = q[j-1];
                } else {
                    if (smt6[j-1] || smt5[j])
                        flux[j] = q[j] + (Real(1) + xt1) * (bl[j] + xt1 * b0[j]);
                    else
                        flux[j] = q[j];
                }
            }

        } else if (mord == 4) {
            for (int j = js - 1; j <= je + 1; ++j) {
                bl[j] = al_s[j]   - q[j];
                br[j] = al_s[j+1] - q[j];
                b0[j] = bl[j] + br[j];
                const Real x0 = std::abs(b0[j]);
                const Real xt = std::abs(bl[j] - br[j]);
                smt5[j] =         x0 < xt;
                smt6[j] = Real(3)*x0 < xt;
            }
            for (int j = js; j <= je + 1; ++j) {
                xt1 = cry[j];
                hi5 = smt5[j-1] && smt5[j];
                hi6 = smt6[j-1] || smt6[j];
                hi5 = hi5 || hi6;
                if (xt1 > Real(0)) {
                    fx1 = (Real(1) - xt1) * (br[j-1] - xt1 * b0[j-1]);
                    flux[j] = q[j-1];
                } else {
                    fx1 = (Real(1) + xt1) * (bl[j] + xt1 * b0[j]);
                    flux[j] = q[j];
                }
                if (hi5) flux[j] += fx1;
            }

        } else {
            // mord == 5 or 6
            if (jord == 5) {
                for (int j = js - 1; j <= je + 1; ++j) {
                    bl[j]   = al_s[j]   - q[j];
                    br[j]   = al_s[j+1] - q[j];
                    b0[j]   = bl[j] + br[j];
                    smt5[j] = bl[j] * br[j] < Real(0);
                }
            } else if (jord == -5) {
                for (int j = js - 1; j <= je + 1; ++j) {
                    bl[j]   = al_s[j]   - q[j];
                    br[j]   = al_s[j+1] - q[j];
                    b0[j]   = bl[j] + br[j];
                    xt1     = br[j] - bl[j];
                    a4_val  = -Real(3) * b0[j];
                    smt5[j] = bl[j] * br[j] < Real(0);
                    if (std::abs(xt1) < -a4_val) {
                        if (q[j] + Real(0.25)/a4_val * xt1*xt1 + a4_val*C::r12 < Real(0)) {
                            if (!smt5[j]) {
                                br[j] = Real(0); bl[j] = Real(0); b0[j] = Real(0);
                            } else if (xt1 > Real(0)) {
                                br[j] = -Real(2) * bl[j]; b0[j] = -bl[j];
                            } else {
                                bl[j] = -Real(2) * br[j]; b0[j] = -br[j];
                            }
                        }
                    }
                }
            } else {
                // jord == 6 or jord == -6
                for (int j = js - 1; j <= je + 1; ++j) {
                    bl[j]   = al_s[j]   - q[j];
                    br[j]   = al_s[j+1] - q[j];
                    b0[j]   = bl[j] + br[j];
                    smt5[j] = Real(3)*std::abs(b0[j]) < std::abs(bl[j] - br[j]);
                }
                // WMP edge fix (Fortran lines 938-951)
                if (!nested && grid_type < 3) {
                    if (js == 1) {
                        smt5[0] = bl[0] * br[0] < Real(0);
                        smt5[1] = bl[1] * br[1] < Real(0);
                    }
                    if ((je + 1) == npy) {
                        smt5[npy-1] = bl[npy-1] * br[npy-1] < Real(0);
                        smt5[npy  ] = bl[npy  ] * br[npy  ] < Real(0);
                    }
                }
            }

            // Common flux loop for mord 5/6 (Fortran lines 955-967)
            for (int j = js; j <= je + 1; ++j) {
                if (cry[j] > Real(0)) {
                    fx1 = (Real(1) - cry[j]) * (br[j-1] - cry[j] * b0[j-1]);
                    flux[j] = q[j-1];
                } else {
                    fx1 = (Real(1) + cry[j]) * (bl[j] + cry[j] * b0[j]);
                    flux[j] = q[j];
                }
                if (smt5[j-1] || smt5[j]) flux[j] += fx1;
            }
        }
        return; // jord < 7: done
    }

    // =========================================================================
    // jord >= 7: Monotonic PPM (Fortran lines 972-1145)
    // =========================================================================

    // Compute limited slopes dm (Fortran lines 977-983)
    for (int j = js - 2; j <= je + 2; ++j) {
        const Real xt    = Real(0.25) * (q[j+1] - q[j-1]);
        const Real qmax  = detail::fmax3(q[j-1], q[j], q[j+1]);
        const Real qmin  = detail::fmin3(q[j-1], q[j], q[j+1]);
        const Real lim   = detail::fmin3(std::abs(xt), qmax - q[j], q[j] - qmin);
        dm[j] = std::copysign(lim, xt);
    }

    // Compute edge values al_s (Fortran lines 984-988)
    for (int j = js1; j <= je1 + 1; ++j)
        al_s[j] = Real(0.5)*(q[j-1] + q[j]) + C::r3*(dm[j-1] - dm[j]);

    // Compute bl/br based on jord (Fortran lines 990-1060)
    if (jord == 8) {
        for (int j = js1; j <= je1; ++j) {
            const Real xt   = Real(2) * dm[j];
            const Real abxt = std::abs(xt);
            const Real bll  = std::abs(al_s[j]   - q[j]);
            const Real brr  = std::abs(al_s[j+1] - q[j]);
            bl[j] = -std::copysign(abxt < bll ? abxt : bll, xt);
            br[j] =  std::copysign(abxt < brr ? abxt : brr, xt);
        }

    } else if (jord == 10) {
        for (int j = js1 - 2; j <= je1 + 1; ++j)
            dq[j] = Real(2) * (q[j+1] - q[j]);
        for (int j = js1; j <= je1; ++j) {
            bl[j] = al_s[j]   - q[j];
            br[j] = al_s[j+1] - q[j];
            const Real dm_sum = std::abs(dm[j-1]) + std::abs(dm[j]) + std::abs(dm[j+1]);
            if (dm_sum < C::near_zero) {
                bl[j] = Real(0);
                br[j] = Real(0);
            } else if (std::abs(Real(3)*(bl[j] + br[j])) > std::abs(bl[j] - br[j])) {
                const Real pmp_2 = dq[j-1];
                const Real lac_2 = pmp_2 - Real(0.75) * dq[j-2];
                const Real brmax = pmp_2 > Real(0) ? pmp_2 : Real(0);
                const Real brmin = pmp_2 < Real(0) ? pmp_2 : Real(0);
                // br = min(max(0,pmp_2,lac_2), max(br, min(0,pmp_2,lac_2)))
                const Real brhi  = detail::fmax3(brmax, lac_2, Real(0));
                const Real brlo  = detail::fmin3(brmin, lac_2, Real(0));
                br[j] = br[j] > brlo ? br[j] : brlo;
                br[j] = br[j] < brhi ? br[j] : brhi;

                const Real pmp_1 = -dq[j];
                const Real lac_1 = pmp_1 + Real(0.75) * dq[j+1];
                const Real blmax = pmp_1 > Real(0) ? pmp_1 : Real(0);
                const Real blmin = pmp_1 < Real(0) ? pmp_1 : Real(0);
                const Real blhi  = detail::fmax3(blmax, lac_1, Real(0));
                const Real bllo  = detail::fmin3(blmin, lac_1, Real(0));
                bl[j] = bl[j] > bllo ? bl[j] : bllo;
                bl[j] = bl[j] < blhi ? bl[j] : blhi;
            }
        }

    } else if (jord == 11) {
        for (int j = js1; j <= je1; ++j) {
            const Real xt   = C::ppm_fac * dm[j];
            const Real abxt = std::abs(xt);
            const Real bll  = std::abs(al_s[j]   - q[j]);
            const Real brr  = std::abs(al_s[j+1] - q[j]);
            bl[j] = -std::copysign(abxt < bll ? abxt : bll, xt);
            br[j] =  std::copysign(abxt < brr ? abxt : brr, xt);
        }

    } else if (jord == 7 || jord == 12) {
        for (int j = js1; j <= je1; ++j) {
            bl[j]  = al_s[j]   - q[j];
            br[j]  = al_s[j+1] - q[j];
            xt1    = br[j] - bl[j];
            a4_val = -Real(3) * (br[j] + bl[j]);
            hi5    = bl[j] * br[j] > Real(0);
            hi6    = std::abs(xt1) < -a4_val;
            if (hi6) {
                if (q[j] + Real(0.25)/a4_val * xt1*xt1 + a4_val*C::r12 < Real(0)) {
                    if (hi5) {
                        br[j] = Real(0); bl[j] = Real(0);
                    } else if (xt1 > Real(0)) {
                        br[j] = -Real(2) * bl[j];
                    } else {
                        bl[j] = -Real(2) * br[j];
                    }
                }
            }
        }

    } else {
        // jord == 9, 13, and any other value
        for (int j = js1; j <= je1; ++j) {
            bl[j] = al_s[j]   - q[j];
            br[j] = al_s[j+1] - q[j];
        }
    }

    // Positive-definite constraint for jord==9 or jord==13 (Fortran lines 1062-1067)
    if (jord == 9 || jord == 13) {
        for (int j = js1; j <= je1; ++j)
            pert_ppm(1, q + j, bl + j, br + j, 0);
    }

    // Cubed-sphere boundary treatment (Fortran lines 1069-1112)
    if (!nested && grid_type < 3) {
        if (js == 1) {
            bl[0] = C::s14*dm[-1] + C::s11*(q[-1] - q[0]);

            Real xt = Real(0.5) * (
                ((Real(2)*dya[0] + dya[-1])*q[0] - dya[0]*q[-1]) / (dya[-1] + dya[0])
              + ((Real(2)*dya[1] + dya[ 2])*q[1] - dya[1]*q[ 2]) / (dya[ 1] + dya[2]));
            xt = xt > detail::fmin4(q[-1], q[0], q[1], q[2]) ? xt : detail::fmin4(q[-1], q[0], q[1], q[2]);
            xt = xt < detail::fmax4(q[-1], q[0], q[1], q[2]) ? xt : detail::fmax4(q[-1], q[0], q[1], q[2]);

            br[0] = xt - q[0];
            bl[1] = xt - q[1];

            xt    = C::s15*q[1] + C::s11*q[2] - C::s14*dm[2];
            br[1] = xt - q[1];
            bl[2] = xt - q[2];

            br[2] = al_s[3] - q[2];

            // pert_ppm for 3 cells: q[0..2], bl[0..2], br[0..2]
            pert_ppm(3, q + 0, bl + 0, br + 0, 1);
        }

        if ((je + 1) == npy) {
            bl[npy-2] = al_s[npy-2] - q[npy-2];

            Real xt = C::s15*q[npy-1] + C::s11*q[npy-2] + C::s14*dm[npy-2];
            br[npy-2] = xt - q[npy-2];
            bl[npy-1] = xt - q[npy-1];

            xt = Real(0.5) * (
                ((Real(2)*dya[npy-1] + dya[npy-2])*q[npy-1] - dya[npy-1]*q[npy-2]) / (dya[npy-2] + dya[npy-1])
              + ((Real(2)*dya[npy  ] + dya[npy+1])*q[npy  ] - dya[npy  ]*q[npy+1]) / (dya[npy  ] + dya[npy+1]));
            xt = xt > detail::fmin4(q[npy-2], q[npy-1], q[npy], q[npy+1]) ? xt : detail::fmin4(q[npy-2], q[npy-1], q[npy], q[npy+1]);
            xt = xt < detail::fmax4(q[npy-2], q[npy-1], q[npy], q[npy+1]) ? xt : detail::fmax4(q[npy-2], q[npy-1], q[npy], q[npy+1]);

            br[npy-1] = xt - q[npy-1];
            bl[npy  ] = xt - q[npy  ];

            br[npy] = C::s11*(q[npy+1] - q[npy]) - C::s14*dm[npy+1];

            pert_ppm(3, q + (npy-2), bl + (npy-2), br + (npy-2), 1);
        }
    }

    // =========================================================================
    // Final flux computation for jord >= 7 (Fortran lines 1116-1145)
    // =========================================================================
    if (jord == 7) {
        for (int j = js - 1; j <= je + 1; ++j) {
            b0[j]   = bl[j] + br[j];
            smt5[j] = bl[j] * br[j] < Real(0);
        }
        for (int j = js; j <= je + 1; ++j) {
            if (cry[j] > Real(0)) {
                fx1 = (Real(1) - cry[j]) * (br[j-1] - cry[j] * b0[j-1]);
                flux[j] = q[j-1];
            } else {
                fx1 = (Real(1) + cry[j]) * (bl[j] + cry[j] * b0[j]);
                flux[j] = q[j];
            }
            if (smt5[j-1] || smt5[j]) flux[j] += fx1;
        }
    } else {
        // jord == 8, 9, 10, 11, 12, 13
        for (int j = js; j <= je + 1; ++j) {
            if (cry[j] > Real(0)) {
                flux[j] = q[j-1] + (Real(1) - cry[j]) * (br[j-1] - cry[j] * (bl[j-1] + br[j-1]));
            } else {
                flux[j] = q[j]   + (Real(1) + cry[j]) * (bl[j]   + cry[j] * (bl[j]   + br[j]  ));
            }
        }
    }
}

// ---------------------------------------------------------------------------
// yppm: multi-column wrapper matching the Fortran yppm signature.
//
// Arrays use Fortran column-major layout:
//   flux(ifirst:ilast, js:je+1)   stored as flux[(i-ifirst) + ni_q*(j-js)]
//   q(ifirst:ilast, jsd:jed)      stored as q[(i-ifirst) + ni_q*(j-jsd)]
//   cry(isd:ied, js:je+1)         stored as cry[(i-isd) + ni_cry*(j-js)]
//   dya(isd:ied, jsd:jed)         stored as dya[(i-isd) + ni_cry*(j-jsd)]
//
// scratch is reused across columns; on GPU each thread owns its own scratch.
// NMAX must satisfy NMAX >= (je - js + 1).
// ---------------------------------------------------------------------------
template <typename Real, int NMAX>
void yppm(
    Real*       flux,
    const Real* q,
    const Real* cry,
    int jord,
    int ifirst, int ilast,
    int isd,    int ied,
    int js,     int je,
    int jsd,    int jed,
    int npx,    int npy,
    const Real* dya,
    bool nested,
    int grid_type,
    Real lim_fac,
    ScratchYPPM<Real, NMAX>& scratch)
{
    const int ni_q   = ilast - ifirst + 1;
    const int ni_cry = ied   - isd    + 1;
    const int nj_q   = jed   - jsd    + 1;
    const int nj_cry = je    - js     + 2;

    // Temporary column buffers (stack-allocated; fixed by NMAX)
    Real q_buf   [NMAX + 7];
    Real cry_buf [NMAX + 3];
    Real dya_buf [NMAX + 7];
    Real flux_buf[NMAX + 3];

    for (int i = ifirst; i <= ilast; ++i) {
        const int qi = i - ifirst;  // 0-based x index into q/flux
        const int ci = i - isd;     // 0-based x index into cry/dya

        // Extract this column from the 2D column-major arrays
        for (int j = 0; j < nj_q; ++j)
            q_buf[j] = q[qi + ni_q * j];
        for (int j = 0; j < nj_cry; ++j)
            cry_buf[j] = cry[ci + ni_cry * j];
        for (int j = 0; j < nj_q; ++j)
            dya_buf[j] = dya[ci + ni_cry * j];

        yppm_col<Real, NMAX>(
            flux_buf, q_buf, cry_buf,
            jord, js, je, jsd, jed, npx, npy,
            dya_buf, nested, grid_type, lim_fac,
            scratch);

        // Write flux column back
        for (int j = 0; j < nj_cry; ++j)
            flux[qi + ni_q * j] = flux_buf[j];
    }
}

} // namespace fv3
