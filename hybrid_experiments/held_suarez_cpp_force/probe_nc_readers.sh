#!/usr/bin/env bash
# One-shot probe: what can read a NetCDF file inside the container?
# Reports the output file format, any ncdump binary on disk, alternate python
# interpreters that import netCDF4/scipy, and whether pip can add a backend.
set -euo pipefail

CONTAINER=${CONTAINER:-/lscratch/rlgill/isca-debian_latest}
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
export GFDL_BASE=${GFDL_BASE_OVERRIDE:-${SCRIPT_DIR}}
export GFDL_DATA=${GFDL_DATA:-/explore/nobackup/people/rlgill/SystemTesting/AAI/Isca/isca_data}

apptainer exec --nv \
  --bind /explore/nobackup/people/rlgill:/explore/nobackup/people/rlgill \
  "${CONTAINER}" \
  bash -lc "
set +e
export GFDL_DATA=${GFDL_DATA}
NC=\$(ls \${GFDL_DATA}/nccl_correctness_host/*/*.nc 2>/dev/null | head -1)
echo \"sample file: \${NC}\"
echo '--- magic (first 4 bytes) ---'
head -c 4 \"\${NC}\" | od -An -c
echo '--- ncdump on disk ---'
command -v ncdump || \
  for d in /usr/bin /usr/local/bin /bin /opt/conda/bin /opt/conda/envs/*/bin \
           /usr/lib/x86_64-linux-gnu/netcdf/bin; do
    [ -x \"\$d/ncdump\" ] && echo \"found: \$d/ncdump\"
  done
echo '--- python interpreters with a backend ---'
for py in python3 python /opt/conda/bin/python /usr/bin/python3; do
  command -v \"\$py\" >/dev/null 2>&1 || continue
  echo \"[\$py]\"
  \"\$py\" -c 'import netCDF4; print(\"  netCDF4\", netCDF4.__version__)' 2>/dev/null
  \"\$py\" -c 'import scipy; print(\"  scipy\", scipy.__version__)' 2>/dev/null
  \"\$py\" -c 'import h5netcdf; print(\"  h5netcdf\", h5netcdf.__version__)' 2>/dev/null
done
echo '--- conda envs ---'
ls /opt/conda/envs 2>/dev/null; ls /opt/conda 2>/dev/null | head
echo '--- libnetcdf / nc-config ---'
command -v nc-config && nc-config --version
ldconfig -p 2>/dev/null | grep -i netcdf | head
echo '--- pip offline check (dry, no install) ---'
python3 -m pip --version 2>/dev/null
"
