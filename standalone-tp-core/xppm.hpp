// xppm.hpp — C++ port of the xppm subroutine from tp_core.F90
//
// xppm is the X-direction (zonal) counterpart of yppm: it computes PPM
// advective fluxes in i, sweeping along i for each j-row. It is structurally
// identical to yppm under the substitution
//   j -> i,  js/je/jsd/jed -> is/ie/isd/ied,  npy -> npx,  dya -> dxa,
//   cry -> c (Courant number),  jord -> iord.
// The numerics here are a direct rename of the verified yppm_col.
//
// This header REUSES the direction-agnostic infrastructure from yppm.hpp
// (detail::, pert_ppm, the YPPM_HOST_DEVICE / YPPM_INLINE macros, and the
// ScratchYPPMView / yppm_make_scratch_view / yppm_scratch_* helpers — the
// scratch is the same shape regardless of sweep direction). Nothing is
// redefined, so both headers may be included in one translation unit.
//
// CPU usage (single row):
//   ScratchXPPM<float, 20> scratch;                       // stack storage
//   xppm_col<float>(flux_row, q_row, c_row, iord, is, ie, isd, ied,
//                   npx, npy, dxa_row, nested, grid_type, lim_fac,
//                   scratch.view(ie - is + 1));
//
// GPU usage: call xppm_col from a __global__ kernel, one thread per j-row,
//   handing each thread a ScratchYPPMView over a slice of one device buffer
//   (see xppm_gpu.cuh). ni = ie - is + 1 sets the scratch stride, so any
//   runtime resolution is supported.
#pragma once

#include "yppm.hpp"   // detail::, pert_ppm, macros, scratch view + helpers

namespace fv3 {

// The scratch view/sizing helpers are direction-agnostic; alias them with
// xppm-flavored names for readability (single shared implementation).
template <typename Real>            using ScratchXPPMView = ScratchYPPMView<Real>;
template <typename Real, int NMAX>  using ScratchXPPM     = ScratchYPPM<Real, NMAX>;

// ---------------------------------------------------------------------------
// xppm_col: X-direction PPM flux for a single j-row.
//
// Array arguments are 0-indexed from their lower Fortran bounds:
//   flux_row[i - is],  i in [is, ie+1]          (output)
//   q_row[i - isd],    i in [isd, ied]           (input)
//   c_row[i - is],     i in [is, ie+1]           (Courant number, input)
//   dxa_row[i - isd],  i in [isd, ied]           (grid spacing, input)
//
// s is a ScratchYPPMView laid out for ni = ie - is + 1 (yppm_make_scratch_view).
// ---------------------------------------------------------------------------
template <typename Real>
YPPM_HOST_DEVICE
void xppm_col(
    Real*       flux_row,
    const Real* q_row,
    const Real* c_row,
    int iord,
    int is, int ie,
    int isd, int ied,
    int npx, int npy,
    const Real* dxa_row,
    bool nested,
    int grid_type,
    Real lim_fac,
    const ScratchYPPMView<Real>& s)
{
    using C = detail::Const<Real>;

    // Build offset pointers so that arr[i] corresponds to Fortran arr(i).
    Real*       flux = flux_row - is;
    const Real* q    = q_row    - isd;
    const Real* c    = c_row    - is;
    const Real* dxa  = dxa_row  - isd;

    Real* dm   = s.dm   - (is - 2);
    Real* al_s = s.al   - (is - 1);
    Real* bl   = s.bl   - (is - 1);
    Real* br   = s.br   - (is - 1);
    Real* b0   = s.b0   - (is - 1);
    Real* dq   = s.dq   - (is - 3);
    bool* smt5 = s.smt5 - (is - 1);
    bool* smt6 = s.smt6 - (is - 1);

    // Per-i temporaries (Fortran's dimension(is-1:ie+1) arrays reduce to
    // scalars when each i is computed and consumed independently).
    Real fx1, xt1, a4_val;
    bool hi5, hi6;

    // Stencil loop bounds (Fortran lines 349-355)
    int is1, ie3, ie1;
    if (!nested && grid_type < 3) {
        is1 = (is - 1) > 3 ? (is - 1) : 3;                 // max(3, is-1)
        ie3 = (npx - 2) < (ie + 2) ? (npx - 2) : (ie + 2); // min(npx-2, ie+2)
        ie1 = (npx - 3) < (ie + 1) ? (npx - 3) : (ie + 1); // min(npx-3, ie+1)
    } else {
        is1 = is - 1;
        ie3 = ie + 2;
        ie1 = ie + 1;
    }

    const int mord = iord >= 0 ? iord : -iord;

    // =========================================================================
    if (iord < 7) {
    // =========================================================================
    // Low-order schemes (|iord| = 1..6)
    // =========================================================================

        for (int i = is1; i <= ie3; ++i)
            al_s[i] = C::p1*(q[i-1] + q[i]) + C::p2*(q[i-2] + q[i+1]);

        if (!nested && grid_type < 3) {
            if (is == 1) {
                al_s[0] = C::c1*q[-2] + C::c2*q[-1] + C::c3*q[0];
                al_s[1] = Real(0.5) * (
                    ((Real(2)*dxa[0] + dxa[-1])*q[0]  - dxa[0]*q[-1])  / (dxa[-1] + dxa[0])
                  + ((Real(2)*dxa[1] + dxa[ 2])*q[1]  - dxa[1]*q[ 2])  / (dxa[ 1] + dxa[2]));
                al_s[2] = C::c3*q[1] + C::c2*q[2] + C::c1*q[3];
            }
            if ((ie + 1) == npx) {
                al_s[npx-1] = C::c1*q[npx-3] + C::c2*q[npx-2] + C::c3*q[npx-1];
                al_s[npx]   = Real(0.5) * (
                    ((Real(2)*dxa[npx-1] + dxa[npx-2])*q[npx-1] - dxa[npx-1]*q[npx-2]) / (dxa[npx-2] + dxa[npx-1])
                  + ((Real(2)*dxa[npx  ] + dxa[npx+1])*q[npx  ] - dxa[npx  ]*q[npx+1]) / (dxa[npx  ] + dxa[npx+1]));
                al_s[npx+1] = C::c3*q[npx] + C::c2*q[npx+1] + C::c1*q[npx+2];
            }
        }

        if (iord < 0) {
            for (int i = is - 1; i <= ie + 2; ++i)
                if (al_s[i] < Real(0)) al_s[i] = Real(0);
        }

        if (mord == 1) {
            for (int i = is - 1; i <= ie + 1; ++i) {
                bl[i]   = al_s[i]   - q[i];
                br[i]   = al_s[i+1] - q[i];
                b0[i]   = bl[i] + br[i];
                smt5[i] = detail::yabs(lim_fac * b0[i]) < detail::yabs(bl[i] - br[i]);
            }
            for (int i = is; i <= ie + 1; ++i) {
                if (c[i] > Real(0)) {
                    fx1 = (Real(1) - c[i]) * (br[i-1] - c[i] * b0[i-1]);
                    flux[i] = q[i-1];
                } else {
                    fx1 = (Real(1) + c[i]) * (bl[i] + c[i] * b0[i]);
                    flux[i] = q[i];
                }
                if (smt5[i-1] || smt5[i]) flux[i] += fx1;
            }

        } else if (mord == 2) {
            for (int i = is; i <= ie + 1; ++i) {
                const Real xt = c[i];
                Real qtmp;
                if (xt > Real(0)) {
                    qtmp    = q[i-1];
                    flux[i] = qtmp + (Real(1) - xt) * (al_s[i] - qtmp - xt*(al_s[i-1] + al_s[i] - Real(2)*qtmp));
                } else {
                    qtmp    = q[i];
                    flux[i] = qtmp + (Real(1) + xt) * (al_s[i] - qtmp + xt*(al_s[i] + al_s[i+1] - Real(2)*qtmp));
                }
            }

        } else if (mord == 3) {
            for (int i = is - 1; i <= ie + 1; ++i) {
                bl[i] = al_s[i]   - q[i];
                br[i] = al_s[i+1] - q[i];
                b0[i] = bl[i] + br[i];
                const Real x0 = detail::yabs(b0[i]);
                const Real xt = detail::yabs(bl[i] - br[i]);
                smt5[i] =         x0 < xt;
                smt6[i] = Real(3)*x0 < xt;
            }
            for (int i = is; i <= ie + 1; ++i) {
                xt1 = c[i];
                if (xt1 > Real(0)) {
                    if (smt5[i-1] || smt6[i])
                        flux[i] = q[i-1] + (Real(1) - xt1) * (br[i-1] - xt1 * b0[i-1]);
                    else
                        flux[i] = q[i-1];
                } else {
                    if (smt6[i-1] || smt5[i])
                        flux[i] = q[i] + (Real(1) + xt1) * (bl[i] + xt1 * b0[i]);
                    else
                        flux[i] = q[i];
                }
            }

        } else if (mord == 4) {
            for (int i = is - 1; i <= ie + 1; ++i) {
                bl[i] = al_s[i]   - q[i];
                br[i] = al_s[i+1] - q[i];
                b0[i] = bl[i] + br[i];
                const Real x0 = detail::yabs(b0[i]);
                const Real xt = detail::yabs(bl[i] - br[i]);
                smt5[i] =         x0 < xt;
                smt6[i] = Real(3)*x0 < xt;
            }
            for (int i = is; i <= ie + 1; ++i) {
                xt1 = c[i];
                hi5 = smt5[i-1] && smt5[i];
                hi6 = smt6[i-1] || smt6[i];
                hi5 = hi5 || hi6;
                if (xt1 > Real(0)) {
                    fx1 = (Real(1) - xt1) * (br[i-1] - xt1 * b0[i-1]);
                    flux[i] = q[i-1];
                } else {
                    fx1 = (Real(1) + xt1) * (bl[i] + xt1 * b0[i]);
                    flux[i] = q[i];
                }
                if (hi5) flux[i] += fx1;
            }

        } else {
            // mord == 5 or 6
            if (iord == 5) {
                for (int i = is - 1; i <= ie + 1; ++i) {
                    bl[i]   = al_s[i]   - q[i];
                    br[i]   = al_s[i+1] - q[i];
                    b0[i]   = bl[i] + br[i];
                    smt5[i] = bl[i] * br[i] < Real(0);
                }
            } else if (iord == -5) {
                for (int i = is - 1; i <= ie + 1; ++i) {
                    bl[i]   = al_s[i]   - q[i];
                    br[i]   = al_s[i+1] - q[i];
                    b0[i]   = bl[i] + br[i];
                    xt1     = br[i] - bl[i];
                    a4_val  = -Real(3) * b0[i];
                    smt5[i] = bl[i] * br[i] < Real(0);
                    if (detail::yabs(xt1) < -a4_val) {
                        if (q[i] + Real(0.25)/a4_val * xt1*xt1 + a4_val*C::r12 < Real(0)) {
                            if (!smt5[i]) {
                                br[i] = Real(0); bl[i] = Real(0); b0[i] = Real(0);
                            } else if (xt1 > Real(0)) {
                                br[i] = -Real(2) * bl[i]; b0[i] = -bl[i];
                            } else {
                                bl[i] = -Real(2) * br[i]; b0[i] = -br[i];
                            }
                        }
                    }
                }
            } else {
                // iord == 6 or iord == -6
                for (int i = is - 1; i <= ie + 1; ++i) {
                    bl[i]   = al_s[i]   - q[i];
                    br[i]   = al_s[i+1] - q[i];
                    b0[i]   = bl[i] + br[i];
                    smt5[i] = Real(3)*detail::yabs(b0[i]) < detail::yabs(bl[i] - br[i]);
                }
                // WMP edge fix (Fortran lines 532-541)
                if (!nested && grid_type < 3) {
                    if (is == 1) {
                        smt5[0] = bl[0] * br[0] < Real(0);
                        smt5[1] = bl[1] * br[1] < Real(0);
                    }
                    if ((ie + 1) == npx) {
                        smt5[npx-1] = bl[npx-1] * br[npx-1] < Real(0);
                        smt5[npx  ] = bl[npx  ] * br[npx  ] < Real(0);
                    }
                }
            }

            for (int i = is; i <= ie + 1; ++i) {
                if (c[i] > Real(0)) {
                    fx1 = (Real(1) - c[i]) * (br[i-1] - c[i] * b0[i-1]);
                    flux[i] = q[i-1];
                } else {
                    fx1 = (Real(1) + c[i]) * (bl[i] + c[i] * b0[i]);
                    flux[i] = q[i];
                }
                if (smt5[i-1] || smt5[i]) flux[i] += fx1;
            }
        }
        return; // iord < 7: done
    }

    // =========================================================================
    // iord >= 7: Monotonic PPM (Fortran lines 567-705)
    // =========================================================================

    for (int i = is - 2; i <= ie + 2; ++i) {
        const Real xt    = Real(0.25) * (q[i+1] - q[i-1]);
        const Real qmax  = detail::fmax3(q[i-1], q[i], q[i+1]);
        const Real qmin  = detail::fmin3(q[i-1], q[i], q[i+1]);
        const Real lim   = detail::fmin3(detail::yabs(xt), qmax - q[i], q[i] - qmin);
        dm[i] = detail::ycopysign(lim, xt);
    }

    for (int i = is1; i <= ie1 + 1; ++i)
        al_s[i] = Real(0.5)*(q[i-1] + q[i]) + C::r3*(dm[i-1] - dm[i]);

    if (iord == 8) {
        for (int i = is1; i <= ie1; ++i) {
            const Real xt   = Real(2) * dm[i];
            const Real abxt = detail::yabs(xt);
            const Real bll  = detail::yabs(al_s[i]   - q[i]);
            const Real brr  = detail::yabs(al_s[i+1] - q[i]);
            bl[i] = -detail::ycopysign(abxt < bll ? abxt : bll, xt);
            br[i] =  detail::ycopysign(abxt < brr ? abxt : brr, xt);
        }

    } else if (iord == 10) {
        for (int i = is1 - 2; i <= ie1 + 1; ++i)
            dq[i] = Real(2) * (q[i+1] - q[i]);
        for (int i = is1; i <= ie1; ++i) {
            bl[i] = al_s[i]   - q[i];
            br[i] = al_s[i+1] - q[i];
            const Real dm_sum = detail::yabs(dm[i-1]) + detail::yabs(dm[i]) + detail::yabs(dm[i+1]);
            if (dm_sum < C::near_zero) {
                bl[i] = Real(0);
                br[i] = Real(0);
            } else if (detail::yabs(Real(3)*(bl[i] + br[i])) > detail::yabs(bl[i] - br[i])) {
                const Real pmp_2 = dq[i-1];
                const Real lac_2 = pmp_2 - Real(0.75) * dq[i-2];
                const Real brmax = pmp_2 > Real(0) ? pmp_2 : Real(0);
                const Real brmin = pmp_2 < Real(0) ? pmp_2 : Real(0);
                const Real brhi  = detail::fmax3(brmax, lac_2, Real(0));
                const Real brlo  = detail::fmin3(brmin, lac_2, Real(0));
                br[i] = br[i] > brlo ? br[i] : brlo;
                br[i] = br[i] < brhi ? br[i] : brhi;

                const Real pmp_1 = -dq[i];
                const Real lac_1 = pmp_1 + Real(0.75) * dq[i+1];
                const Real blmax = pmp_1 > Real(0) ? pmp_1 : Real(0);
                const Real blmin = pmp_1 < Real(0) ? pmp_1 : Real(0);
                const Real blhi  = detail::fmax3(blmax, lac_1, Real(0));
                const Real bllo  = detail::fmin3(blmin, lac_1, Real(0));
                bl[i] = bl[i] > bllo ? bl[i] : bllo;
                bl[i] = bl[i] < blhi ? bl[i] : blhi;
            }
        }

    } else if (iord == 11) {
        for (int i = is1; i <= ie1; ++i) {
            const Real xt   = C::ppm_fac * dm[i];
            const Real abxt = detail::yabs(xt);
            const Real bll  = detail::yabs(al_s[i]   - q[i]);
            const Real brr  = detail::yabs(al_s[i+1] - q[i]);
            bl[i] = -detail::ycopysign(abxt < bll ? abxt : bll, xt);
            br[i] =  detail::ycopysign(abxt < brr ? abxt : brr, xt);
        }

    } else if (iord == 7 || iord == 12) {
        for (int i = is1; i <= ie1; ++i) {
            bl[i]  = al_s[i]   - q[i];
            br[i]  = al_s[i+1] - q[i];
            xt1    = br[i] - bl[i];
            a4_val = -Real(3) * (br[i] + bl[i]);
            hi5    = bl[i] * br[i] > Real(0);
            hi6    = detail::yabs(xt1) < -a4_val;
            if (hi6) {
                if (q[i] + Real(0.25)/a4_val * xt1*xt1 + a4_val*C::r12 < Real(0)) {
                    if (hi5) {
                        br[i] = Real(0); bl[i] = Real(0);
                    } else if (xt1 > Real(0)) {
                        br[i] = -Real(2) * bl[i];
                    } else {
                        bl[i] = -Real(2) * br[i];
                    }
                }
            }
        }

    } else {
        // iord == 9, 13, and any other value
        for (int i = is1; i <= ie1; ++i) {
            bl[i] = al_s[i]   - q[i];
            br[i] = al_s[i+1] - q[i];
        }
    }

    // Positive-definite constraint for iord==9 or iord==13 (Fortran line 638)
    if (iord == 9 || iord == 13) {
        for (int i = is1; i <= ie1; ++i)
            pert_ppm(1, q + i, bl + i, br + i, 0);
    }

    // Cubed-sphere boundary treatment (Fortran lines 640-678)
    if (!nested && grid_type < 3) {
        if (is == 1) {
            bl[0] = C::s14*dm[-1] + C::s11*(q[-1] - q[0]);

            Real xt = Real(0.5) * (
                ((Real(2)*dxa[0] + dxa[-1])*q[0] - dxa[0]*q[-1]) / (dxa[-1] + dxa[0])
              + ((Real(2)*dxa[1] + dxa[ 2])*q[1] - dxa[1]*q[ 2]) / (dxa[ 1] + dxa[2]));
            xt = xt > detail::fmin4(q[-1], q[0], q[1], q[2]) ? xt : detail::fmin4(q[-1], q[0], q[1], q[2]);
            xt = xt < detail::fmax4(q[-1], q[0], q[1], q[2]) ? xt : detail::fmax4(q[-1], q[0], q[1], q[2]);

            br[0] = xt - q[0];
            bl[1] = xt - q[1];

            xt    = C::s15*q[1] + C::s11*q[2] - C::s14*dm[2];
            br[1] = xt - q[1];
            bl[2] = xt - q[2];

            br[2] = al_s[3] - q[2];

            pert_ppm(3, q + 0, bl + 0, br + 0, 1);
        }

        if ((ie + 1) == npx) {
            bl[npx-2] = al_s[npx-2] - q[npx-2];

            Real xt = C::s15*q[npx-1] + C::s11*q[npx-2] + C::s14*dm[npx-2];
            br[npx-2] = xt - q[npx-2];
            bl[npx-1] = xt - q[npx-1];

            xt = Real(0.5) * (
                ((Real(2)*dxa[npx-1] + dxa[npx-2])*q[npx-1] - dxa[npx-1]*q[npx-2]) / (dxa[npx-2] + dxa[npx-1])
              + ((Real(2)*dxa[npx  ] + dxa[npx+1])*q[npx  ] - dxa[npx  ]*q[npx+1]) / (dxa[npx  ] + dxa[npx+1]));
            xt = xt > detail::fmin4(q[npx-2], q[npx-1], q[npx], q[npx+1]) ? xt : detail::fmin4(q[npx-2], q[npx-1], q[npx], q[npx+1]);
            xt = xt < detail::fmax4(q[npx-2], q[npx-1], q[npx], q[npx+1]) ? xt : detail::fmax4(q[npx-2], q[npx-1], q[npx], q[npx+1]);

            br[npx-1] = xt - q[npx-1];
            bl[npx  ] = xt - q[npx  ];

            br[npx] = C::s11*(q[npx+1] - q[npx]) - C::s14*dm[npx+1];

            pert_ppm(3, q + (npx-2), bl + (npx-2), br + (npx-2), 1);
        }
    }

    // =========================================================================
    // Final flux computation for iord >= 7 (Fortran lines 682-705)
    // =========================================================================
    if (iord == 7) {
        for (int i = is - 1; i <= ie + 1; ++i) {
            b0[i]   = bl[i] + br[i];
            smt5[i] = bl[i] * br[i] < Real(0);
        }
        for (int i = is; i <= ie + 1; ++i) {
            if (c[i] > Real(0)) {
                fx1 = (Real(1) - c[i]) * (br[i-1] - c[i] * b0[i-1]);
                flux[i] = q[i-1];
            } else {
                fx1 = (Real(1) + c[i]) * (bl[i] + c[i] * b0[i]);
                flux[i] = q[i];
            }
            if (smt5[i-1] || smt5[i]) flux[i] += fx1;
        }
    } else {
        // iord == 8, 9, 10, 11, 12, 13
        for (int i = is; i <= ie + 1; ++i) {
            if (c[i] > Real(0)) {
                flux[i] = q[i-1] + (Real(1) - c[i]) * (br[i-1] - c[i] * (bl[i-1] + br[i-1]));
            } else {
                flux[i] = q[i]   + (Real(1) + c[i]) * (bl[i]   + c[i] * (bl[i]   + br[i]  ));
            }
        }
    }
}

// ---------------------------------------------------------------------------
// xppm: multi-row wrapper matching the Fortran xppm signature.
//
// Arrays use Fortran column-major layout (i is the fast dimension, so each
// j-row is a contiguous slice):
//   flux(is:ie+1, jfirst:jlast) stored as flux[(i-is) + ni_c*(j-jfirst)]
//   q(isd:ied, jfirst:jlast)    stored as q[(i-isd) + ni_q*(j-jfirst)]
//   c(is:ie+1, jfirst:jlast)    stored as c[(i-is) + ni_c*(j-jfirst)]
//   dxa(isd:ied, jsd:jed)       stored as dxa[(i-isd) + ni_q*(j-jsd)]
//
// scratch is reused across rows; on GPU each thread owns its own scratch.
// NMAX must satisfy NMAX >= (ie - is + 1).
// ---------------------------------------------------------------------------
template <typename Real, int NMAX>
void xppm(
    Real*       flux,
    const Real* q,
    const Real* c,
    int iord,
    int is,     int ie,
    int isd,    int ied,
    int jfirst, int jlast,
    int jsd,    int jed,
    int npx,    int npy,
    const Real* dxa,
    bool nested,
    int grid_type,
    Real lim_fac,
    ScratchXPPM<Real, NMAX>& scratch)
{
    const int ni_q = ied - isd + 1;   // q/dxa per-row length (i is contiguous)
    const int ni_c = ie  - is  + 2;   // c/flux per-row length

    for (int j = jfirst; j <= jlast; ++j) {
        const Real* q_row    = q   + static_cast<long>(j - jfirst) * ni_q;
        const Real* c_row    = c   + static_cast<long>(j - jfirst) * ni_c;
        Real*       flux_row = flux + static_cast<long>(j - jfirst) * ni_c;
        const Real* dxa_row  = dxa + static_cast<long>(j - jsd)    * ni_q;

        xppm_col<Real>(
            flux_row, q_row, c_row,
            iord, is, ie, isd, ied, npx, npy,
            dxa_row, nested, grid_type, lim_fac,
            scratch.view(ie - is + 1));
    }
}

} // namespace fv3
