
FC = gfortran
FFLAGS = -O2 -fopenmp

MODULE1 = ../newtonian_damping/newtonian_damping_standalone.F90
MODULE2 = ../rayleigh_damping/rayleigh_damping_standalone.F90


all: test_forcing_module

test_forcing_module: test_forcing_module.F90
	$(MAKE) -C ../newtonian_damping
	$(MAKE) -C ../rayleigh_damping
	$(FC) $(FFLAGS) -I../newtonian_damping -I../rayleigh_damping -o test_forcing_module test_forcing_module.F90 \
		../newtonian_damping/newtonian_damping_standalone.o ../rayleigh_damping/rayleigh_damping_standalone.o

clean:
	rm -f *.o *.mod test_forcing_module

.PHONY: all clean
