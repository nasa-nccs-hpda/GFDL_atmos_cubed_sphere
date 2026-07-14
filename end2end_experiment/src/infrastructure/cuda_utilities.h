#ifndef CUDA_UTILITIES_H
#define CUDA_UTILITIES_H

#include <cuda_runtime.h>
#include <cuComplex.h>
#include <iostream>
#include <string>
#include <sstream>

namespace held_suarez {
namespace infrastructure {

/**
 * @brief CUDA error checking macro
 * 
 * Usage:
 *   CUDA_CHECK(cudaMalloc(&ptr, size));
 */
#define CUDA_CHECK(call) do { \
    cudaError_t err = call; \
    if (err != cudaSuccess) { \
        std::stringstream ss; \
        ss << "CUDA error in " << __FILE__ << ":" << __LINE__ \
           << " - " << cudaGetErrorString(err); \
        throw std::runtime_error(ss.str()); \
    } \
} while(0)

/**
 * @brief Check last CUDA error (for kernel launches)
 * 
 * Usage:
 *   kernel<<<grid, block>>>(...);
 *   CUDA_CHECK_LAST();
 */
#define CUDA_CHECK_LAST() CUDA_CHECK(cudaGetLastError())

/**
 * @brief Synchronize and check for errors
 */
#define CUDA_SYNC_CHECK() do { \
    CUDA_CHECK(cudaDeviceSynchronize()); \
    CUDA_CHECK(cudaGetLastError()); \
} while(0)

/**
 * @brief GPU device properties query
 */
struct GPUDeviceInfo {
    int device_id;
    std::string name;
    size_t total_memory;
    size_t free_memory;
    int compute_capability_major;
    int compute_capability_minor;
    int multiprocessor_count;
    int max_threads_per_block;
    int max_threads_per_multiprocessor;
    
    static GPUDeviceInfo get_current() {
        GPUDeviceInfo info;
        
        CUDA_CHECK(cudaGetDevice(&info.device_id));
        
        cudaDeviceProp prop;
        CUDA_CHECK(cudaGetDeviceProperties(&prop, info.device_id));
        
        info.name = prop.name;
        info.total_memory = prop.totalGlobalMem;
        info.compute_capability_major = prop.major;
        info.compute_capability_minor = prop.minor;
        info.multiprocessor_count = prop.multiProcessorCount;
        info.max_threads_per_block = prop.maxThreadsPerBlock;
        info.max_threads_per_multiprocessor = prop.maxThreadsPerMultiProcessor;
        
        size_t free, total;
        CUDA_CHECK(cudaMemGetInfo(&free, &total));
        info.free_memory = free;
        
        return info;
    }
    
    void print(std::ostream& os = std::cout) const {
        os << "\n=== GPU Device Info ===\n";
        os << "Device ID:           " << device_id << "\n";
        os << "Name:                " << name << "\n";
        os << "Compute Capability:  " << compute_capability_major << "." 
           << compute_capability_minor << "\n";
        os << "Total Memory:        " << total_memory / (1024.0 * 1024.0 * 1024.0) 
           << " GB\n";
        os << "Free Memory:         " << free_memory / (1024.0 * 1024.0 * 1024.0) 
           << " GB\n";
        os << "Multiprocessors:     " << multiprocessor_count << "\n";
        os << "Max Threads/Block:   " << max_threads_per_block << "\n";
        os << "Max Threads/SM:      " << max_threads_per_multiprocessor << "\n";
        os << "=======================\n\n";
    }
};

/**
 * @brief Compute optimal 1D grid/block configuration
 */
inline void compute_1d_config(int n, dim3& grid, dim3& block, int block_size = 256) {
    block = dim3(block_size);
    grid = dim3((n + block.x - 1) / block.x);
}

/**
 * @brief Compute optimal 2D grid/block configuration
 */
inline void compute_2d_config(int nx, int ny, dim3& grid, dim3& block, 
                              int block_x = 16, int block_y = 16) {
    block = dim3(block_x, block_y);
    grid = dim3((nx + block.x - 1) / block.x,
                (ny + block.y - 1) / block.y);
}

/**
 * @brief Compute optimal 3D grid/block configuration
 */
inline void compute_3d_config(int nx, int ny, int nz, dim3& grid, dim3& block,
                              int block_x = 8, int block_y = 8, int block_z = 4) {
    block = dim3(block_x, block_y, block_z);
    grid = dim3((nx + block.x - 1) / block.x,
                (ny + block.y - 1) / block.y,
                (nz + block.z - 1) / block.z);
}

/**
 * @brief Simple timer for GPU operations
 */
class GPUTimer {
public:
    GPUTimer() {
        CUDA_CHECK(cudaEventCreate(&start_));
        CUDA_CHECK(cudaEventCreate(&stop_));
    }
    
    ~GPUTimer() {
        cudaEventDestroy(start_);
        cudaEventDestroy(stop_);
    }
    
    void start() {
        CUDA_CHECK(cudaEventRecord(start_));
    }
    
    void stop() {
        CUDA_CHECK(cudaEventRecord(stop_));
        CUDA_CHECK(cudaEventSynchronize(stop_));
    }
    
    float elapsed_ms() {
        float ms = 0;
        CUDA_CHECK(cudaEventElapsedTime(&ms, start_, stop_));
        return ms;
    }
    
private:
    cudaEvent_t start_;
    cudaEvent_t stop_;
};

/**
 * @brief Memory copy helpers
 */
template<typename T>
inline void copy_to_device(T* d_dst, const T* h_src, size_t count) {
    CUDA_CHECK(cudaMemcpy(d_dst, h_src, count * sizeof(T), cudaMemcpyHostToDevice));
}

template<typename T>
inline void copy_from_device(T* h_dst, const T* d_src, size_t count) {
    CUDA_CHECK(cudaMemcpy(h_dst, d_src, count * sizeof(T), cudaMemcpyDeviceToHost));
}

template<typename T>
inline void copy_device_to_device(T* d_dst, const T* d_src, size_t count) {
    CUDA_CHECK(cudaMemcpy(d_dst, d_src, count * sizeof(T), cudaMemcpyDeviceToDevice));
}

/**
 * @brief Zero out device memory
 */
template<typename T>
inline void zero_device(T* d_ptr, size_t count) {
    CUDA_CHECK(cudaMemset(d_ptr, 0, count * sizeof(T)));
}

/**
 * @brief Complex number helpers for CUDA
 */
namespace complex_ops {
    
    __device__ __forceinline__
    cuDoubleComplex operator+(const cuDoubleComplex& a, const cuDoubleComplex& b) {
        return cuCadd(a, b);
    }
    
    __device__ __forceinline__
    cuDoubleComplex operator-(const cuDoubleComplex& a, const cuDoubleComplex& b) {
        return cuCsub(a, b);
    }
    
    __device__ __forceinline__
    cuDoubleComplex operator*(const cuDoubleComplex& a, const cuDoubleComplex& b) {
        return cuCmul(a, b);
    }
    
    __device__ __forceinline__
    cuDoubleComplex operator*(const cuDoubleComplex& a, double b) {
        return make_cuDoubleComplex(cuCreal(a) * b, cuCimag(a) * b);
    }
    
    __device__ __forceinline__
    cuDoubleComplex operator*(double a, const cuDoubleComplex& b) {
        return make_cuDoubleComplex(a * cuCreal(b), a * cuCimag(b));
    }
    
    __device__ __forceinline__
    cuDoubleComplex operator/(const cuDoubleComplex& a, const cuDoubleComplex& b) {
        return cuCdiv(a, b);
    }
    
    __device__ __forceinline__
    double abs(const cuDoubleComplex& a) {
        return cuCabs(a);
    }
    
    __device__ __forceinline__
    cuDoubleComplex conj(const cuDoubleComplex& a) {
        return cuConj(a);
    }
    
} // namespace complex_ops

/**
 * @brief Array indexing helpers
 */
namespace indexing {
    
    // 3D array indexing: (i, j, k) -> linear index
    __device__ __host__ __forceinline__
    int index_3d(int i, int j, int k, int nx, int ny, int nz) {
        return i + nx * (j + ny * k);
    }
    
    // 3D array indexing with stride
    __device__ __host__ __forceinline__
    int index_3d_stride(int i, int j, int k, int stride_x, int stride_y) {
        return i * stride_x + j * stride_y + k;
    }
    
    // Convert linear index to 3D coordinates
    __device__ __host__ __forceinline__
    void linear_to_3d(int idx, int nx, int ny, int& i, int& j, int& k) {
        k = idx / (nx * ny);
        int tmp = idx % (nx * ny);
        j = tmp / nx;
        i = tmp % nx;
    }
    
} // namespace indexing

/**
 * @brief Common math helpers
 */
namespace math {
    
    __device__ __forceinline__
    double sign(double x) {
        return (x > 0.0) - (x < 0.0);
    }
    
    __device__ __forceinline__
    double clamp(double x, double min_val, double max_val) {
        return fmin(fmax(x, min_val), max_val);
    }
    
    __device__ __forceinline__
    int iclamp(int x, int min_val, int max_val) {
        return min(max(x, min_val), max_val);
    }
    
    // Van Leer limiter
    __device__ __forceinline__
    double vanleer_limiter(double a, double b) {
        if (a * b <= 0.0) return 0.0;
        return 2.0 * a * b / (a + b);
    }
    
    // Minmod limiter
    __device__ __forceinline__
    double minmod(double a, double b) {
        if (a * b <= 0.0) return 0.0;
        return (fabs(a) < fabs(b)) ? a : b;
    }
    
} // namespace math

/**
 * @brief Reduction operations
 */
template<typename T, int BLOCK_SIZE>
__device__ void block_reduce_max(T* sdata, int tid) {
    __syncthreads();
    
    if (BLOCK_SIZE >= 1024 && tid < 512) {
        sdata[tid] = fmax(sdata[tid], sdata[tid + 512]);
    }
    __syncthreads();
    
    if (BLOCK_SIZE >= 512 && tid < 256) {
        sdata[tid] = fmax(sdata[tid], sdata[tid + 256]);
    }
    __syncthreads();
    
    if (BLOCK_SIZE >= 256 && tid < 128) {
        sdata[tid] = fmax(sdata[tid], sdata[tid + 128]);
    }
    __syncthreads();
    
    if (BLOCK_SIZE >= 128 && tid < 64) {
        sdata[tid] = fmax(sdata[tid], sdata[tid + 64]);
    }
    __syncthreads();
    
    // Warp reduction (no sync needed)
    if (tid < 32) {
        if (BLOCK_SIZE >= 64) sdata[tid] = fmax(sdata[tid], sdata[tid + 32]);
        if (BLOCK_SIZE >= 32) sdata[tid] = fmax(sdata[tid], sdata[tid + 16]);
        if (BLOCK_SIZE >= 16) sdata[tid] = fmax(sdata[tid], sdata[tid + 8]);
        if (BLOCK_SIZE >= 8) sdata[tid] = fmax(sdata[tid], sdata[tid + 4]);
        if (BLOCK_SIZE >= 4) sdata[tid] = fmax(sdata[tid], sdata[tid + 2]);
        if (BLOCK_SIZE >= 2) sdata[tid] = fmax(sdata[tid], sdata[tid + 1]);
    }
}

template<typename T, int BLOCK_SIZE>
__device__ void block_reduce_sum(T* sdata, int tid) {
    __syncthreads();
    
    if (BLOCK_SIZE >= 1024 && tid < 512) {
        sdata[tid] += sdata[tid + 512];
    }
    __syncthreads();
    
    if (BLOCK_SIZE >= 512 && tid < 256) {
        sdata[tid] += sdata[tid + 256];
    }
    __syncthreads();
    
    if (BLOCK_SIZE >= 256 && tid < 128) {
        sdata[tid] += sdata[tid + 128];
    }
    __syncthreads();
    
    if (BLOCK_SIZE >= 128 && tid < 64) {
        sdata[tid] += sdata[tid + 64];
    }
    __syncthreads();
    
    // Warp reduction
    if (tid < 32) {
        if (BLOCK_SIZE >= 64) sdata[tid] += sdata[tid + 32];
        if (BLOCK_SIZE >= 32) sdata[tid] += sdata[tid + 16];
        if (BLOCK_SIZE >= 16) sdata[tid] += sdata[tid + 8];
        if (BLOCK_SIZE >= 8) sdata[tid] += sdata[tid + 4];
        if (BLOCK_SIZE >= 4) sdata[tid] += sdata[tid + 2];
        if (BLOCK_SIZE >= 2) sdata[tid] += sdata[tid + 1];
    }
}

} // namespace infrastructure
} // namespace held_suarez

#endif // CUDA_UTILITIES_H