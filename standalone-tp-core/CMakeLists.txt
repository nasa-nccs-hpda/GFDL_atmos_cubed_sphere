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

# ---- CPU benchmark drivers (header-only C++; same workload as the GPU drivers) ----
add_executable(yppm-driver-cpu driver_yppm_cpu.cc)
add_executable(xppm-driver-cpu driver_xppm_cpu.cc)
foreach(cpu_tgt yppm-driver-cpu xppm-driver-cpu)
  set_target_properties(${cpu_tgt} PROPERTIES CXX_STANDARD 11 CXX_STANDARD_REQUIRED ON)
endforeach()

# ---- GPU targets (optional — only when nvcc is available) ----
# The launch API (yppm_gpu.cuh) is header-only, so each .cu just includes it;
# no separate CUDA library target is needed.
include(CheckLanguage)
check_language(CUDA)
if(CMAKE_CUDA_COMPILER)
  enable_language(CUDA)

  add_executable(test_yppm_gpu        test_yppm_gpu.cu)    # multi-column unit test
  add_executable(tp-core-driver-gpu   driver_yppm_gpu.cu)  # yppm command-line benchmark
  add_executable(test_xppm_gpu        test_xppm_gpu.cu)    # multi-row unit test
  add_executable(tp-core-driver-gpu-x driver_xppm_gpu.cu)  # xppm command-line benchmark

  foreach(gpu_tgt test_yppm_gpu tp-core-driver-gpu test_xppm_gpu tp-core-driver-gpu-x)
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

  add_test(NAME test_yppm_gpu COMMAND test_yppm_gpu)
  add_test(NAME test_xppm_gpu COMMAND test_xppm_gpu)
else()
  message(STATUS "CUDA compiler not found — skipping GPU targets (test_yppm_gpu, tp-core-driver-gpu, test_xppm_gpu, tp-core-driver-gpu-x)")
endif()
