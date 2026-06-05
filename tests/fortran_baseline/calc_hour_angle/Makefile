# Makefile for Calc Hour Angle Fortran Baseline Test
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
TARGET = test_calc_hour_angle

# Source files
SRCS = calc_hour_angle_standalone.F90 test_harness.F90

# Object files
OBJS = calc_hour_angle_standalone.o test_harness.o

# Output data files
DATA_FILES = input_lat.bin input_dec.bin params.bin output_hour_angle.bin

.PHONY: all run clean cleanall

all: $(TARGET)

$(TARGET): $(OBJS)
	$(FC) $(FFLAGS) -o $@ $^

calc_hour_angle_standalone.o: calc_hour_angle_standalone.F90
	$(FC) $(FFLAGS) -c $<

test_harness.o: test_harness.F90 calc_hour_angle_standalone.o
	$(FC) $(FFLAGS) -c $<

run: $(TARGET)
	./$(TARGET)

clean:
	rm -f $(TARGET) $(OBJS) *.mod

cleanall: clean
	rm -f $(DATA_FILES)
