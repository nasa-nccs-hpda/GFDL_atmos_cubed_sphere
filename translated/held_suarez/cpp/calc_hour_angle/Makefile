# Makefile for Calc Hour Angle C++ Test
#
# Usage:
#   make      - Build the test executable
#   make run  - Build and run the test
#   make clean - Remove generated files

CXX = g++
CXXFLAGS = -std=c++17 -O2 -g -Wall -Wextra

# Executable name
TARGET = test_calc_hour_angle

# Source files
SRCS = test_driver.cpp

# Header files
HDRS = calc_hour_angle.hpp

.PHONY: all run clean

all: $(TARGET)

$(TARGET): $(SRCS) $(HDRS)
	$(CXX) $(CXXFLAGS) -o $@ $(SRCS)

run: $(TARGET)
	./$(TARGET)

clean:
	rm -f $(TARGET)
