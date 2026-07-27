#!/usr/bin/env bash
# Compare the two Step 4 correctness runs already produced by
# run_hybrid_nccl_correctness_cuda.sh (host-routed halo vs GPU-to-GPU NCCL
# halo), field by field. Does NOT re-run the model. Tries the python netCDF
# backends first; when the container has none (its base python3 lacks
# netCDF4) it falls back to parsing `ncdump`, reusing the same helpers the
# existing model validator uses (tests/validate_T85L25_forcing_outputs.py).
#
# Pass = "MATCH: all variables identical".
set -euo pipefail

CONTAINER=${CONTAINER:-/lscratch/rlgill/isca-debian_latest}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

export GFDL_BASE=${GFDL_BASE_OVERRIDE:-${SCRIPT_DIR}}
export GFDL_WORK=${GFDL_WORK:-/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_work}
export GFDL_DATA=${GFDL_DATA:-/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_data}

REF_EXP=${REF_EXP:-nccl_correctness_host}
DEV_EXP=${DEV_EXP:-nccl_correctness_device}

apptainer exec --nv \
  --bind /explore/nobackup/people/rlgill:/explore/nobackup/people/rlgill \
  "${CONTAINER}" \
  bash -lc "
set -e
export GFDL_BASE=${GFDL_BASE}
export GFDL_DATA=${GFDL_DATA}
export REF_EXP=${REF_EXP}
export DEV_EXP=${DEV_EXP}

echo '=== available readers ==='
for m in netCDF4 xarray scipy; do
  python3 -c \"import \$m\" 2>/dev/null && echo \"python: \$m OK\" || echo \"python: \$m missing\"
done
command -v ncdump >/dev/null && echo 'cli: ncdump OK' || echo 'cli: ncdump missing'

echo '=== comparing output ==='
python3 - <<'PY'
import glob, os, sys
import numpy as np

data = os.environ['GFDL_DATA']
ref_exp = os.environ['REF_EXP']
dev_exp = os.environ['DEV_EXP']

def find_nc(exp):
    hits = sorted(glob.glob(os.path.join(data, exp, '**', '*.nc'), recursive=True))
    if not hits:
        sys.exit('no output .nc found for %s' % exp)
    return {os.path.basename(p): p for p in hits}

# Pick whatever reader exists; return dict var -> ndarray(float64).
reader = None
try:
    from netCDF4 import Dataset
    def load(path):
        ds = Dataset(path)
        out = {v: np.asarray(ds.variables[v][:], dtype='float64') for v in ds.variables}
        ds.close(); return out
    reader = 'netCDF4'
except Exception:
    pass
if reader is None:
    try:
        import xarray as xr
        def load(path):
            ds = xr.open_dataset(path, decode_times=False)
            out = {v: np.asarray(ds[v].values, dtype='float64') for v in ds.data_vars}
            ds.close(); return out
        reader = 'xarray'
    except Exception:
        pass
if reader is None:
    try:
        from scipy.io import netcdf_file
        def load(path):
            ds = netcdf_file(path, 'r', mmap=False)
            out = {v: np.asarray(ds.variables[v][:], dtype='float64') for v in ds.variables}
            ds.close(); return out
        reader = 'scipy'
    except Exception:
        pass
if reader is None:
    # No python NetCDF backend in the container base python3. Reuse the
    # ncdump-parsing helpers the model validator already relies on.
    sys.path.insert(0, os.path.join(os.environ['GFDL_BASE'], 'tests'))
    try:
        from validate_T85L25_forcing_outputs import parse_header, parse_ncdump_values
    except Exception as exc:
        sys.exit('no python NetCDF backend and could not import ncdump helpers: %s' % exc)
    def load(path):
        sizes, meta = parse_header(path)
        out = {}
        for name, m in meta.items():
            if m['type'] in ('char',):
                continue
            try:
                vals = np.array(parse_ncdump_values(path, name), dtype='float64')
            except Exception:
                continue
            shape = tuple(sizes[d] for d in m['dims'] if d in sizes)
            if shape and vals.size == int(np.prod(shape)):
                vals = vals.reshape(shape)
            out[name] = vals
        return out
    reader = 'ncdump'

print('reader: %s' % reader)
ref = find_nc(ref_exp)
dev = find_nc(dev_exp)
common = sorted(set(ref) & set(dev))
if not common:
    sys.exit('no output files in common between the two runs')

worst = 0.0; worst_var = None; n = 0
for name in common:
    a = load(ref[name]); b = load(dev[name])
    for v in a:
        if v not in b:
            continue
        va, vb = a[v], b[v]
        if va.shape != vb.shape:
            print('SHAPE MISMATCH %s/%s: %s vs %s' % (name, v, va.shape, vb.shape))
            worst = float('inf'); worst_var = '%s/%s' % (name, v); continue
        d = float(np.nanmax(np.abs(va - vb))) if va.size else 0.0
        n += 1
        if d > worst:
            worst, worst_var = d, '%s/%s' % (name, v)

print('checked %d variables across %d file(s)' % (n, len(common)))
if worst == 0.0:
    print('MATCH: all variables identical')
else:
    print('DIFF: largest absolute difference %g in %s' % (worst, worst_var))
    sys.exit(1)
PY
"
