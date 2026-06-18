# T85L25 Forcing Performance Results

Date: 2026-06-17

## Inputs

Log files used:

```text
logs/T85L25_fortran_30day.log
logs/T85L25_hybrid_cpu_30day.log
logs/T85L25_hybrid_cuda_30day.log
```

Note: the requested `logs/T85L25_cpu_hybrid_30day.log` and
`logs/T85L25_cuda_hybrid_30day.log` names were not present; the actual run
scripts wrote `T85L25_hybrid_cpu_30day.log` and
`T85L25_hybrid_cuda_30day.log`.

Run configuration:

```text
resolution = T85
levels = 25
dt_atmos = 300 s
duration = 30 days
MPI ranks = 16
diagnostics = production Held-Suarez monthly diagnostics
forcing calls = 8640 per MPI rank
```

## Runtime Summary

Primary speedup numbers below use the model MPP `Total runtime` from the FMS
timing table. Shell `real` time is included as a secondary end-to-end launch
measurement.

| Variant | Backend | MPP Runtime (s) | Shell Real (s) | Shell User (s) | Shell Sys (s) |
|---|---|---:|---:|---:|---:|
| Fortran | original Fortran | 206.761 | 214.209 | 3109.911 | 203.236 |
| CPU hybrid | C++ CPU forcing | 200.475 | 207.580 | 3029.809 | 182.059 |
| CUDA hybrid | CUDA forcing POC | 320.956 | 328.019 | 4538.236 | 532.620 |

## Observed Speedups

| Comparison | MPP Speedup | Shell Real Speedup | Interpretation |
|---|---:|---:|---|
| CPU hybrid vs Fortran | 1.031x | 1.032x | Small end-to-end speedup |
| CUDA hybrid vs Fortran | 0.644x | 0.653x | Slowdown |
| CUDA hybrid vs CPU hybrid | 0.625x | 0.633x | CUDA run is about 1.60x slower than CPU hybrid |

Equivalently, the CPU hybrid reduced MPP runtime by about 3.0%, while the CUDA
hybrid increased MPP runtime by about 55.2% relative to the Fortran baseline.

## Forcing Timing

Hybrid forcing profile summaries print once per MPI rank.  The table uses the
maximum rank time because the slowest rank controls elapsed MPI runtime.

| Variant | Region | Calls | Time Min (s) | Time Mean (s) | Time Max (s) | Avg Time/Call at Max (s) | Fraction of MPP Runtime |
|---|---|---:|---:|---:|---:|---:|---:|
| CPU hybrid | Fortran ISO_C wrapper | 8640 | 8.564 | 8.655 | 8.763 | 1.014e-3 | 4.37% |
| CPU hybrid | C interface entry | 8640 | 8.553 | 8.635 | 8.740 | 1.012e-3 | 4.36% |
| CPU hybrid | C++ forcing driver | 8640 | 8.532 | 8.614 | 8.719 | 1.009e-3 | 4.35% |
| CUDA hybrid | Fortran ISO_C wrapper | 8640 | 80.498 | 81.731 | 83.690 | 9.686e-3 | 26.08% |
| CUDA hybrid | C interface entry | 8640 | 80.584 | 81.744 | 83.750 | 9.693e-3 | 26.09% |

CPU C++ hotspot split, max rank:

| CPU Region | Time Max (s) | Fraction of C++ Driver |
|---|---:|---:|
| newtonian_vertical | 6.987 | about 80% |
| rayleigh_damping | 0.708 | about 8% |
| accumulate_wind | 0.421 | about 5% |
| accumulate_temperature | 0.294 | about 3% |
| newtonian_lat_precompute | 0.121 | about 1% |

The CUDA profile currently reports the total C interface entry time but does
not expose the same internal kernel breakdown.  The total includes CPU/GPU data
movement, kernel launch, synchronization, and local per-call allocation/free
overhead.

## Amdahl Estimates

Because the unmodified all-Fortran forcing routine was not instrumented in this
run, the forcing fraction is estimated from the CPU hybrid timing:

```text
estimated forcing fraction of Fortran baseline
  = CPU hybrid C interface max time / Fortran MPP runtime
  = 8.739947634 / 206.761356
  = 4.23%
```

The theoretical maximum speedup if this entire forcing region became free is:

```text
S_max = 1 / (1 - f)
      = 1 / (1 - 0.0423)
      = 1.044x
```

| Case | Forcing Fraction Used | Theoretical Max Speedup | Observed Speedup vs Fortran | Efficiency |
|---|---:|---:|---:|---:|
| CPU hybrid | 4.23% of Fortran MPP runtime | 1.044x | 1.031x | 71% of possible improvement |
| CUDA hybrid | same Fortran forcing opportunity | 1.044x | 0.644x | negative improvement; slowdown |

Here, "efficiency" for CPU means:

```text
(observed_speedup - 1) / (theoretical_max_speedup - 1)
```

For CPU hybrid, the observed 3.1% speedup captures roughly 71% of the maximum
possible gain implied by the measured forcing fraction.  For CUDA, the same
Amdahl ceiling is not approached because the CUDA forcing path is slower than
the CPU path.

For context, using the CUDA run's own measured forcing wrapper time:

```text
CUDA forcing fraction of CUDA MPP runtime = 83.750 / 320.956 = 26.09%
```

This does not mean the model has a large useful CUDA speedup opportunity.  It
means the CUDA forcing implementation added a large per-call overhead region.

## Why Observed Speedup Differs from Ideal

The CPU hybrid is close to the Amdahl limit because the forcing module is only
about 4% of total runtime at T85L25.  Even making the forcing infinitely fast
could only produce about a 4.4% end-to-end speedup.  The observed 3.1% speedup
is therefore plausible and already near the useful ceiling for a forcing-only
replacement.

The CUDA hybrid is slower because this CUDA backend was intentionally built as
an architecture proof of concept, not an optimized performance path:

- every forcing call transfers data between CPU and GPU;
- GPU allocations are local to each forcing call;
- each call pays kernel launch and synchronization overhead;
- the rest of the model remains CPU-resident;
- the forcing arithmetic is too small relative to transfer/launch overhead;
- 16 MPI ranks may contend for the same visible GPU resource unless the run is
  explicitly mapped across GPUs;
- the CUDA profile reports only C interface entry time, so the measured 80+ s
  includes transfer and runtime overhead rather than pure kernel arithmetic.

## Conclusion

For T85L25, the CPU C++ hybrid forcing path gives a small but measurable
end-to-end speedup.  The CUDA forcing path is a successful architecture
validation path but is not a useful speedup target in this form.

Recommended interpretation:

```text
CPU C++ forcing replacement: small positive performance value.
CUDA forcing replacement: architecture proof only; performance impact is negative.
Next performance work: target larger dynamics/transform/advection regions rather than Held-Suarez forcing.
```
