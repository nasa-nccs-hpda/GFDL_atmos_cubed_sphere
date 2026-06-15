CXX = g++
CXXFLAGS = -O2 -std=c++17 -Iinclude
NVCC ?= nvcc
NVCCFLAGS ?= -O2 -std=c++17 -Iinclude -I../../cuda/forcing_module
AR = ar
ARFLAGS = rcs

SRC = $(wildcard src/*.cpp)
OBJ = $(patsubst src/%.cpp,build/%.o,$(SRC))
CUDA_SRC = ../../cuda/forcing_module/hs_forcing_cuda.cu
CUDA_OBJ = build/hs_forcing_cuda.o
LIB = libhs_forcing.a
BIN_DIR = bin
TEST_SRC = tests/driver_forcing_module.cpp
TEST_BIN = $(BIN_DIR)/driver_forcing_module
CUDA_TEST_SRC = ../../cuda/forcing_module/validate_hs_forcing_cuda.cpp
CUDA_TEST_BIN = $(BIN_DIR)/validate_hs_forcing_cuda

ifeq ($(USE_CUDA_HS_FORCE),1)
CXXFLAGS += -DUSE_CUDA_HS_FORCE -I../../cuda/forcing_module
OBJ += $(CUDA_OBJ)
LDFLAGS += -lcudart
endif

all: lib test

lib: $(LIB)

$(LIB): $(OBJ)
	$(AR) $(ARFLAGS) $@ $^

build/%.o: src/%.cpp | build
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(CUDA_OBJ): $(CUDA_SRC) ../../cuda/forcing_module/hs_forcing_cuda.h ../../cuda/forcing_module/hs_forcing_cuda_kernels.cuh | build
	$(NVCC) $(NVCCFLAGS) -c $< -o $@

test: $(TEST_BIN)

$(TEST_BIN): $(LIB) $(TEST_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) $(TEST_SRC) -L. -lhs_forcing $(LDFLAGS) -o $@

cuda_test: $(CUDA_TEST_BIN)

$(CUDA_TEST_BIN): $(LIB) $(CUDA_TEST_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) $(CUDA_TEST_SRC) -L. -lhs_forcing $(LDFLAGS) -o $@

build:
	mkdir -p build

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

clean:
	rm -rf build $(LIB) $(BIN_DIR)

.PHONY: all lib test cuda_test clean
