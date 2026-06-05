# Makefile for calc_ecc_anomaly C++ translation test
#
# Usage:
#   make          - Build the test driver
#   make run      - Build and run the test
#   make compare  - Run and compare against Fortran baseline
#   make clean    - Remove build artifacts

# Compiler settings
CXX := g++
CXXFLAGS := -std=c++17 -O2 -g -Wall -Wextra -pedantic

# Paths
FORTRAN_BASELINE := ../../../../tests/fortran_baseline/calc_ecc_anomaly

# Source files
HEADER = calc_ecc_anomaly.hpp
DRIVER_SRC = test_driver.cpp

# Output
EXECUTABLE = test_calc_ecc_anomaly

# Build rules
.PHONY: all run compare clean

all: $(EXECUTABLE)

$(EXECUTABLE): $(DRIVER_SRC) $(HEADER)
	$(CXX) $(CXXFLAGS) -o $@ $(DRIVER_SRC)

run: $(EXECUTABLE)
	./$(EXECUTABLE)

# Run with Fortran baseline comparison
compare: $(EXECUTABLE)
	@echo "=== Building Fortran baseline if needed ==="
	$(MAKE) -C $(FORTRAN_BASELINE) run
	@echo ""
	@echo "=== Running C++ test with Fortran comparison ==="
	./$(EXECUTABLE) $(FORTRAN_BASELINE)/inputs.dat $(FORTRAN_BASELINE)/outputs.dat

clean:
	rm -f $(EXECUTABLE) outputs.dat
