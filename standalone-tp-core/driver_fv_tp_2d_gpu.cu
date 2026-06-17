// driver_fv_tp_2d_gpu.cu — device-resident GPU benchmark for the full fv_tp_2d.
//
//   Usage: fv-tp-2d-driver-gpu <resolution> <iterations>
//
// Same single-tile workload as the Fortran tp-core-driver and the C++ CPU
// driver. Allocates ALL fields (inputs, internals, scratch) on the device
// once, copies inputs once, then runs the orchestrator <iterations> times in a
// timed loop on the default stream (device-resident; no per-iter transfers).
// sum(fx)/sum(fy) cross-check the Fortran and CPU drivers.
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <vector>

#include <cuda_runtime.h>

#include "fv_tp_2d.hpp"
#include "fv_tp_2d_gpu.cuh"

#define CUDA_CHECK(call)                                                       \
    do { cudaError_t _e=(call); if(_e!=cudaSuccess){                           \
        std::fprintf(stderr,"CUDA error %s:%d: %s\n",__FILE__,__LINE__,        \
                     cudaGetErrorString(_e)); std::exit(1);} } while(0)

using Real = float;

int main(int argc, char** argv)
{
    if (argc != 3) { std::fprintf(stderr, "Usage: %s <resolution> <iterations>\n", argv[0]); return 2; }
    const int n = std::atoi(argv[1]);
    const int n_iter = std::atoi(argv[2]);
    if (n < 1 || n_iter < 1) { std::fprintf(stderr, "resolution and iterations must be >= 1\n"); return 2; }

    const int ng = 3, hord = 8;
    const Real lim_fac = Real(1);
    const int is = 1, ie = n, js = 1, je = n;
    const int isd = is-ng, ied = ie+ng, jsd = js-ng, jed = je+ng;
    const int npx = n+1, npy = n+1;

    const int niq = ied-isd+1, nicrx = ie-is+2, nirax = ie-is+1;
    const size_t sz_q   = (size_t)niq   * (jed-jsd+1);
    const size_t sz_crx = (size_t)nicrx * (jed-jsd+1);
    const size_t sz_cry = (size_t)niq   * (je-js+2);
    const size_t sz_rax = (size_t)nirax * (jed-jsd+1);
    const size_t sz_ray = (size_t)niq   * (je-js+1);
    const size_t sz_fx  = (size_t)nicrx * (je-js+1);
    const size_t sz_fy  = (size_t)nirax * (je-js+2);
    const size_t sz_qi  = (size_t)niq   * (je-js+1);
    const size_t sz_qj  = (size_t)nirax * (jed-jsd+1);
    const size_t sz_fx2 = (size_t)nicrx * (jed-jsd+1);
    const size_t sz_fy2 = (size_t)niq   * (je-js+2);

    // Host inputs (match the CPU/Fortran drivers).
    std::vector<Real> hq(sz_q);
    std::vector<Real> hcrx(sz_crx,0.5f), hxfx(sz_crx,0.5f), hcry(sz_cry,0.5f), hyfx(sz_cry,0.5f);
    std::vector<Real> hrax(sz_rax,1.0f), hray(sz_ray,1.0f);
    std::vector<Real> harea(sz_q,1.0f), hdxa(sz_q,1.0f), hdya(sz_q,1.0f);
    std::vector<Real> hfx(sz_fx,0.f), hfy(sz_fy,0.f);
    const float PI = 3.1415927f;
    for (int j = jsd; j <= jed; ++j)
        for (int i = isd; i <= ied; ++i)
            hq[fv3::idx2(i,j,isd,jsd,niq)] = std::sin(PI*float(i*j)/float((npx-1)*(npy-1)));

    std::printf("fv_tp_2d GPU driver: resolution=%d iterations=%d\n", n, n_iter);

    const fv3::FvTpGpuScratch g = fv3::fv_tp_2d_gpu_scratch(is,ie,js,je,isd,ied,jsd,jed);

    Real *q,*crx,*cry,*xfx,*yfx,*ra_x,*ra_y,*area,*dxa,*dya,*fx,*fy,
         *qi,*qj,*fx2,*fy2,*sr,*lines; bool *sb;
    CUDA_CHECK(cudaMalloc(&q,   sz_q  *sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&crx, sz_crx*sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&cry, sz_cry*sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&xfx, sz_crx*sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&yfx, sz_cry*sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&ra_x,sz_rax*sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&ra_y,sz_ray*sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&area,sz_q  *sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&dxa, sz_q  *sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&dya, sz_q  *sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&fx,  sz_fx *sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&fy,  sz_fy *sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&qi,  sz_qi *sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&qj,  sz_qj *sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&fx2, sz_fx2*sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&fy2, sz_fy2*sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&sr,  g.sreal_words*sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&sb,  g.sbool_words*sizeof(bool)));
    CUDA_CHECK(cudaMalloc(&lines, g.line_words*sizeof(Real)));

    CUDA_CHECK(cudaMemcpy(q,   hq.data(),   sz_q  *sizeof(Real), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(crx, hcrx.data(), sz_crx*sizeof(Real), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(cry, hcry.data(), sz_cry*sizeof(Real), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(xfx, hxfx.data(), sz_crx*sizeof(Real), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(yfx, hyfx.data(), sz_cry*sizeof(Real), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ra_x,hrax.data(), sz_rax*sizeof(Real), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ra_y,hray.data(), sz_ray*sizeof(Real), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(area,harea.data(),sz_q  *sizeof(Real), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(dxa, hdxa.data(), sz_q  *sizeof(Real), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(dya, hdya.data(), sz_q  *sizeof(Real), cudaMemcpyHostToDevice));

    auto launch = [&](){
        return fv3::fv_tp_2d_gpu_launch<Real>(
            q, crx, cry, xfx, yfx, ra_x, ra_y, area, dxa, dya, fx, fy,
            qi, qj, fx2, fy2, sr, sb, lines, g,
            is,ie,js,je,isd,ied,jsd,jed, npx,npy, hord, lim_fac,
            false, 0, true,true,true,true);
    };

    CUDA_CHECK(launch());
    CUDA_CHECK(cudaDeviceSynchronize());

    cudaEvent_t start, stop;
    CUDA_CHECK(cudaEventCreate(&start));
    CUDA_CHECK(cudaEventCreate(&stop));
    CUDA_CHECK(cudaEventRecord(start));
    for (int it = 0; it < n_iter; ++it) CUDA_CHECK(launch());
    CUDA_CHECK(cudaEventRecord(stop));
    CUDA_CHECK(cudaEventSynchronize(stop));
    float msf = 0.f; CUDA_CHECK(cudaEventElapsedTime(&msf, start, stop));

    CUDA_CHECK(cudaMemcpy(hfx.data(), fx, sz_fx*sizeof(Real), cudaMemcpyDeviceToHost));
    CUDA_CHECK(cudaMemcpy(hfy.data(), fy, sz_fy*sizeof(Real), cudaMemcpyDeviceToHost));
    double sfx = 0.0, sfy = 0.0;
    for (size_t t = 0; t < sz_fx; ++t) sfx += double(hfx[t]);
    for (size_t t = 0; t < sz_fy; ++t) sfy += double(hfy[t]);

    std::printf("time taken: %.6f s  (%.4f ms/iter over %d iters)\n",
                msf/1000.0, msf/double(n_iter), n_iter);
    std::printf("sum(fx): %.10e , sum(fy): %.10e\n", sfx, sfy);

    cudaEventDestroy(start); cudaEventDestroy(stop);
    cudaFree(q);cudaFree(crx);cudaFree(cry);cudaFree(xfx);cudaFree(yfx);
    cudaFree(ra_x);cudaFree(ra_y);cudaFree(area);cudaFree(dxa);cudaFree(dya);
    cudaFree(fx);cudaFree(fy);cudaFree(qi);cudaFree(qj);cudaFree(fx2);cudaFree(fy2);
    cudaFree(sr);cudaFree(sb);cudaFree(lines);
    return 0;
}
