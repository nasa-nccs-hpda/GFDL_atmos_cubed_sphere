CXX ?= g++
CXXFLAGS ?= -O2 -std=c++17 -Wall -Wextra -Iinclude
NVCC ?= nvcc
NVCCFLAGS ?= -O2 -std=c++17 -Iinclude -I../../../cuda/fv_advection/kernels

BASELINE_DIR ?= ../../../../../tests/fortran_baseline/fv_advection_kernels
REPORT ?= ../../../../../tests/reports/fv_advection_kernels_cpp_compare_report.json
CUDA_REPORT ?= ../../../../../tests/reports/fv_advection_kernels_cuda_compare_report.json
COMPARE_TOL ?= 1e-12

LIB = libfv_advection_kernels.a
CPU_OBJ = build/fv_advection_kernels.o
OBJ = $(CPU_OBJ)
DRIVER = bin/run_fv_advection_kernels_fixture
CUDA_SRC = ../../../cuda/fv_advection/kernels/fv_advection_kernels_cuda.cu
CUDA_OBJ = build/fv_advection_kernels_cuda.o
CUDA_VALIDATE_SRC = ../../../cuda/fv_advection/kernels/validate_fv_advection_kernels_cuda.cpp
CUDA_DRIVER = bin/validate_fv_advection_kernels_cuda

ifeq ($(USE_CUDA_FV_ADVECTION_KERNELS),1)
OBJ += $(CUDA_OBJ)
CXXFLAGS += -DUSE_CUDA_FV_ADVECTION_KERNELS -I../../../cuda/fv_advection/kernels
endif

.PHONY: all lib run compare check cuda_check cuda_check_impl clean

all: lib $(DRIVER)

lib: $(LIB)

$(LIB): $(OBJ)
	ar rcs $@ $^

$(CPU_OBJ): src/fv_advection_kernels.cpp include/fv_advection_kernels.hpp include/fv_advection_kernel_profile.hpp | build
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(CUDA_OBJ): $(CUDA_SRC) ../../../cuda/fv_advection/kernels/fv_advection_kernels_cuda.h include/fv_advection_kernel_profile.hpp | build
	$(NVCC) $(NVCCFLAGS) -c $< -o $@

$(DRIVER): tests/run_fv_advection_kernels_fixture.cpp $(LIB) include/fv_advection_kernels.hpp | bin
	$(CXX) $(CXXFLAGS) $< -L. -lfv_advection_kernels -o $@

run: $(DRIVER)
	./$(DRIVER) $(BASELINE_DIR) outputs

compare:
	python3 compare_outputs.py $(BASELINE_DIR)/outputs outputs $(REPORT) $(COMPARE_TOL)

check: run compare

cuda_check:
	$(MAKE) clean
	$(MAKE) USE_CUDA_FV_ADVECTION_KERNELS=1 cuda_check_impl

$(CUDA_DRIVER): $(LIB) $(CUDA_VALIDATE_SRC) ../../../cuda/fv_advection/kernels/fv_advection_kernels_cuda.h | bin
	$(NVCC) $(NVCCFLAGS) $(CUDA_VALIDATE_SRC) -L. -lfv_advection_kernels -o $@

cuda_check_impl: $(CUDA_DRIVER)
	./$(CUDA_DRIVER) $(BASELINE_DIR) outputs $(CUDA_REPORT) $(COMPARE_TOL) $(COMPARE_TOL)

build bin:
	mkdir -p $@

clean:
	rm -rf build bin outputs $(LIB)
