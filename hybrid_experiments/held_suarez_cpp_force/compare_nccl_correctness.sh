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

# Candidate readers, best first. Each returns a load(path) -> {var: ndarray}.
# The container base python3 has no netCDF4/scipy and xarray has no working
# engine, but the netCDF C library (libnetcdf.so.19) is installed, so the
# reliable path is to call it directly through ctypes: it does all the offset
# and unlimited-dimension bookkeeping itself. Each candidate is verified by
# actually opening a file before use, so an importable-but-unusable backend
# (xarray with no engine) is rejected rather than crashing mid-run.

def make_netcdf4():
    from netCDF4 import Dataset
    def load(path):
        ds = Dataset(path)
        out = {v: np.asarray(ds.variables[v][:], dtype='float64') for v in ds.variables}
        ds.close(); return out
    return load

def make_scipy():
    from scipy.io import netcdf_file
    def load(path):
        ds = netcdf_file(path, 'r', mmap=False)
        out = {v: np.asarray(ds.variables[v][:], dtype='float64') for v in ds.variables}
        ds.close(); return out
    return load

def make_xarray():
    import xarray as xr
    def load(path):
        ds = xr.open_dataset(path, decode_times=False)
        out = {v: np.asarray(ds[v].values, dtype='float64') for v in ds.data_vars}
        ds.close(); return out
    return load

def make_ctypes():
    import ctypes
    lib = None
    for name in ('libnetcdf.so.19', 'libnetcdf.so', 'libnetcdf.so.18'):
        try:
            lib = ctypes.CDLL(name); break
        except OSError:
            continue
    if lib is None:
        raise OSError('libnetcdf not loadable')
    c_int, size_t, c_double = ctypes.c_int, ctypes.c_size_t, ctypes.c_double
    P = ctypes.POINTER
    lib.nc_open.argtypes = [ctypes.c_char_p, c_int, P(c_int)]
    lib.nc_inq.argtypes = [c_int, P(c_int), P(c_int), P(c_int), P(c_int)]
    lib.nc_inq_varname.argtypes = [c_int, c_int, ctypes.c_char_p]
    lib.nc_inq_vartype.argtypes = [c_int, c_int, P(c_int)]
    lib.nc_inq_varndims.argtypes = [c_int, c_int, P(c_int)]
    lib.nc_inq_vardimid.argtypes = [c_int, c_int, P(c_int)]
    lib.nc_inq_dimlen.argtypes = [c_int, c_int, P(size_t)]
    lib.nc_get_var_double.argtypes = [c_int, c_int, P(c_double)]
    lib.nc_close.argtypes = [c_int]

    def chk(status, ctx=''):
        if status != 0:
            raise RuntimeError('netcdf error %d (%s)' % (status, ctx))

    NC_CHAR = 2

    def load(path):
        ncid = c_int()
        chk(lib.nc_open(path.encode(), 0, ctypes.byref(ncid)), 'open ' + path)
        try:
            nd, nv, ng, un = c_int(), c_int(), c_int(), c_int()
            chk(lib.nc_inq(ncid, ctypes.byref(nd), ctypes.byref(nv),
                           ctypes.byref(ng), ctypes.byref(un)))
            out = {}
            namebuf = ctypes.create_string_buffer(256)
            for vid in range(nv.value):
                chk(lib.nc_inq_varname(ncid, vid, namebuf))
                vname = namebuf.value.decode()
                xt = c_int(); chk(lib.nc_inq_vartype(ncid, vid, ctypes.byref(xt)))
                if xt.value == NC_CHAR:
                    continue
                vnd = c_int(); chk(lib.nc_inq_varndims(ncid, vid, ctypes.byref(vnd)))
                dimids = (c_int * max(vnd.value, 1))()
                chk(lib.nc_inq_vardimid(ncid, vid, dimids))
                shape = []
                for d in range(vnd.value):
                    ln = size_t()
                    chk(lib.nc_inq_dimlen(ncid, dimids[d], ctypes.byref(ln)))
                    shape.append(ln.value)
                count = 1
                for s in shape:
                    count *= s
                buf = np.empty(max(count, 1), dtype=np.float64)
                chk(lib.nc_get_var_double(
                    ncid, vid, buf.ctypes.data_as(P(c_double))), 'get ' + vname)
                out[vname] = buf[:count].reshape(shape) if shape else buf[:1]
            return out
        finally:
            lib.nc_close(ncid)
    return load

candidates = [('netCDF4', make_netcdf4), ('scipy', make_scipy),
              ('xarray', make_xarray), ('ctypes-netcdf', make_ctypes)]

ref = find_nc(ref_exp)
dev = find_nc(dev_exp)
probe = next(iter(ref.values()))

load = None; reader = None
for label, factory in candidates:
    try:
        fn = factory()
        fn(probe)          # must actually open the file, not just import
        load, reader = fn, label
        break
    except Exception as exc:
        print('reader %s unavailable: %s' % (label, exc))
if load is None:
    sys.exit('no usable NetCDF reader in this container')

print('reader: %s' % reader)
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
