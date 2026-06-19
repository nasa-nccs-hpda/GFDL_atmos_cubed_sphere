CXX ?= g++
CXXFLAGS ?= -O2 -std=c++17 -Wall -Wextra -Iinclude
NVCC ?= nvcc
NVCCFLAGS ?= -O2 -std=c++17 -Iinclude -I../../../cuda/fv_advection/semi_y_3d

BASELINE_DIR ?= ../../../../../tests/fortran_baseline/semi_y_3d
REPORT ?= ../../../../../tests/reports/semi_y_3d_cpp_compare_report.json
CUDA_REPORT ?= ../../../../../tests/reports/semi_y_3d_cuda_compare_report.json

LIB = libsemi_y_3d.a
CPU_OBJ = build/semi_y_3d.o
OBJ = $(CPU_OBJ)
DRIVER = bin/run_semi_y_3d_fixture
CUDA_SRC = ../../../cuda/fv_advection/semi_y_3d/semi_y_3d_cuda.cu
CUDA_OBJ = build/semi_y_3d_cuda.o
CUDA_VALIDATE_SRC = ../../../cuda/fv_advection/semi_y_3d/validate_semi_y_3d_cuda.cpp
CUDA_DRIVER = bin/validate_semi_y_3d_cuda

ifeq ($(USE_CUDA_SEMI_Y_3D),1)
OBJ += $(CUDA_OBJ)
CXXFLAGS += -DUSE_CUDA_SEMI_Y_3D -I../../../cuda/fv_advection/semi_y_3d
endif

.PHONY: all lib run compare check cuda_check cuda_check_impl clean

all: lib $(DRIVER)

lib: $(LIB)

$(LIB): $(OBJ)
	ar rcs $@ $^

$(CPU_OBJ): src/semi_y_3d.cpp include/semi_y_3d.hpp | build
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(CUDA_OBJ): $(CUDA_SRC) ../../../cuda/fv_advection/semi_y_3d/semi_y_3d_cuda.h | build
	$(NVCC) $(NVCCFLAGS) -c $< -o $@

$(DRIVER): tests/run_semi_y_3d_fixture.cpp $(LIB) include/semi_y_3d.hpp | bin
	$(CXX) $(CXXFLAGS) $< -L. -lsemi_y_3d -o $@

run: $(DRIVER)
	./$(DRIVER) $(BASELINE_DIR) outputs

compare:
	python3 compare_outputs.py $(BASELINE_DIR)/outputs outputs $(REPORT)

check: run compare

cuda_check:
	$(MAKE) clean
	$(MAKE) USE_CUDA_SEMI_Y_3D=1 cuda_check_impl

$(CUDA_DRIVER): $(LIB) $(CUDA_VALIDATE_SRC) ../../../cuda/fv_advection/semi_y_3d/semi_y_3d_cuda.h | bin
	$(NVCC) $(NVCCFLAGS) $(CUDA_VALIDATE_SRC) -L. -lsemi_y_3d -o $@

cuda_check_impl: $(CUDA_DRIVER)
	./$(CUDA_DRIVER) $(BASELINE_DIR) outputs $(CUDA_REPORT) 1e-13 1e-13

build bin:
	mkdir -p $@

clean:
	rm -rf build bin outputs $(LIB)
