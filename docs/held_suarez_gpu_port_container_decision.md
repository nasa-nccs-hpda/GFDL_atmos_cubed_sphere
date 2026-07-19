# GPU Porting for Held-Suarez — Container Modification Decision

**Decision at hand:** whether to modify the build container to add the NVIDIA HPC SDK (`nvfortran` + OpenACC runtime), enabling a **direct Fortran→GPU** path, versus the alternatives.

## Terms used below

- **Direct Fortran→GPU:** the model's existing Fortran source annotated with OpenACC directives (`!$acc ...`) and compiled by a GPU-capable Fortran compiler (`nvfortran`) — single-source, no separate C++/CUDA implementation. The algorithm stays in Fortran; only directives are added.
- **Amdahl's law:** the whole-program speedup from accelerating one part is capped by the fraction of total runtime that part represents — an infinitely fast component still only removes its own share of the time.

## Why a container change is even in question (the technical constraint)

- The spectral H-S model is compiled **inside the apptainer container** with gfortran. The container has `nvcc` but **not `nvfortran`**.
- The direct Fortran→GPU path requires a GPU-capable Fortran compiler (`nvfortran`). The container's gfortran advertises nvptx offload but lacks the accelerator backend, so it cannot offload.
- `nvfortran` exists only as a **host** module. Host-built objects cannot be reliably linked into a container (Debian) gfortran binary, and nvfortran Fortran modules cannot be mixed with gfortran modules.
- Therefore the only ways to run the direct Fortran→GPU path *in the model* are: put `nvfortran` in the model's build environment (modify the container), or move the entire model build to the host.

## Options (full set)

| Option | What it is | Enables | Cost |
|---|---|---|---|
| **A. Add nvhpc to the container** | Rebuild/extend the image with the NVIDIA HPC SDK | Direct Fortran→GPU in-model; mirrors the working CUDA hybrid build; reuses all existing plumbing | One-time image rebuild + validation + maintenance/reproducibility burden (below) |
| **B. Whole-model nvfortran build on host** | Build FMS, netCDF, Isca with nvfortran outside the container | Same direct path, no container change | Large, high-risk systems integration; new dependency chain to maintain |
| **C. Stay with CUDA C++ in current container** | Extend the existing nvcc-based overlay | Works today; advection already done | Every new region = substantial CUDA C++ + C interface; not single-source Fortran |

## What makes the container change worthwhile — scope, not language

- Advection (~12% of wall time) is **already ported in CUDA, verified, and measured: ≈1.6% / 0.4% whole-model speedup at T85 / T170.** Redoing it via the direct Fortran→GPU path yields the *same* result. For advection alone, no environment change is justified.
- The real speedup lives in **transforms (~39%) and tracer/correction (~33%) — ~72% combined — and neither is ported in any language.**
- Porting those in CUDA C++ (Option C) means a large, sustained volume of C++ plus C interfaces — the work we want to avoid.
- Porting them via direct Fortran→GPU (Option A or B) is far less code, single-source, and maintainable by the Fortran team.
- **Conclusion:** the container modification is worthwhile only if we commit to porting the large regions. It is a one-time enabling cost that amortizes across ~72% of runtime and avoids a mountain of CUDA C++.

## Cost of modifying the container (for the "worthwhile" judgment)

- Rebuild the image with the NVIDIA HPC SDK (sizable addition; larger image).
- Re-validate the full toolchain in-container (compilers, MPI, netCDF, FMS build) and confirm bit-reproducible model results.
- Reproducibility/governance: version and distribute the new image; all collaborators and CI must adopt it; document provenance.
- Ongoing maintenance: keep SDK/CUDA/driver versions consistent with the GPU nodes.
- Risk is bounded and one-time — unlike Option B, the model build itself is unchanged; only the compiler is added.

## Recommendation / question for the team

- If we intend to GPU-port transforms and tracer/correction: **Option A (modify the container)** is the best value — smallest change that unlocks the direct Fortran→GPU path for all target regions, reusing existing overlay plumbing.
- If advection is the only scope: change nothing; the CUDA result already exists.
- Decision needed: **are we committing to the large regions (transforms, tracer/correction), which is what justifies modifying the container?**
- Caveat (Amdahl's law — speedup is capped by the share of runtime you accelerate): all whole-model gains are bounded this way — advection ~1.6%; meaningful reduction requires the large regions regardless of language or environment.
