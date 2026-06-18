// test_halo_exchange.cu — validate the device-resident, CUDA-aware-MPI halo
// exchange (halo_exchange_gpu.cuh).
//
// 1-D periodic ring decomposition in i: global domain G = nx*nranks columns,
// each rank owns nx interior columns. The field is initialized from a global
// periodic function f(gi,j); after a device halo exchange, each rank's halo
// cells must equal f at the neighbor's global indices. Halos start as a
// sentinel so an unfilled halo fails loudly.
//
// Run:  srun -n <N> ./test_halo_exchange     (or mpirun -np <N> ...)
// Validates the GPU->GPU MPI path; with one GPU, ranks share device 0
// (intra-node cuda_ipc / self), which still exercises pack / device-MPI / unpack.
#include <cmath>
#include <cstdio>
#include <vector>

#include <cuda_runtime.h>
#include <mpi.h>

#include "halo_exchange_gpu.cuh"

#define CUDA_CHECK(c) do{ cudaError_t _e=(c); if(_e!=cudaSuccess){ \
    std::fprintf(stderr,"[rank %d] CUDA error %s:%d: %s\n",rank,__FILE__,__LINE__,cudaGetErrorString(_e)); \
    MPI_Abort(MPI_COMM_WORLD,1);} }while(0)

static float fval(long gi, int j, long G) {
    return std::sin(2.0f*3.14159265358979f*float(gi)/float(G)) + 0.01f*float(j);
}

int main(int argc, char** argv) {
    MPI_Init(&argc, &argv);
    int rank=0, nranks=1;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &nranks);

    int ndev=0; CUDA_CHECK(cudaGetDeviceCount(&ndev));
    if (ndev < 1) { if(rank==0) std::fprintf(stderr,"no CUDA device\n"); MPI_Abort(MPI_COMM_WORLD,1); }
    CUDA_CHECK(cudaSetDevice(rank % ndev));

    const int nx = (argc>1)?atoi(argv[1]):64;   // interior columns per rank
    const int ny = (argc>2)?atoi(argv[2]):48;
    const int ng = 3;
    const long G = (long)nx * nranks;
    const int ni = nx + 2*ng;
    const int left  = (rank-1+nranks)%nranks;
    const int right = (rank+1)%nranks;
    const float SENT = -999.0f;

    auto QI = [ni,ng](int i,int j){ return (size_t)(i-1+ng) + (size_t)ni*(j-1); };

    // Host field: interior = f(global), halos = sentinel.
    std::vector<float> h_q((size_t)ni*ny, SENT);
    for (int j=1;j<=ny;++j)
        for (int i=1;i<=nx;++i)
            h_q[QI(i,j)] = fval((long)rank*nx + i, j, G);

    float *d_q,*d_ws,*d_es,*d_wr,*d_er;
    const int cnt = ng*ny;
    CUDA_CHECK(cudaMalloc(&d_q, (size_t)ni*ny*sizeof(float)));
    CUDA_CHECK(cudaMalloc(&d_ws, cnt*sizeof(float)));
    CUDA_CHECK(cudaMalloc(&d_es, cnt*sizeof(float)));
    CUDA_CHECK(cudaMalloc(&d_wr, cnt*sizeof(float)));
    CUDA_CHECK(cudaMalloc(&d_er, cnt*sizeof(float)));
    CUDA_CHECK(cudaMemcpy(d_q, h_q.data(), (size_t)ni*ny*sizeof(float), cudaMemcpyHostToDevice));

    fv3::halo_exchange_x<float>(d_q, nx, ny, ng, d_ws, d_es, d_wr, d_er,
                                left, right, MPI_COMM_WORLD, MPI_FLOAT);

    CUDA_CHECK(cudaMemcpy(h_q.data(), d_q, (size_t)ni*ny*sizeof(float), cudaMemcpyDeviceToHost));

    // Verify both halos against the global field at the neighbor's indices.
    double maxerr = 0.0; long bad = 0;
    for (int j=1;j<=ny;++j) {
        for (int c=0;c<ng;++c) {
            const int iw = 1-ng+c, ie = nx+1+c;        // west, east halo columns
            const double ew = std::fabs(h_q[QI(iw,j)] - fval((long)rank*nx + iw, j, G));
            const double ee = std::fabs(h_q[QI(ie,j)] - fval((long)rank*nx + ie, j, G));
            maxerr = std::fmax(maxerr, std::fmax(ew,ee));
            if (ew > 1.e-5 || ee > 1.e-5) ++bad;
        }
    }

    double gmax=0.0; long gbad=0;
    MPI_Reduce(&maxerr,&gmax,1,MPI_DOUBLE,MPI_MAX,0,MPI_COMM_WORLD);
    MPI_Reduce(&bad,&gbad,1,MPI_LONG,MPI_SUM,0,MPI_COMM_WORLD);

    int rc = 0;
    if (rank==0) {
        std::printf("halo exchange: nranks=%d nx=%d ny=%d ng=%d (G=%ld)\n", nranks,nx,ny,ng,G);
        std::printf("max|halo-analytic| = %.3e , bad cells = %ld\n", gmax, gbad);
        if (gbad==0) std::printf("PASS\n"); else { std::printf("FAIL\n"); rc=1; }
    }
    MPI_Bcast(&rc,1,MPI_INT,0,MPI_COMM_WORLD);

    cudaFree(d_q);cudaFree(d_ws);cudaFree(d_es);cudaFree(d_wr);cudaFree(d_er);
    MPI_Finalize();
    return rc;
}
