# Makefile for Rayleigh Damping Fortran Baseline Test
#
# Usage:
#   make          - Build the test executable
#   make run      - Build and run the test
#   make clean    - Remove generated files
#   make cleanall - Remove generated files and output data

FC = gfortran
FFLAGS = -O2 -g -fcheck=all -Wall -fbacktrace

# Use double precision by default
FFLAGS += -fdefault-real-8

# Executable name
TARGET = test_rayleigh_damping

# Source files
SRCS = rayleigh_damping_standalone.F90 test_harness.F90

# Object files
OBJS = rayleigh_damping_standalone.o test_harness.o

# Output data files
DATA_FILES = input_ps.bin input_p_full.bin input_u.bin input_v.bin \
             params.bin output_udt.bin output_vdt.bin

.PHONY: all run clean cleanall

all: $(TARGET)

$(TARGET): $(OBJS)
	$(FC) $(FFLAGS) -o $@ $^

rayleigh_damping_standalone.o: rayleigh_damping_standalone.F90
	$(FC) $(FFLAGS) -c $<

test_harness.o: test_harness.F90 rayleigh_damping_standalone.o
	$(FC) $(FFLAGS) -c $<

run: $(TARGET)
	./$(TARGET)

clean:
	rm -f $(TARGET) $(OBJS) *.mod

cleanall: clean
	rm -f $(DATA_FILES)
