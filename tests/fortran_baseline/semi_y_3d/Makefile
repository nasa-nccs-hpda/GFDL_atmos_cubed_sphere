FC = gfortran
FFLAGS ?= -O2

all: test_semi_y_3d

test_semi_y_3d: test_semi_y_3d.F90
	$(FC) $(FFLAGS) -o test_semi_y_3d test_semi_y_3d.F90

run: test_semi_y_3d
	./test_semi_y_3d

clean:
	rm -f *.o *.mod test_semi_y_3d

.PHONY: all run clean
