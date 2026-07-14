# Held-Suarez CUDA Architecture Overview

## System Architecture

This document describes the complete architecture of the GPU-accelerated Held-Suarez atmospheric model.

## Design Goals

1. **Maximum GPU Utilization**: Keep data resident on GPU throughout time integration
2. **Zero Production Code Modification**: All changes via overlays and new code
3. **Modular Design**: Each component can be enabled/disabled independently
4. **Fallback Support**: CPU path always available
5. **Validation-First**: Every component validated before integration

## System Layers

### Layer 1: Fortran Production Code (Unchanged)

```
Original Fortran Model
├── spectral_dynamics.F90       # Main dynamics orchestration
├── fv_advection.F90            # Finite-volume advection
├── hs_forcing.F90              # Held-Suarez forcing
├── transforms.F90              # Grid-spectral transforms
├── leapfrog.F90                # Time integration
└── press_and_geopot.F90        # Pressure/geopotential
```

**Status**: Completely untouched. All modifications via overlay mechanism.

### Layer 2: Fortran Wrapper Layer

**Location**: `end2end_experiment/src/integration/fortran/`

**Purpose**: Minimal Fortran code using `iso_c_binding` to call C API

**Example**:
```fortran
module fv_advection_c_interface
  use iso_c_binding
  implicit none
  
  interface
    subroutine semi_y_3d_c(dq, va, q, nx, ny, nz, dy, dt) bind(C, name="semi_y_3d_c")
      use iso_c_binding
      integer(c_int), value :: nx, ny, nz
      real(c_double), value :: dy, dt
      real(c_double), dimension(nx,ny,nz) :: dq, va, q
    end subroutine
  end interface
  
contains
  
  subroutine semi_y_3d_wrapper(dq, va, q, nx, ny, nz, dy, dt)
    real(8), dimension(nx,ny,nz) :: dq, va, q
    integer :: nx, ny, nz
    real(8) :: dy, dt
    
    call semi_y_3d_c(dq, va, q, nx, ny, nz, dy, dt)
  end subroutine
  
end module
```

### Layer 3: C API Layer

**Location**: `end2end_experiment/src/integration/c_api/`

**Purpose**: Stable ABI between Fortran and C++/CUDA

**Features**:
- Error handling
- Backend selection (CPU vs CUDA)
- Logging and diagnostics
- Thread safety

**Example**:
```cpp
// fv_advection_c_api.h
#ifndef FV_ADVECTION_C_API_H
#define FV_ADVECTION_C_API_H

#ifdef __cplusplus
extern "C" {
#endif

// Error codes
typedef enum {
    FV_SUCCESS = 0,
    FV_ERROR_INVALID_DIMS = -1,
    FV_ERROR_NULL_POINTER = -2,
    FV_ERROR_CUDA_FAILURE = -3,
    FV_ERROR_OUT_OF_MEMORY = -4
} FVErrorCode;

// Backend selection
typedef enum {
    FV_BACKEND_CPU = 0,
    FV_BACKEND_CUDA = 1
} FVBackend;

// Main API functions
FVErrorCode semi_y_3d_c(
    double* dq,
    const double* va,
    const double* q,
    int nx, int ny, int nz,
    double dy, double dt
);

// Configuration
FVErrorCode fv_set_backend(FVBackend backend);
FVBackend fv_get_backend();
const char* fv_get_error_string(FVErrorCode code);

#ifdef __cplusplus
}
#endif

#endif // FV_ADVECTION_C_API_H
```

### Layer 4: C++/CUDA Implementation

**Location**: `end2end_experiment/src/kernels/`

**Organization**:
```
kernels/
├── forcing/              # Held-Suarez forcing
│   ├── newtonian_damping.cu
│   ├── rayleigh_damping.cu
│   └── forcing.h
├── fv_advection/         # Finite-volume advection
│   ├── semi_y_3d.cu
│   ├── semi_x_3d.cu
│   ├── slope_sphere.cu
│   ├── vanleer_sphere_3d.cu
│   └── fv_advection.h
├── spectral/             # Spectral operators
│   ├── laplacian.cu
│   ├── gradient.cu
│   └── spectral_ops.h
├── transforms/           # Grid-spectral transforms
│   ├── fft_wrapper.cu
│   ├── legendre_transform.cu
│   └── transforms.h
├── time_integration/     # Time stepping
│   ├── leapfrog.cu
│   └── time_stepping.h
└── pressure/             # Pressure/geopotential
    ├── press_and_geopot.cu
    └── pressure.h
```

## Data Flow

### Initialization Phase

```
1. Model startup (Fortran)
   ↓
2. Call GPU initialization via C API
   ↓
3. Allocate persistent GPU buffers
   ↓
4. Copy initial conditions to GPU
   ↓
5. Initialize transform precomputed data
```

### Time Integration Loop

```
For each timestep:
  ├─ Spectral → Grid transform (CUDA)
  │  ├─ Inverse FFT (cuFFT)
  │  └─ Inverse Legendre (CUDA)
  │
  ├─ Grid-point physics (CUDA)
  │  ├─ Held-Suarez forcing
  │  │  ├─ Newtonian damping
  │  │  └─ Rayleigh damping
  │  │
  │  └─ Tracer advection
  │     ├─ semi_y_3d
  │     ├─ semi_x_3d
  │     ├─ slope calculations
  │     └─ van Leer flux limiters
  │
  ├─ Grid → Spectral transform (CUDA)
  │  ├─ Forward Legendre (CUDA)
  │  └─ Forward FFT (cuFFT)
  │
  ├─ Spectral-space dynamics (CUDA)
  │  ├─ Compute vorticity/divergence
  │  ├─ Compute Laplacian
  │  ├─ Apply spectral damping
  │  └─ Compute pressure tendencies
  │
  └─ Time step (CUDA)
     └─ Leapfrog with Robert filter
```

**Key Point**: Data stays on GPU for entire integration loop. Only diagnostic output requires GPU→CPU transfer.

### Diagnostic Output Phase

```
1. Copy required fields from GPU to CPU
   ↓
2. Write to NetCDF (Fortran)
   ↓
3. Continue time integration
```

## Memory Management

### GPU Memory Organization

```
GPU Memory Layout:

┌─────────────────────────────────────────┐
│  Persistent State Arrays                │
│  ├─ Grid-point fields (u, v, t)         │
│  ├─ Tracers (ntracers × nx × ny × nz)  │
│  ├─ Spectral coefficients (complex)     │
│  └─ Pressure/geopotential               │
├─────────────────────────────────────────┤
│  Transform Workspace                    │
│  ├─ Fourier coefficients                │
│  ├─ Legendre workspace                  │
│  └─ FFT plans (cuFFT)                   │
├─────────────────────────────────────────┤
│  Advection Workspace                    │
│  ├─ Slope arrays                        │
│  ├─ Flux arrays                         │
│  └─ Intermediate results                │
├─────────────────────────────────────────┤
│  Precomputed Data                       │
│  ├─ Legendre polynomials                │
│  ├─ Gaussian weights                    │
│  ├─ Spherical eigenvalues               │
│  └─ Grid metrics                        │
└─────────────────────────────────────────┘
```

### Memory Manager API

```cpp
class GPUMemoryManager {
public:
    // Allocate named buffer
    template<typename T>
    T* allocate(const std::string& name, size_t count);
    
    // Get existing buffer
    template<typename T>
    T* get(const std::string& name);
    
    // Reallocate if size changed
    template<typename T>
    T* reallocate(const std::string& name, size_t new_count);
    
    // Free specific buffer
    void free(const std::string& name);
    
    // Reset all (for shutdown)
    void reset();
    
    // Statistics
    size_t total_allocated() const;
    size_t peak_allocated() const;
    void print_summary() const;
};
```

### Memory Usage Estimates

**T85L25 Configuration**:
- Horizontal grid: 256 × 128 (Gaussian)
- Vertical levels: 25
- Spectral truncation: T85 (7826 complex coefficients)
- Tracers: 1

**Memory Requirements**:
```
Grid-point state (u,v,t,tracers):
  4 × 256 × 128 × 25 × 8 bytes = 26.2 MB

Spectral state (vorticity,divergence,temp):
  3 × 7826 × 25 × 16 bytes (complex) = 9.4 MB

Transform workspace:
  ~50 MB (Fourier, Legendre, FFT plans)

Advection workspace:
  ~20 MB (slopes, fluxes)

Precomputed data:
  ~10 MB (Legendre, weights, eigenvalues)

Total: ~115 MB
```

**T170L50 Configuration**:
- Horizontal grid: 512 × 256
- Vertical levels: 50
- Spectral truncation: T170 (29926 complex coefficients)

**Memory Requirements**:
```
Total: ~800 MB
```

**Conclusion**: Even high-resolution configurations fit easily in modern GPU memory (16+ GB).

## Kernel Design Patterns

### Pattern 1: Simple Element-wise Operation

**Example**: Newtonian damping

```cuda
__global__ void newtonian_damping_kernel(
    double* tdt,           // output: temperature tendency
    const double* t,       // input: temperature
    const double* teq,     // input: equilibrium temperature
    const double* k_t,     // input: relaxation coefficient
    int n_total            // total array size
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n_total) {
        tdt[idx] = -k_t[idx] * (t[idx] - teq[idx]);
    }
}

// Launch with 1D grid
dim3 block(256);
dim3 grid((n_total + block.x - 1) / block.x);
newtonian_damping_kernel<<<grid, block>>>(tdt, t, teq, k_t, n_total);
```

### Pattern 2: 3D Stencil Operation

**Example**: Semi-Lagrangian advection

```cuda
__global__ void semi_y_3d_kernel(
    double* dq,            // output: tracer increment
    const double* va,      // input: meridional velocity
    const double* q,       // input: tracer values
    int nx, int ny, int nz,
    double dy, double dt
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;
    
    if (i < nx && j < ny && k < nz) {
        int idx = i + nx * (j + ny * k);
        
        // Semi-Lagrangian update logic
        double v = va[idx];
        double cfl = v * dt / dy;
        
        // Upstream interpolation
        int j_up = j - int(cfl);
        double frac = cfl - int(cfl);
        
        // Boundary handling
        if (j_up >= 0 && j_up < ny-1) {
            int idx_up = i + nx * (j_up + ny * k);
            int idx_up1 = i + nx * ((j_up+1) + ny * k);
            dq[idx] = (1.0 - frac) * q[idx_up] + frac * q[idx_up1] - q[idx];
        }
    }
}

// Launch with 3D grid
dim3 block(8, 8, 4);
dim3 grid((nx + block.x - 1) / block.x,
          (ny + block.y - 1) / block.y,
          (nz + block.z - 1) / block.z);
semi_y_3d_kernel<<<grid, block>>>(dq, va, q, nx, ny, nz, dy, dt);
```

### Pattern 3: Reduction Operation

**Example**: Compute maximum CFL number

```cuda
__global__ void compute_max_cfl_kernel(
    double* partial_max,   // output: partial maxima per block
    const double* u,       // input: u velocity
    const double* v,       // input: v velocity
    double dx, double dy, double dt,
    int n_total
) {
    __shared__ double sdata[256];
    
    int tid = threadIdx.x;
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    
    // Compute local CFL
    double cfl = 0.0;
    if (idx < n_total) {
        double cfl_x = fabs(u[idx]) * dt / dx;
        double cfl_y = fabs(v[idx]) * dt / dy;
        cfl = max(cfl_x, cfl_y);
    }
    sdata[tid] = cfl;
    __syncthreads();
    
    // Block-level reduction
    for (int s = blockDim.x / 2; s > 0; s >>= 1) {
        if (tid < s) {
            sdata[tid] = max(sdata[tid], sdata[tid + s]);
        }
        __syncthreads();
    }
    
    // Write block result
    if (tid == 0) {
        partial_max[blockIdx.x] = sdata[0];
    }
}
```

### Pattern 4: Complex Number Operations

**Example**: Spectral Laplacian

```cuda
#include <cuComplex.h>

__global__ void spectral_laplacian_kernel(
    cuDoubleComplex* field_out,       // output: Laplacian
    const cuDoubleComplex* field_in,  // input: field
    const double* eigenvalues,        // input: -n(n+1)/a^2
    int n_total, int n_level
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n_total * n_level) {
        int n_idx = idx % n_total;
        int k = idx / n_total;
        
        // Laplacian = eigenvalue × field
        double lambda = eigenvalues[n_idx];
        field_out[idx] = make_cuDoubleComplex(
            cuCreal(field_in[idx]) * lambda,
            cuCimag(field_in[idx]) * lambda
        );
    }
}
```

## Error Handling

### CUDA Error Checking

```cpp
#define CUDA_CHECK(call) do { \
    cudaError_t err = call; \
    if (err != cudaSuccess) { \
        fprintf(stderr, "CUDA error in %s:%d: %s\n", \
                __FILE__, __LINE__, cudaGetErrorString(err)); \
        return FV_ERROR_CUDA_FAILURE; \
    } \
} while(0)

// Example usage
FVErrorCode semi_y_3d_c(double* dq, const double* va, const double* q,
                        int nx, int ny, int nz, double dy, double dt) {
    // Validate inputs
    if (!dq || !va || !q) return FV_ERROR_NULL_POINTER;
    if (nx <= 0 || ny <= 0 || nz <= 0) return FV_ERROR_INVALID_DIMS;
    
    // Allocate device memory
    double *d_dq, *d_va, *d_q;
    CUDA_CHECK(cudaMalloc(&d_dq, nx*ny*nz*sizeof(double)));
    CUDA_CHECK(cudaMalloc(&d_va, nx*ny*nz*sizeof(double)));
    CUDA_CHECK(cudaMalloc(&d_q, nx*ny*nz*sizeof(double)));
    
    // Copy inputs
    CUDA_CHECK(cudaMemcpy(d_va, va, nx*ny*nz*sizeof(double), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_q, q, nx*ny*nz*sizeof(double), cudaMemcpyHostToDevice));
    
    // Launch kernel
    dim3 block(8, 8, 4);
    dim3 grid((nx + block.x - 1) / block.x,
              (ny + block.y - 1) / block.y,
              (nz + block.z - 1) / block.z);
    semi_y_3d_kernel<<<grid, block>>>(d_dq, d_va, d_q, nx, ny, nz, dy, dt);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());
    
    // Copy result
    CUDA_CHECK(cudaMemcpy(dq, d_dq, nx*ny*nz*sizeof(double), cudaMemcpyDeviceToHost));
    
    // Cleanup
    cudaFree(d_dq);
    cudaFree(d_va);
    cudaFree(d_q);
    
    return FV_SUCCESS;
}
```

## Performance Optimization Strategies

### 1. Kernel Fusion

Combine multiple small kernels to reduce launch overhead:

```cuda
// Instead of separate kernels:
vanleer_limiter_kernel<<<grid, block>>>(...);
apply_flux_kernel<<<grid, block>>>(...);

// Fuse into one:
vanleer_with_flux_kernel<<<grid, block>>>(...);
```

### 2. Shared Memory

Use shared memory for frequently accessed data:

```cuda
__global__ void slope_sphere_kernel(...) {
    __shared__ double s_q[BLOCK_Y+2][BLOCK_X+2];
    
    // Load halo into shared memory
    // Compute slopes using shared data
    // Write results
}
```

### 3. Stream Parallelism

Overlap computation and transfers:

```cpp
cudaStream_t streams[4];
for (int i = 0; i < 4; i++) {
    cudaStreamCreate(&streams[i]);
}

// Process multiple levels in parallel
for (int k = 0; k < nz; k++) {
    int stream_id = k % 4;
    kernel<<<grid, block, 0, streams[stream_id]>>>(
        &data[k * nx * ny], ...);
}
```

### 4. Persistent Buffers

Avoid repeated allocations:

```cpp
// Bad: allocate every call
void process() {
    double* d_temp;
    cudaMalloc(&d_temp, size);
    kernel<<<grid, block>>>(d_temp, ...);
    cudaFree(d_temp);
}

// Good: allocate once
struct Context {
    double* d_workspace;
};

void init(Context* ctx, size_t size) {
    cudaMalloc(&ctx->d_workspace, size);
}

void process(Context* ctx) {
    kernel<<<grid, block>>>(ctx->d_workspace, ...);
}
```

## Build Configuration

### CMake Options

```cmake
# CUDA architecture targets
set(CMAKE_CUDA_ARCHITECTURES "70;75;80;86" CACHE STRING "CUDA architectures")

# Enable/disable backends
option(ENABLE_CUDA "Enable CUDA backend" ON)
option(ENABLE_CPU_FALLBACK "Enable CPU fallback" ON)

# Optimization flags
set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -O3 --use_fast_math")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -march=native")

# Debug options
option(ENABLE_NVTX "Enable NVTX profiling" OFF)
option(CUDA_DEBUG "Enable CUDA debug info" OFF)
```

## Testing Strategy

See `docs/validation/testing_framework.md` for detailed testing procedures.

## Performance Monitoring

See `docs/performance/profiling_guide.md` for profiling and optimization workflows.

---

**Last Updated**: 2024