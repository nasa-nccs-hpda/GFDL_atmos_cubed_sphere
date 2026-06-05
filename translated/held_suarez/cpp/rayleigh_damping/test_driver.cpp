//-----------------------------------------------------------------------
// Test Driver for Rayleigh Damping C++ Translation
//
// Reads input arrays from Fortran baseline test, runs the C++ kernel,
// and compares output against Fortran reference.
//-----------------------------------------------------------------------

#include "rayleigh_damping.hpp"

#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <string>
#include <vector>

//-----------------------------------------------------------------------
// File I/O utilities
//-----------------------------------------------------------------------

std::vector<double> read_array(const std::string& filename, size_t count) {
    std::vector<double> data(count);
    std::ifstream file(filename, std::ios::binary);
    if (!file) {
        std::cerr << "Error: Cannot open file " << filename << std::endl;
        std::exit(1);
    }
    file.read(reinterpret_cast<char*>(data.data()), count * sizeof(double));
    if (!file) {
        std::cerr << "Error: Failed to read " << count << " doubles from " << filename << std::endl;
        std::exit(1);
    }
    return data;
}

struct Params {
    int nlon, nlat, nlev;
    double vkf, sigma_b;
};

Params read_params(const std::string& filename) {
    Params p;
    std::ifstream file(filename, std::ios::binary);
    if (!file) {
        std::cerr << "Error: Cannot open file " << filename << std::endl;
        std::exit(1);
    }
    // Fortran writes integers as 4-byte by default
    int32_t dims[3];
    file.read(reinterpret_cast<char*>(dims), 3 * sizeof(int32_t));
    p.nlon = dims[0];
    p.nlat = dims[1];
    p.nlev = dims[2];
    file.read(reinterpret_cast<char*>(&p.vkf), sizeof(double));
    file.read(reinterpret_cast<char*>(&p.sigma_b), sizeof(double));
    return p;
}

//-----------------------------------------------------------------------
// Comparison utilities
//-----------------------------------------------------------------------

struct CompareResult {
    double max_abs_diff;
    double max_rel_diff;
    int max_abs_idx;
    int max_rel_idx;
    bool passed;
};

CompareResult compare_arrays(const std::vector<double>& cpp_arr,
                              const std::vector<double>& ref_arr,
                              double rtol = 1e-14,
                              double atol = 1e-20) {
    CompareResult result = {0.0, 0.0, -1, -1, true};

    for (size_t i = 0; i < cpp_arr.size(); ++i) {
        double abs_diff = std::abs(cpp_arr[i] - ref_arr[i]);
        double denom = std::max(std::abs(ref_arr[i]), atol);
        double rel_diff = abs_diff / denom;

        if (abs_diff > result.max_abs_diff) {
            result.max_abs_diff = abs_diff;
            result.max_abs_idx = static_cast<int>(i);
        }
        if (rel_diff > result.max_rel_diff) {
            result.max_rel_diff = rel_diff;
            result.max_rel_idx = static_cast<int>(i);
        }

        // Check tolerance
        if (abs_diff > atol && rel_diff > rtol) {
            result.passed = false;
        }
    }
    return result;
}

void print_array_stats(const std::string& name, const std::vector<double>& arr) {
    double min_val = arr[0], max_val = arr[0];
    for (double v : arr) {
        if (v < min_val) min_val = v;
        if (v > max_val) max_val = v;
    }
    std::cout << "  " << name << " range: [" << std::scientific << std::setprecision(6)
              << min_val << ", " << max_val << "]" << std::endl;
}

//-----------------------------------------------------------------------
// Main driver
//-----------------------------------------------------------------------

int main(int argc, char* argv[]) {
    // Default data directory is the Fortran baseline test location
    std::string data_dir = "../../../../tests/fortran_baseline/rayleigh_damping/";

    if (argc > 1) {
        data_dir = argv[1];
        if (data_dir.back() != '/') data_dir += '/';
    }

    std::cout << "======================================" << std::endl;
    std::cout << "Rayleigh Damping C++ Test Driver" << std::endl;
    std::cout << "======================================" << std::endl;
    std::cout << std::endl;
    std::cout << "Data directory: " << data_dir << std::endl;
    std::cout << std::endl;

    //-------------------------------------------------------------------
    // Read parameters
    //-------------------------------------------------------------------
    std::cout << "Reading parameters..." << std::endl;
    Params params = read_params(data_dir + "params.bin");

    std::cout << "Grid dimensions:" << std::endl;
    std::cout << "  nlon  = " << params.nlon << std::endl;
    std::cout << "  nlat  = " << params.nlat << std::endl;
    std::cout << "  nlev  = " << params.nlev << std::endl;
    std::cout << std::endl;
    std::cout << "Parameters:" << std::endl;
    std::cout << "  vkf     = " << std::scientific << std::setprecision(10) << params.vkf << std::endl;
    std::cout << "  sigma_b = " << params.sigma_b << std::endl;
    std::cout << std::endl;

    size_t size_2d = params.nlon * params.nlat;
    size_t size_3d = params.nlon * params.nlat * params.nlev;

    //-------------------------------------------------------------------
    // Read input arrays
    //-------------------------------------------------------------------
    std::cout << "Reading input arrays..." << std::endl;
    std::vector<double> ps = read_array(data_dir + "input_ps.bin", size_2d);
    std::vector<double> p_full = read_array(data_dir + "input_p_full.bin", size_3d);
    std::vector<double> u = read_array(data_dir + "input_u.bin", size_3d);
    std::vector<double> v = read_array(data_dir + "input_v.bin", size_3d);

    print_array_stats("ps", ps);
    print_array_stats("p_full", p_full);
    print_array_stats("u", u);
    print_array_stats("v", v);
    std::cout << std::endl;

    //-------------------------------------------------------------------
    // Read reference output
    //-------------------------------------------------------------------
    std::cout << "Reading Fortran reference output..." << std::endl;
    std::vector<double> udt_ref = read_array(data_dir + "output_udt.bin", size_3d);
    std::vector<double> vdt_ref = read_array(data_dir + "output_vdt.bin", size_3d);

    print_array_stats("udt_ref", udt_ref);
    print_array_stats("vdt_ref", vdt_ref);
    std::cout << std::endl;

    //-------------------------------------------------------------------
    // Allocate output arrays
    //-------------------------------------------------------------------
    std::vector<double> udt(size_3d, 0.0);
    std::vector<double> vdt(size_3d, 0.0);

    //-------------------------------------------------------------------
    // Call C++ kernel
    //-------------------------------------------------------------------
    std::cout << "Calling C++ rayleigh_damping kernel..." << std::endl;

    hs_forcing::rayleigh_damping(
        params.nlon, params.nlat, params.nlev,
        ps.data(),
        p_full.data(),
        u.data(),
        v.data(),
        params.vkf,
        params.sigma_b,
        udt.data(),
        vdt.data(),
        nullptr  // no mask
    );

    std::cout << "Done." << std::endl;
    std::cout << std::endl;

    //-------------------------------------------------------------------
    // Print C++ results
    //-------------------------------------------------------------------
    std::cout << "C++ results:" << std::endl;
    print_array_stats("udt", udt);
    print_array_stats("vdt", vdt);
    std::cout << std::endl;

    //-------------------------------------------------------------------
    // Compare against Fortran reference
    //-------------------------------------------------------------------
    std::cout << "Comparing against Fortran reference..." << std::endl;
    std::cout << std::endl;

    CompareResult udt_cmp = compare_arrays(udt, udt_ref);
    CompareResult vdt_cmp = compare_arrays(vdt, vdt_ref);

    std::cout << "udt comparison:" << std::endl;
    std::cout << "  Max absolute difference: " << std::scientific << std::setprecision(6)
              << udt_cmp.max_abs_diff << " at index " << udt_cmp.max_abs_idx << std::endl;
    std::cout << "  Max relative difference: " << udt_cmp.max_rel_diff
              << " at index " << udt_cmp.max_rel_idx << std::endl;
    std::cout << "  Status: " << (udt_cmp.passed ? "PASS" : "FAIL") << std::endl;
    std::cout << std::endl;

    std::cout << "vdt comparison:" << std::endl;
    std::cout << "  Max absolute difference: " << std::scientific << std::setprecision(6)
              << vdt_cmp.max_abs_diff << " at index " << vdt_cmp.max_abs_idx << std::endl;
    std::cout << "  Max relative difference: " << vdt_cmp.max_rel_diff
              << " at index " << vdt_cmp.max_rel_idx << std::endl;
    std::cout << "  Status: " << (vdt_cmp.passed ? "PASS" : "FAIL") << std::endl;
    std::cout << std::endl;

    //-------------------------------------------------------------------
    // Per-level comparison
    //-------------------------------------------------------------------
    std::cout << "Per-level max|udt| comparison:" << std::endl;
    for (int k = 0; k < params.nlev; ++k) {
        double max_cpp = 0.0, max_ref = 0.0;
        for (int j = 0; j < params.nlat; ++j) {
            for (int i = 0; i < params.nlon; ++i) {
                int idx = i + params.nlon * (j + params.nlat * k);
                if (std::abs(udt[idx]) > max_cpp) max_cpp = std::abs(udt[idx]);
                if (std::abs(udt_ref[idx]) > max_ref) max_ref = std::abs(udt_ref[idx]);
            }
        }
        std::cout << "  Level " << k + 1 << ": C++=" << std::scientific << std::setprecision(4)
                  << max_cpp << ", Fortran=" << max_ref
                  << ", diff=" << std::abs(max_cpp - max_ref) << std::endl;
    }
    std::cout << std::endl;

    //-------------------------------------------------------------------
    // Overall result
    //-------------------------------------------------------------------
    bool all_passed = udt_cmp.passed && vdt_cmp.passed;

    std::cout << "======================================" << std::endl;
    std::cout << "OVERALL RESULT: " << (all_passed ? "PASS" : "FAIL") << std::endl;
    std::cout << "======================================" << std::endl;

    return all_passed ? 0 : 1;
}
