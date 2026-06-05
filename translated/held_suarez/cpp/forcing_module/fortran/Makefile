# Makefile for Fortran-C++ integration tests
# Build Fortran code and link with C++ libhs_forcing.a

FC = gfortran
FFLAGS = -O2 -std=f2008 -Wall -fcheck=bounds
LDFLAGS = -L.. -lhs_forcing -lstdc++ -lm

SRC_DIR = .
OBJ_DIR = build

INTERFACE_SRC = $(SRC_DIR)/hs_forcing_c_interface.F90
TEST_SRC = $(SRC_DIR)/test_hs_forcing_integration.F90
RUN_SRC = $(SRC_DIR)/run_on_baseline.F90
INTERFACE_OBJ = $(OBJ_DIR)/hs_forcing_c_interface.o
TEST_OBJ = $(OBJ_DIR)/test_hs_forcing_integration.o
RUN_OBJ = $(OBJ_DIR)/run_on_baseline.o
TEST_BIN = test_hs_forcing_integration
RUN_BIN = run_on_baseline

.PHONY: all run clean

all: $(TEST_BIN)

$(OBJ_DIR):
	mkdir -p $(OBJ_DIR)

$(INTERFACE_OBJ): $(INTERFACE_SRC) | $(OBJ_DIR)
	$(FC) $(FFLAGS) -c $(INTERFACE_SRC) -o $@ -J$(OBJ_DIR)

$(TEST_OBJ): $(TEST_SRC) $(INTERFACE_OBJ) | $(OBJ_DIR)
	$(FC) $(FFLAGS) -c $(TEST_SRC) -o $@ -J$(OBJ_DIR)

$(RUN_OBJ): $(RUN_SRC) $(INTERFACE_OBJ) | $(OBJ_DIR)
	$(FC) $(FFLAGS) -c $(RUN_SRC) -o $@ -J$(OBJ_DIR)

$(TEST_BIN): $(INTERFACE_OBJ) $(TEST_OBJ)
	$(FC) $(FFLAGS) $(INTERFACE_OBJ) $(TEST_OBJ) -o $@ $(LDFLAGS)
	@echo "Build successful: $(TEST_BIN)"

$(RUN_BIN): $(INTERFACE_OBJ) $(RUN_OBJ)
	$(FC) $(FFLAGS) $(INTERFACE_OBJ) $(RUN_OBJ) -o $@ $(LDFLAGS)
	@echo "Build successful: $(RUN_BIN)"

run: $(TEST_BIN)
	./$(TEST_BIN)

run_baseline: $(RUN_BIN)
	./$(RUN_BIN)

clean:
	rm -rf $(OBJ_DIR) *.mod $(TEST_BIN)
