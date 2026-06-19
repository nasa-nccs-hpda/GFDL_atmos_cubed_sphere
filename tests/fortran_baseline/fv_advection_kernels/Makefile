FC ?= mpifort
FFLAGS ?= -O2 -cpp -ffree-line-length-none -fdefault-real-8 -fdefault-double-8 -fallow-argument-mismatch

.PHONY: all run clean

all: test_fv_advection_kernels

test_fv_advection_kernels: test_fv_advection_kernels.F90
	$(FC) $(FFLAGS) $< -o $@

run: test_fv_advection_kernels
	./test_fv_advection_kernels

clean:
	rm -f test_fv_advection_kernels *.o *.mod
	rm -f inputs/*.bin inputs/params.txt outputs/*.bin
