# Makefile — transform-stack compute prototype (T2).
#
# Builds on the GPU host (inside the apptainer container where nvcc/cuFFT/cuBLAS
# live), NOT on the local editing checkout. See
# docs/transform_compute_prototype_results.md for the container invocation.
#
#   make                      # build ./transform_bench
#   make ARCH=sm_70           # override GPU arch (default sm_80)
#   make run                  # build + run with defaults
#   ./transform_bench [gpu_iters] [cpu_iters]

NVCC   ?= nvcc
ARCH   ?= sm_90          # H100 GPU nodes; override e.g. ARCH=sm_80 elsewhere
CPPDIR := ../../cpp/transforms
OPT    := -O3
STD    := -std=c++14
INC    := -I. -I$(CPPDIR)
NVCCFLAGS := $(STD) $(OPT) -arch=$(ARCH) $(INC) -lineinfo
LDLIBS := -lcufft -lcublas

CU_SRC  := transform_gpu.cu transform_bench.cu
CPP_SRC := $(CPPDIR)/transform_tables.cpp $(CPPDIR)/transform_reference.cpp
OBJ     := transform_gpu.o transform_bench.o transform_tables.o transform_reference.o

TARGET := transform_bench

all: $(TARGET)

transform_gpu.o: transform_gpu.cu transform_gpu.h $(CPPDIR)/transform_reference.h $(CPPDIR)/transform_tables.h
	$(NVCC) $(NVCCFLAGS) -c $< -o $@

transform_bench.o: transform_bench.cu transform_gpu.h $(CPPDIR)/transform_reference.h $(CPPDIR)/transform_tables.h
	$(NVCC) $(NVCCFLAGS) -c $< -o $@

transform_tables.o: $(CPPDIR)/transform_tables.cpp $(CPPDIR)/transform_tables.h
	$(NVCC) $(NVCCFLAGS) -c $< -o $@

transform_reference.o: $(CPPDIR)/transform_reference.cpp $(CPPDIR)/transform_reference.h $(CPPDIR)/transform_tables.h
	$(NVCC) $(NVCCFLAGS) -c $< -o $@

$(TARGET): $(OBJ)
	$(NVCC) $(NVCCFLAGS) $(OBJ) -o $@ $(LDLIBS)

run: $(TARGET)
	./$(TARGET)

clean:
	rm -f $(OBJ) $(TARGET)

.PHONY: all run clean
