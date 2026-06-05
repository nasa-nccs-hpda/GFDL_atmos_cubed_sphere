CXX = g++
CXXFLAGS = -O2 -std=c++17 -Iinclude
AR = ar
ARFLAGS = rcs

SRC = $(wildcard src/*.cpp)
OBJ = $(patsubst src/%.cpp,build/%.o,$(SRC))
LIB = libhs_forcing.a
BIN_DIR = bin
TEST_SRC = tests/driver_forcing_module.cpp
TEST_BIN = $(BIN_DIR)/driver_forcing_module

all: lib test

lib: $(LIB)

$(LIB): $(OBJ)
	$(AR) $(ARFLAGS) $@ $^

build/%.o: src/%.cpp | build
	$(CXX) $(CXXFLAGS) -c $< -o $@

test: $(TEST_BIN)

$(TEST_BIN): $(LIB) $(TEST_SRC) | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) $(TEST_SRC) -L. -lhs_forcing -o $@

build:
	mkdir -p build

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

clean:
	rm -rf build $(LIB) $(BIN_DIR)

.PHONY: all lib test clean
