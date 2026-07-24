NVCC ?= nvcc
NVCCFLAGS ?= -O3 -std=c++17 -I../../cuda/press_and_geopot
AR ?= ar
ARFLAGS ?= rcs

LIB = libpress_and_geopot_cuda.a
CUDA_SRC = ../../cuda/press_and_geopot/press_and_geopot_cuda.cu
CUDA_OBJ = build/press_and_geopot_cuda.o

.PHONY: all lib clean

all: lib

lib: $(LIB)

$(LIB): $(CUDA_OBJ)
	$(AR) $(ARFLAGS) $@ $^

$(CUDA_OBJ): $(CUDA_SRC) ../../cuda/press_and_geopot/press_and_geopot_cuda.h | build
	$(NVCC) $(NVCCFLAGS) -c $< -o $@

build:
	mkdir -p build

clean:
	rm -rf build $(LIB)
