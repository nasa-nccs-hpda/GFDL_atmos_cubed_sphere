cmake_minimum_required(VERSION 3.20)
project(tp_core_driver LANGUAGES Fortran CXX)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

option(ENABLE_CUDA_CPP "Build the CUDA C++ tp_core benchmark target" OFF)

set(CMAKE_Fortran_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/mod)

set(TP_CORE_COMMON_SOURCES
  ../model/tp-core-driver/stubs/fv_mp_mod_stub.F90
  ../model/tp-core-driver/stubs/fv_grid_utils_stub.F90
  ../model/tp-core-driver/stubs/fv_arrays_stub.F90
  ../model/tp-core-driver/input/input_arrays.f90
  ../model/tp-core-driver/output/output_arrays.f90
  ../model/tp_core.F90
)

add_executable(tp-core-driver
  ${TP_CORE_COMMON_SOURCES}
  ../model/tp-core-driver/driver_cpu.f90
  ../model/tp-core-driver/main.f90
)

foreach(target tp-core-driver)
  if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    target_compile_options(${target} PRIVATE -ffree-line-length-none)
  elseif(CMAKE_Fortran_COMPILER_ID MATCHES "Intel")
    target_compile_options(${target} PRIVATE -extend-source)
  elseif(CMAKE_Fortran_COMPILER_ID MATCHES "NVHPC|PGI")
    target_compile_options(${target} PRIVATE -Mextend)
  endif()
endforeach()

find_package(OpenMP)
if(OpenMP_Fortran_FOUND)
  target_link_libraries(tp-core-driver PRIVATE OpenMP::OpenMP_Fortran)
endif()

if(ENABLE_CUDA_CPP)
  enable_language(CUDA)
  add_executable(tp-core-driver-cuda-cpp
    ${TP_CORE_COMMON_SOURCES}
    ../model/tp-core-driver/driver_cuda_cpp.f90
    ../model/tp-core-driver/main_cuda_cpp.f90
    ../model/tp_core_cuda_cpp.cu
  )

  if(CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
    target_compile_options(tp-core-driver-cuda-cpp PRIVATE
      $<$<COMPILE_LANGUAGE:Fortran>:-ffree-line-length-none>
    )
  elseif(CMAKE_Fortran_COMPILER_ID MATCHES "Intel")
    target_compile_options(tp-core-driver-cuda-cpp PRIVATE
      $<$<COMPILE_LANGUAGE:Fortran>:-extend-source>
    )
  elseif(CMAKE_Fortran_COMPILER_ID MATCHES "NVHPC|PGI")
    target_compile_options(tp-core-driver-cuda-cpp PRIVATE
      $<$<COMPILE_LANGUAGE:Fortran>:-Mextend>
    )
  endif()

  target_compile_features(tp-core-driver-cuda-cpp PRIVATE cxx_std_17)
  set_target_properties(tp-core-driver-cuda-cpp PROPERTIES
    CUDA_STANDARD 17
    CUDA_ARCHITECTURES 80
  )

  if(OpenMP_Fortran_FOUND)
    target_link_libraries(tp-core-driver-cuda-cpp PRIVATE OpenMP::OpenMP_Fortran)
  endif()
endif()

