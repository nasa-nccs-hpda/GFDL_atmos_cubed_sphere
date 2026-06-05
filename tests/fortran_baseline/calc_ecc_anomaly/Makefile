# Makefile for calc_ecc_anomaly Fortran baseline test
#
# Usage:
#   make          - Build the test harness
#   make run      - Build and run the test
#   make clean    - Remove build artifacts
#   make distclean - Remove build artifacts and output files

# Compiler settings
FC := gfortran
FFLAGS := -O2 -g -Wall -Wextra -fcheck=all -fbacktrace

# Intel Fortran alternative (uncomment if using ifort)
# FC = ifort
# FFLAGS = -O2 -g -warn all -check all -traceback

# NVIDIA HPC SDK alternative (uncomment if using nvfortran)
# FC = nvfortran
# FFLAGS = -O2 -g -Minform=warn

# Source files
MOD_SRC = calc_ecc_anomaly.F90
HARNESS_SRC = test_harness.F90

# Output
EXECUTABLE = test_calc_ecc_anomaly
MOD_FILE = calc_ecc_anomaly_mod.mod

# Build rules
.PHONY: all run clean distclean

all: $(EXECUTABLE)

$(EXECUTABLE): $(MOD_SRC) $(HARNESS_SRC)
	$(FC) $(FFLAGS) -o $@ $(MOD_SRC) $(HARNESS_SRC)

run: $(EXECUTABLE)
	./$(EXECUTABLE)

clean:
	rm -f $(EXECUTABLE) $(MOD_FILE) *.o *.mod

distclean: clean
	rm -f inputs.dat outputs.dat
