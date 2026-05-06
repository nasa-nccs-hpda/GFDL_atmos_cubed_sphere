# ILAB Development Setup

## Installing the Core Version

Modified the Cmakelist file to compile the repo without dependencies.

### Discover

1. Modify bashrc with the following:

```bash
umask 0022
ulimit -s unlimited

# Run things in this if-block only if we're in an interactive shell
if [[ $- == *i* ]]
then

   # Only put module use or other module commands here
   # and in the correct OS version

   export LMOD_SYSTEM_NAME=SLES15
   module purge
   module use -a /discover/swdev/gmao_SIteam/modulefiles-SLES15
   module load GEOSenv

   # Add any other things you want with interactive shells here

fi
```

2. Clone Repo

```bash
git clone https://github.com/nasa-nccs-hpda/GFDL_atmos_cubed_sphere
git checkout agentic-ai-develop
``` 

3. Load Module

```bash
module load GEOSenv
```

4. Compile CPU Version

```bash
cmake -S standalone-tp-core -B build-cpu -DCMAKE_BUILD_TYPE=Release
cmake --build build-cpu -j 8
```

5. Run CPU Example

```bash
./build-cpu/tp-core-driver 180 10
```

6. Compile GPU Version

```bash
module load nvidia/nvhpc
cmake -S standalone-tp-core -B build-gpu   -DCMAKE_BUILD_TYPE=Release   -DENABLE_CUDA_CPP=ON
cmake --build build-gpu --target tp-core-driver-cuda-cpp -j 8
```

7. Run GPU Example

```bash
./build-gpu/tp-core-driver-cuda-cpp 720 1000
```
