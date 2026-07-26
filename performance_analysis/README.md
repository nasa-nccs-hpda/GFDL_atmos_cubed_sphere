# FV Matrix Performance Analysis

This directory contains the analysis workflow for the Held-Suarez FV advection
resolution/GPU matrix logs.

Source logs:

```text
../logs/matrix*.log
```

The current analysis intentionally excludes `16gpu` logs because the 16-GPU
path is still a launcher/infrastructure issue.

## Generate Raw Tables

From the repository root:

```bash
python3 performance_analysis/parse_matrix_logs.py
```

Outputs:

```text
performance_analysis/data/matrix_runs.csv
performance_analysis/data/matrix_runs.json
performance_analysis/data/matrix_completion.csv
```

## Plot Figures

Open:

```text
performance_analysis/fv_matrix_figures.ipynb
```

Run all cells. Figures are written to:

```text
performance_analysis/figures/
```

The notebook needs:

```text
pandas
matplotlib
```

If needed, install them in your analysis environment with:

```bash
python3 -m pip install -r performance_analysis/requirements.txt
```

## Figure Set

The notebook produces:

1. Completion matrix
2. MPP runtime heatmap
3. Speedup vs Fortran heatmap
4. Runtime per simulated day
5. CUDA phase stacked bars
6. Resolution scaling for 30-day runs

## Notes

- `T42L25` and `T85L25` form the clean complete matrix.
- `T170L25` is included as a partial extension.
- `T170L25/fv_cuda_a_grid_4gpu/30day` completed, but is marked as an outlier.
- `T170L25/fv_cuda_a_grid_4gpu/60day` hit the time limit and is excluded from
  speedup/runtime calculations.
