// halo_exchange_gpu.cuh — device-resident halo exchange via CUDA-aware MPI.
//
// The GPU-MPI primitive that production tracer_2d / d_sw need: exchange the
// halo of a device-resident 2-D field with neighbor ranks WITHOUT staging
// through host memory. A CUDA kernel packs the strided edge cells into a
// contiguous device buffer; MPI_Isend/Irecv are called on the DEVICE pointers
// (CUDA-aware MPI / UCX moves GPU->GPU via cuda_ipc or GPUDirect RDMA); a CUDA
// kernel unpacks into the halo. No host round-trip, no directives.
//
// This validates the mechanism on a simple 1-D periodic ring decomposition in
// the i-direction (the FV3 cubed-sphere topology itself is handled by FMS; the
// transferable part is the pack / device-MPI / unpack pattern).
//
// Local field q is column-major (i fastest), bounds (1-ng:nx+ng, 1:ny), so
// ni = nx + 2*ng and q(i,j) is at (i-(1-ng)) + ni*(j-1) = (i-1+ng) + ni*(j-1).
// Edges are ng columns; a buffer holds ng*ny values as buf[c*ny + (j-1)].
#pragma once

#include <cuda_runtime.h>
#include <mpi.h>

namespace fv3 {

// Pack ng columns starting at column col0 into a contiguous buffer.
template <typename Real>
__global__ void halo_pack_kernel(const Real* q, Real* buf, int ni, int ng, int ny, int col0) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= ng * ny) return;
    const int c = idx / ny, jj = idx % ny;          // column 0..ng-1, row 0..ny-1
    buf[idx] = q[(col0 + c - 1 + ng) + ni * jj];
}

// Unpack a contiguous buffer into ng halo columns starting at column halo0.
template <typename Real>
__global__ void halo_unpack_kernel(Real* q, const Real* buf, int ni, int ng, int ny, int halo0) {
    const int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx >= ng * ny) return;
    const int c = idx / ny, jj = idx % ny;
    q[(halo0 + c - 1 + ng) + ni * jj] = buf[idx];
}

// Exchange the i-direction halo of d_q with left/right neighbors.
//   interior columns 1..nx, halos [1-ng..0] (west) and [nx+1..nx+ng] (east).
//   Sends east edge -> right, west edge -> left; fills west halo from left,
//   east halo from right.  All buffers are DEVICE pointers (CUDA-aware MPI).
//   d_*_send/d_*_recv must each hold ng*ny elements.
template <typename Real>
inline void halo_exchange_x(
    Real* d_q, int nx, int ny, int ng,
    Real* d_w_send, Real* d_e_send, Real* d_w_recv, Real* d_e_recv,
    int left, int right, MPI_Comm comm, MPI_Datatype dt,
    int tpb = 128, cudaStream_t stream = 0)
{
    const int ni  = nx + 2 * ng;
    const int cnt = ng * ny;
    const int nb  = (cnt + tpb - 1) / tpb;

    // Pack west edge [1..ng] and east edge [nx-ng+1..nx] on the device.
    halo_pack_kernel<Real><<<nb, tpb, 0, stream>>>(d_q, d_w_send, ni, ng, ny, 1);
    halo_pack_kernel<Real><<<nb, tpb, 0, stream>>>(d_q, d_e_send, ni, ng, ny, nx - ng + 1);
    cudaStreamSynchronize(stream);   // packs must complete before MPI reads the device buffers

    // CUDA-aware MPI on device pointers. Tag 0 = east-edge->right (fills right's
    // west halo); tag 1 = west-edge->left (fills left's east halo).
    MPI_Request req[4];
    MPI_Irecv(d_w_recv, cnt, dt, left,  0, comm, &req[0]);   // west halo  <- left's east edge  (tag 0)
    MPI_Irecv(d_e_recv, cnt, dt, right, 1, comm, &req[1]);   // east halo  <- right's west edge (tag 1)
    MPI_Isend(d_e_send, cnt, dt, right, 0, comm, &req[2]);   // east edge  -> right             (tag 0)
    MPI_Isend(d_w_send, cnt, dt, left,  1, comm, &req[3]);   // west edge  -> left              (tag 1)
    MPI_Waitall(4, req, MPI_STATUSES_IGNORE);

    // Unpack into west halo [1-ng..0] and east halo [nx+1..nx+ng].
    halo_unpack_kernel<Real><<<nb, tpb, 0, stream>>>(d_q, d_w_recv, ni, ng, ny, 1 - ng);
    halo_unpack_kernel<Real><<<nb, tpb, 0, stream>>>(d_q, d_e_recv, ni, ng, ny, nx + 1);
    cudaStreamSynchronize(stream);
}

} // namespace fv3
