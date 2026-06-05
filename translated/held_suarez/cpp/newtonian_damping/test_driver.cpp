//-----------------------------------------------------------------------
// Test Driver for Newtonian Damping C++ Translation
//
// Reads input arrays from Fortran baseline test, runs the C++ kernel,
// and compares output against Fortran reference.
//-----------------------------------------------------------------------

#include "newtonian_damping.hpp"

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
    double t_zero, t_strat, delh, delv, eps;
    double P00, KAPPA, tka, tks, sigma_b;
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

    // Read 10 double parameters
    double params[10];
    file.read(reinterpret_cast<char*>(params), 10 * sizeof(double));
    p.t_zero = params[0];
    p.t_strat = params[1];
    p.delh = params[2];
    p.delv = params[3];
    p.eps = params[4];
    p.P00 = params[5];
    p.KAPPA = params[6];
    p.tka = params[7];
    p.tks = params[8];
    p.sigma_b = params[9];

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
    std::string data_dir = "../../../../tests/fortran_baseline/newtonian_damping/";

    if (argc > 1) {
        data_dir = argv[1];
        if (data_dir.back() != '/') data_dir += '/';
    }

    std::cout << "======================================" << std::endl;
    std::cout << "Newtonian Damping C++ Test Driver" << std::endl;
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
    std::cout << "Held-Suarez parameters:" << std::endl;
    std::cout << std::fixed << std::setprecision(6);
    std::cout << "  t_zero  = " << params.t_zero << " K" << std::endl;
    std::cout << "  t_strat = " << params.t_strat << " K" << std::endl;
    std::cout << "  delh    = " << params.delh << " K" << std::endl;
    std::cout << "  delv    = " << params.delv << " K" << std::endl;
    std::cout << "  eps     = " << params.eps << " K" << std::endl;
    std::cout << "  P00     = " << std::scientific << params.P00 << " Pa" << std::endl;
    std::cout << "  KAPPA   = " << std::fixed << params.KAPPA << std::endl;
    std::cout << "  tka     = " << std::scientific << params.tka << " 1/s" << std::endl;
    std::cout << "  tks     = " << params.tks << " 1/s" << std::endl;
    std::cout << "  sigma_b = " << std::fixed << params.sigma_b << std::endl;
    std::cout << std::endl;

    size_t size_2d = params.nlon * params.nlat;
    size_t size_3d = params.nlon * params.nlat * params.nlev;

    //-------------------------------------------------------------------
    // Read input arrays
    //-------------------------------------------------------------------
    std::cout << "Reading input arrays..." << std::endl;
    std::vector<double> lat = read_array(data_dir + "input_lat.bin", size_2d);
    std::vector<double> ps = read_array(data_dir + "input_ps.bin", size_2d);
    std::vector<double> p_full = read_array(data_dir + "input_p_full.bin", size_3d);
    std::vector<double> t = read_array(data_dir + "input_t.bin", size_3d);

    print_array_stats("lat", lat);
    print_array_stats("ps", ps);
    print_array_stats("p_full", p_full);
    print_array_stats("t", t);
    std::cout << std::endl;

    //-------------------------------------------------------------------
    // Read reference output
    //-------------------------------------------------------------------
    std::cout << "Reading Fortran reference output..." << std::endl;
    std::vector<double> tdt_ref = read_array(data_dir + "output_tdt.bin", size_3d);
    std::vector<double> teq_ref = read_array(data_dir + "output_teq.bin", size_3d);

    print_array_stats("tdt_ref", tdt_ref);
    print_array_stats("teq_ref", teq_ref);
    std::cout << std::endl;

    //-------------------------------------------------------------------
    // Allocate output arrays
    //-------------------------------------------------------------------
    std::vector<double> tdt(size_3d, 0.0);
    std::vector<double> teq(size_3d, 0.0);

    //-------------------------------------------------------------------
    // Call C++ kernel
    //-------------------------------------------------------------------
    std::cout << "Calling C++ newtonian_damping kernel..." << std::endl;

    hs_forcing::newtonian_damping(
        params.nlon, params.nlat, params.nlev,
        lat.data(),
        ps.data(),
        p_full.data(),
        t.data(),
        params.t_zero,
        params.t_strat,
        params.delh,
        params.delv,
        params.eps,
        params.P00,
        params.KAPPA,
        params.tka,
        params.tks,
        params.sigma_b,
        tdt.data(),
        teq.data(),
        nullptr  // no mask
    );

    std::cout << "Done." << std::endl;
    std::cout << std::endl;

    //-------------------------------------------------------------------
    // Print C++ results
    //-------------------------------------------------------------------
    std::cout << "C++ results:" << std::endl;
    print_array_stats("tdt", tdt);
    print_array_stats("teq", teq);
    std::cout << std::endl;

    //-------------------------------------------------------------------
    // Compare against Fortran reference
    //-------------------------------------------------------------------
    std::cout << "Comparing against Fortran reference..." << std::endl;
    std::cout << std::endl;

    CompareResult tdt_cmp = compare_arrays(tdt, tdt_ref);
    CompareResult teq_cmp = compare_arrays(teq, teq_ref);

    std::cout << "tdt comparison:" << std::endl;
    std::cout << "  Max absolute difference: " << std::scientific << std::setprecision(6)
              << tdt_cmp.max_abs_diff << " at index " << tdt_cmp.max_abs_idx << std::endl;
    std::cout << "  Max relative difference: " << tdt_cmp.max_rel_diff
              << " at index " << tdt_cmp.max_rel_idx << std::endl;
    std::cout << "  Status: " << (tdt_cmp.passed ? "PASS" : "FAIL") << std::endl;
    std::cout << std::endl;

    std::cout << "teq comparison:" << std::endl;
    std::cout << "  Max absolute difference: " << std::scientific << std::setprecision(6)
              << teq_cmp.max_abs_diff << " at index " << teq_cmp.max_abs_idx << std::endl;
    std::cout << "  Max relative difference: " << teq_cmp.max_rel_diff
              << " at index " << teq_cmp.max_rel_idx << std::endl;
    std::cout << "  Status: " << (teq_cmp.passed ? "PASS" : "FAIL") << std::endl;
    std::cout << std::endl;

    //-------------------------------------------------------------------
    // Per-level comparison
    //-------------------------------------------------------------------
    std::cout << "Per-level teq comparison:" << std::endl;
    for (int k = 0; k < params.nlev; ++k) {
        double max_diff = 0.0;
        double max_cpp = 0.0, max_ref = 0.0;
        for (int j = 0; j < params.nlat; ++j) {
            for (int i = 0; i < params.nlon; ++i) {
                int idx = i + params.nlon * (j + params.nlat * k);
                double diff = std::abs(teq[idx] - teq_ref[idx]);
                if (diff > max_diff) max_diff = diff;
                if (teq[idx] > max_cpp) max_cpp = teq[idx];
                if (teq_ref[idx] > max_ref) max_ref = teq_ref[idx];
            }
        }
        std::cout << "  Level " << k + 1 << ": C++ max=" << std::fixed << std::setprecision(2)
                  << max_cpp << " K, Fortran max=" << max_ref
                  << " K, max_diff=" << std::scientific << std::setprecision(2) << max_diff << std::endl;
    }
    std::cout << std::endl;

    std::cout << "Per-level tdt comparison:" << std::endl;
    for (int k = 0; k < params.nlev; ++k) {
        double max_abs_cpp = 0.0, max_abs_ref = 0.0;
        double max_diff = 0.0;
        for (int j = 0; j < params.nlat; ++j) {
            for (int i = 0; i < params.nlon; ++i) {
                int idx = i + params.nlon * (j + params.nlat * k);
                double diff = std::abs(tdt[idx] - tdt_ref[idx]);
                if (diff > max_diff) max_diff = diff;
                if (std::abs(tdt[idx]) > max_abs_cpp) max_abs_cpp = std::abs(tdt[idx]);
                if (std::abs(tdt_ref[idx]) > max_abs_ref) max_abs_ref = std::abs(tdt_ref[idx]);
            }
        }
        std::cout << "  Level " << k + 1 << ": C++ max|tdt|=" << std::scientific << std::setprecision(4)
                  << max_abs_cpp << ", Fortran=" << max_abs_ref
                  << ", diff=" << max_diff << std::endl;
    }
    std::cout << std::endl;

    //-------------------------------------------------------------------
    // Overall result
    //-------------------------------------------------------------------
    bool all_passed = tdt_cmp.passed && teq_cmp.passed;

    std::cout << "======================================" << std::endl;
    std::cout << "OVERALL RESULT: " << (all_passed ? "PASS" : "FAIL") << std::endl;
    std::cout << "======================================" << std::endl;

    return all_passed ? 0 : 1;
}
