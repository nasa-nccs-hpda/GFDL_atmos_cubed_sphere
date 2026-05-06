cmake_minimum_required(VERSION 3.20)
project(tp_core_driver LANGUAGES Fortran)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

set(CMAKE_Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/mod)

add_executable(tp-core-driver
  ../model/tp-core-driver/stubs/fv_mp_mod_stub.F90
  ../model/tp-core-driver/stubs/fv_grid_utils_stub.F90
  ../model/tp-core-driver/stubs/fv_arrays_stub.F90
  ../model/tp-core-driver/input/input_arrays.f90
  ../model/tp-core-driver/output/output_arrays.f90
  ../model/tp_core.F90
  ../model/tp-core-driver/driver_cpu.f90
  ../model/tp-core-driver/main.f90
)

# tp_core.F90 has free-form lines longer than the default 132 columns.
if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
  target_compile_options(tp-core-driver PRIVATE
    -ffree-line-length-none
  )
elseif(CMAKE_Fortran_COMPILER_ID MATCHES "Intel")
  target_compile_options(tp-core-driver PRIVATE
    -extend-source
  )
elseif(CMAKE_Fortran_COMPILER_ID MATCHES "NVHPC|PGI")
  target_compile_options(tp-core-driver PRIVATE
    -Mextend
  )
endif()

find_package(OpenMP)
if(OpenMP_Fortran_FOUND)
  target_link_libraries(tp-core-driver PRIVATE OpenMP::OpenMP_Fortran)
endif()

