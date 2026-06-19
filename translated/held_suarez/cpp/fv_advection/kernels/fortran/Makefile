FC ?= gfortran
FFLAGS ?= -O2 -std=f2008 -Wall -fcheck=bounds -cpp -ffree-line-length-none

BACKEND ?= cpu
CUDA_HOME ?= /usr/local/cuda
CUDA_LIBDIR ?= $(CUDA_HOME)/lib64
BASELINE_DIR ?= ../../../../../../tests/fortran_baseline/fv_advection_kernels
REPORT ?= ../../../../../../tests/reports/fv_advection_kernels_fortran_c_compare_report.json
CUDA_REPORT ?= ../../../../../../tests/reports/fv_advection_kernels_fortran_cuda_c_compare_report.json
COMPARE_TOL ?= 1e-12

PARENT_DIR = ..
LIB = $(PARENT_DIR)/libfv_advection_kernels.a
OBJ_DIR = build
INTERFACE_SRC = fv_advection_kernels_c_interface.F90
RUN_SRC = run_on_baseline.F90
INTERFACE_OBJ = $(OBJ_DIR)/fv_advection_kernels_c_interface.o
RUN_OBJ = $(OBJ_DIR)/run_on_baseline.o
RUN_BIN = run_on_baseline

ifeq ($(BACKEND),cuda)
FFLAGS += -DUSE_CUDA_FV_ADVECTION_KERNELS
LDFLAGS ?= -L$(PARENT_DIR) -L$(CUDA_LIBDIR) -lfv_advection_kernels -lstdc++ -lcudart
COMPARE_SUFFIX = fortran_cuda_c
COMPARE_REPORT = $(CUDA_REPORT)
else
LDFLAGS ?= -L$(PARENT_DIR) -lfv_advection_kernels -lstdc++
COMPARE_SUFFIX = fortran_c
COMPARE_REPORT = $(REPORT)
endif

.PHONY: all prepare_lib run compare check clean

all: $(RUN_BIN)

$(OBJ_DIR):
	mkdir -p $(OBJ_DIR)

$(INTERFACE_OBJ): $(INTERFACE_SRC) | $(OBJ_DIR)
	$(FC) $(FFLAGS) -c $< -o $@ -J$(OBJ_DIR)

$(RUN_OBJ): $(RUN_SRC) $(INTERFACE_OBJ) | $(OBJ_DIR)
	$(FC) $(FFLAGS) -c $< -o $@ -J$(OBJ_DIR)

$(RUN_BIN): $(INTERFACE_OBJ) $(RUN_OBJ) $(LIB)
	$(FC) $(FFLAGS) $(INTERFACE_OBJ) $(RUN_OBJ) -o $@ $(LDFLAGS)

prepare_lib:
	$(MAKE) -C $(PARENT_DIR) clean
ifeq ($(BACKEND),cuda)
	$(MAKE) -C $(PARENT_DIR) USE_CUDA_FV_ADVECTION_KERNELS=1 lib
else
	$(MAKE) -C $(PARENT_DIR) lib
endif

run: $(RUN_BIN) inputs outputs
	cp $(BASELINE_DIR)/inputs/*.bin inputs/
	cp $(BASELINE_DIR)/inputs/params.txt inputs/
	FV_ADVECTION_KERNELS_BACKEND=$(BACKEND) ./$(RUN_BIN)

compare:
	python3 ../compare_outputs.py $(BASELINE_DIR)/outputs outputs $(COMPARE_REPORT) $(COMPARE_TOL) $(COMPARE_SUFFIX)

check: clean prepare_lib run compare

inputs outputs:
	mkdir -p $@

clean:
	rm -rf $(OBJ_DIR) inputs outputs $(RUN_BIN)
