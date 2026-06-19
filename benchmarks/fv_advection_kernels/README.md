# FV Advection CUDA Microbenchmark

This standalone benchmark compares the existing model-facing FV advection
kernel boundary in three modes:

1. CPU C++ baseline.
2. Current CUDA lifecycle: allocate, H2D, launch, synchronize, D2H, free on
   every call.
3. Persistent CUDA lifecycle: allocate/copy once, launch the kernel repeatedly,
   then copy/free once.

It does not modify or link into the Held-Suarez model executable. The CUDA
kernels mirror the current implementations for:

- `semi_x_3d`
- `vanleer_x_3d`
- `vanleer_sphere_3d`

## Build

Inside the CUDA-capable Isca container:

```bash
cd benchmarks/fv_advection_kernels
make clean all NVCC=/usr/local/cuda/bin/nvcc
```

## Run

```bash
./bin/fv_advection_cuda_benchmark --resolution T42 --iterations 100 --mode all
./bin/fv_advection_cuda_benchmark --resolution T85 --iterations 100 --mode all
./bin/fv_advection_cuda_benchmark --resolution T170 --iterations 100 --mode all
```

Modes:

```text
cpu
cuda-current
cuda-persistent
all
```

The reported `kernel_ms` is CUDA-event device execution time. `sync_ms` is host
time waiting for the event and overlaps `kernel_ms`; do not add both when
reconstructing `total_ms`. Allocation, H2D, launch, D2H, and free are host-side
wall-clock measurements.

The representative dimensions assume 16 MPI ranks with latitude decomposition:

| Label | Global horizontal grid | Local array per rank | Levels |
|---|---:|---:|---:|
| T42 | 128 x 64 | 128 x 4 | 25 |
| T85 | 256 x 128 | 256 x 8 | 25 |
| T170 | 512 x 256 | 512 x 16 | 25 |

Use `--nx`, `--ny`, and `--nz` to override dimensions.
