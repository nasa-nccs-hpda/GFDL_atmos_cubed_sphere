cmake_minimum_required(VERSION 3.20)
project(tp_core_driver LANGUAGES Fortran)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# tp_core.F90 has free-form lines longer than the default 132 columns.
# Apply this flag to any target that compiles tp_core.F90.
function(target_tp_core_flags tgt)
  if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    target_compile_options(${tgt} PRIVATE $<$<COMPILE_LANGUAGE:Fortran>:-ffree-line-length-none>)
  elseif(CMAKE_Fortran_COMPILER_ID MATCHES "Intel")
    target_compile_options(${tgt} PRIVATE $<$<COMPILE_LANGUAGE:Fortran>:-extend-source>)
  elseif(CMAKE_Fortran_COMPILER_ID MATCHES "NVHPC|PGI")
    target_compile_options(${tgt} PRIVATE $<$<COMPILE_LANGUAGE:Fortran>:-Mextend>)
  endif()
endfunction()

set(stub_srcs
  ../model/tp-core-driver/stubs/fv_mp_mod_stub.F90
  ../model/tp-core-driver/stubs/fv_grid_utils_stub.F90
  ../model/tp-core-driver/stubs/fv_arrays_stub.F90
)

# ---- Main driver executable ----
add_executable(tp-core-driver
  ${stub_srcs}
  ../model/tp-core-driver/input/input_arrays.f90
  ../model/tp-core-driver/output/output_arrays.f90
  ../model/tp_core.F90
  ../model/tp-core-driver/driver_cpu.f90
  ../model/tp-core-driver/main.f90
)
set_target_properties(tp-core-driver PROPERTIES
  Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/mod/driver)
target_tp_core_flags(tp-core-driver)

find_package(OpenMP)
if(OpenMP_Fortran_FOUND)
  target_link_libraries(tp-core-driver PRIVATE OpenMP::OpenMP_Fortran)
endif()

# ---- Unit tests ----
enable_testing()

add_executable(test_yppm
  ${stub_srcs}
  ../model/tp_core.F90
  test_yppm.f90
)
set_target_properties(test_yppm PROPERTIES
  Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/mod/test_yppm)
target_tp_core_flags(test_yppm)

add_test(NAME test_yppm COMMAND test_yppm)

# ---- C++ unit tests ----
enable_language(CXX)

add_executable(test_yppm_cpp
  ${stub_srcs}
  ../model/tp_core.F90
  yppm_c_binding.f90
  test_yppm_cpp.cpp
)
set_target_properties(test_yppm_cpp PROPERTIES
  Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/mod/test_yppm_cpp
  CXX_STANDARD 11
  CXX_STANDARD_REQUIRED ON)
target_tp_core_flags(test_yppm_cpp)

add_test(NAME test_yppm_cpp COMMAND test_yppm_cpp)

add_executable(test_xppm_cpp
  ${stub_srcs}
  ../model/tp_core.F90
  xppm_c_binding.f90
  test_xppm_cpp.cpp
)
set_target_properties(test_xppm_cpp PROPERTIES
  Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/mod/test_xppm_cpp
  CXX_STANDARD 11
  CXX_STANDARD_REQUIRED ON)
target_tp_core_flags(test_xppm_cpp)

add_test(NAME test_xppm_cpp COMMAND test_xppm_cpp)

add_executable(test_fv_tp_2d_cpp
  ${stub_srcs}
  ../model/tp_core.F90
  fv_tp_2d_c_binding.f90
  test_fv_tp_2d_cpp.cpp
)
set_target_properties(test_fv_tp_2d_cpp PROPERTIES
  Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/mod/test_fv_tp_2d_cpp
  CXX_STANDARD 11
  CXX_STANDARD_REQUIRED ON)
target_tp_core_flags(test_fv_tp_2d_cpp)

add_test(NAME test_fv_tp_2d_cpp COMMAND test_fv_tp_2d_cpp)

add_executable(test_tracer_2d_cpp
  ${stub_srcs}
  ../model/tp_core.F90
  tracer_2d_core_c_binding.f90
  test_tracer_2d_cpp.cpp
)
set_target_properties(test_tracer_2d_cpp PROPERTIES
  Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/mod/test_tracer_2d_cpp
  CXX_STANDARD 11
  CXX_STANDARD_REQUIRED ON)
target_tp_core_flags(test_tracer_2d_cpp)

add_test(NAME test_tracer_2d_cpp COMMAND test_tracer_2d_cpp)

# ---- CPU benchmark drivers (header-only C++; same workload as the GPU drivers) ----
add_executable(yppm-driver-cpu      driver_yppm_cpu.cc)
add_executable(xppm-driver-cpu      driver_xppm_cpu.cc)
add_executable(fv-tp-2d-driver-cpu  driver_fv_tp_2d_cpu.cc)
add_executable(tracer-2d-driver-cpu driver_tracer_2d_cpu.cc)
foreach(cpu_tgt yppm-driver-cpu xppm-driver-cpu fv-tp-2d-driver-cpu tracer-2d-driver-cpu)
  set_target_properties(${cpu_tgt} PROPERTIES CXX_STANDARD 11 CXX_STANDARD_REQUIRED ON)
endforeach()

# ---- Original-Fortran benchmark drivers (call tp_core_mod yppm/xppm directly) ----
add_executable(yppm-driver-fortran
  ${stub_srcs}
  ../model/tp_core.F90
  driver_yppm_fortran.f90
)
set_target_properties(yppm-driver-fortran PROPERTIES
  Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/mod/yppm_driver_fortran)
target_tp_core_flags(yppm-driver-fortran)

add_executable(xppm-driver-fortran
  ${stub_srcs}
  ../model/tp_core.F90
  driver_xppm_fortran.f90
)
set_target_properties(xppm-driver-fortran PROPERTIES
  Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/mod/xppm_driver_fortran)
target_tp_core_flags(xppm-driver-fortran)

# ---- GPU targets (optional — only when nvcc is available) ----
# The launch API (yppm_gpu.cuh) is header-only, so each .cu just includes it;
# no separate CUDA library target is needed.
include(CheckLanguage)
check_language(CUDA)
if(CMAKE_CUDA_COMPILER)
  enable_language(CUDA)

  add_executable(test_yppm_gpu         test_yppm_gpu.cu)      # multi-column unit test
  add_executable(tp-core-driver-gpu    driver_yppm_gpu.cu)    # yppm command-line benchmark
  add_executable(test_xppm_gpu         test_xppm_gpu.cu)      # multi-row unit test
  add_executable(tp-core-driver-gpu-x  driver_xppm_gpu.cu)    # xppm command-line benchmark
  add_executable(test_fv_tp_2d_gpu     test_fv_tp_2d_gpu.cu)  # fv_tp_2d GPU-vs-CPU test
  add_executable(fv-tp-2d-driver-gpu   driver_fv_tp_2d_gpu.cu)# fv_tp_2d command-line benchmark
  add_executable(test_tracer_2d_gpu    test_tracer_2d_gpu.cu) # tracer_2d GPU-vs-CPU test
  add_executable(tracer-2d-driver-gpu  driver_tracer_2d_gpu.cu)# tracer_2d command-line benchmark

  foreach(gpu_tgt test_yppm_gpu tp-core-driver-gpu test_xppm_gpu tp-core-driver-gpu-x
                  test_fv_tp_2d_gpu fv-tp-2d-driver-gpu
                  test_tracer_2d_gpu tracer-2d-driver-gpu)
    set_target_properties(${gpu_tgt} PROPERTIES
      CUDA_STANDARD 14
      CUDA_STANDARD_REQUIRED ON)
    # A100 = sm_80; override with -DCMAKE_CUDA_ARCHITECTURES=<arch> as needed.
    if(NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
      set_target_properties(${gpu_tgt} PROPERTIES CUDA_ARCHITECTURES 80)
    endif()
    # GCC 7.x is officially unsupported by newer nvcc; suppress the warning.
    target_compile_options(${gpu_tgt} PRIVATE
      $<$<COMPILE_LANGUAGE:CUDA>:--allow-unsupported-compiler>)
  endforeach()

  add_test(NAME test_yppm_gpu     COMMAND test_yppm_gpu)
  add_test(NAME test_xppm_gpu     COMMAND test_xppm_gpu)
  add_test(NAME test_fv_tp_2d_gpu COMMAND test_fv_tp_2d_gpu)
  add_test(NAME test_tracer_2d_gpu COMMAND test_tracer_2d_gpu)

  # ---- Device halo-exchange primitive (needs CUDA-aware MPI) ----
  # Run with: srun -n <N> ./test_halo_exchange   (not a ctest — needs mpirun/srun).
  find_package(MPI QUIET)
  if(MPI_CXX_FOUND)
    add_executable(test_halo_exchange test_halo_exchange.cu)
    set_target_properties(test_halo_exchange PROPERTIES CUDA_STANDARD 14 CUDA_STANDARD_REQUIRED ON)
    if(NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
      set_target_properties(test_halo_exchange PROPERTIES CUDA_ARCHITECTURES 80)
    endif()
    target_compile_options(test_halo_exchange PRIVATE
      $<$<COMPILE_LANGUAGE:CUDA>:--allow-unsupported-compiler>)
    target_link_libraries(test_halo_exchange PRIVATE MPI::MPI_CXX)
  else()
    message(STATUS "MPI not found — skipping test_halo_exchange")
  endif()
else()
  message(STATUS "CUDA compiler not found — skipping GPU targets")
endif()
