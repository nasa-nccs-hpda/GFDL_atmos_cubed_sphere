// transform_gpu.cu — see transform_gpu.h.
//
// Data layouts on device
//   d_spectral [(m*nn + n)*nlev + k]            cuDoubleComplex  (matches CPU ref)
//   d_fspec    [(lat*nlev + k)*lenc + m]        cuDoubleComplex  (FFT-contiguous)
//   d_grid     [(lat*nlev + k)*N   + x]         double
//
// Legendre operands are precomputed column-major, batched per m:
//   forward  A_even[m][jh + ne*NHEM]  = legendre(m, 2*ne,   jh)    (M=NHEM,K=nE)
//   forward  A_odd [m][jh + no*NHEM]  = legendre(m, 2*no+1, jh)    (M=NHEM,K=nO)
//   inverse  W_even[m][ne + jh*nE]    = legendre_wts(m, 2*ne,   jh)(M=nE,  K=NHEM)
//   inverse  W_odd [m][no + jh*nO]    = legendre_wts(m, 2*no+1, jh)(M=nO,  K=NHEM)

#include "transform_gpu.h"

#include <cublas_v2.h>
#include <cufft.h>
#include <cuComplex.h>
#include <cuda_runtime.h>

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <stdexcept>

namespace transforms {

#define CUDA_CHECK(x) do { cudaError_t e_=(x); if(e_!=cudaSuccess){ \
    fprintf(stderr,"CUDA %s:%d %s\n",__FILE__,__LINE__,cudaGetErrorString(e_)); \
    throw std::runtime_error("cuda"); } } while(0)
#define CUBLAS_CHECK(x) do { cublasStatus_t s_=(x); if(s_!=CUBLAS_STATUS_SUCCESS){ \
    fprintf(stderr,"cuBLAS %s:%d status %d\n",__FILE__,__LINE__,(int)s_); \
    throw std::runtime_error("cublas"); } } while(0)
#define CUFFT_CHECK(x) do { cufftResult r_=(x); if(r_!=CUFFT_SUCCESS){ \
    fprintf(stderr,"cuFFT %s:%d result %d\n",__FILE__,__LINE__,(int)r_); \
    throw std::runtime_error("cufft"); } } while(0)

// ------------------------------- kernels -----------------------------------
// Pack spectral(m,n,k) into even/odd column-major GEMM operands.
__global__ void k_pack_spec(const cuDoubleComplex* spec, cuDoubleComplex* Be,
                            cuDoubleComplex* Bo, int m0, int m1, int nn,
                            int nlev, int nE, int nO) {
    int k = blockIdx.x * blockDim.x + threadIdx.x;
    int m = blockIdx.y + m0;
    if (k >= nlev || m >= m1) return;
    for (int ne = 0; ne < nE; ++ne)
        Be[(size_t)m * nE * nlev + ne + k * nE] =
            spec[((size_t)m * nn + 2 * ne) * nlev + k];
    for (int no = 0; no < nO; ++no)
        Bo[(size_t)m * nO * nlev + no + k * nO] =
            spec[((size_t)m * nn + 2 * no + 1) * nlev + k];
}

// Combine Xeven/Xodd (per m, [jh + k*NHEM]) into d_fspec at south/north lats.
__global__ void k_combine_fwd(const cuDoubleComplex* Xe, const cuDoubleComplex* Xo,
                              cuDoubleComplex* fspec, int m0, int m1, int nhem,
                              int nlev, int lenc, int lat_max) {
    int k = blockIdx.x * blockDim.x + threadIdx.x;
    int jh = blockIdx.y;
    int m = blockIdx.z + m0;
    if (k >= nlev || jh >= nhem || m >= m1) return;
    size_t off = (size_t)m * nhem * nlev + jh + k * nhem;
    cuDoubleComplex xe = Xe[off], xo = Xo[off];
    int south = jh, north = lat_max - 1 - jh;
    fspec[((size_t)south * nlev + k) * lenc + m] = cuCsub(xe, xo);
    fspec[((size_t)north * nlev + k) * lenc + m] = cuCadd(xe, xo);
}

// Zero the truncation pad (m in [nm, lenc)) for every (lat,k).
__global__ void k_pad_fourier(cuDoubleComplex* fspec, int nm, int lenc,
                              int nlev, int lat_max) {
    int m = nm + blockIdx.x * blockDim.x + threadIdx.x;
    int lk = blockIdx.y * blockDim.y + threadIdx.y;  // lat*nlev + k
    if (m >= lenc || lk >= lat_max * nlev) return;
    fspec[(size_t)lk * lenc + m] = make_cuDoubleComplex(0.0, 0.0);
}

// Scale D2Z output by 1/N (analysis normalization), over lat-range * nlev.
__global__ void k_scale_fourier(cuDoubleComplex* fspec, double inv_n, int lat0,
                                int lat1, int nlev, int lenc) {
    int m = blockIdx.x * blockDim.x + threadIdx.x;
    int lk = blockIdx.y * blockDim.y + threadIdx.y;  // index into [lat0,lat1)*nlev
    int total = (lat1 - lat0) * nlev;
    if (m >= lenc || lk >= total) return;
    size_t base = (size_t)(lat0 * nlev + lk) * lenc + m;
    fspec[base] = make_cuDoubleComplex(cuCreal(fspec[base]) * inv_n,
                                       cuCimag(fspec[base]) * inv_n);
}

// Build Xe = fspec(north)+fspec(south), Xo = fspec(north)-fspec(south).
__global__ void k_build_xe_xo(const cuDoubleComplex* fspec, cuDoubleComplex* Xe,
                              cuDoubleComplex* Xo, int m0, int m1, int nhem,
                              int nlev, int lenc, int lat_max) {
    int k = blockIdx.x * blockDim.x + threadIdx.x;
    int jh = blockIdx.y;
    int m = blockIdx.z + m0;
    if (k >= nlev || jh >= nhem || m >= m1) return;
    int south = jh, north = lat_max - 1 - jh;
    cuDoubleComplex fs = fspec[((size_t)south * nlev + k) * lenc + m];
    cuDoubleComplex fn = fspec[((size_t)north * nlev + k) * lenc + m];
    size_t off = (size_t)m * nhem * nlev + jh + k * nhem;
    Xe[off] = cuCadd(fn, fs);
    Xo[off] = cuCsub(fn, fs);
}

// Scatter Spec_even/odd GEMM results back into spectral(m,n,k).
__global__ void k_unpack_spec(cuDoubleComplex* spec, const cuDoubleComplex* Se,
                              const cuDoubleComplex* So, int m0, int m1, int nn,
                              int nlev, int nE, int nO) {
    int k = blockIdx.x * blockDim.x + threadIdx.x;
    int m = blockIdx.y + m0;
    if (k >= nlev || m >= m1) return;
    for (int ne = 0; ne < nE; ++ne)
        spec[((size_t)m * nn + 2 * ne) * nlev + k] =
            Se[(size_t)m * nE * nlev + ne + k * nE];
    for (int no = 0; no < nO; ++no)
        spec[((size_t)m * nn + 2 * no + 1) * nlev + k] =
            So[(size_t)m * nO * nlev + no + k * nO];
}

// ------------------------------- Impl --------------------------------------
struct GpuTransform::Impl {
    Config cfg;
    Tile tile;
    int nE, nO, NHEM, nlev, nm, nn, lenc, N, lat_max;

    cublasHandle_t blas;
    cufftHandle plan_z2d, plan_d2z;   // sized to tile lat-range * nlev
    int fft_batch;

    // device buffers
    cuDoubleComplex *d_spec, *d_fspec;
    double *d_grid;
    cuDoubleComplex *d_Be, *d_Bo, *d_Xe, *d_Xo, *d_Se, *d_So;
    cuDoubleComplex *d_Af_e, *d_Af_o;  // forward Legendre operands
    cuDoubleComplex *d_Wi_e, *d_Wi_o;  // inverse Legendre operands

    void *h_stage;      // pinned host staging buffer for transfer-inclusive timing
    size_t h_stage_bytes;

    cudaEvent_t ev0, ev1;

    Impl(const Tables& t, const Tile& tl) : cfg(t.cfg), tile(tl) {
        nE = cfg.num_spherical / 2 + 1;
        nO = (cfg.num_spherical + 1) / 2;
        NHEM = cfg.nhem(); nlev = cfg.num_levels; nm = cfg.nm();
        nn = cfg.nn(); lenc = cfg.lenc(); N = cfg.lon_max; lat_max = cfg.lat_max;
        fft_batch = (tile.lat1 - tile.lat0) * nlev;

        CUBLAS_CHECK(cublasCreate(&blas));
        // cuFFT batched plans over the tile's latitude range.
        int nfft[1] = {N};
        int inembed_c[1] = {lenc}, onembed_r[1] = {N};
        CUFFT_CHECK(cufftPlanMany(&plan_z2d, 1, nfft,
                                  inembed_c, 1, lenc, onembed_r, 1, N,
                                  CUFFT_Z2D, fft_batch));
        int inembed_r[1] = {N}, onembed_c[1] = {lenc};
        CUFFT_CHECK(cufftPlanMany(&plan_d2z, 1, nfft,
                                  inembed_r, 1, N, onembed_c, 1, lenc,
                                  CUFFT_D2Z, fft_batch));

        alloc();
        upload_operands(t);
        // pinned staging buffer >= the largest single-stage transfer volume
        h_stage_bytes = (size_t)lat_max * nlev * lenc * sizeof(cuDoubleComplex);
        CUDA_CHECK(cudaMallocHost(&h_stage, h_stage_bytes));
        CUDA_CHECK(cudaEventCreate(&ev0));
        CUDA_CHECK(cudaEventCreate(&ev1));
    }
    ~Impl() {
        cudaFree(d_spec); cudaFree(d_fspec); cudaFree(d_grid);
        cudaFree(d_Be); cudaFree(d_Bo); cudaFree(d_Xe); cudaFree(d_Xo);
        cudaFree(d_Se); cudaFree(d_So);
        cudaFree(d_Af_e); cudaFree(d_Af_o); cudaFree(d_Wi_e); cudaFree(d_Wi_o);
        cudaFreeHost(h_stage);
        cufftDestroy(plan_z2d); cufftDestroy(plan_d2z);
        cublasDestroy(blas);
        cudaEventDestroy(ev0); cudaEventDestroy(ev1);
    }

    void alloc() {
        auto zc = [](cuDoubleComplex** p, size_t n) {
            CUDA_CHECK(cudaMalloc(p, n * sizeof(cuDoubleComplex)));
            CUDA_CHECK(cudaMemset(*p, 0, n * sizeof(cuDoubleComplex)));
        };
        zc(&d_spec, (size_t)nm * nn * nlev);
        zc(&d_fspec, (size_t)lat_max * nlev * lenc);
        CUDA_CHECK(cudaMalloc(&d_grid, (size_t)lat_max * nlev * N * sizeof(double)));
        CUDA_CHECK(cudaMemset(d_grid, 0, (size_t)lat_max * nlev * N * sizeof(double)));
        zc(&d_Be, (size_t)nm * nE * nlev);
        zc(&d_Bo, (size_t)nm * nO * nlev);
        zc(&d_Xe, (size_t)nm * NHEM * nlev);
        zc(&d_Xo, (size_t)nm * NHEM * nlev);
        zc(&d_Se, (size_t)nm * nE * nlev);
        zc(&d_So, (size_t)nm * nO * nlev);
        zc(&d_Af_e, (size_t)nm * NHEM * nE);
        zc(&d_Af_o, (size_t)nm * NHEM * nO);
        zc(&d_Wi_e, (size_t)nm * nE * NHEM);
        zc(&d_Wi_o, (size_t)nm * nO * NHEM);
    }

    // Build column-major Legendre operands on host, upload once.
    void upload_operands(const Tables& t) {
        std::vector<cuDoubleComplex> Afe((size_t)nm * NHEM * nE);
        std::vector<cuDoubleComplex> Afo((size_t)nm * NHEM * nO);
        std::vector<cuDoubleComplex> Wie((size_t)nm * nE * NHEM);
        std::vector<cuDoubleComplex> Wio((size_t)nm * nO * NHEM);
        for (int m = 0; m < nm; ++m)
            for (int jh = 0; jh < NHEM; ++jh) {
                for (int ne = 0; ne < nE; ++ne) {
                    double L = t.legendre[t.idx(m, 2 * ne, jh)];
                    double W = t.legendre_wts[t.idx(m, 2 * ne, jh)];
                    Afe[(size_t)m * NHEM * nE + jh + ne * NHEM] =
                        make_cuDoubleComplex(L, 0.0);
                    Wie[(size_t)m * nE * NHEM + ne + jh * nE] =
                        make_cuDoubleComplex(W, 0.0);
                }
                for (int no = 0; no < nO; ++no) {
                    double L = t.legendre[t.idx(m, 2 * no + 1, jh)];
                    double W = t.legendre_wts[t.idx(m, 2 * no + 1, jh)];
                    Afo[(size_t)m * NHEM * nO + jh + no * NHEM] =
                        make_cuDoubleComplex(L, 0.0);
                    Wio[(size_t)m * nO * NHEM + no + jh * nO] =
                        make_cuDoubleComplex(W, 0.0);
                }
            }
        auto cp = [](cuDoubleComplex* d, std::vector<cuDoubleComplex>& h) {
            CUDA_CHECK(cudaMemcpy(d, h.data(), h.size() * sizeof(cuDoubleComplex),
                                  cudaMemcpyHostToDevice));
        };
        cp(d_Af_e, Afe); cp(d_Af_o, Afo); cp(d_Wi_e, Wie); cp(d_Wi_o, Wio);
    }

    // ---- device stage runners (assume inputs resident) -------------------
    void run_legendre_fwd() {
        int m0 = tile.m0, m1 = tile.m1, nmt = m1 - m0;
        dim3 tb(32), gb((nlev + 31) / 32, nmt);
        k_pack_spec<<<gb, tb>>>(d_spec, d_Be, d_Bo, m0, m1, nn, nlev, nE, nO);
        cuDoubleComplex one = make_cuDoubleComplex(1, 0), zero = make_cuDoubleComplex(0, 0);
        // even: C(NHEM x nlev) = A(NHEM x nE) * B(nE x nlev), batched over m
        CUBLAS_CHECK(cublasZgemmStridedBatched(blas, CUBLAS_OP_N, CUBLAS_OP_N,
            NHEM, nlev, nE, &one,
            d_Af_e + (size_t)m0 * NHEM * nE, NHEM, (long long)NHEM * nE,
            d_Be + (size_t)m0 * nE * nlev, nE, (long long)nE * nlev,
            &zero, d_Xe + (size_t)m0 * NHEM * nlev, NHEM, (long long)NHEM * nlev,
            nmt));
        CUBLAS_CHECK(cublasZgemmStridedBatched(blas, CUBLAS_OP_N, CUBLAS_OP_N,
            NHEM, nlev, nO, &one,
            d_Af_o + (size_t)m0 * NHEM * nO, NHEM, (long long)NHEM * nO,
            d_Bo + (size_t)m0 * nO * nlev, nO, (long long)nO * nlev,
            &zero, d_Xo + (size_t)m0 * NHEM * nlev, NHEM, (long long)NHEM * nlev,
            nmt));
        dim3 gc((nlev + 31) / 32, NHEM, nmt);
        k_combine_fwd<<<gc, tb>>>(d_Xe, d_Xo, d_fspec, m0, m1, NHEM, nlev, lenc, lat_max);
        dim3 tp(32, 8), gp((lenc - nm + 31) / 32, (lat_max * nlev + 7) / 8);
        if (lenc > nm)
            k_pad_fourier<<<gp, tp>>>(d_fspec, nm, lenc, nlev, lat_max);
    }

    void run_fft_inv() {
        CUFFT_CHECK(cufftExecZ2D(plan_z2d,
            d_fspec + (size_t)tile.lat0 * nlev * lenc,
            d_grid + (size_t)tile.lat0 * nlev * N));
    }

    void run_fft_fwd() {
        CUFFT_CHECK(cufftExecD2Z(plan_d2z,
            d_grid + (size_t)tile.lat0 * nlev * N,
            d_fspec + (size_t)tile.lat0 * nlev * lenc));
        dim3 tb(32, 8), gb((lenc + 31) / 32, (fft_batch + 7) / 8);
        k_scale_fourier<<<gb, tb>>>(d_fspec, 1.0 / double(N), tile.lat0, tile.lat1,
                                    nlev, lenc);
    }

    void run_legendre_inv() {
        int m0 = tile.m0, m1 = tile.m1, nmt = m1 - m0;
        dim3 tb(32), gx((nlev + 31) / 32, NHEM, nmt);
        k_build_xe_xo<<<gx, tb>>>(d_fspec, d_Xe, d_Xo, m0, m1, NHEM, nlev, lenc, lat_max);
        cuDoubleComplex one = make_cuDoubleComplex(1, 0), zero = make_cuDoubleComplex(0, 0);
        // even: C(nE x nlev) = W(nE x NHEM) * Xe(NHEM x nlev), batched over m
        CUBLAS_CHECK(cublasZgemmStridedBatched(blas, CUBLAS_OP_N, CUBLAS_OP_N,
            nE, nlev, NHEM, &one,
            d_Wi_e + (size_t)m0 * nE * NHEM, nE, (long long)nE * NHEM,
            d_Xe + (size_t)m0 * NHEM * nlev, NHEM, (long long)NHEM * nlev,
            &zero, d_Se + (size_t)m0 * nE * nlev, nE, (long long)nE * nlev, nmt));
        CUBLAS_CHECK(cublasZgemmStridedBatched(blas, CUBLAS_OP_N, CUBLAS_OP_N,
            nO, nlev, NHEM, &one,
            d_Wi_o + (size_t)m0 * nO * NHEM, nO, (long long)nO * NHEM,
            d_Xo + (size_t)m0 * NHEM * nlev, NHEM, (long long)NHEM * nlev,
            &zero, d_So + (size_t)m0 * nO * nlev, nO, (long long)nO * nlev, nmt));
        dim3 gb((nlev + 31) / 32, nmt);
        k_unpack_spec<<<gb, tb>>>(d_spec, d_Se, d_So, m0, m1, nn, nlev, nE, nO);
    }
};

// ------------------------------- public API --------------------------------
GpuTransform::GpuTransform(const Tables& tables, const Tile& tile)
    : cfg_(tables.cfg), tile_(tile) {
    p_ = new Impl(tables, tile);
}
GpuTransform::~GpuTransform() { delete p_; }

void GpuTransform::round_trip(const std::vector<cd>& spectral_in,
                              std::vector<cd>& spectral_out, double& total_ms) {
    Impl& I = *p_;
    CUDA_CHECK(cudaEventRecord(I.ev0));
    CUDA_CHECK(cudaMemcpy(I.d_spec, spectral_in.data(),
                          spectral_in.size() * sizeof(cd), cudaMemcpyHostToDevice));
    I.run_legendre_fwd();
    I.run_fft_inv();
    I.run_fft_fwd();
    I.run_legendre_inv();
    spectral_out.resize(spectral_in.size());
    CUDA_CHECK(cudaMemcpy(spectral_out.data(), I.d_spec,
                          spectral_out.size() * sizeof(cd), cudaMemcpyDeviceToHost));
    CUDA_CHECK(cudaEventRecord(I.ev1));
    CUDA_CHECK(cudaEventSynchronize(I.ev1));
    float ms = 0; CUDA_CHECK(cudaEventElapsedTime(&ms, I.ev0, I.ev1));
    total_ms = ms;
}

// Timing helper: run `fn` iters times, kernel-only vs transfer-inclusive.
template <class KFn, class XFn>
static StageTiming time_stage(GpuTransform::Impl& I, int iters, long long flops,
                              long long b_h2d, long long b_d2h,
                              KFn kernels, XFn xfer) {
    StageTiming t; t.flops = flops; t.bytes_h2d = b_h2d; t.bytes_d2h = b_d2h;
    kernels(); CUDA_CHECK(cudaDeviceSynchronize());  // warmup
    CUDA_CHECK(cudaEventRecord(I.ev0));
    for (int i = 0; i < iters; ++i) kernels();
    CUDA_CHECK(cudaEventRecord(I.ev1));
    CUDA_CHECK(cudaEventSynchronize(I.ev1));
    float ms = 0; CUDA_CHECK(cudaEventElapsedTime(&ms, I.ev0, I.ev1));
    t.kernel_ms = ms / iters;
    CUDA_CHECK(cudaEventRecord(I.ev0));
    for (int i = 0; i < iters; ++i) xfer();
    CUDA_CHECK(cudaEventRecord(I.ev1));
    CUDA_CHECK(cudaEventSynchronize(I.ev1));
    ms = 0; CUDA_CHECK(cudaEventElapsedTime(&ms, I.ev0, I.ev1));
    t.xfer_ms = ms / iters;
    return t;
}

// Genuine H2D of b_h2d bytes into `din`, run kernels, D2H b_d2h bytes from
// `dout` — the naive per-call offload the study is testing for the transfer trap.
StageTiming GpuTransform::time_legendre_fwd(int iters) {
    Impl& I = *p_;
    int nmt = tile_.m1 - tile_.m0;
    long long flops = 8LL * I.NHEM * I.nlev * (I.nE + I.nO) * nmt;  // 2 complex GEMMs
    long long h2d = (long long)nmt * I.nn * I.nlev * sizeof(cd);
    long long d2h = (long long)2 * I.NHEM * I.nlev * nmt * sizeof(cd);
    void* din = I.d_spec + (size_t)tile_.m0 * I.nn * I.nlev;
    return time_stage(I, iters, flops, h2d, d2h,
        [&]{ I.run_legendre_fwd(); },
        [&]{ CUDA_CHECK(cudaMemcpy(din, I.h_stage, h2d, cudaMemcpyHostToDevice));
             I.run_legendre_fwd();
             CUDA_CHECK(cudaMemcpy(I.h_stage, I.d_fspec, d2h, cudaMemcpyDeviceToHost)); });
}

StageTiming GpuTransform::time_legendre_inv(int iters) {
    Impl& I = *p_;
    int nmt = tile_.m1 - tile_.m0;
    long long flops = 8LL * (I.nE + I.nO) * I.nlev * I.NHEM * nmt;
    long long h2d = (long long)2 * I.NHEM * I.nlev * nmt * sizeof(cd);
    long long d2h = (long long)nmt * I.nn * I.nlev * sizeof(cd);
    void* dout = I.d_spec + (size_t)tile_.m0 * I.nn * I.nlev;
    return time_stage(I, iters, flops, h2d, d2h,
        [&]{ I.run_legendre_inv(); },
        [&]{ CUDA_CHECK(cudaMemcpy(I.d_fspec, I.h_stage, h2d, cudaMemcpyHostToDevice));
             I.run_legendre_inv();
             CUDA_CHECK(cudaMemcpy(I.h_stage, dout, d2h, cudaMemcpyDeviceToHost)); });
}

StageTiming GpuTransform::time_fft_inv(int iters) {
    Impl& I = *p_;
    double lg = std::log2((double)I.N);
    long long flops = (long long)(2.5 * I.N * lg) * I.fft_batch;  // real FFT nominal
    long long h2d = (long long)I.fft_batch * I.lenc * sizeof(cd);
    long long d2h = (long long)I.fft_batch * I.N * sizeof(double);
    void* din = I.d_fspec + (size_t)tile_.lat0 * I.nlev * I.lenc;
    void* dout = I.d_grid + (size_t)tile_.lat0 * I.nlev * I.N;
    return time_stage(I, iters, flops, h2d, d2h,
        [&]{ I.run_fft_inv(); },
        [&]{ CUDA_CHECK(cudaMemcpy(din, I.h_stage, h2d, cudaMemcpyHostToDevice));
             I.run_fft_inv();
             CUDA_CHECK(cudaMemcpy(I.h_stage, dout, d2h, cudaMemcpyDeviceToHost)); });
}

StageTiming GpuTransform::time_fft_fwd(int iters) {
    Impl& I = *p_;
    double lg = std::log2((double)I.N);
    long long flops = (long long)(2.5 * I.N * lg) * I.fft_batch;
    long long h2d = (long long)I.fft_batch * I.N * sizeof(double);
    long long d2h = (long long)I.fft_batch * I.lenc * sizeof(cd);
    void* din = I.d_grid + (size_t)tile_.lat0 * I.nlev * I.N;
    void* dout = I.d_fspec + (size_t)tile_.lat0 * I.nlev * I.lenc;
    return time_stage(I, iters, flops, h2d, d2h,
        [&]{ I.run_fft_fwd(); },
        [&]{ CUDA_CHECK(cudaMemcpy(din, I.h_stage, h2d, cudaMemcpyHostToDevice));
             I.run_fft_fwd();
             CUDA_CHECK(cudaMemcpy(I.h_stage, dout, d2h, cudaMemcpyDeviceToHost)); });
}

}  // namespace transforms
