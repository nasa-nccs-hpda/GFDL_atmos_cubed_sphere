cmake_minimum_required(VERSION 3.20)
project(tp_core_driver LANGUAGES Fortran)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# tp_core.F90 has free-form lines longer than the default 132 columns.
# Apply this flag to any target that compiles tp_core.F90.
function(target_tp_core_flags tgt)
  if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    target_compile_options(${tgt} PRIVATE -ffree-line-length-none)
  elseif(CMAKE_Fortran_COMPILER_ID MATCHES "Intel")
    target_compile_options(${tgt} PRIVATE -extend-source)
  elseif(CMAKE_Fortran_COMPILER_ID MATCHES "NVHPC|PGI")
    target_compile_options(${tgt} PRIVATE -Mextend)
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

