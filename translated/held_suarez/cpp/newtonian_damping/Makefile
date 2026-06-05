# Makefile for Newtonian Damping C++ Translation Test
#
# Usage:
#   make          - Build the test executable
#   make run      - Build and run the test (requires Fortran baseline data)
#   make clean    - Remove generated files

CXX = g++
CXXFLAGS = -std=c++17 -O2 -g -Wall -Wextra

# Executable name
TARGET = test_newtonian_damping

# Source files
SRCS = test_driver.cpp

# Header files
HDRS = newtonian_damping.hpp

# Path to Fortran baseline test data
BASELINE_DIR = ../../../../tests/fortran_baseline/newtonian_damping

.PHONY: all run clean check-baseline

all: $(TARGET)

$(TARGET): $(SRCS) $(HDRS)
	$(CXX) $(CXXFLAGS) -o $@ $(SRCS)

run: $(TARGET) check-baseline
	./$(TARGET) $(BASELINE_DIR)

check-baseline:
	@if [ ! -f $(BASELINE_DIR)/params.bin ]; then \
		echo "Error: Fortran baseline data not found."; \
		echo "Run 'module load gcc/12.1.0 && make run' in $(BASELINE_DIR) first."; \
		exit 1; \
	fi

clean:
	rm -f $(TARGET)
