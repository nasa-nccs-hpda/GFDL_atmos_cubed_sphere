// test_driver.cpp
// C++ test driver for calc_ecc_anomaly
// Reads inputs from Fortran baseline harness and compares outputs

#include "calc_ecc_anomaly.hpp"
#include <fstream>
#include <iomanip>
#include <sstream>
#include <string>
#include <vector>
#include <cmath>

// Test case structure
struct TestCase {
    int id;
    double mean_anomaly;
    double ecc;
    double ecc_anomaly;      // computed
    double residual;         // computed
    double fortran_ecc_anomaly;  // from Fortran baseline (if available)
    double fortran_residual;     // from Fortran baseline (if available)
};

// Read Fortran input file
std::vector<TestCase> read_fortran_inputs(const std::string& filename) {
    std::vector<TestCase> tests;
    std::ifstream file(filename);

    if (!file.is_open()) {
        std::cerr << "Warning: Could not open " << filename << std::endl;
        return tests;
    }

    std::string line;
    while (std::getline(file, line)) {
        // Skip comment lines
        if (line.empty() || line[0] == '#') continue;

        TestCase tc;
        std::istringstream iss(line);
        if (iss >> tc.id >> tc.mean_anomaly >> tc.ecc) {
            tc.ecc_anomaly = 0.0;
            tc.residual = 0.0;
            tc.fortran_ecc_anomaly = 0.0;
            tc.fortran_residual = 0.0;
            tests.push_back(tc);
        }
    }

    return tests;
}

// Read Fortran output file for comparison
void read_fortran_outputs(const std::string& filename, std::vector<TestCase>& tests) {
    std::ifstream file(filename);

    if (!file.is_open()) {
        std::cerr << "Warning: Could not open " << filename << " for comparison" << std::endl;
        return;
    }

    std::string line;
    size_t idx = 0;
    while (std::getline(file, line) && idx < tests.size()) {
        // Skip comment lines
        if (line.empty() || line[0] == '#') continue;

        int id;
        double ecc_anomaly, residual;
        std::istringstream iss(line);
        if (iss >> id >> ecc_anomaly >> residual) {
            if (id == tests[idx].id) {
                tests[idx].fortran_ecc_anomaly = ecc_anomaly;
                tests[idx].fortran_residual = residual;
                ++idx;
            }
        }
    }
}

// Generate synthetic test cases (same as Fortran harness)
std::vector<TestCase> generate_test_cases() {
    const double pi = 3.14159265358979323846;
    std::vector<TestCase> tests(12);

    // Case 1: Zero eccentricity (E should equal M)
    tests[0] = {1, pi / 4.0, 0.0, 0, 0, 0, 0};

    // Case 2: Zero mean anomaly (E should be 0)
    tests[1] = {2, 0.0, 0.5, 0, 0, 0, 0};

    // Case 3: Circular orbit at pi
    tests[2] = {3, pi, 0.0, 0, 0, 0, 0};

    // Case 4: Earth-like eccentricity
    tests[3] = {4, 1.0, 0.0167, 0, 0, 0, 0};

    // Case 5: Mars-like eccentricity
    tests[4] = {5, 2.0, 0.0934, 0, 0, 0, 0};

    // Case 6: Mercury-like eccentricity
    tests[5] = {6, 1.5, 0.2056, 0, 0, 0, 0};

    // Case 7: High eccentricity
    tests[6] = {7, 0.5, 0.9, 0, 0, 0, 0};

    // Case 8: Negative mean anomaly (antisymmetry test)
    tests[7] = {8, -1.5, 0.3, 0, 0, 0, 0};

    // Case 9: Positive mean anomaly (pair for antisymmetry)
    tests[8] = {9, 1.5, 0.3, 0, 0, 0, 0};

    // Case 10: High eccentricity (e=0.95)
    tests[9] = {10, 0.1, 0.95, 0, 0, 0, 0};

    // Case 11: M = 2*pi (full orbit)
    tests[10] = {11, 2.0 * pi, 0.5, 0, 0, 0, 0};

    // Case 12: Edge case - high ecc near perihelion
    tests[11] = {12, 3.0, 0.999, 0, 0, 0, 0};

    return tests;
}

int main(int argc, char* argv[]) {
    std::vector<TestCase> tests;
    bool have_fortran_comparison = false;

    // Try to read from Fortran baseline files
    std::string input_file = "../../tests/fortran_baseline/calc_ecc_anomaly/inputs.dat";
    std::string output_file = "../../tests/fortran_baseline/calc_ecc_anomaly/outputs.dat";

    // Allow override via command line
    if (argc >= 2) {
        input_file = argv[1];
    }
    if (argc >= 3) {
        output_file = argv[2];
    }

    tests = read_fortran_inputs(input_file);

    if (tests.empty()) {
        std::cout << "No Fortran inputs found, generating synthetic test cases..." << std::endl;
        tests = generate_test_cases();
    } else {
        std::cout << "Read " << tests.size() << " test cases from " << input_file << std::endl;
        read_fortran_outputs(output_file, tests);
        have_fortran_comparison = true;
    }

    // Run all test cases through C++ implementation
    for (auto& tc : tests) {
        auto result = hs_forcing::calc_ecc_anomaly(tc.mean_anomaly, tc.ecc);
        tc.ecc_anomaly = result.ecc_anomaly;
        // Compute residual: should be ~0 if converged (Kepler's equation)
        tc.residual = tc.ecc_anomaly - tc.ecc * std::sin(tc.ecc_anomaly) - tc.mean_anomaly;
    }

    // Write C++ outputs in same format as Fortran
    {
        std::ofstream outfile("outputs.dat");
        outfile << "# Test outputs for calc_ecc_anomaly (C++)" << std::endl;
        outfile << "# Columns: test_id, ecc_anomaly, residual" << std::endl;
        outfile << std::scientific << std::setprecision(16);
        for (const auto& tc : tests) {
            outfile << std::setw(4) << tc.id
                    << std::setw(25) << tc.ecc_anomaly
                    << std::setw(25) << tc.residual << std::endl;
        }
        std::cout << "Wrote C++ outputs to: outputs.dat" << std::endl;
    }

    // Print summary
    std::cout << std::endl;
    std::cout << "===== calc_ecc_anomaly C++ Test Results =====" << std::endl;
    std::cout << std::endl;
    std::cout << std::setw(4) << "ID"
              << std::setw(16) << "M (rad)"
              << std::setw(12) << "e"
              << std::setw(20) << "E (rad)"
              << std::setw(16) << "Residual" << std::endl;
    std::cout << "------------------------------------------------------------" << std::endl;

    std::cout << std::fixed;
    for (const auto& tc : tests) {
        std::cout << std::setw(4) << tc.id
                  << std::setw(16) << std::setprecision(10) << tc.mean_anomaly
                  << std::setw(12) << std::setprecision(6) << tc.ecc
                  << std::setw(20) << std::setprecision(14) << tc.ecc_anomaly
                  << std::setw(16) << std::scientific << std::setprecision(6) << tc.residual
                  << std::fixed << std::endl;
    }
    std::cout << std::endl;

    // Verification
    std::cout << "===== Verification =====" << std::endl;
    std::cout << std::endl;

    int pass_count = 0;
    int fail_count = 0;

    // Check e=0 case: E should equal M
    if (std::abs(tests[0].ecc_anomaly - tests[0].mean_anomaly) < 1.0e-10) {
        std::cout << "PASS: e=0 case (E = M)" << std::endl;
        ++pass_count;
    } else {
        std::cout << "FAIL: e=0 case" << std::endl;
        ++fail_count;
    }

    // Check M=0 case: E should be 0
    if (std::abs(tests[1].ecc_anomaly) < 1.0e-10) {
        std::cout << "PASS: M=0 case (E = 0)" << std::endl;
        ++pass_count;
    } else {
        std::cout << "FAIL: M=0 case" << std::endl;
        ++fail_count;
    }

    // Check antisymmetry: E(-M) = -E(M)
    if (std::abs(tests[7].ecc_anomaly + tests[8].ecc_anomaly) < 1.0e-10) {
        std::cout << "PASS: Antisymmetry E(-M) = -E(M)" << std::endl;
        ++pass_count;
    } else {
        std::cout << "FAIL: Antisymmetry" << std::endl;
        ++fail_count;
    }

    // Check all residuals are small
    double max_residual = 0.0;
    for (const auto& tc : tests) {
        max_residual = std::max(max_residual, std::abs(tc.residual));
    }
    if (max_residual < 1.0e-8) {
        std::cout << "PASS: All residuals < 1e-8" << std::endl;
        ++pass_count;
    } else {
        std::cout << "FAIL: Some residuals too large, max = " << max_residual << std::endl;
        ++fail_count;
    }

    // Compare with Fortran baseline if available
    if (have_fortran_comparison) {
        std::cout << std::endl;
        std::cout << "===== Fortran Comparison =====" << std::endl;
        std::cout << std::endl;

        double max_diff = 0.0;
        for (const auto& tc : tests) {
            double diff = std::abs(tc.ecc_anomaly - tc.fortran_ecc_anomaly);
            max_diff = std::max(max_diff, diff);
        }

        std::cout << "Max |E_cpp - E_fortran| = " << std::scientific << max_diff << std::endl;

        if (max_diff < 1.0e-10) {
            std::cout << "PASS: C++ matches Fortran within 1e-10" << std::endl;
            ++pass_count;
        } else if (max_diff < 1.0e-6) {
            std::cout << "PASS: C++ matches Fortran within 1e-6 (precision difference expected)" << std::endl;
            ++pass_count;
        } else {
            std::cout << "FAIL: C++ differs from Fortran by more than 1e-6" << std::endl;
            ++fail_count;
        }

        // Detailed comparison table
        std::cout << std::endl;
        std::cout << std::setw(4) << "ID"
                  << std::setw(22) << "E (C++)"
                  << std::setw(22) << "E (Fortran)"
                  << std::setw(16) << "Difference" << std::endl;
        std::cout << "----------------------------------------------------------------" << std::endl;

        for (const auto& tc : tests) {
            double diff = tc.ecc_anomaly - tc.fortran_ecc_anomaly;
            std::cout << std::setw(4) << tc.id
                      << std::setw(22) << std::setprecision(14) << std::fixed << tc.ecc_anomaly
                      << std::setw(22) << tc.fortran_ecc_anomaly
                      << std::setw(16) << std::scientific << std::setprecision(6) << diff
                      << std::endl;
        }
    }

    std::cout << std::endl;
    std::cout << "===== Summary =====" << std::endl;
    std::cout << "Passed: " << pass_count << std::endl;
    std::cout << "Failed: " << fail_count << std::endl;
    std::cout << std::endl;

    return fail_count > 0 ? 1 : 0;
}
