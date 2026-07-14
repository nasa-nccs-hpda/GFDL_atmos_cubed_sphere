# Held-Suarez Complete CUDA Conversion - Master Plan

Date: 2024

## Executive Summary

This document outlines the complete end-to-end CUDA conversion of the Held-Suarez atmospheric model test case. All new code, documentation, and build artifacts will reside in `end2end_experiment/`, leaving the original production codebase completely untouched.

## Design Philosophy

### Core Principles

1. **Zero modification to production Fortran code**
2. **GPU-first design with CPU fallback**
3. **Data residency - minimize CPU-GPU transfers**
4. **Modular architecture - independent kernel enablement**
5. **Validation-driven development**
6. **Performance transparency**

### Integration Strategy

```
┌─────────────────────────────────────────────────────────────┐
│  Production Fortran Model (unchanged)                       │
│  src/atmos_spectral/model/spectral_dynamics.F90            │
│  src/atmos_spectral/model/fv_advection.F90                 │
│  src/atmos_param/hs_forcing/hs_forcing.F90                 │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ↓ (optional overlay path)
┌─────────────────────────────────────────────────────────────┐
│  Fortran Wrapper Layer (end2end_experiment/src/integration/)│
│  - iso_c_binding interfaces                                 │
│  - Minimal state management                                 │
│  - Array marshalling                                        │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────────┐
│  C API Layer (end2end_experiment/src/integration/c_api/)    │
│  - Stable ABI between Fortran and C++                       │
│  - Error handling                                           │
│  - Backend selection (CPU/CUDA)                             │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ↓
┌─────────────────────────────────────────────────────────────┐
│  C++/CUDA Implementation (end2end_experiment/src/kernels/)  │
│  - Memory management                                        │
│  - Kernel orchestration                                     │
│  - Performance optimization                                 │
└─────────────────────────────────────────────────────────────┘
```

## Module Inventory and Priority

### Tier 1: Completed (Reference Implementation)

| Component | Status | Location | Validation |
|-----------|--------|----------|------------|
| hs_forcing | ✅ Complete | existing translated/ | 30-day runs |
| semi_y_3d | ✅ Complete | existing translated/ | 30-day runs |

### Tier 2: High-Priority FV Advection Kernels

| Kernel | LOC | Dependencies | GPU Suitability | Priority |
|--------|-----|--------------|-----------------|----------|
| semi_x_3d | ~60 | None | High | 1 |
| slope_sphere | ~80 | None | High | 2 |
| slope_x | ~70 | None | High | 3 |
| vanleer_sphere_3d | ~120 | slope_sphere | High | 4 |
| vanleer_x_3d | ~100 | slope_x | High | 5 |
| find_cell_x | ~40 | None | Medium | 6 |
| integer_flux_x | ~50 | find_cell_x | Medium | 7 |

### Tier 3: Spectral Operations (Keep Fortran Wrapper)

| Component | Strategy | Rationale |
|-----------|----------|----------|
| Laplacian operator | CUDA kernel | Regular array operation |
| Gradient operator | CUDA kernel | Regular array operation |
| Divergence/vorticity | CUDA kernel | Spectral-space operations |
| Pressure/geopotential | C++ first | Moderate complexity |

### Tier 4: Transform Layer (Library Strategy)

| Component | Approach | Tool |
|-----------|----------|------|
| FFT (longitude) | cuFFT | NVIDIA library |
| Legendre (latitude) | Custom CUDA | Matrix-vector ops |
| Transform orchestration | C++ | Manage library calls |

### Tier 5: Infrastructure (Keep Fortran)

| Component | Decision | Rationale |
|-----------|----------|----------|
| MPI/domain decomposition | Fortran | Complex distributed logic |
| Halo exchanges | Fortran | Domain-specific |
| I/O and diagnostics | Fortran | FMS integration |
| Time management | Fortran | Model orchestration |

## Implementation Phases

### Phase 1: FV Advection Kernel Suite (Current)

**Objective**: Complete all local finite-volume advection kernels

**Timeline**: Weeks 1-4

**Deliverables**:
- [ ] `semi_x_3d` CUDA kernel + validation
- [ ] `slope_sphere` CUDA kernel + validation
- [ ] `slope_x` CUDA kernel + validation
- [ ] `vanleer_sphere_3d` CUDA kernel + validation
- [ ] `vanleer_x_3d` CUDA kernel + validation
- [ ] `find_cell_x` CUDA kernel + validation
- [ ] `integer_flux_x` CUDA kernel + validation
- [ ] Unified FV kernel library
- [ ] Integration test suite

**Structure**:
```
end2end_experiment/src/kernels/fv_advection/
├── semi_x_3d/
│   ├── semi_x_3d.cu
│   ├── semi_x_3d.h
│   └── tests/
├── slope_sphere/
│   ├── slope_sphere.cu
│   ├── slope_sphere.h
│   └── tests/
├── vanleer_sphere_3d/
│   ├── vanleer_sphere_3d.cu
│   ├── vanleer_sphere_3d.h
│   └── tests/
└── ...
```

**Validation Strategy**:
1. Extract Fortran baseline from `fv_advection.F90` for each kernel
2. Create synthetic test cases
3. Capture production fixtures from running model
4. Compare: Fortran baseline vs C++ vs CUDA
5. Tolerances: exact for CPU, <1e-14 relative for CUDA

### Phase 2: FV Advection Integration

**Objective**: Integrate all FV kernels into `a_grid_horiz_advection_3d`

**Timeline**: Weeks 5-6

**Deliverables**:
- [ ] GPU-resident data structures for advection
- [ ] Fortran overlay for `fv_advection_mod`
- [ ] C API for advection orchestration
- [ ] Memory management layer (avoid per-call allocation)
- [ ] 1-day hybrid run
- [ ] 30-day validation run
- [ ] Performance comparison vs all-Fortran

**Memory Strategy**:
```cpp
// Persistent GPU buffers allocated once
struct FVAdvectionBuffers {
    double* d_dq;        // tracer increments
    double* d_va;        // meridional wind
    double* d_q;         // tracer values
    double* d_slope;     // slope arrays
    double* d_flux;      // flux arrays
    size_t capacity;     // buffer sizes
};

// Initialize once at model startup
FVAdvectionBuffers* fv_advection_init(int nx, int ny, int nz, int ntracers);

// Use throughout model run
void fv_advection_update(FVAdvectionBuffers* bufs, /* params */);

// Cleanup at model end
void fv_advection_finalize(FVAdvectionBuffers* bufs);
```

### Phase 3: Spectral Operators

**Objective**: CUDA kernels for spectral-space operations

**Timeline**: Weeks 7-9

**Deliverables**:
- [ ] Laplacian operator CUDA kernel
- [ ] Gradient operator CUDA kernel
- [ ] Divergence/vorticity CUDA kernels
- [ ] Spectral damping CUDA kernel
- [ ] Integration with spectral_dynamics orchestration

**Example Kernel**:
```cuda
// Compute Laplacian in spectral space
// del^2(field) = -n(n+1)/a^2 * field
__global__ void spectral_laplacian(
    const cuDoubleComplex* field_in,
    cuDoubleComplex* field_out,
    const double* eigenvalues,
    int n_total, int n_level
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n_total * n_level) {
        int n_idx = idx % n_total;
        field_out[idx] = field_in[idx] * eigenvalues[n_idx];
    }
}
```

### Phase 4: Transform Layer

**Objective**: GPU-accelerated grid-spectral transforms

**Timeline**: Weeks 10-14

**Approach**:
1. Use cuFFT for longitude (FFT) direction
2. Implement custom CUDA kernels for latitude (Legendre) direction
3. Optimize for batched operations
4. Manage distributed memory across MPI ranks (keep in Fortran)

**Deliverables**:
- [ ] cuFFT integration for grid_fourier operations
- [ ] CUDA Legendre transform kernels
- [ ] Transform orchestration layer
- [ ] Round-trip validation (grid→spectral→grid)
- [ ] Energy conservation tests

**Legendre Transform Strategy**:
```cuda
// Latitude transform: Fourier coefficients → Spherical harmonics
// Sum over Gaussian latitudes weighted by Legendre polynomials
__global__ void legendre_transform(
    const double* fourier_coeffs,  // [n_fourier, n_lat]
    double* spectral_coeffs,        // [n_total]
    const double* legendre_matrix,  // [n_total, n_lat] precomputed
    const double* gauss_weights,    // [n_lat]
    int n_fourier, int n_lat, int n_total
) {
    // Matrix-vector product with Gaussian weights
    // Use shared memory for coalesced access
}
```

### Phase 5: Pressure and Geopotential

**Objective**: C++/CUDA implementation of press_and_geopot

**Timeline**: Weeks 15-16

**Deliverables**:
- [ ] Baseline harness from `press_and_geopot.F90`
- [ ] C++ implementation
- [ ] CUDA kernel for vertical integration
- [ ] Validation against Fortran

### Phase 6: Time Integration

**Objective**: GPU-accelerated leapfrog time stepping

**Timeline**: Weeks 17-18

**Deliverables**:
- [ ] CUDA kernel for Robert-Asselin-Williams filter
- [ ] GPU-resident spectral state arrays
- [ ] Integration with spectral_dynamics

**Leapfrog Kernel**:
```cuda
// Three-time-level leapfrog with Robert-Asselin-Williams filter
__global__ void leapfrog_raw_filter(
    cuDoubleComplex* state_prev,
    cuDoubleComplex* state_curr,
    const cuDoubleComplex* tendency,
    double dt, double robert_coeff,
    int n_total, int n_level
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n_total * n_level) {
        // Forward step
        cuDoubleComplex state_future = state_prev[idx] + 
            make_cuDoubleComplex(2.0 * dt, 0.0) * tendency[idx];
        
        // Robert filter
        state_curr[idx] += robert_coeff * 
            (state_prev[idx] - 2.0 * state_curr[idx] + state_future);
        
        // Time level rotation
        state_prev[idx] = state_curr[idx];
        state_curr[idx] = state_future;
    }
}
```

### Phase 7: End-to-End Integration

**Objective**: Complete GPU-accelerated Held-Suarez model

**Timeline**: Weeks 19-20

**Deliverables**:
- [ ] Unified build system
- [ ] Full integration test
- [ ] 1-day smoke test
- [ ] 30-day validation run
- [ ] T85L25 performance comparison
- [ ] T170L50 scaling test
- [ ] Memory profiling report
- [ ] Performance analysis report

## Directory Structure (Complete)

```
end2end_experiment/
├── README.md
├── MASTER_PLAN.md
├── CMakeLists.txt
├── docs/
│   ├── architecture/
│   │   ├── memory_management.md
│   │   ├── data_residency.md
│   │   ├── kernel_fusion.md
│   │   └── error_handling.md
│   ├── validation/
│   │   ├── unit_test_results/
│   │   ├── integration_test_results/
│   │   ├── 30day_validation_reports/
│   │   └── numerical_accuracy_analysis.md
│   └── performance/
│       ├── profiling_methodology.md
│       ├── T85L25_results.md
│       ├── T170L50_results.md
│       └── scaling_analysis.md
├── src/
│   ├── kernels/
│   │   ├── forcing/
│   │   │   ├── newtonian_damping.cu
│   │   │   ├── rayleigh_damping.cu
│   │   │   └── forcing.h
│   │   ├── fv_advection/
│   │   │   ├── semi_y_3d.cu
│   │   │   ├── semi_x_3d.cu
│   │   │   ├── slope_sphere.cu
│   │   │   ├── slope_x.cu
│   │   │   ├── vanleer_sphere_3d.cu
│   │   │   ├── vanleer_x_3d.cu
│   │   │   ├── find_cell_x.cu
│   │   │   ├── integer_flux_x.cu
│   │   │   └── fv_advection.h
│   │   ├── spectral/
│   │   │   ├── laplacian.cu
│   │   │   ├── gradient.cu
│   │   │   ├── divergence_vorticity.cu
│   │   │   ├── spectral_damping.cu
│   │   │   └── spectral_ops.h
│   │   ├── transforms/
│   │   │   ├── fft_wrapper.cu
│   │   │   ├── legendre_transform.cu
│   │   │   ├── transform_orchestration.cpp
│   │   │   └── transforms.h
│   │   ├── time_integration/
│   │   │   ├── leapfrog.cu
│   │   │   └── time_stepping.h
│   │   └── pressure/
│   │       ├── press_and_geopot.cu
│   │       └── pressure.h
│   ├── orchestration/
│   │   ├── dynamics_driver.cpp
│   │   ├── advection_driver.cpp
│   │   └── model_orchestration.h
│   ├── infrastructure/
│   │   ├── gpu_memory_manager.cpp
│   │   ├── gpu_memory_manager.h
│   │   ├── error_handling.cpp
│   │   ├── error_handling.h
│   │   ├── cuda_utilities.cu
│   │   └── cuda_utilities.h
│   └── integration/
│       ├── c_api/
│       │   ├── forcing_c_api.h
│       │   ├── forcing_c_api.cpp
│       │   ├── fv_advection_c_api.h
│       │   ├── fv_advection_c_api.cpp
│       │   ├── spectral_c_api.h
│       │   ├── spectral_c_api.cpp
│       │   └── transform_c_api.h
│       └── fortran/
│           ├── forcing_c_interface.F90
│           ├── fv_advection_c_interface.F90
│           ├── spectral_c_interface.F90
│           └── transform_c_interface.F90
├── tests/
│   ├── unit/
│   │   ├── test_forcing.cu
│   │   ├── test_semi_y_3d.cu
│   │   ├── test_semi_x_3d.cu
│   │   ├── test_slopes.cu
│   │   ├── test_vanleer.cu
│   │   ├── test_spectral_ops.cu
│   │   ├── test_transforms.cu
│   │   └── test_leapfrog.cu
│   ├── integration/
│   │   ├── test_fv_advection_suite.cpp
│   │   ├── test_spectral_dynamics.cpp
│   │   └── test_full_timestep.cpp
│   └── validation/
│       ├── fortran_baselines/
│       ├── run_1day_test.sh
│       ├── run_30day_test.sh
│       ├── compare_outputs.py
│       └── validation_report_template.md
├── benchmarks/
│   ├── kernel_microbenchmarks/
│   ├── memory_bandwidth_tests/
│   ├── full_model_timings/
│   └── scaling_studies/
├── scripts/
│   ├── build_all.sh
│   ├── build_kernels.sh
│   ├── build_integration.sh
│   ├── run_unit_tests.sh
│   ├── run_integration_tests.sh
│   ├── run_validation.sh
│   ├── profile_gpu.sh
│   ├── generate_performance_report.sh
│   └── utils/
│       ├── compare_netcdf.py
│       ├── extract_timings.py
│       └── plot_results.py
└── data/
    ├── fixtures/
    │   ├── forcing/
    │   ├── fv_advection/
    │   ├── spectral/
    │   └── transforms/
    └── reference_outputs/
        ├── 1day/
        ├── 30day/
        └── T85L25/
```

## Build System

### CMake Structure

```cmake
# end2end_experiment/CMakeLists.txt
cmake_minimum_required(VERSION 3.18)
project(HeldSuarezCUDA LANGUAGES CXX CUDA Fortran)

# Options
option(ENABLE_CUDA "Enable CUDA backend" ON)
option(BUILD_TESTS "Build test suite" ON)
option(ENABLE_PROFILING "Enable NVTX profiling" OFF)

# Find packages
find_package(CUDAToolkit REQUIRED)
find_package(MPI REQUIRED)

# Subdirectories
add_subdirectory(src/kernels)
add_subdirectory(src/infrastructure)
add_subdirectory(src/orchestration)
add_subdirectory(src/integration)

if(BUILD_TESTS)
    add_subdirectory(tests)
endif()

if(BUILD_BENCHMARKS)
    add_subdirectory(benchmarks)
endif()
```

### Kernel Library CMake

```cmake
# end2end_experiment/src/kernels/CMakeLists.txt

# FV Advection kernels
add_library(fv_advection_cuda STATIC
    fv_advection/semi_y_3d.cu
    fv_advection/semi_x_3d.cu
    fv_advection/slope_sphere.cu
    fv_advection/slope_x.cu
    fv_advection/vanleer_sphere_3d.cu
    fv_advection/vanleer_x_3d.cu
    fv_advection/find_cell_x.cu
    fv_advection/integer_flux_x.cu
)

target_include_directories(fv_advection_cuda PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/fv_advection
)

target_link_libraries(fv_advection_cuda
    CUDA::cudart
    gpu_infrastructure
)

set_target_properties(fv_advection_cuda PROPERTIES
    CUDA_SEPARABLE_COMPILATION ON
    CUDA_ARCHITECTURES "70;75;80;86"
)
```

## Testing Framework

### Unit Test Example

```cuda
// end2end_experiment/tests/unit/test_semi_y_3d.cu

#include <gtest/gtest.h>
#include "semi_y_3d.h"
#include "test_fixtures.h"

TEST(SemiY3D, SyntheticPositiveVelocity) {
    // Setup
    const int nx = 64, ny = 32, nz = 16;
    auto fixture = create_semi_y_3d_fixture(nx, ny, nz, "positive_va");
    
    // Allocate device memory
    double *d_dq, *d_va, *d_q;
    cudaMalloc(&d_dq, nx*ny*nz*sizeof(double));
    cudaMalloc(&d_va, nx*ny*nz*sizeof(double));
    cudaMalloc(&d_q, nx*ny*nz*sizeof(double));
    
    // Copy inputs
    cudaMemcpy(d_va, fixture.va.data(), fixture.va.size()*sizeof(double), 
               cudaMemcpyHostToDevice);
    cudaMemcpy(d_q, fixture.q.data(), fixture.q.size()*sizeof(double), 
               cudaMemcpyHostToDevice);
    
    // Run kernel
    semi_y_3d_cuda(d_dq, d_va, d_q, nx, ny, nz, fixture.dy, fixture.dt);
    
    // Copy result
    std::vector<double> result(nx*ny*nz);
    cudaMemcpy(result.data(), d_dq, result.size()*sizeof(double), 
               cudaMemcpyDeviceToHost);
    
    // Compare against baseline
    auto baseline = load_baseline("semi_y_3d_positive_va.bin");
    double max_err = compare_arrays(result, baseline, 1e-14);
    
    EXPECT_LT(max_err, 1e-14);
    
    // Cleanup
    cudaFree(d_dq);
    cudaFree(d_va);
    cudaFree(d_q);
}
```

## Memory Management Strategy

### GPU Memory Manager

```cpp
// end2end_experiment/src/infrastructure/gpu_memory_manager.h

class GPUMemoryManager {
public:
    // Singleton access
    static GPUMemoryManager& instance();
    
    // Allocate persistent buffer
    template<typename T>
    T* allocate(const std::string& name, size_t count);
    
    // Get existing buffer
    template<typename T>
    T* get(const std::string& name);
    
    // Free specific buffer
    void free(const std::string& name);
    
    // Free all buffers
    void reset();
    
    // Memory usage statistics
    size_t total_allocated() const;
    size_t peak_allocated() const;
    
private:
    GPUMemoryManager() = default;
    ~GPUMemoryManager();
    
    struct BufferInfo {
        void* ptr;
        size_t size;
        std::string type_name;
    };
    
    std::unordered_map<std::string, BufferInfo> buffers_;
    size_t total_allocated_ = 0;
    size_t peak_allocated_ = 0;
};
```

### Data Residency Pattern

```cpp
// Initialize once at model startup
void initialize_gpu_state(const ModelConfig& config) {
    auto& mem = GPUMemoryManager::instance();
    
    // Allocate all persistent arrays
    mem.allocate<double>("state_u", config.nx * config.ny * config.nz);
    mem.allocate<double>("state_v", config.nx * config.ny * config.nz);
    mem.allocate<double>("state_t", config.nx * config.ny * config.nz);
    mem.allocate<double>("tracers", config.nx * config.ny * config.nz * config.ntracers);
    
    // Spectral arrays
    mem.allocate<cuDoubleComplex>("spectral_vort", config.n_total * config.nz);
    mem.allocate<cuDoubleComplex>("spectral_div", config.n_total * config.nz);
    mem.allocate<cuDoubleComplex>("spectral_temp", config.n_total * config.nz);
    
    // Workspace arrays
    mem.allocate<double>("work_slopes", config.nx * config.ny * config.nz * 2);
    mem.allocate<double>("work_fluxes", config.nx * config.ny * config.nz);
}

// Use throughout time integration
void timestep_gpu(int step) {
    auto& mem = GPUMemoryManager::instance();
    
    // All kernels access persistent GPU memory - zero CPU-GPU transfers
    fv_advection_update(
        mem.get<double>("tracers"),
        mem.get<double>("state_u"),
        mem.get<double>("state_v"),
        mem.get<double>("work_slopes"),
        mem.get<double>("work_fluxes")
    );
    
    spectral_dynamics_update(
        mem.get<cuDoubleComplex>("spectral_vort"),
        mem.get<cuDoubleComplex>("spectral_div"),
        mem.get<cuDoubleComplex>("spectral_temp")
    );
}
```

## Validation Protocol

### Tolerance Specification

| Test Type | Absolute Tolerance | Relative Tolerance | Rationale |
|-----------|-------------------|-------------------|----------|
| Unit (CPU) | 0.0 | 0.0 | Exact match expected |
| Unit (CUDA) | 1e-15 | 1e-14 | Double precision limit |
| Integration | 1e-12 | 1e-11 | Accumulation of kernel errors |
| 1-day run | 1e-10 | 1e-9 | Multiple timesteps |
| 30-day run | 1e-6 | 1e-5 | Long integration, chaos |

### Comparison Metrics

```python
# end2end_experiment/scripts/utils/compare_netcdf.py

def compare_fields(baseline, candidate, field_name, tolerance):
    """
    Compare two NetCDF fields with detailed diagnostics.
    """
    base_data = baseline.variables[field_name][:]
    cand_data = candidate.variables[field_name][:]
    
    metrics = {
        'max_abs_diff': np.max(np.abs(base_data - cand_data)),
        'rmse': np.sqrt(np.mean((base_data - cand_data)**2)),
        'max_rel_diff': np.max(np.abs((base_data - cand_data) / (base_data + 1e-30))),
        'correlation': np.corrcoef(base_data.flat, cand_data.flat)[0, 1],
        'pattern_correlation': pattern_corr(base_data, cand_data)
    }
    
    passed = metrics['max_abs_diff'] < tolerance['absolute'] and \
             metrics['max_rel_diff'] < tolerance['relative']
    
    return passed, metrics
```

## Performance Targets

### Expected Speedups

| Component | Target Speedup | Confidence |
|-----------|----------------|------------|
| FV advection kernels | 5-10x | High |
| Spectral operators | 3-5x | Medium |
| Transforms | 10-20x | High (with cuFFT) |
| Overall model | 3-5x | Medium |

### Profiling Methodology

```bash
# Profile CUDA kernels
nsys profile -o timeline.qdrep \
    --stats=true \
    ./held_suarez_cuda.x

# Analyze results
nsys stats timeline.qdrep

# Generate report
python scripts/utils/extract_timings.py timeline.qdrep > timings.json
python scripts/utils/plot_results.py timings.json
```

## Risk Mitigation

### Technical Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Numerical accuracy drift | High | Strict validation at every stage |
| GPU memory exhaustion | High | Profiling, optimization, fallback to CPU |
| Transform accuracy issues | High | Extensive round-trip testing |
| MPI/GPU interaction | Medium | Keep MPI in Fortran, careful host-device sync |
| Build complexity | Medium | Modular CMake, clear documentation |

### Schedule Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Transform layer complexity | High | Allow extra time, consider library-only approach |
| Integration issues | Medium | Incremental integration with rollback points |
| Hardware availability | Medium | Cloud GPU instances, queue time planning |

## Success Criteria

### Phase 1-2 (FV Advection)
- ✅ All FV kernels pass unit tests
- ✅ 30-day run completes
- ✅ Output fields within tolerance
- ✅ Measurable speedup in advection region

### Phase 3-4 (Spectral + Transforms)
- ✅ Spectral operators validated
- ✅ Transform round-trip < 1e-12 error
- ✅ Energy conservation maintained
- ✅ Significant overall speedup

### Phase 7 (End-to-End)
- ✅ Complete GPU-accelerated model runs
- ✅ 30-day climatology matches baseline
- ✅ 3x+ speedup on T85L25
- ✅ 5x+ speedup on T170L50
- ✅ All documentation complete
- ✅ Reproducible build process

## Deliverables Checklist

### Code
- [ ] All CUDA kernels in `src/kernels/`
- [ ] C API layer complete
- [ ] Fortran wrappers complete
- [ ] Memory management infrastructure
- [ ] Build system (CMake)
- [ ] All unit tests
- [ ] Integration test suite
- [ ] Validation scripts

### Documentation
- [ ] This master plan
- [ ] Architecture documentation
- [ ] Per-kernel documentation
- [ ] Build instructions
- [ ] User guide
- [ ] Performance analysis reports
- [ ] Validation reports

### Validation
- [ ] All unit test results
- [ ] Integration test results
- [ ] 1-day validation reports
- [ ] 30-day validation reports
- [ ] T85L25 performance comparison
- [ ] T170L50 scaling study
- [ ] Memory profiling results

## Next Steps

### Immediate (Week 1)
1. ✅ Create directory structure
2. ✅ Write master plan (this document)
3. [ ] Set up CMake build system
4. [ ] Implement GPU memory manager
5. [ ] Create first kernel: `semi_x_3d`

### Short-term (Weeks 2-4)
1. [ ] Complete all FV advection kernels
2. [ ] Unit test suite for all kernels
3. [ ] Integration test for FV advection
4. [ ] First 30-day validation run

### Medium-term (Weeks 5-12)
1. [ ] Spectral operators
2. [ ] Transform layer
3. [ ] Time integration
4. [ ] Performance optimization

### Long-term (Weeks 13-20)
1. [ ] End-to-end integration
2. [ ] Comprehensive validation
3. [ ] Scaling studies
4. [ ] Final documentation
5. [ ] Publication preparation

---

**Document Status**: Living document, updated as implementation progresses
**Last Updated**: 2024
**Next Review**: After Phase 1 completion