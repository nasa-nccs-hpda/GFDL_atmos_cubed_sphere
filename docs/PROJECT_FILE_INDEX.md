# Held-Suarez Modernization Project File Index

Search this file by topic, module, script name, experiment name, or artifact type.
Paths are relative to the repository unless shown as absolute.

## Handoff Entry Points

| Path | Description |
|---|---|
| `docs/PROJECT_HANDOFF_EXECUTIVE_SUMMARY.md` | Project motivation, achievements, performance conclusions, risks, and roadmap for leads. |
| `docs/PROJECT_HANDOFF_TECHNICAL_GUIDE.md` | Repository architecture, build, validation, profiling, CUDA modes, and pitfalls for developers. |
| `docs/PROJECT_HANDOFF_RESUME_GUIDE.md` | Current state, do-not-repeat list, prioritized next task, and exact continuation commands. |
| `memory/FINAL_PROJECT_CHECKPOINT_2026-06-19.md` | Dated factual restart point with branch, executables, outputs, results, and next action. |
| `docs/PROJECT_FILE_INDEX.md` | This searchable artifact catalog. |

## Current Status And Checkpoints

| Path | Description |
|---|---|
| `memory/MIGRATION_STATUS.md` | Concise status ledger for forcing and early FV milestones. |
| `memory/PERFORMANCE_MODERNIZATION_CHECKPOINT_2026-06-18.md` | Profiling-driven transition from forcing to FV advection. |
| `memory/FV_ADVECTION_KERNEL_BUNDLE_CHECKPOINT.md` | Complete CPU/CUDA kernel-bundle checkpoint before residency optimization. |
| `memory/T85L25_FORCING_PERFORMANCE_CHECKPOINT.md` | T85L25 forcing experiment commands, outputs, timing, and lessons. |
| `memory/FULL_CUDA_MODERNIZATION_CHECKPOINT.md` | Full-model CUDA roadmap checkpoint. |
| `memory/SEMI_Y_3D_PHASE1_CHECKPOINT.md` | Baseline-harness restart point for the first FV kernel. |
| `memory/HYBRID_PHASE4_CHECKPOINT.md` | Historical native forcing-overlay build checkpoint. |
| `memory/PERFORMANCE_MODERNIZATION_CHECKPOINT.md` | Earlier performance modernization status; superseded by dated checkpoint. |
| `memory/CODEX_HANDOFF.md` | Historical build-investigation handoff; many blockers are now solved. |
| `memory/KNOWN_ISSUES.md` | Historical compiler/container issues and environment notes. |

## Architecture And Master Plans

| Path | Description |
|---|---|
| `docs/end_to_end_hybrid_modernization_workflow.md` | Reusable Fortran-to-C++/CUDA modernization workflow. |
| `docs/full_held_suarez_cuda_modernization_master_plan.md` | Phased roadmap for modernizing the full Held-Suarez path. |
| `docs/full_cuda_modernization_module_table.md` | Module inventory classified by CUDA strategy, risk, and validation path. |
| `docs/isca_overlay_strategy.md` | How `CodeBase.compile()`, source overlays, and precedence work. |
| `docs/native_overlay_build.md` | Native overlay classes, flags, templates, and executable locations. |
| `docs/hybrid_build_process_map.md` | Isca build flow and generated artifact relationships. |
| `docs/hybrid_integration_plan.md` | Original forcing hybrid integration design. |
| `docs/hybrid_run_plan.md` | How a prebuilt hybrid executable is selected and run. |
| `docs/resolution_scaling_plan.md` | T42/T85/T170 performance-scaling workflow. |
| `docs/resolution_scaling_matrix.md` | Scaling results/template matrix including forcing and dynamics columns. |

## Profiling And Target Selection

| Path | Description |
|---|---|
| `docs/profiling_plan_for_module_selection.md` | Method for selecting targets by measured wall-clock contribution. |
| `docs/next_module_ranking.md` | Initial static candidate ranking. |
| `docs/next_module_performance_decision.md` | Performance-oriented top candidates and initial recommendation. |
| `docs/four_in_one_feasibility_analysis.md` | Interface and dependency analysis for `four_in_one`. |
| `docs/four_in_one_timing_plan.md` | Overlay timing design for `four_in_one`. |
| `docs/four_in_one_profile_recommendation.md` | Measured 2.6% result and no-go performance decision. |
| `docs/vert_advection_profile_plan.md` | Call-site timing plan for u, v, and temperature vertical advection. |
| `docs/vert_advection_profile_recommendation.md` | Measured 0.34% result and no-go decision. |
| `docs/dynamics_region_profile_plan.md` | Coarse dynamics-region instrumentation plan. |
| `docs/dynamics_region_profile_recommendation.md` | Coarse hotspot ranking: transforms, tracer/correction, advection, pressure. |
| `docs/dynamics_deep_profile_plan.md` | Second-level timer design. |
| `docs/dynamics_deep_profile_recommendation.md` | Deep result identifying `update_tracers` and tracer horizontal advection. |

## FV Advection Design And Translation

| Path | Description |
|---|---|
| `docs/a_grid_horiz_advection_3d_feasibility_analysis.md` | Recommends Fortran halo/domain wrapper with local translated kernels. |
| `docs/fv_advection_kernel_modernization_plan.md` | Kernel call graph, ranking, fixture design, and first-kernel selection. |
| `docs/translation_spec_semi_y_3d.md` | Exact `semi_y_3d` semantics, indexing, API, and validation specification. |
| `docs/semi_y_3d_baseline_harness_report.md` | Test-only Fortran fixture and private-routine strategy. |
| `docs/semi_y_3d_cpp_translation_report.md` | CPU C++ implementation and comparison result. |
| `docs/semi_y_3d_cuda_fixture_report.md` | CUDA fixture implementation and result. |
| `docs/semi_y_3d_fortran_c_integration_report.md` | CPU/CUDA C ABI and Fortran wrapper validation. |
| `docs/semi_y_3d_native_overlay_integration_report.md` | Native model build, smoke test, and 30-day semi-y validation. |
| `docs/fv_advection_kernel_bundle_plan.md` | Multi-kernel bundle scope and implementation sequence. |
| `docs/fv_advection_kernel_bundle_translation_report.md` | Bundle source, ABI, fixture, native build, and model validation status. |
| `docs/fv_advection_kernel_bundle_profile_plan.md` | CPU/CUDA bundle profiling markers and run plan. |

## CUDA Performance Architecture

| Path | Description |
|---|---|
| `docs/cuda_fv_advection_performance_diagnosis.md` | Why per-call fine-grained CUDA wrappers are structurally slow. |
| `docs/fv_advection_cuda_microbenchmark_plan.md` | Stateless versus persistent unit benchmark design. |
| `docs/fv_advection_cuda_microbenchmark_results.md` | Allocation, transfer, launch, synchronization, and kernel timing results. |
| `docs/fv_advection_cuda_data_residency_design.md` | Persistent buffers, fusion, and broader-boundary alternatives. |
| `docs/fv_advection_cuda_persistent_buffer_plan.md` | Persistent per-rank buffer implementation plan. |
| `docs/fv_advection_cuda_persistent_buffer_report.md` | Persistent mode implementation and standalone validation. |
| `docs/fv_advection_cuda_persistent_performance_results.md` | 30-day persistent result; only 1.039x over stateless. |
| `docs/fv_advection_cuda_fused_boundary_design.md` | Options A-D for reducing H2D and Fortran/CUDA crossings. |
| `docs/fv_advection_cuda_resident_boundary_report.md` | Implemented two-phase resident boundary and exact validation. |
| `docs/fv_advection_cuda_resident_performance_results.md` | Latest result: 1.172x over persistent, still 4.25x slower than CPU. |

## Forcing Module Documents

| Path | Description |
|---|---|
| `docs/held_suarez_forcing_module_scope.md` | Original forcing module boundary and translation scope. |
| `docs/translation_spec_held_suarez_forcing_module.md` | Full forcing translation specification. |
| `docs/T85L25_forcing_performance_experiment_plan.md` | Controlled T85L25 Fortran/CPU/CUDA run plan. |
| `docs/T85L25_run_checklist.md` | Build and run checklist for the T85L25 experiment. |
| `docs/T85L25_forcing_performance_results.md` | Authoritative forcing timing, Amdahl analysis, and conclusion. |
| `tests/reports/hs_forcing_profile_30day_report.md` | 30-day forcing profile interpretation. |
| `tests/reports/hs_forcing_cuda_poc_report.md` | CUDA forcing POC build and validation report. |
| `tests/reports/T85L25_forcing_validation_report.md` | Numerical comparison of T85L25 Fortran, CPU, and CUDA outputs. |
| `tests/reports/T85L25_forcing_validation_report.json` | Machine-readable T85L25 forcing comparison. |

## Build Diagnosis History

| Path | Description |
|---|---|
| `docs/hybrid_build_diagnosis.md` | Initial custom helper diagnosis. |
| `docs/hybrid_build_diagnosis_phase2.md` | `mkmf`, `path_names`, and source-root investigation. |
| `docs/hybrid_environment_diagnosis.md` | Production/container compiler, MPI, NetCDF, and module environment. |
| `docs/hybrid_build_report_phase3.md` | First populated Makefile and compilation start. |
| `docs/hybrid_build_report_phase4.md` | Overlay compile/link blockers and fixes. |
| `docs/hybrid_run_report_phase1.md` | Initial one-day hybrid run outcome. |

## Major Build And Run Scripts

| Path | Description |
|---|---|
| `run_compile_hybrid.sh` | Builds forcing hybrid in Apptainer; optional CUDA via `USE_CUDA_HS_FORCE=1`. |
| `run_compile_fv_semi_y.sh` | Builds standalone semi-y CPU/CUDA overlay variants. |
| `run_compile_fv_kernels.sh` | Builds FV bundle CPU or CUDA executable and records build logs. |
| `hybrid_experiments/held_suarez_cpp_force/compile_native_overlay.py` | Central `DryCodeBase` and `CodeBase.compile()` orchestrator. |
| `hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py` | Runs a selected prebuilt executable with original experiment settings. |
| `hybrid_experiments/held_suarez_cpp_force/run_hybrid_1day_cuda.sh` | One-day forcing CUDA run. |
| `hybrid_experiments/held_suarez_cpp_force/run_hybrid_30day_cuda.sh` | Thirty-day forcing CUDA run. |
| `scripts/run_T85L25_all.sh` | Sequential T85L25 Fortran, CPU hybrid, CUDA hybrid study. |
| `scripts/run_T85L25_fortran_30day.sh` | T85L25 all-Fortran run. |
| `scripts/run_T85L25_cpu_hybrid_30day.sh` | T85L25 CPU forcing hybrid run. |
| `scripts/run_T85L25_cuda_hybrid_30day.sh` | T85L25 CUDA forcing hybrid run. |
| `scripts/run_fv_kernels_1day_smoke.sh` | CPU/CUDA FV bundle one-day smoke workflow. |
| `scripts/run_fv_kernels_cpu_30day.sh` | CPU C++ FV bundle 30-day profile run. |
| `scripts/run_fv_kernels_cuda_30day.sh` | Stateless CUDA FV bundle 30-day run. |
| `scripts/run_fv_kernels_persistent_1day.sh` | Persistent CUDA one-day run. |
| `scripts/run_fv_kernels_persistent_30day.sh` | Persistent CUDA 30-day profile run. |
| `scripts/run_fv_kernels_resident_1day.sh` | Current resident-boundary one-day smoke test. |
| `scripts/run_fv_kernels_resident_30day.sh` | Current resident-boundary 30-day profile run. |
| `scripts/run_resolution_scaling_profiles.sh` | Resolution matrix runner for forcing and dynamics profiles. |

## Validation Scripts

| Path | Description |
|---|---|
| `tests/validate_T85L25_forcing_outputs.py` | Three-way NetCDF dimension/variable/error comparison. |
| `tests/compare_hybrid_outputs.py` | General baseline/hybrid NetCDF comparison. |
| `scripts/validate_fv_kernels_1day.sh` | One-day bundle comparison. |
| `scripts/validate_fv_kernels_persistent_30day.sh` | Persistent versus baseline/CPU/stateless validation. |
| `scripts/validate_fv_kernels_resident_1day.sh` | One-day resident file comparison; not authoritative with monthly cadence. |
| `scripts/validate_fv_kernels_resident_30day.sh` | Authoritative 30-day resident comparison. |
| `scripts/validate_fv_semi_y_30day.sh` | Semi-y CPU/CUDA 30-day comparison. |
| `scripts/run_port_validation.sh` | Earlier translated-routine validation runner. |

## Standalone Baseline Fixtures

| Path | Description |
|---|---|
| `tests/fortran_baseline/forcing_module/` | Full forcing input/output binary fixture. |
| `tests/fortran_baseline/semi_y_3d/` | Deterministic private-routine test copy and fixture. |
| `tests/fortran_baseline/fv_advection_kernels/` | Shared fixture for all translated FV kernels. |
| `tests/fortran_baseline/calc_ecc_anomaly/` | Orbital routine baseline. |
| `tests/fortran_baseline/calc_hour_angle/` | Hour-angle routine baseline. |
| `tests/fortran_baseline/newtonian_damping/` | Newtonian damping baseline. |
| `tests/fortran_baseline/rayleigh_damping/` | Rayleigh damping baseline. |
| `tests/fortran_baseline/top_down_newtonian_damping/` | Top-down damping baseline. |

## Translated Source Locations

| Path | Description |
|---|---|
| `translated/held_suarez/cpp/forcing_module/` | CPU forcing, C API, wrapper harness, profile support, static library. |
| `translated/held_suarez/cuda/forcing_module/` | CUDA forcing backend and standalone validator. |
| `translated/held_suarez/cpp/fv_advection/semi_y_3d/` | CPU semi-y implementation and wrapper harness. |
| `translated/held_suarez/cuda/fv_advection/semi_y_3d/` | CUDA semi-y implementation and validator. |
| `translated/held_suarez/cpp/fv_advection/kernels/` | CPU bundle, C API, profiling, wrapper harness, and Makefile. |
| `translated/held_suarez/cuda/fv_advection/kernels/` | Stateless, persistent, and resident CUDA bundle implementation. |

## Overlay Sources

| Path | Description |
|---|---|
| `src/extra/local_overrides/hs_forcing/hs_forcing.F90` | Forcing C++/CUDA dispatch overlay. |
| `src/extra/local_overrides/fv_advection/fv_advection.F90` | Standalone semi-y overlay. |
| `src/extra/local_overrides/fv_advection_kernels/fv_advection.F90` | Current FV bundle and resident-boundary overlay. |
| `src/extra/local_overrides/spectral_dynamics/spectral_dynamics.F90` | Dynamics and call-site profiling overlay. |
| `src/extra/local_overrides/vert_advection/vert_advection.F90` | Historical vertical-advection instrumentation overlay. |

## Authoritative Validation Reports

| Path | Description |
|---|---|
| `tests/reports/fv_advection_kernels_cpp_compare_report.json` | CPU bundle versus Fortran fixture. |
| `tests/reports/fv_advection_kernels_cuda_compare_report.json` | Stateless CUDA bundle versus Fortran fixture. |
| `tests/reports/fv_advection_kernels_cuda_persistent_compare_report.json` | Persistent CUDA fixture result. |
| `tests/reports/fv_advection_kernels_cuda_resident_compare_report.json` | Resident CUDA fixture result, including combined resident phases. |
| `tests/reports/fv_advection_kernels_fortran_c_compare_report.json` | Fortran-to-C CPU wrapper result. |
| `tests/reports/fv_advection_kernels_fortran_cuda_c_compare_report.json` | Fortran-to-C stateless CUDA result. |
| `tests/reports/fv_advection_kernels_fortran_cuda_persistent_c_compare_report.json` | Fortran-to-C persistent CUDA result. |
| `tests/reports/fv_advection_kernels_resident_30day_model_validation.md` | Exact 30-day all-Fortran/CPU/resident model comparison. |
| `tests/reports/fv_advection_kernels_resident_30day_model_validation.json` | Machine-readable resident 30-day result. |
| `tests/reports/semi_y_3d_30day_model_validation_report.md` | Semi-y model-level validation. |

## Important Logs

| Path | Description |
|---|---|
| `logs/hybrid_compile_latest.log` | Symlink to latest forcing hybrid build log. |
| `logs/hybrid_hs_profile_30day.log` | Forcing module 30-day timing. |
| `logs/T85L25_fortran_30day.log` | T85L25 all-Fortran timing. |
| `logs/T85L25_hybrid_cpu_30day.log` | T85L25 CPU forcing hybrid timing. |
| `logs/T85L25_hybrid_cuda_30day.log` | T85L25 CUDA forcing hybrid timing. |
| `logs/four_in_one_profile_30day.log` | `four_in_one` profile evidence. |
| `logs/vert_advection_profile_30day_callsite.log` | Field-separated vertical-advection timing. |
| `logs/dynamics_region_profile_30day.log` | Broad dynamics-region timing. |
| `logs/dynamics_deep_profile_30day.log` | Deep hotspot timing. |
| `logs/fv_advection_cuda_microbenchmark.log` | Unit-level CUDA overhead benchmark. |
| `logs/fv_kernels_cpu_30day.log` | CPU C++ FV bundle performance baseline. |
| `logs/fv_kernels_cuda_30day.log` | Stateless CUDA performance baseline. |
| `logs/fv_kernels_cuda_persistent_30day.log` | Persistent CUDA first 30-day timing. |
| `logs/fv_kernels_cuda_persistent_30day_repeat.log` | Persistent repeat/noise check. |
| `logs/fv_kernels_cuda_resident_1day.log` | Resident smoke-test runtime and markers. |
| `logs/fv_kernels_cuda_resident_30day.log` | Latest resident 30-day performance evidence. |
| `logs/fv_kernels_cuda_resident_30day_validation.log` | Resident NetCDF validation transcript. |

## Executables In The Isca Work Tree

Build root:

```text
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_explore_nobackup_people_jli30_workspace_GFDL_atmos_cubed_sphere/build
```

| Relative path | Description | Present 2026-06-19 |
|---|---|---|
| `held_suarez_hybrid/held_suarez_hybrid.x` | Forcing CPU/CUDA hybrid executable. | Yes |
| `held_suarez_fv_semi_y_3d/held_suarez_fv_semi_y_3d.x` | CPU semi-y overlay. | Yes |
| `held_suarez_fv_semi_y_3d_cuda/held_suarez_fv_semi_y_3d_cuda.x` | CUDA semi-y overlay. | Yes |
| `held_suarez_fv_kernels/held_suarez_fv_kernels.x` | CPU FV kernel bundle. | Yes |
| `held_suarez_fv_kernels_cuda/held_suarez_fv_kernels_cuda.x` | CUDA bundle; runtime-selects stateless/persistent/resident. | Yes |
| `held_suarez_fortran/held_suarez_fortran.x` | Separately named custom Fortran baseline. | No; rebuild if needed |

## Major Model Outputs

Data root:

```text
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data
```

| Relative path | Description |
|---|---|
| `held_suarez_default/run0001/atmos_monthly.nc` | Stock all-Fortran T42L25 baseline used by FV validation. |
| `held_suarez_hybrid_cpu_T85L25/run0001/atmos_monthly.nc` | T85L25 CPU forcing hybrid output. |
| `held_suarez_hybrid_cuda_T85L25/run0001/atmos_monthly.nc` | T85L25 CUDA forcing output. |
| `held_suarez_fv_kernels_30day/run0001/atmos_monthly.nc` | CPU C++ FV bundle output. |
| `held_suarez_fv_kernels_cuda_30day/run0001/atmos_monthly.nc` | Stateless CUDA FV output. |
| `held_suarez_fv_kernels_cuda_persistent_30day/run0001/atmos_monthly.nc` | Persistent CUDA first output. |
| `held_suarez_fv_kernels_cuda_persistent_30day_repeat/run0001/atmos_monthly.nc` | Persistent repeat output. |
| `held_suarez_fv_kernels_cuda_resident_30day/run0001/atmos_monthly.nc` | Current resident CUDA output. |

## Naming And Authority Notes

- Reports named `T85L25_forcing_*` may contain reusable comparison tooling, but FV
  production runs described above are T42L25 unless explicitly stated otherwise.
- The resident 30-day report is authoritative; the resident one-day
  production-diagnostic comparison is not a numerical gate because of fill
  values.
- Later performance reports supersede earlier plans and templates.
- Generated libraries, objects, modules, executables, and NetCDF files are
  artifacts. Recreate them through documented scripts rather than treating them
  as source.
