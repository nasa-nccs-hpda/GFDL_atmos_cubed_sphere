# Makefile for Top-Down Newtonian Damping Fortran Baseline Test
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
TARGET = test_top_down_newtonian_damping

# Source files
SRCS = top_down_newtonian_damping_standalone.F90 test_harness.F90

# Object files
OBJS = top_down_newtonian_damping_standalone.o test_harness.o

# Output data files
DATA_FILES = input_lat.bin input_ps.bin input_p_full.bin input_zfull.bin \
             input_t.bin input_tg_prev.bin params.bin \
             output_tdt.bin output_teq.bin output_h_trop.bin output_tg_new.bin

.PHONY: all run clean cleanall

all: $(TARGET)

$(TARGET): $(OBJS)
	$(FC) $(FFLAGS) -o $@ $^

top_down_newtonian_damping_standalone.o: top_down_newtonian_damping_standalone.F90
	$(FC) $(FFLAGS) -c $<

test_harness.o: test_harness.F90 top_down_newtonian_damping_standalone.o
	$(FC) $(FFLAGS) -c $<

run: $(TARGET)
	./$(TARGET)

clean:
	rm -f $(TARGET) $(OBJS) *.mod

cleanall: clean
	rm -f $(DATA_FILES)
