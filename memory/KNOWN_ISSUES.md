# Known Issues

## Fortran Compiler on NCCS Discover

### Problem

The `gfortran` compiler is not available in the default PATH on NCCS Discover. Attempting to compile Fortran code without loading a module results in:

```
make: gfortran: Command not found
```

Additionally, running a compiled Fortran executable without the module loaded fails with:

```
./test_rayleigh_damping: error while loading shared libraries: libgfortran.so.5: cannot open shared object file: No such file or directory
```

### Solution

Load the GCC module before compiling **and** before running:

```bash
module load gcc/12.1.0
make
./test_rayleigh_damping
```

Or combine into a single command:

```bash
module load gcc/12.1.0 && make run
```

### Available GCC Versions

```
gcc/9.2.0
gcc/10.1.0
gcc/11.2.0
gcc/12.1.0  (default, recommended)
gcc/14.2.0
```

### Precision Warnings

When compiling with `-fdefault-real-8`, GCC may emit warnings about precision conversion:

```
Warning: Possible change of value in conversion from REAL(16) to REAL(8)
```

These warnings are benign — they occur because `d0` literals are promoted to quad precision before being assigned to double precision variables. The numerical results are correct.

To suppress these warnings (not recommended for development):
```makefile
FFLAGS += -Wno-conversion
```

---

## C++ Header Include Requirements

### Problem

When translating Fortran routines that use temporary arrays (e.g., `newtonian_damping`), the C++ header-only implementation uses `std::vector` for dynamic allocation. Forgetting to include `<vector>` results in compilation errors:

```
error: 'vector' is not a member of 'std'
    std::vector<double> sin_lat(nlon * nlat);
         ^~~~~~
note: 'std::vector' is defined in header '<vector>'; did you forget to '#include <vector>'?
```

### Solution

Ensure all required headers are included in the kernel header file:

```cpp
#include <algorithm>  // for std::max
#include <cmath>      // for std::sin, std::cos, std::log, std::pow
#include <cstddef>    // for size_t
#include <vector>     // for std::vector (temporary arrays)
```

### Checklist for Header-Only Kernels

When creating a new kernel header, include:
- `<cmath>` — if using math functions (`sin`, `cos`, `log`, `pow`, `abs`)
- `<algorithm>` — if using `std::max`, `std::min`
- `<vector>` — if using `std::vector` for temporary arrays
- `<cstddef>` — if using `size_t`
