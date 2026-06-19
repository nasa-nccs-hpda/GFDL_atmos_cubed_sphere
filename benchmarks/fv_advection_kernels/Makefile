CXX ?= g++
NVCC ?= nvcc
CXXFLAGS ?= -O3 -std=c++17 -Wall -Wextra
NVCCFLAGS ?= -O3 -std=c++17

ROOT := ../..
CPU_DIR := $(ROOT)/translated/held_suarez/cpp/fv_advection/kernels
INCLUDES := -I$(CPU_DIR)/include

BUILD_DIR := build
BIN_DIR := bin
TARGET := $(BIN_DIR)/fv_advection_cuda_benchmark
CPU_OBJ := $(BUILD_DIR)/fv_advection_kernels_cpu.o
BENCH_OBJ := $(BUILD_DIR)/fv_advection_cuda_benchmark.o

.PHONY: all run clean

all: $(TARGET)

$(CPU_OBJ): $(CPU_DIR)/src/fv_advection_kernels.cpp \
            $(CPU_DIR)/include/fv_advection_kernels.hpp \
            $(CPU_DIR)/include/fv_advection_kernel_profile.hpp | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(INCLUDES) -c $< -o $@

$(BENCH_OBJ): fv_advection_cuda_benchmark.cu | $(BUILD_DIR)
	$(NVCC) $(NVCCFLAGS) $(INCLUDES) -c $< -o $@

$(TARGET): $(CPU_OBJ) $(BENCH_OBJ) | $(BIN_DIR)
	$(NVCC) $(NVCCFLAGS) $^ -o $@

$(BUILD_DIR) $(BIN_DIR):
	mkdir -p $@

run: $(TARGET)
	./$(TARGET) --resolution T42 --iterations 100 --mode all

clean:
	rm -rf $(BUILD_DIR) $(BIN_DIR)
