FC = gfortran
FFLAGS ?= -O2 -std=f2008 -Wall -fcheck=bounds -cpp

BACKEND ?= cpu
CUDA_HOME ?= /usr/local/cuda
CUDA_LIBDIR ?= $(CUDA_HOME)/lib64
BASELINE_DIR ?= ../../../../../../tests/fortran_baseline/semi_y_3d
REPORT ?= ../../../../../../tests/reports/semi_y_3d_fortran_c_compare_report.json
CUDA_REPORT ?= ../../../../../../tests/reports/semi_y_3d_fortran_cuda_c_compare_report.json

PARENT_DIR = ..
LIB = $(PARENT_DIR)/libsemi_y_3d.a
OBJ_DIR = build
INTERFACE_SRC = semi_y_3d_c_interface.F90
RUN_SRC = run_on_baseline.F90
INTERFACE_OBJ = $(OBJ_DIR)/semi_y_3d_c_interface.o
RUN_OBJ = $(OBJ_DIR)/run_on_baseline.o
RUN_BIN = run_on_baseline

ifeq ($(BACKEND),cuda)
FFLAGS += -DUSE_CUDA_SEMI_Y_3D
LDFLAGS ?= -L$(PARENT_DIR) -L$(CUDA_LIBDIR) -lsemi_y_3d -lstdc++ -lcudart
else
LDFLAGS ?= -L$(PARENT_DIR) -lsemi_y_3d -lstdc++
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
	$(MAKE) -C $(PARENT_DIR) USE_CUDA_SEMI_Y_3D=1 lib
else
	$(MAKE) -C $(PARENT_DIR) lib
endif

run: $(RUN_BIN) inputs outputs
	cp $(BASELINE_DIR)/inputs/*.bin inputs/
	SEMI_Y_3D_BACKEND=$(BACKEND) ./$(RUN_BIN)

compare:
ifeq ($(BACKEND),cuda)
	python3 ../compare_outputs.py $(BASELINE_DIR)/outputs outputs $(CUDA_REPORT) output_dq_fortran_cuda_c.bin
else
	python3 ../compare_outputs.py $(BASELINE_DIR)/outputs outputs $(REPORT) output_dq_fortran_c.bin
endif

check: clean prepare_lib run compare

inputs outputs:
	mkdir -p $@

clean:
	rm -rf $(OBJ_DIR) inputs outputs $(RUN_BIN)
