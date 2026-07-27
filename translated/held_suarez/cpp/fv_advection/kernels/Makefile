CXX ?= g++
CXXFLAGS ?= -O2 -std=c++17 -Wall -Wextra -Iinclude
NVCC ?= nvcc
NVCCFLAGS ?= -O2 -std=c++17 -Iinclude -I../../../cuda/fv_advection/kernels -I../../../cuda/fv_advection/semi_y_3d

BASELINE_DIR ?= ../../../../../tests/fortran_baseline/fv_advection_kernels
REPORT ?= ../../../../../tests/reports/fv_advection_kernels_cpp_compare_report.json
CUDA_REPORT ?= ../../../../../tests/reports/fv_advection_kernels_cuda_compare_report.json
CUDA_PERSISTENT_REPORT ?= ../../../../../tests/reports/fv_advection_kernels_cuda_persistent_compare_report.json
CUDA_RESIDENT_REPORT ?= ../../../../../tests/reports/fv_advection_kernels_cuda_resident_compare_report.json
COMPARE_TOL ?= 1e-12

LIB = libfv_advection_kernels.a
CPU_OBJ = build/fv_advection_kernels.o
OBJ = $(CPU_OBJ)
DRIVER = bin/run_fv_advection_kernels_fixture
CUDA_SRC = ../../../cuda/fv_advection/kernels/fv_advection_kernels_cuda.cu
CUDA_OBJ = build/fv_advection_kernels_cuda.o
SEMI_Y_CUDA_SRC = ../../../cuda/fv_advection/semi_y_3d/semi_y_3d_cuda.cu
SEMI_Y_CUDA_OBJ = build/semi_y_3d_cuda.o
CUDA_VALIDATE_SRC = ../../../cuda/fv_advection/kernels/validate_fv_advection_kernels_cuda.cpp
CUDA_DRIVER = bin/validate_fv_advection_kernels_cuda

ifeq ($(USE_CUDA_FV_ADVECTION_KERNELS),1)
OBJ += $(CUDA_OBJ) $(SEMI_Y_CUDA_OBJ)
CXXFLAGS += -DUSE_CUDA_FV_ADVECTION_KERNELS -I../../../cuda/fv_advection/kernels
endif

# GPU-to-GPU halo exchange (FV transfer PoC, Level 1). Compiling the CUDA
# sources with NCCL pulls in MPI + NCCL, so it is opt-in: the model build turns
# it on, while the standalone CUDA validate/fixture targets leave it off and
# stay MPI-free. -ccbin mpicxx lets nvcc find <mpi.h> for the host code; nccl.h
# and libnccl are on the container's default include/library paths.
USE_FV_ADVECTION_NCCL ?= 0
ifeq ($(USE_FV_ADVECTION_NCCL),1)
NVCCFLAGS += -DFV_ADVECTION_USE_NCCL -ccbin mpicxx
endif

.PHONY: all lib run compare check cuda_check cuda_check_impl \
	cuda_persistent_check cuda_persistent_check_impl \
	cuda_resident_check cuda_resident_check_impl clean

all: lib $(DRIVER)

lib: $(LIB)

$(LIB): $(OBJ)
	ar rcs $@ $^

$(CPU_OBJ): src/fv_advection_kernels.cpp include/fv_advection_kernels.hpp include/fv_advection_kernel_profile.hpp | build
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(CUDA_OBJ): $(CUDA_SRC) ../../../cuda/fv_advection/kernels/fv_advection_kernels_cuda.h include/fv_advection_kernel_profile.hpp | build
	$(NVCC) $(NVCCFLAGS) -c $< -o $@

$(SEMI_Y_CUDA_OBJ): $(SEMI_Y_CUDA_SRC) ../../../cuda/fv_advection/semi_y_3d/semi_y_3d_cuda.h | build
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

cuda_persistent_check:
	$(MAKE) clean
	$(MAKE) USE_CUDA_FV_ADVECTION_KERNELS=1 cuda_persistent_check_impl

cuda_persistent_check_impl: $(CUDA_DRIVER)
	FV_KERNELS_CUDA_MODE=persistent ./$(CUDA_DRIVER) \
		$(BASELINE_DIR) outputs $(CUDA_PERSISTENT_REPORT) $(COMPARE_TOL) $(COMPARE_TOL)

cuda_resident_check:
	$(MAKE) clean
	$(MAKE) USE_CUDA_FV_ADVECTION_KERNELS=1 cuda_resident_check_impl

cuda_resident_check_impl: $(CUDA_DRIVER)
	FV_KERNELS_CUDA_MODE=resident ./$(CUDA_DRIVER) \
		$(BASELINE_DIR) outputs $(CUDA_RESIDENT_REPORT) $(COMPARE_TOL) $(COMPARE_TOL)

build bin:
	mkdir -p $@

clean:
	rm -rf build bin outputs $(LIB)
