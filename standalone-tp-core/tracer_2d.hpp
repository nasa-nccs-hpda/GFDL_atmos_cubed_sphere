// tracer_2d.hpp — C++ port of the GPU-parallel compute core of tracer_2d
// (fv_tracer2d.F90), for the nsplt=1, single-tile path on a unit grid.
//
// tracer_2d advects nq tracers over npz levels; its inner body (per level k,
// per tracer iq) is: fv_tp_2d (MASS-flux variant) -> tracer update
//   q = ( q*dp1 + div(fx,fy)*rarea ) / dp2,   dp2 = dp1 + div(mfx,mfy)*rarea
// with ra_x/ra_y and xfx/yfx prepared per level. The GPU win is batching the
// fv_tp_2d calls over the full npz*nq dimension (see tracer_2d_gpu.cuh).
//
// Scope / simplifications (documented):
//   - Unit grid: sin_sg=1, dx=dy=dxa=dya=1, area=rarea=1, so xfx=cx, yfx=cy.
//     (Real metrics would be passed in the model; GPU parallelism is identical.)
//   - nsplt=1 (no Courant sub-cycling), no MPI halo exchange, no deln_flux.
//     Those are the host-side orchestration seam (loop + halo) deferred per the
//     port plan. This captures the device-resident, tracer-scaling compute.
//
// Array layouts (Fortran column-major, per-level tiles stacked over k, then nq):
//   q  (isd:ied,jsd:jed,npz,nq)  q(i,j,k,iq) = (iq*npz+k)*Tq + idx2(i,j,isd,jsd,niq)
//   dp1(isd:ied,jsd:jed,npz)     dp1(i,j,k)  = k*Tq        + idx2(i,j,isd,jsd,niq)
//   cx (is:ie+1,jsd:jed,npz)     cx(i,j,k)   = k*Tcx       + idx2(i,j,is,jsd,nicrx)
//   cy (isd:ied,js:je+1,npz)     cy(i,j,k)   = k*Tcy       + idx2(i,j,isd,js,niq)
//   mfx(is:ie+1,js:je,npz)       mfx(i,j,k)  = k*Tmfx      + idx2(i,j,is,js,nicrx)
//   mfy(is:ie,js:je+1,npz)       mfy(i,j,k)  = k*Tmfy      + idx2(i,j,is,js,nirax)
#pragma once

#include "fv_tp_2d.hpp"
#include <vector>

namespace fv3 {

// Shared device cell ops (single source for CPU and GPU).
template <typename Real>
YPPM_HOST_DEVICE YPPM_INLINE Real trc_div(Real a_i, Real a_ip, Real b_j, Real b_jp) {
    return (a_i - a_ip) + (b_j - b_jp);   // div(flux) numerator, *rarea applied by caller
}
template <typename Real>
YPPM_HOST_DEVICE YPPM_INLINE Real trc_update(Real q, Real dp1, Real fluxdiv, Real rarea, Real dp2) {
    return (q * dp1 + fluxdiv * rarea) / dp2;
}

// Per-level tile element counts (unit grid: area/dxa/dya all 1).
struct TracerTiles { int Tq, Tcx, Tcy, Tmfx, Tmfy, Tfx, Tfy, Trax, Tray; int niq, njq, nicrx, nicry, nirax; };
inline TracerTiles tracer_tiles(int is,int ie,int js,int je,int isd,int ied,int jsd,int jed) {
    const int niq=ied-isd+1, njq=jed-jsd+1, nicrx=ie-is+2, nirax=ie-is+1;
    TracerTiles t;
    t.niq=niq; t.njq=njq; t.nicrx=nicrx; t.nicry=niq; t.nirax=nirax;
    t.Tq   = niq*njq;
    t.Tcx  = nicrx*njq;
    t.Tcy  = niq*(je-js+2);
    t.Tmfx = nicrx*(je-js+1);
    t.Tmfy = nirax*(je-js+2);
    t.Tfx  = nicrx*(je-js+1);
    t.Tfy  = nirax*(je-js+2);
    t.Trax = nirax*njq;          // ra_x (is:ie, jsd:jed)
    t.Tray = niq*(je-js+1);      // ra_y (isd:ied, js:je)
    return t;
}

// ---------------------------------------------------------------------------
// CPU reference: tracer_2d compute core (nsplt=1, unit grid).
// q is updated in place; corners of each q(:,:,k,iq) are touched by fv_tp_2d.
// ---------------------------------------------------------------------------
template <typename Real>
void tracer_2d_cpu(
    Real*       q,      // (isd:ied,jsd:jed,npz,nq)  inout
    const Real* dp1,    // (isd:ied,jsd:jed,npz)
    const Real* cx,     // (is:ie+1,jsd:jed,npz)
    const Real* cy,     // (isd:ied,js:je+1,npz)
    const Real* mfx,    // (is:ie+1,js:je,npz)
    const Real* mfy,    // (is:ie,js:je+1,npz)
    int is, int ie, int js, int je, int isd, int ied, int jsd, int jed,
    int npx, int npy, int npz, int nq, int hord, Real lim_fac,
    bool nested, int grid_type, bool sw, bool se, bool nw, bool ne)
{
    const TracerTiles T = tracer_tiles(is,ie,js,je,isd,ied,jsd,jed);
    const int niq=T.niq, nicrx=T.nicrx, nirax=T.nirax;
    const Real rarea = Real(1);

    // Unit metric arrays (one level tile) reused for every fv_tp_2d call.
    std::vector<Real> unit(static_cast<size_t>(T.Tq), Real(1)); // area/dxa/dya

    // Per-level prep + per-tracer transport/update.
    std::vector<Real> dp2(static_cast<size_t>((ie-is+1)*(je-js+1)));   // (is:ie,js:je)
    std::vector<Real> ra_x(static_cast<size_t>(T.Trax));              // (is:ie,jsd:jed)
    std::vector<Real> ra_y(static_cast<size_t>(T.Tray));              // (isd:ied,js:je)
    std::vector<Real> fx(static_cast<size_t>(T.Tfx)), fy(static_cast<size_t>(T.Tfy));
    const int nfx = nicrx, ndp2 = ie-is+1;

    for (int k = 0; k < npz; ++k) {
        const Real* cxk  = cx  + static_cast<size_t>(k)*T.Tcx;
        const Real* cyk  = cy  + static_cast<size_t>(k)*T.Tcy;
        const Real* mfxk = mfx + static_cast<size_t>(k)*T.Tmfx;
        const Real* mfyk = mfy + static_cast<size_t>(k)*T.Tmfy;
        const Real* dp1k = dp1 + static_cast<size_t>(k)*T.Tq;

        // dp2 = dp1 + div(mfx,mfy)*rarea     (is:ie, js:je)
        for (int j = js; j <= je; ++j)
            for (int i = is; i <= ie; ++i)
                dp2[(i-is) + ndp2*(j-js)] = dp1k[idx2(i,j,isd,jsd,niq)] + rarea * trc_div<Real>(
                    mfxk[idx2(i,j,is,js,nicrx)], mfxk[idx2(i+1,j,is,js,nicrx)],
                    mfyk[idx2(i,j,is,js,nirax)], mfyk[idx2(i,j+1,is,js,nirax)]);

        // ra_x = 1 + (xfx(i)-xfx(i+1)),  xfx=cx   (is:ie, jsd:jed)
        for (int j = jsd; j <= jed; ++j)
            for (int i = is; i <= ie; ++i)
                ra_x[(i-is) + nirax*(j-jsd)] = Real(1) +
                    (cxk[idx2(i,j,is,jsd,nicrx)] - cxk[idx2(i+1,j,is,jsd,nicrx)]);
        // ra_y = 1 + (yfx(j)-yfx(j+1)),  yfx=cy   (isd:ied, js:je)
        for (int j = js; j <= je; ++j)
            for (int i = isd; i <= ied; ++i)
                ra_y[(i-isd) + niq*(j-js)] = Real(1) +
                    (cyk[idx2(i,j,isd,js,niq)] - cyk[idx2(i,j+1,isd,js,niq)]);

        for (int iq = 0; iq < nq; ++iq) {
            Real* qkiq = q + (static_cast<size_t>(iq)*npz + k) * T.Tq;

            // fv_tp_2d (mass-flux variant): crx=xfx=cx, cry=yfx=cy on unit grid.
            fv_tp_2d_cpu<Real>(
                qkiq, cxk, cyk, cxk, cyk, ra_x.data(), ra_y.data(),
                unit.data(), unit.data(), unit.data(), fx.data(), fy.data(),
                is,ie,js,je,isd,ied,jsd,jed, npx,npy, hord, lim_fac,
                nested, grid_type, sw,se,nw,ne,
                /*use_mass*/true, mfxk, mfyk);

            // tracer update over (is:ie, js:je)
            for (int j = js; j <= je; ++j)
                for (int i = is; i <= ie; ++i) {
                    const Real fd = trc_div<Real>(
                        fx[idx2(i,j,is,js,nfx)], fx[idx2(i+1,j,is,js,nfx)],
                        fy[idx2(i,j,is,js,nirax)], fy[idx2(i,j+1,is,js,nirax)]);
                    qkiq[idx2(i,j,isd,jsd,niq)] = trc_update<Real>(
                        qkiq[idx2(i,j,isd,jsd,niq)], dp1k[idx2(i,j,isd,jsd,niq)],
                        fd, rarea, dp2[(i-is) + ndp2*(j-js)]);
                }
        }
    }
}

} // namespace fv3
