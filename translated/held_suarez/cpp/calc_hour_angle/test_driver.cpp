//-----------------------------------------------------------------------
// Test Driver for Calc Hour Angle C++ Translation
//
// Reads input arrays from Fortran baseline test, runs the C++ kernel,
// and compares output against Fortran reference.
//-----------------------------------------------------------------------

#include "calc_hour_angle.hpp"

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

double read_scalar(const std::string& filename) {
    double value;
    std::ifstream file(filename, std::ios::binary);
    if (!file) {
        std::cerr << "Error: Cannot open file " << filename << std::endl;
        std::exit(1);
    }
    file.read(reinterpret_cast<char*>(&value), sizeof(double));
    if (!file) {
        std::cerr << "Error: Failed to read scalar from " << filename << std::endl;
        std::exit(1);
    }
    return value;
}

struct Params {
    int nlon, nlat;
};

Params read_params(const std::string& filename) {
    Params p;
    std::ifstream file(filename, std::ios::binary);
    if (!file) {
        std::cerr << "Error: Cannot open file " << filename << std::endl;
        std::exit(1);
    }
    // Fortran writes integers as 4-byte by default
    int32_t dims[2];
    file.read(reinterpret_cast<char*>(dims), 2 * sizeof(int32_t));
    p.nlon = dims[0];
    p.nlat = dims[1];
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
    std::string data_dir = "../../../../tests/fortran_baseline/calc_hour_angle/";

    if (argc > 1) {
        data_dir = argv[1];
        if (data_dir.back() != '/') data_dir += '/';
    }

    constexpr double PI = 3.14159265358979323846;

    std::cout << "======================================" << std::endl;
    std::cout << "Calc Hour Angle C++ Test Driver" << std::endl;
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
    std::cout << std::endl;

    size_t size_2d = params.nlon * params.nlat;

    //-------------------------------------------------------------------
    // Read input arrays
    //-------------------------------------------------------------------
    std::cout << "Reading input arrays..." << std::endl;
    std::vector<double> lat = read_array(data_dir + "input_lat.bin", size_2d);
    double dec = read_scalar(data_dir + "input_dec.bin");

    print_array_stats("lat", lat);
    std::cout << "  dec = " << std::scientific << std::setprecision(10) << dec
              << " rad (" << std::fixed << std::setprecision(2) << dec * 180.0 / PI << " deg)" << std::endl;
    std::cout << std::endl;

    //-------------------------------------------------------------------
    // Read reference output
    //-------------------------------------------------------------------
    std::cout << "Reading Fortran reference output..." << std::endl;
    std::vector<double> hour_angle_ref = read_array(data_dir + "output_hour_angle.bin", size_2d);

    print_array_stats("hour_angle_ref", hour_angle_ref);
    std::cout << std::endl;

    //-------------------------------------------------------------------
    // Allocate output array
    //-------------------------------------------------------------------
    std::vector<double> hour_angle(size_2d, 0.0);

    //-------------------------------------------------------------------
    // Call C++ kernel
    //-------------------------------------------------------------------
    std::cout << "Calling C++ calc_hour_angle kernel..." << std::endl;

    hs_forcing::calc_hour_angle(
        params.nlon, params.nlat,
        lat.data(),
        dec,
        hour_angle.data()
    );

    std::cout << "Done." << std::endl;
    std::cout << std::endl;

    //-------------------------------------------------------------------
    // Print C++ results
    //-------------------------------------------------------------------
    std::cout << "C++ results:" << std::endl;
    print_array_stats("hour_angle", hour_angle);
    std::cout << std::endl;

    //-------------------------------------------------------------------
    // Compare against Fortran reference
    //-------------------------------------------------------------------
    std::cout << "Comparing against Fortran reference..." << std::endl;
    std::cout << std::endl;

    CompareResult cmp = compare_arrays(hour_angle, hour_angle_ref);

    std::cout << "hour_angle comparison:" << std::endl;
    std::cout << "  Max absolute difference: " << std::scientific << std::setprecision(6)
              << cmp.max_abs_diff << " at index " << cmp.max_abs_idx << std::endl;
    std::cout << "  Max relative difference: " << cmp.max_rel_diff
              << " at index " << cmp.max_rel_idx << std::endl;
    std::cout << "  Status: " << (cmp.passed ? "PASS" : "FAIL") << std::endl;
    std::cout << std::endl;

    //-------------------------------------------------------------------
    // Per-latitude comparison
    //-------------------------------------------------------------------
    std::cout << "Per-latitude comparison (hour angle in degrees):" << std::endl;
    for (int j = 0; j < params.nlat; ++j) {
        int idx = 0 + params.nlon * j;  // First longitude point
        double cpp_deg = hour_angle[idx] * 180.0 / PI;
        double ref_deg = hour_angle_ref[idx] * 180.0 / PI;
        double lat_deg = lat[idx] * 180.0 / PI;
        double diff = std::abs(hour_angle[idx] - hour_angle_ref[idx]);
        std::cout << "  lat=" << std::fixed << std::setprecision(1) << std::setw(7) << lat_deg
                  << " deg: C++=" << std::setprecision(4) << std::setw(10) << cpp_deg
                  << ", Fortran=" << std::setw(10) << ref_deg
                  << ", diff=" << std::scientific << std::setprecision(2) << diff << std::endl;
    }
    std::cout << std::endl;

    //-------------------------------------------------------------------
    // Overall result
    //-------------------------------------------------------------------
    std::cout << "======================================" << std::endl;
    std::cout << "OVERALL RESULT: " << (cmp.passed ? "PASS" : "FAIL") << std::endl;
    std::cout << "======================================" << std::endl;

    return cmp.passed ? 0 : 1;
}
