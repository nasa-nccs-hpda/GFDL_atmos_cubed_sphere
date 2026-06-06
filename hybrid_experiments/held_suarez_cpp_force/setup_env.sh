#!/usr/bin/env bash
# Recreate the production Held-Suarez build toolchain environment as closely
# as possible for the hybrid build. Source this file before running make:
#
#   source hybrid_experiments/held_suarez_cpp_force/setup_env.sh
#
# The successful production build was generated inside the Isca container using
# src/extra/env/ubuntu_conda and mkmf.template.ubuntu_conda.

if [ -n "${BASH_SOURCE[0]:-}" ]; then
  _hybrid_env_script="${BASH_SOURCE[0]}"
else
  _hybrid_env_script="$0"
fi
_hybrid_env_dir="$(cd "$(dirname "${_hybrid_env_script}")" && pwd)"
_hybrid_repo="$(cd "${_hybrid_env_dir}/../.." && pwd)"
if [ ! -d "${_hybrid_repo}/src/extra/env" ]; then
  _hybrid_repo="$(cd "${_hybrid_env_dir}/../../.." && pwd)"
fi

echo "Loading hybrid Held-Suarez production-like environment"

if [ -f /isca/src/extra/env/ubuntu_conda ]; then
  # Exact path used by the production compile.sh inside the container.
  # shellcheck disable=SC1091
  source /isca/src/extra/env/ubuntu_conda
elif [ -f "${_hybrid_repo}/src/extra/env/ubuntu_conda" ]; then
  # Same env file, but from the checked-out repository.
  # shellcheck disable=SC1091
  source "${_hybrid_repo}/src/extra/env/ubuntu_conda"
else
  export GFDL_MKMF_TEMPLATE=ubuntu_conda
  export F90=mpifort
  export CC=mpicc
fi

export GFDL_MKMF_TEMPLATE=ubuntu_conda
export F90="${F90:-mpifort}"
export FC="${FC:-${F90}}"
export CC="${CC:-mpicc}"
export CPP="${CPP:-cpp}"

# These are the MPI runtime settings used by run_held_suarez.sh.
export OMPI_MCA_rmaps_base_oversubscribe="${OMPI_MCA_rmaps_base_oversubscribe:-1}"
export OMPI_MCA_btl_vader_single_copy_mechanism="${OMPI_MCA_btl_vader_single_copy_mechanism:-none}"

# Container defaults used by requirements/Dockerfile/run_held_suarez.sh.
export GFDL_ENV="${GFDL_ENV:-ubuntu_conda}"
export GFDL_BASE="${GFDL_BASE:-${_hybrid_repo}}"
export GFDL_WORK="${GFDL_WORK:-/explore/nobackup/people/jli30/SystemTesting/Isca/isca_work}"
export GFDL_DATA="${GFDL_DATA:-/explore/nobackup/people/jli30/SystemTesting/Isca/isca_data}"

_hybrid_missing=0
for _hybrid_tool in "${F90}" "${CC}" nc-config nf-config; do
  if ! command -v "${_hybrid_tool}" >/dev/null 2>&1; then
    echo "ERROR: required production build tool not found in PATH: ${_hybrid_tool}" >&2
    _hybrid_missing=1
  fi
done

if ! command -v "${CPP}" >/dev/null 2>&1; then
  echo "ERROR: CPP not found in PATH: ${CPP}" >&2
  _hybrid_missing=1
fi

if [ "$(uname -m)" != "aarch64" ]; then
  echo "WARNING: production held_suarez.x is aarch64, current shell is $(uname -m)." >&2
  echo "WARNING: use the same ARM/container environment before comparing build outputs." >&2
fi

if [ "${_hybrid_missing}" -ne 0 ]; then
  echo "Hybrid environment does not match production; do not run make yet." >&2
  return 1 2>/dev/null || exit 1
fi

echo "Hybrid environment matches the production tool names:"
echo "  F90=${F90}"
echo "  FC=${FC}"
echo "  CC=${CC}"
echo "  CPP=${CPP}"
echo "  GFDL_MKMF_TEMPLATE=${GFDL_MKMF_TEMPLATE}"
echo "  nc-config=$(command -v nc-config)"
echo "  nf-config=$(command -v nf-config)"
