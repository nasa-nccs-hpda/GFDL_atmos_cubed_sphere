// driver_fv_tp_2d_gpu.cu — device-resident BATCHED GPU benchmark for fv_tp_2d.
//
//   Usage: fv-tp-2d-driver-gpu <resolution> <iterations> [levels]
//
// Processes `levels` independent tiles per orchestrator launch (the batch
// dimension that feeds the line-parallel PPM steps). Allocates all fields for
// all tiles on the device once, copies once, then runs the batched
// orchestrator <iterations> times in a timed loop on the default stream.
// sum(fx)/sum(fy) are summed over all tiles (= levels x the single-tile sum,
// which cross-checks the Fortran/CPU drivers at levels=1).
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
    if (argc < 3 || argc > 4) { std::fprintf(stderr, "Usage: %s <resolution> <iterations> [levels]\n", argv[0]); return 2; }
    const int n = std::atoi(argv[1]);
    const int n_iter = std::atoi(argv[2]);
    const int levels = (argc == 4) ? std::atoi(argv[3]) : 1;
    if (n < 1 || n_iter < 1 || levels < 1) { std::fprintf(stderr, "args must be >= 1\n"); return 2; }

    const int ng = 3, hord = 8;
    const Real lim_fac = Real(1);
    const int is = 1, ie = n, js = 1, je = n;
    const int isd = is-ng, ied = ie+ng, jsd = js-ng, jed = je+ng;
    const int npx = n+1, npy = n+1;
    const int niq = ied-isd+1;

    const fv3::FvTpTiles T = fv3::fv_tp_tiles(is,ie,js,je,isd,ied,jsd,jed);
    const fv3::FvTpGpuScratch g = fv3::fv_tp_2d_gpu_scratch(is,ie,js,je,isd,ied,jsd,jed,levels);
    const size_t B = (size_t)levels;

    std::printf("fv_tp_2d GPU driver: resolution=%d iterations=%d levels=%d\n", n, n_iter, levels);

    // Host inputs (q replicated per tile; uniform fields elsewhere).
    std::vector<Real> hq(B*T.TQ);
    std::vector<Real> hcrx(B*T.TCRX,0.5f), hxfx(B*T.TCRX,0.5f), hcry(B*T.TCRY,0.5f), hyfx(B*T.TCRY,0.5f);
    std::vector<Real> hrax(B*T.TRAX,1.0f), hray(B*T.TRAY,1.0f);
    std::vector<Real> harea(B*T.TQ,1.0f), hdxa(B*T.TQ,1.0f), hdya(B*T.TQ,1.0f);
    std::vector<Real> hfx(B*T.TFX,0.f), hfy(B*T.TFY,0.f);
    const float PI = 3.1415927f;
    for (size_t b = 0; b < B; ++b)
        for (int j = jsd; j <= jed; ++j)
            for (int i = isd; i <= ied; ++i)
                hq[b*T.TQ + fv3::idx2(i,j,isd,jsd,niq)] =
                    std::sin(PI*float(i*j)/float((npx-1)*(npy-1)));

    Real *q,*crx,*cry,*xfx,*yfx,*ra_x,*ra_y,*area,*dxa,*dya,*fx,*fy,
         *qi,*qj,*fx2,*fy2,*sr,*lines; bool *sb;
    CUDA_CHECK(cudaMalloc(&q,   B*T.TQ  *sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&crx, B*T.TCRX*sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&cry, B*T.TCRY*sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&xfx, B*T.TCRX*sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&yfx, B*T.TCRY*sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&ra_x,B*T.TRAX*sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&ra_y,B*T.TRAY*sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&area,B*T.TQ  *sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&dxa, B*T.TQ  *sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&dya, B*T.TQ  *sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&fx,  B*T.TFX *sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&fy,  B*T.TFY *sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&qi,  B*T.TQI *sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&qj,  B*T.TQJ *sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&fx2, B*T.TCRX*sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&fy2, B*T.TCRY*sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&sr,  g.sreal_words*sizeof(Real)));
    CUDA_CHECK(cudaMalloc(&sb,  g.sbool_words*sizeof(bool)));
    CUDA_CHECK(cudaMalloc(&lines, g.line_words*sizeof(Real)));

    CUDA_CHECK(cudaMemcpy(q,   hq.data(),   B*T.TQ  *sizeof(Real), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(crx, hcrx.data(), B*T.TCRX*sizeof(Real), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(cry, hcry.data(), B*T.TCRY*sizeof(Real), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(xfx, hxfx.data(), B*T.TCRX*sizeof(Real), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(yfx, hyfx.data(), B*T.TCRY*sizeof(Real), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ra_x,hrax.data(), B*T.TRAX*sizeof(Real), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ra_y,hray.data(), B*T.TRAY*sizeof(Real), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(area,harea.data(),B*T.TQ  *sizeof(Real), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(dxa, hdxa.data(), B*T.TQ  *sizeof(Real), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(dya, hdya.data(), B*T.TQ  *sizeof(Real), cudaMemcpyHostToDevice));

    auto launch = [&](){
        return fv3::fv_tp_2d_gpu_launch<Real>(
            q, crx, cry, xfx, yfx, ra_x, ra_y, area, dxa, dya, fx, fy,
            qi, qj, fx2, fy2, sr, sb, lines, g, T, levels,
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

    CUDA_CHECK(cudaMemcpy(hfx.data(), fx, B*T.TFX*sizeof(Real), cudaMemcpyDeviceToHost));
    CUDA_CHECK(cudaMemcpy(hfy.data(), fy, B*T.TFY*sizeof(Real), cudaMemcpyDeviceToHost));
    double sfx = 0.0, sfy = 0.0;
    for (size_t t = 0; t < hfx.size(); ++t) sfx += double(hfx[t]);
    for (size_t t = 0; t < hfy.size(); ++t) sfy += double(hfy[t]);

    printf("time taken: %.6f s  (%.4f ms/iter over %d iters)\n",
           msf/1000.0, msf/double(n_iter), n_iter);
    printf("sum(fx): %.10e , sum(fy): %.10e  (over %d tiles)\n", sfx, sfy, levels);

    cudaEventDestroy(start); cudaEventDestroy(stop);
    cudaFree(q);cudaFree(crx);cudaFree(cry);cudaFree(xfx);cudaFree(yfx);
    cudaFree(ra_x);cudaFree(ra_y);cudaFree(area);cudaFree(dxa);cudaFree(dya);
    cudaFree(fx);cudaFree(fy);cudaFree(qi);cudaFree(qj);cudaFree(fx2);cudaFree(fy2);
    cudaFree(sr);cudaFree(sb);cudaFree(lines);
    return 0;
}
