# Makefile for Newtonian Damping Fortran Baseline Test
#
# Usage:
#   module load gcc/12.1.0   # Required on NCCS Discover
#   make          - Build the test executable
#   make run      - Build and run the test
#   make clean    - Remove generated files
#   make cleanall - Remove generated files and output data

FC = gfortran
FFLAGS = -O2 -g -fcheck=all -Wall -fbacktrace

# Use double precision by default
FFLAGS += -fdefault-real-8

# Executable name
TARGET = test_newtonian_damping

# Source files
SRCS = newtonian_damping_standalone.F90 test_harness.F90

# Object files
OBJS = newtonian_damping_standalone.o test_harness.o

# Output data files
DATA_FILES = input_lat.bin input_ps.bin input_p_full.bin input_t.bin \
             params.bin output_tdt.bin output_teq.bin

.PHONY: all run clean cleanall

all: $(TARGET)

$(TARGET): $(OBJS)
	$(FC) $(FFLAGS) -o $@ $^

newtonian_damping_standalone.o: newtonian_damping_standalone.F90
	$(FC) $(FFLAGS) -c $<

test_harness.o: test_harness.F90 newtonian_damping_standalone.o
	$(FC) $(FFLAGS) -c $<

run: $(TARGET)
	./$(TARGET)

clean:
	rm -f $(TARGET) $(OBJS) *.mod

cleanall: clean
	rm -f $(DATA_FILES)
