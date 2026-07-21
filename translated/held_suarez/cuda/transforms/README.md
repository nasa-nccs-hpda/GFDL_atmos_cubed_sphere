# transforms — T2 compute-ceiling prototype

Standalone GPU prototype for the transform-stack feasibility study (phase T2).
Single rank, **no transpose**: measures the compute ceiling of the Legendre
(cuBLAS batched ZGEMM) + FFT (cuFFT) halves vs a single-core CPU reference, at
the full single-rank tile and the 16-rank per-rank tile.

- Design, plan, and go/no-go path: `docs/transform_stack_feasibility_plan.md`
- T1 structure/transpose analysis: `docs/transform_feasibility_analysis.md`
- **Build/run commands + results template: `docs/transform_compute_prototype_results.md`**

CPU reference + tables are in `../../cpp/transforms/` (pure C++, no CUDA); the
GPU stages, timing, and harness are here. Build on an H100 node in the
container:

```bash
make ARCH=sm_90 && ./transform_bench
```

The transform math, FFT normalization, and GEMM operand layouts are already
validated off-device (see the results doc); the host run adds only the CUDA
execution + timing numbers.
