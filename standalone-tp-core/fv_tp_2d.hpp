// fv_tp_2d.hpp — C++ port of fv_tp_2d (the FV3 2-D transport operator) and
// copy_corners from tp_core.F90, for the non-mass / no-divergence-damping path
// that the standalone driver exercises.
//
// fv_tp_2d combines xppm and yppm with cross-advection intermediates:
//   copy_corners(q, dir=2)
//   fy2 = yppm(q)                                   ! y flux of q
//   q_i = (q*area + d/dy[yfx*fy2]) / ra_y           ! y-advanced q
//   fx  = xppm(q_i)                                 ! x flux of q_i
//   copy_corners(q, dir=1)
//   fx2 = xppm(q)                                   ! x flux of q
//   q_j = (q*area + d/dx[xfx*fx2]) / ra_x           ! x-advanced q
//   fy  = yppm(q_j)                                 ! y flux of q_j
//   fx  = 0.5*(fx + fx2)*xfx ;  fy = 0.5*(fy + fy2)*yfx
//
// Layout: all 2-D arrays are Fortran column-major (i fastest), with explicit
// lower bounds, matching the Fortran. idx2(i,j,ilo,jlo,ni) addresses them.
//
// The numerics reuse the verified yppm_col / xppm_col (per line) plus the
// shared __host__ __device__ cell ops below, so the CPU reference here and the
// GPU orchestrator in fv_tp_2d_gpu.cuh compute byte-for-byte the same scheme
// on each device (FMA aside).
#pragma once

#include "yppm.hpp"
#include "xppm.hpp"

#include <vector>   // fv_tp_2d_cpu is host-only; std::vector is fine under nvcc host

namespace fv3 {

static const int FV_NG = 3;   // halo width (tp_core ng)

// Column-major index: array(i,j) with i in [ilo,..], ni = (ihi-ilo+1).
YPPM_HOST_DEVICE YPPM_INLINE int idx2(int i, int j, int ilo, int jlo, int ni) {
    return (i - ilo) + ni * (j - jlo);
}

// Shared elementwise arithmetic (single source of truth for CPU and GPU).
//   cross: (q*area + a - b)/ra  — used for q_i (a,b = yfx*fy2 at j,j+1)
//                                 and q_j (a,b = xfx*fx2 at i,i+1)
template <typename Real>
YPPM_HOST_DEVICE YPPM_INLINE Real fv_cross(Real q, Real area, Real a, Real b, Real ra) {
    return (q * area + a - b) / ra;
}
//   flux average: 0.5*(f1 + f2)*w
template <typename Real>
YPPM_HOST_DEVICE YPPM_INLINE Real fv_avg_flux(Real f1, Real f2, Real w) {
    return Real(0.5) * (f1 + f2) * w;
}

// ---------------------------------------------------------------------------
// copy_corners: fill the cubed-sphere corner ghost cells of q (in place).
// q is q(isd:ied, jsd:jed), niq = ied-isd+1. dir = 1 (x) or 2 (y).
// Tiny work — on GPU run with a single thread.
// ---------------------------------------------------------------------------
template <typename Real>
YPPM_HOST_DEVICE
void fv_copy_corners(Real* q, int isd, int jsd, int niq,
                     int npx, int npy, int dir,
                     bool sw, bool se, bool nw, bool ne)
{
    const int ng = FV_NG;
    #define Q(ii,jj) q[idx2((ii),(jj),isd,jsd,niq)]
    if (dir == 1) {
        if (sw) for (int j=1-ng; j<=0; ++j) for (int i=1-ng; i<=0; ++i)              Q(i,j) = Q(j, 1-i);
        if (se) for (int j=1-ng; j<=0; ++j) for (int i=npx; i<=npx+ng-1; ++i)        Q(i,j) = Q(npy-j, i-npx+1);
        if (ne) for (int j=npy; j<=npy+ng-1; ++j) for (int i=npx; i<=npx+ng-1; ++i)  Q(i,j) = Q(j, 2*npx-1-i);
        if (nw) for (int j=npy; j<=npy+ng-1; ++j) for (int i=1-ng; i<=0; ++i)        Q(i,j) = Q(npy-j, i-1+npx);
    } else {
        if (sw) for (int j=1-ng; j<=0; ++j) for (int i=1-ng; i<=0; ++i)              Q(i,j) = Q(1-j, i);
        if (se) for (int j=1-ng; j<=0; ++j) for (int i=npx; i<=npx+ng-1; ++i)        Q(i,j) = Q(npy+j-1, npx-i);
        if (ne) for (int j=npy; j<=npy+ng-1; ++j) for (int i=npx; i<=npx+ng-1; ++i)  Q(i,j) = Q(2*npy-1-j, i);
        if (nw) for (int j=npy; j<=npy+ng-1; ++j) for (int i=1-ng; i<=0; ++i)        Q(i,j) = Q(j+1-npx, npy-i);
    }
    #undef Q
}

// ---------------------------------------------------------------------------
// CPU reference: fv_tp_2d for the non-mass / no-damping path.
// All arrays are caller-provided flat column-major buffers with the Fortran
// bounds (see comments). hord selects the PPM order (ord_in/ord_ou as in
// the Fortran). Reuses yppm_col / xppm_col per line via gather buffers.
// q is modified in place at the corners (copy_corners), as in the Fortran.
// ---------------------------------------------------------------------------
template <typename Real>
void fv_tp_2d_cpu(
    Real*       q,      // (isd:ied, jsd:jed)   inout
    const Real* crx,    // (is:ie+1, jsd:jed)
    const Real* cry,    // (isd:ied, js:je+1)
    const Real* xfx,    // (is:ie+1, jsd:jed)
    const Real* yfx,    // (isd:ied, js:je+1)
    const Real* ra_x,   // (is:ie,   jsd:jed)
    const Real* ra_y,   // (isd:ied, js:je)
    const Real* area,   // (isd:ied, jsd:jed)
    const Real* dxa,    // (isd:ied, jsd:jed)
    const Real* dya,    // (isd:ied, jsd:jed)
    Real*       fx,     // (is:ie+1, js:je)     out
    Real*       fy,     // (is:ie,   js:je+1)   out
    int is, int ie, int js, int je,
    int isd, int ied, int jsd, int jed,
    int npx, int npy, int hord, Real lim_fac,
    bool nested, int grid_type,
    bool sw, bool se, bool nw, bool ne,
    // Mass-flux combine variant (tracer transport): when use_mass, the flux
    // average multiplies by mfx/mfy instead of xfx/yfx. mfx is (is:ie+1,js:je),
    // mfy is (is:ie,js:je+1). The q_i/q_j cross terms always use xfx/yfx.
    bool use_mass = false, const Real* mfx = nullptr, const Real* mfy = nullptr)
{
    const int ord_in = (hord == 10) ? 8 : hord;
    const int ord_ou = hord;

    // Strides (i-extent) of each array.
    const int niq   = ied - isd + 1;   // q, area, dxa, dya, cry, yfx, fy2, q_i, ra_y
    const int nicrx = ie  - is  + 2;   // crx, xfx, fx, fx2
    const int nirax = ie  - is  + 1;   // ra_x, q_j, fy

    // Internals.
    std::vector<Real> fy2(static_cast<size_t>(niq)   * (je - js + 2), Real(0)); // (isd:ied, js:je+1)
    std::vector<Real> fx2(static_cast<size_t>(nicrx) * (jed - jsd + 1), Real(0)); // (is:ie+1, jsd:jed)
    std::vector<Real> q_i(static_cast<size_t>(niq)   * (je - js + 1), Real(0)); // (isd:ied, js:je)
    std::vector<Real> q_j(static_cast<size_t>(nirax) * (jed - jsd + 1), Real(0)); // (is:ie, jsd:jed)

    // Scratch + line buffers (sized to the larger of the two sweep extents).
    const int nmax = (je - js + 1 > ie - is + 1) ? (je - js + 1) : (ie - is + 1);
    std::vector<Real> rbuf(yppm_scratch_real_words(nmax));
    std::vector<char> bbuf(yppm_scratch_bool_words(nmax));
    ScratchYPPMView<Real> s = yppm_make_scratch_view<Real>(
        rbuf.data(), reinterpret_cast<bool*>(bbuf.data()), nmax);

    const int nj_q_y = jed - jsd + 1, nj_f_y = je - js + 2;
    const int ni_q_x = ied - isd + 1, ni_f_x = ie - is + 2;
    std::vector<Real> ql(static_cast<size_t>(nj_q_y > ni_q_x ? nj_q_y : ni_q_x));
    std::vector<Real> cl(static_cast<size_t>(nj_f_y > ni_f_x ? nj_f_y : ni_f_x));
    std::vector<Real> al(ql.size());
    std::vector<Real> fl(cl.size());

    // ---- copy_corners (y) then fy2 = yppm(q) over columns i = isd..ied ----
    if (!nested) fv_copy_corners<Real>(q, isd, jsd, niq, npx, npy, 2, sw, se, nw, ne);

    for (int i = isd; i <= ied; ++i) {
        for (int j = jsd; j <= jed; ++j) ql[j-jsd] = q  [idx2(i,j,isd,jsd,niq)];
        for (int j = js;  j <= je+1; ++j) cl[j-js]  = cry[idx2(i,j,isd,js, niq)];
        for (int j = jsd; j <= jed; ++j) al[j-jsd] = dya[idx2(i,j,isd,jsd,niq)];
        yppm_col<Real>(fl.data(), ql.data(), cl.data(), ord_in,
                       js, je, jsd, jed, npx, npy, al.data(),
                       nested, grid_type, lim_fac, s);
        for (int j = js; j <= je+1; ++j) fy2[idx2(i,j,isd,js,niq)] = fl[j-js];
    }

    // ---- q_i = (q*area + d/dy[yfx*fy2]) / ra_y, j = js..je, i = isd..ied ----
    for (int j = js; j <= je; ++j)
        for (int i = isd; i <= ied; ++i) {
            const Real a = yfx[idx2(i,j,  isd,js,niq)] * fy2[idx2(i,j,  isd,js,niq)];
            const Real b = yfx[idx2(i,j+1,isd,js,niq)] * fy2[idx2(i,j+1,isd,js,niq)];
            q_i[idx2(i,j,isd,js,niq)] = fv_cross<Real>(
                q[idx2(i,j,isd,jsd,niq)], area[idx2(i,j,isd,jsd,niq)],
                a, b, ra_y[idx2(i,j,isd,js,niq)]);
        }

    // ---- fx = xppm(q_i) over rows j = js..je ----
    for (int j = js; j <= je; ++j) {
        for (int i = isd; i <= ied; ++i) ql[i-isd] = q_i[idx2(i,j,isd,js,niq)];
        for (int i = is;  i <= ie+1; ++i) cl[i-is]  = crx[idx2(i,j,is,jsd,nicrx)];
        for (int i = isd; i <= ied; ++i) al[i-isd] = dxa[idx2(i,j,isd,jsd,niq)];
        xppm_col<Real>(fl.data(), ql.data(), cl.data(), ord_ou,
                       is, ie, isd, ied, npx, npy, al.data(),
                       nested, grid_type, lim_fac, s);
        for (int i = is; i <= ie+1; ++i) fx[idx2(i,j,is,js,nicrx)] = fl[i-is];
    }

    // ---- copy_corners (x) then fx2 = xppm(q) over rows j = jsd..jed ----
    if (!nested) fv_copy_corners<Real>(q, isd, jsd, niq, npx, npy, 1, sw, se, nw, ne);

    for (int j = jsd; j <= jed; ++j) {
        for (int i = isd; i <= ied; ++i) ql[i-isd] = q  [idx2(i,j,isd,jsd,niq)];
        for (int i = is;  i <= ie+1; ++i) cl[i-is]  = crx[idx2(i,j,is,jsd,nicrx)];
        for (int i = isd; i <= ied; ++i) al[i-isd] = dxa[idx2(i,j,isd,jsd,niq)];
        xppm_col<Real>(fl.data(), ql.data(), cl.data(), ord_in,
                       is, ie, isd, ied, npx, npy, al.data(),
                       nested, grid_type, lim_fac, s);
        for (int i = is; i <= ie+1; ++i) fx2[idx2(i,j,is,jsd,nicrx)] = fl[i-is];
    }

    // ---- q_j = (q*area + d/dx[xfx*fx2]) / ra_x, j = jsd..jed, i = is..ie ----
    for (int j = jsd; j <= jed; ++j)
        for (int i = is; i <= ie; ++i) {
            const Real a = xfx[idx2(i,  j,is,jsd,nicrx)] * fx2[idx2(i,  j,is,jsd,nicrx)];
            const Real b = xfx[idx2(i+1,j,is,jsd,nicrx)] * fx2[idx2(i+1,j,is,jsd,nicrx)];
            q_j[idx2(i,j,is,jsd,nirax)] = fv_cross<Real>(
                q[idx2(i,j,isd,jsd,niq)], area[idx2(i,j,isd,jsd,niq)],
                a, b, ra_x[idx2(i,j,is,jsd,nirax)]);
        }

    // ---- fy = yppm(q_j) over columns i = is..ie ----
    for (int i = is; i <= ie; ++i) {
        for (int j = jsd; j <= jed; ++j) ql[j-jsd] = q_j[idx2(i,j,is,jsd,nirax)];
        for (int j = js;  j <= je+1; ++j) cl[j-js]  = cry[idx2(i,j,isd,js, niq)];
        for (int j = jsd; j <= jed; ++j) al[j-jsd] = dya[idx2(i,j,isd,jsd,niq)];
        yppm_col<Real>(fl.data(), ql.data(), cl.data(), ord_ou,
                       js, je, jsd, jed, npx, npy, al.data(),
                       nested, grid_type, lim_fac, s);
        for (int j = js; j <= je+1; ++j) fy[idx2(i,j,is,js,nirax)] = fl[j-js];
    }

    // ---- flux averaging: *xfx/*yfx (non-mass) or *mfx/*mfy (mass) ----
    for (int j = js; j <= je; ++j)
        for (int i = is; i <= ie+1; ++i) {
            const Real wx = use_mass ? mfx[idx2(i,j,is,js,nicrx)]
                                     : xfx[idx2(i,j,is,jsd,nicrx)];
            fx[idx2(i,j,is,js,nicrx)] = fv_avg_flux<Real>(
                fx[idx2(i,j,is,js,nicrx)], fx2[idx2(i,j,is,jsd,nicrx)], wx);
        }
    for (int j = js; j <= je+1; ++j)
        for (int i = is; i <= ie; ++i) {
            const Real wy = use_mass ? mfy[idx2(i,j,is,js,nirax)]
                                     : yfx[idx2(i,j,isd,js,niq)];
            fy[idx2(i,j,is,js,nirax)] = fv_avg_flux<Real>(
                fy[idx2(i,j,is,js,nirax)], fy2[idx2(i,j,isd,js,niq)], wy);
        }
}

} // namespace fv3
