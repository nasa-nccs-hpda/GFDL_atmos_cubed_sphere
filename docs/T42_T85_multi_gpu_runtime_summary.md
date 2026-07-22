# T42/T85 Multi-GPU Runtime Summary

## Purpose

Summarize the Held-Suarez FV advection CUDA resident `a_grid` multi-GPU
experiments and decide where to look next for performance.

The tested CUDA path is:

```text
FV_KERNELS_CUDA_MODE=resident
FV_KERNELS_RESIDENT_BOUNDARY=a_grid
FV_KERNELS_RESIDENT_STATIC_METRICS=1
FV_KERNELS_RESIDENT_Q1_TRANSFER=halo_only
```

The multi-GPU mapping code uses:

```text
FV_KERNELS_GPU_MAPPING=local_rank
```

For one rank per node/GPU:

```text
FV_KERNELS_REQUIRE_UNIQUE_GPU=1
```

## Source Logs

```text
logs/fv_kernels_cuda_a_grid_30day.log
logs/fv_kernels_cuda_a_grid_4node_4gpu_manual_30day.log
logs/fv_kernels_cuda_a_grid_16rank_4node_4gpu_manual_30day.log
logs/fv_kernels_cuda_a_grid_16node_16gpu_manual_30day_final.log
logs/fv_kernels_cuda_a_grid_16node_16gpu_T85L25_30day.log
logs/T85L25_dynamics_region_profile_16node_30day.log
```

## Runtime Table

| Case | Resolution | MPI Layout | GPU Layout | MPP Runtime | CUDA Region Max | Result |
|---|---|---|---|---:|---:|---|
| CPU C++ FV bundle | T42L25 | 16 ranks | CPU only | 25.546 s | n/a | Reference |
| CUDA `a_grid` single GPU | T42L25 | 16 ranks on 1 node | 16 ranks / 1 GPU | 51.000 s | about 20.3 s | Best CUDA total runtime so far |
| CUDA `a_grid` 4 nodes | T42L25 | 4 ranks, 1/node | 1 rank / GPU | 96.413 s | not primary | Too few MPI ranks |
| CUDA `a_grid` 4 nodes | T42L25 | 16 ranks, 4/node | 4 ranks / GPU | 85.330 s | about 4.85 s | CUDA faster, total slower |
| CUDA `a_grid` 16 nodes | T42L25 | 16 ranks, 1/node | 1 rank / GPU | 63.973 s | 1.019 s | CUDA fastest, total still slower |
| CUDA `a_grid` 16 nodes | T85L25 | 16 ranks, 1/node | 1 rank / GPU | 319.243 s | 1.862 s | Full runtime dominated elsewhere |

## T42L25 Findings

The T42L25 runs confirmed that GPU contention was a real CUDA-region bottleneck.

CUDA resident region max:

```text
16 ranks / 1 GPU:    about 20.3 s
16 ranks / 4 GPUs:   about 4.85 s
16 ranks / 16 GPUs:  about 1.02 s
```

However, total MPP runtime did not improve with multi-node multi-GPU execution:

```text
16 ranks / 1 GPU:    51.000 s
16 ranks / 4 GPUs:   85.330 s
16 ranks / 16 GPUs:  63.973 s
```

Interpretation:

```text
Multi-GPU mapping solves CUDA contention, but T42L25 is too communication-heavy
and too small per rank for multi-node execution to improve end-to-end runtime.
```

## T85L25 Findings

The T85L25 16-node / 16-GPU run completed successfully.

Model domain decomposition:

```text
X-AXIS = 256
Y-AXIS = 8 x 16 ranks
```

Runtime:

```text
Total runtime tmax = 319.242612 s
```

CUDA resident profile:

```text
calls/rank = 17280
CUDA resident total mean = 1.839 s
CUDA resident total max  = 1.862 s
H2D mean                 = 0.946 s
kernel mean              = 0.257 s
sync mean                = 0.133 s
D2H mean                 = 0.181 s
```

FV CUDA resident fraction of T85L25 runtime:

```text
1.862 / 319.243 = 0.58%
```

Interpretation:

```text
At T85L25, the FV advection CUDA resident boundary is no longer an important
fraction of total runtime. The bottleneck is elsewhere in dynamics, transforms,
communication, diagnostics, or another non-FV region.
```

## Scaling Observation

Going from T42L25 to T85L25 on 16 nodes / 16 GPUs:

| Metric | T42L25 | T85L25 | Growth |
|---|---:|---:|---:|
| Total MPP runtime | 63.973 s | 319.243 s | 4.99x |
| CUDA resident max | 1.019 s | 1.862 s | 1.83x |
| CUDA runtime fraction | 1.59% | 0.58% | lower |

The full model runtime grows much faster than the FV CUDA region. That means
the next performance target should not be more FV kernel tuning.

## Conclusion

The multi-GPU CUDA mapping work was successful as an architecture experiment:

- node-aware local-rank GPU selection works;
- 16 nodes / 16 GPUs runs correctly;
- CUDA runtime drops dramatically when GPU sharing is removed;
- node-local sandbox management is now reproducible with `build_sandbox.sh`.

But for performance:

```text
FV advection CUDA resident `a_grid` is not the dominant T85L25 bottleneck.
```

The follow-up T85L25 dynamics-region profile confirmed the next bottleneck is
elsewhere in spectral dynamics:

| T85L25 Region | Time Max | MPP Runtime Fraction |
|---|---:|---:|
| `transforms` | 142.453 s | 46.54% |
| `tracer_correction_diagnostics` | 65.415 s | 21.37% |
| `advection` | 33.061 s | 10.80% |
| `press_geopot` | 18.411 s | 6.01% |
| `damping` | 7.891 s | 2.58% |
| `leapfrog_update` | 1.347 s | 0.44% |

## Recommendation

Use the T85L25 dynamics-region result to guide the next profiling step.

The top measured region is:

```text
transforms
```

But it is coupled enough that translation should not begin directly from the
coarse timer. The next step is deeper T85L25 timing inside:

- transform-heavy spectral dynamics;
- tracer/update/correction/diagnostic region;
- remaining advection region;
- pressure/geopotential as a fallback.

Detailed recommendation:

```text
docs/T85L25_dynamics_region_profile_recommendation.md
```
