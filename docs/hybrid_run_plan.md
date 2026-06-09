# Hybrid Held-Suarez Run Plan

Generated: 2026-06-08

## Objective

Run the same Held-Suarez experiment path as the original all-Fortran case while
selecting only the hybrid executable:

```text
held_suarez_hybrid.x
```

The first run is a minimal smoke test, not a long validation run.

## Original Run Path

Original script:

```text
exp/test_cases/held_suarez/held_suarez_test_case.py
```

The original case creates:

```python
cb = DryCodeBase.from_directory(GFDL_BASE)
exp = Experiment("held_suarez_default", codebase=cb)
```

and launches:

```python
cb.compile()
exp.run(1, num_cores=16, use_restart=False)
```

`Experiment.run()` writes `input.nml`, `field_table`, and `diag_table`, then
creates a run script from `src/extra/python/isca/templates/run.sh`.  That
template launches:

```text
mpirun -np <num_cores> <codebase.builddir>/<codebase.executable_name>
```

Therefore the executable is selected by the attached `CodeBase` object.

## Hybrid Run Strategy

New script:

```text
hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py
```

The script defines a small `DryCodeBase` subclass:

```python
class HeldSuarezHybridRuntimeCodeBase(DryCodeBase):
    executable_name = "held_suarez_hybrid.x"
```

This makes `Experiment.run()` use:

```text
.../build/held_suarez_hybrid/held_suarez_hybrid.x
```

without modifying the original Held-Suarez run script or source tree.

## Output Location

Default hybrid experiment name:

```text
held_suarez_hybrid
```

Default output directory:

```text
${GFDL_DATA}/held_suarez_hybrid
```

The original output remains under:

```text
${GFDL_DATA}/held_suarez_default
```

## Smoke Test

Run inside the same Apptainer container environment used for the successful
compile:

```bash
python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py --dry-run
python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py --days 1 --overwrite
```

The smoke runner reuses the original namelist, diagnostic field list, and
resolution.  For the smoke default it changes only:

```text
main_nml.days = 1
diag_table file cadence = 1 day
```

The diagnostic cadence change is only to make a one-day smoke run produce a
NetCDF diagnostic file.  Use `--production-diag` to keep the original 30-day
diagnostic cadence exactly.

## Production-Matching Run

After the smoke test succeeds:

```bash
python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py \
  --days 30 \
  --production-diag \
  --overwrite
```

This should produce a first monthly file comparable with:

```text
${GFDL_DATA}/held_suarez_default/run0001/atmos_monthly.nc
```

## Comparison

New comparison script:

```text
tests/compare_hybrid_outputs.py
```

Default comparison:

```bash
python3 tests/compare_hybrid_outputs.py
```

This compares:

```text
${GFDL_DATA}/held_suarez_default/run0001/atmos_monthly.nc
${GFDL_DATA}/held_suarez_hybrid/run0001/atmos_monthly.nc
```

It reports:

```text
dimension match
missing variables
global means
mean difference
max abs error
RMSE
```

Default fields:

```text
ps, bk, pk, ucomp, vcomp, temp, vor, div
```

Use `--all-fields` to compare every numeric variable present in either file.

## Stop Conditions

For the current phase, stop after either:

```text
short smoke test succeeds and writes output
```

or:

```text
first runtime failure from the hybrid executable
```
