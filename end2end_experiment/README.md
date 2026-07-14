# End-to-End CUDA Held-Suarez Experiment

## Objective

Complete CUDA conversion of the entire Held-Suarez test case, building upon existing validated components while keeping all original source files untouched.

## Status

This directory contains the complete end-to-end CUDA implementation of Held-Suarez, organized independently from the original codebase.

### Completed Components (from existing work)
- ✅ hs_forcing module (CPU/CUDA validated)
- ✅ semi_y_3d kernel (CPU/CUDA validated, 30-day runs complete)

### New Components (in this directory)
- 🔄 Complete FV advection kernel suite
- 🔄 Spectral dynamics components
- 🔄 Transform layer
- 🔄 Full integration harness

## Directory Structure

```
end2end_experiment/
├── README.md                          # This file
├── MASTER_PLAN.md                     # Complete conversion roadmap
├── docs/                              # All new documentation
│   ├── architecture/                  # System design docs
│   ├── validation/                    # Validation reports
│   └── performance/                   # Performance analysis
├── src/                               # All CUDA/C++ source code
│   ├── kernels/                       # Individual CUDA kernels
│   │   ├── forcing/                   # Forcing kernels
│   │   ├── fv_advection/             # Finite-volume advection
│   │   ├── spectral/                  # Spectral operators
│   │   └── transforms/                # Transform routines
│   ├── orchestration/                 # High-level orchestration
│   ├── infrastructure/                # Memory management, utilities
│   └── integration/                   # Fortran/C++ integration layer
├── tests/                             # All test harnesses
│   ├── unit/                          # Per-kernel unit tests
│   ├── integration/                   # Multi-kernel integration tests
│   └── validation/                    # Full model validation
├── benchmarks/                        # Performance benchmarks
├── scripts/                           # Build and run scripts
└── data/                              # Reference data and fixtures

```

## Design Principles

1. **Non-invasive**: Zero modifications to original Fortran source
2. **Modular**: Each kernel/module can be enabled/disabled independently
3. **Validated**: Every component has unit tests and validation against Fortran baseline
4. **Performance-aware**: Profile-guided optimization priorities
5. **GPU-resident**: Minimize CPU-GPU transfers through persistent data structures
6. **Fallback-ready**: CPU path always available

## Build Strategy

All builds will be self-contained within this directory, using:
- CMake for build configuration
- Custom integration with Isca's CodeBase.compile() where needed
- Separate compilation targets for each module layer

## Integration Approach

```
Fortran Production Code (untouched)
    ↓
Fortran Overlay Wrappers (src/integration/fortran/)
    ↓
C API Layer (src/integration/c_api/)
    ↓
C++/CUDA Implementations (src/kernels/)
```

## Validation Ladder

Every component follows this progression:
1. **Unit test** - Synthetic fixtures, exact validation
2. **Module test** - Captured model fixtures
3. **Integration test** - Multi-module orchestration
4. **1-day run** - Smoke test
5. **30-day run** - Scientific validation
6. **Scaling test** - T85/T170 performance

## Current Phase

**Phase 1**: Complete FV advection kernel suite
- Target: All kernels in `fv_advection_mod`
- Status: semi_y_3d complete, expanding to remaining kernels

## Quick Start

```bash
cd end2end_experiment

# Build all components
./scripts/build_all.sh

# Run unit tests
./scripts/run_unit_tests.sh

# Run validation suite
./scripts/run_validation.sh

# Generate performance report
./scripts/generate_performance_report.sh
```

## References

See existing documentation:
- `memory/FULL_CUDA_MODERNIZATION_CHECKPOINT.md`
- `docs/full_held_suarez_cuda_modernization_master_plan.md`
- `memory/SEMI_Y_3D_PHASE1_CHECKPOINT.md`

---

Last updated: 2024