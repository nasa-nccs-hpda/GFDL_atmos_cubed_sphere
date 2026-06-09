# Hybrid Run Report Phase 1

Generated: 2026-06-08

## Status

The hybrid executable was successfully generated and the first 1-day smoke run
completed successfully:

```text
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/codebase/_explore_nobackup_people_jli30_workspace_GFDL_atmos_cubed_sphere/build/held_suarez_hybrid/held_suarez_hybrid.x
```

Logs inspected:

```text
logs/hybrid_run_dryrun.log
logs/hybrid_run_1day.log
```

## Original Executable Selection

The original Held-Suarez script uses:

```python
cb = DryCodeBase.from_directory(GFDL_BASE)
exp = Experiment("held_suarez_default", codebase=cb)
```

`Experiment.run()` launches:

```text
<cb.builddir>/<cb.executable_name>
```

through the generated `run.sh` template.

For `DryCodeBase`, the executable is:

```text
held_suarez.x
```

## Hybrid Runtime Mechanism

Created:

```text
hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py
```

The script defines:

```text
HeldSuarezHybridRuntimeCodeBase
```

with:

```text
executable_name = "held_suarez_hybrid.x"
```

It reuses the original Held-Suarez:

```text
namelist
diagnostic fields
T42 / 25-level resolution
num_cores default of 16
GFDL_WORK and GFDL_DATA layout
```

It writes to a separate experiment directory:

```text
${GFDL_DATA}/held_suarez_hybrid
```

## Dry Run

The dry run selected:

```text
Experiment = held_suarez_hybrid
Data dir = /explore/nobackup/people/jli30/SystemTesting/Isca/isca_data/held_suarez_hybrid
Run dir = /explore/nobackup/people/jli30/SystemTesting/Isca/isca_work/experiment/held_suarez_hybrid/run
Executable = .../build/held_suarez_hybrid/held_suarez_hybrid.x
Days = 1
dt_atmos = 600
num_cores = 16
production_diag = False
```

## Smoke Test

Command run by user inside the container:

```bash
python3 hybrid_experiments/held_suarez_cpp_force/run_hybrid_held_suarez.py --days 1 --overwrite
```

Smoke-only changes:

```text
main_nml.days = 1
diagnostic file cadence = 1 day
```

The run log shows:

```text
Beginning run 1
Integration completed through 2000 Jan  2   0: 0: 0
Run 1 complete
atmos_monthly.nc combined and copied to data directory
Restart archive created at .../held_suarez_hybrid/restarts/res0001.tar.gz
```

Conclusion:

```text
Hybrid executable starts, runs 1 day on 16 MPI ranks, writes diagnostics, and
archives restart output.
```

## Generated Files

Hybrid output directory inspected:

```text
/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data/held_suarez_hybrid
```

Generated files:

```text
run0001/atmos_monthly.nc        4,153,576 bytes
run0001/diag_table                  863 bytes
run0001/field_table                 355 bytes
run0001/git_hash_used.txt        19,485 bytes
run0001/input.nml                   928 bytes
restarts/res0001.tar.gz      24,764,733 bytes
```

The NetCDF file is recognized by `file` as:

```text
NetCDF Data Format data
```

## Baseline Availability

Available original all-Fortran output:

```text
${GFDL_DATA}/held_suarez_default/run0001/atmos_monthly.nc
```

However, the saved baseline namelist is a 30-day production run:

```text
main_nml.days = 30
diag_table cadence = 30 days
```

The hybrid smoke output is a 1-day run:

```text
main_nml.days = 1
diag_table cadence = 1 day
```

Therefore the existing all-Fortran output is not a duration-matched baseline
for numeric comparison against the 1-day hybrid smoke test.

The files are not byte-identical, as expected for different run durations and
diagnostic cadence.

## Comparison Status

No numeric NetCDF comparison was performed in this shell because:

```text
available baseline duration differs from the hybrid smoke duration
local shell lacks xarray/numpy/ncdump
```

The comparison tool remains available for the container environment:

```text
tests/compare_hybrid_outputs.py
```

## Required 1-Day All-Fortran Baseline

Run this inside the same Isca container/runtime environment to create a
duration-matched all-Fortran baseline:

```bash
python3 - <<'PY'
import sys
from pathlib import Path

from isca import DryCodeBase, Experiment, GFDL_BASE

sys.path.insert(0, str(Path(GFDL_BASE) / "exp" / "test_cases" / "held_suarez"))
from held_suarez_test_case import namelist, diag, RESOLUTION

cb = DryCodeBase.from_directory(GFDL_BASE)
exp = Experiment("held_suarez_fortran_1day", codebase=cb)
exp.namelist = namelist.copy()
exp.diag_table = diag.copy()
exp.set_resolution(*RESOLUTION)
exp.update_namelist({"main_nml": {"days": 1}})

for output_file in exp.diag_table.files.values():
    output_file["freq"] = 1
    output_file["units"] = "days"
    output_file["time_units"] = "days"

exp.run(1, num_cores=16, use_restart=False, overwrite_data=True)
PY
```

Expected output:

```text
${GFDL_DATA}/held_suarez_fortran_1day/run0001/atmos_monthly.nc
```

Then compare:

```bash
python3 tests/compare_hybrid_outputs.py \
  --baseline-exp held_suarez_fortran_1day \
  --candidate-exp held_suarez_hybrid \
  --run 1 \
  --out tests/reports/hybrid_1day_compare_report.json
```

## Do Not Run Yet

Do not run the monthly hybrid simulation yet.  The next step is only to produce
the duration-matched 1-day all-Fortran baseline and compare it with the already
completed 1-day hybrid smoke run.
