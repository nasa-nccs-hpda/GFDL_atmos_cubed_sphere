//-----------------------------------------------------------------------
// Test Driver for Top-Down Newtonian Damping C++ Translation
//
// Reads input arrays from Fortran baseline test, runs the C++ kernel,
// and compares output against Fortran reference.
//-----------------------------------------------------------------------

#include "top_down_newtonian_damping.hpp"

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
    int current_time;
    double dt;
    double solar_const, stefan, pi;
    double orbital_period, ecc, obliq, peri_time, smaxis;
    double albedo, lapse, h_a, tau_s, heat_capacity, ml_depth;
    double t_strat, eps, sigma_b, tka, tks, P00;
    int strat_option;
};

Params read_params(const std::string& filename) {
    Params p;
    std::ifstream file(filename, std::ios::binary);
    if (!file) {
        std::cerr << "Error: Cannot open file " << filename << std::endl;
        std::exit(1);
    }

    // Grid dimensions (4-byte integers)
    int32_t dims[3];
    file.read(reinterpret_cast<char*>(dims), 3 * sizeof(int32_t));
    p.nlon = dims[0];
    p.nlat = dims[1];
    p.nlev = dims[2];

    // Time (4-byte integer)
    int32_t ctime;
    file.read(reinterpret_cast<char*>(&ctime), sizeof(int32_t));
    p.current_time = ctime;

    // Timestep
    file.read(reinterpret_cast<char*>(&p.dt), sizeof(double));

    // Physical constants
    file.read(reinterpret_cast<char*>(&p.solar_const), sizeof(double));
    file.read(reinterpret_cast<char*>(&p.stefan), sizeof(double));
    file.read(reinterpret_cast<char*>(&p.pi), sizeof(double));

    // Orbital parameters
    file.read(reinterpret_cast<char*>(&p.orbital_period), sizeof(double));
    file.read(reinterpret_cast<char*>(&p.ecc), sizeof(double));
    file.read(reinterpret_cast<char*>(&p.obliq), sizeof(double));
    file.read(reinterpret_cast<char*>(&p.peri_time), sizeof(double));
    file.read(reinterpret_cast<char*>(&p.smaxis), sizeof(double));

    // Thermal parameters
    file.read(reinterpret_cast<char*>(&p.albedo), sizeof(double));
    file.read(reinterpret_cast<char*>(&p.lapse), sizeof(double));
    file.read(reinterpret_cast<char*>(&p.h_a), sizeof(double));
    file.read(reinterpret_cast<char*>(&p.tau_s), sizeof(double));
    file.read(reinterpret_cast<char*>(&p.heat_capacity), sizeof(double));
    file.read(reinterpret_cast<char*>(&p.ml_depth), sizeof(double));

    // Held-Suarez parameters
    file.read(reinterpret_cast<char*>(&p.t_strat), sizeof(double));
    file.read(reinterpret_cast<char*>(&p.eps), sizeof(double));
    file.read(reinterpret_cast<char*>(&p.sigma_b), sizeof(double));
    file.read(reinterpret_cast<char*>(&p.tka), sizeof(double));
    file.read(reinterpret_cast<char*>(&p.tks), sizeof(double));
    file.read(reinterpret_cast<char*>(&p.P00), sizeof(double));

    // Stratosphere option (4-byte integer)
    int32_t strat;
    file.read(reinterpret_cast<char*>(&strat), sizeof(int32_t));
    p.strat_option = strat;

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
    std::string data_dir = "../../../../tests/fortran_baseline/top_down_newtonian_damping/";

    if (argc > 1) {
        data_dir = argv[1];
        if (data_dir.back() != '/') data_dir += '/';
    }

    std::cout << "======================================" << std::endl;
    std::cout << "Top-Down Newtonian Damping C++ Test" << std::endl;
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
    std::cout << "Time parameters:" << std::endl;
    std::cout << "  current_time = " << params.current_time << " seconds ("
              << params.current_time / 86400 << " days)" << std::endl;
    std::cout << "  dt = " << params.dt << " seconds" << std::endl;
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
    std::vector<double> zfull = read_array(data_dir + "input_zfull.bin", size_3d);
    std::vector<double> t = read_array(data_dir + "input_t.bin", size_3d);
    std::vector<double> tg_prev = read_array(data_dir + "input_tg_prev.bin", size_2d);

    print_array_stats("lat", lat);
    print_array_stats("ps", ps);
    print_array_stats("zfull", zfull);
    print_array_stats("t", t);
    print_array_stats("tg_prev", tg_prev);
    std::cout << std::endl;

    //-------------------------------------------------------------------
    // Read reference outputs
    //-------------------------------------------------------------------
    std::cout << "Reading Fortran reference outputs..." << std::endl;
    std::vector<double> tdt_ref = read_array(data_dir + "output_tdt.bin", size_3d);
    std::vector<double> teq_ref = read_array(data_dir + "output_teq.bin", size_3d);
    std::vector<double> h_trop_ref = read_array(data_dir + "output_h_trop.bin", size_2d);
    std::vector<double> tg_new_ref = read_array(data_dir + "output_tg_new.bin", size_2d);

    print_array_stats("tdt_ref", tdt_ref);
    print_array_stats("teq_ref", teq_ref);
    print_array_stats("h_trop_ref", h_trop_ref);
    print_array_stats("tg_new_ref", tg_new_ref);
    std::cout << std::endl;

    //-------------------------------------------------------------------
    // Allocate output arrays
    //-------------------------------------------------------------------
    std::vector<double> tdt(size_3d, 0.0);
    std::vector<double> teq(size_3d, 0.0);
    std::vector<double> h_trop(size_2d, 0.0);
    std::vector<double> tg_new(size_2d, 0.0);

    //-------------------------------------------------------------------
    // Build params struct
    //-------------------------------------------------------------------
    hs_forcing::TopDownParams kernel_params;
    kernel_params.solar_const = params.solar_const;
    kernel_params.stefan = params.stefan;
    kernel_params.pi = params.pi;
    kernel_params.orbital_period = params.orbital_period;
    kernel_params.ecc = params.ecc;
    kernel_params.obliq = params.obliq;
    kernel_params.peri_time = params.peri_time;
    kernel_params.smaxis = params.smaxis;
    kernel_params.albedo = params.albedo;
    kernel_params.lapse = params.lapse;
    kernel_params.h_a = params.h_a;
    kernel_params.tau_s = params.tau_s;
    kernel_params.heat_capacity = params.heat_capacity;
    kernel_params.ml_depth = params.ml_depth;
    kernel_params.t_strat = params.t_strat;
    kernel_params.eps = params.eps;
    kernel_params.sigma_b = params.sigma_b;
    kernel_params.tka = params.tka;
    kernel_params.tks = params.tks;
    kernel_params.P00 = params.P00;
    kernel_params.strat_option = params.strat_option;

    //-------------------------------------------------------------------
    // Call C++ kernel
    //-------------------------------------------------------------------
    std::cout << "Calling C++ top_down_newtonian_damping kernel..." << std::endl;

    hs_forcing::top_down_newtonian_damping(
        params.nlon, params.nlat, params.nlev,
        params.current_time,
        params.dt,
        lat.data(),
        ps.data(),
        p_full.data(),
        zfull.data(),
        t.data(),
        tg_prev.data(),
        kernel_params,
        tdt.data(),
        teq.data(),
        h_trop.data(),
        tg_new.data(),
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
    print_array_stats("h_trop", h_trop);
    print_array_stats("tg_new", tg_new);
    std::cout << std::endl;

    //-------------------------------------------------------------------
    // Compare against Fortran reference
    //-------------------------------------------------------------------
    std::cout << "Comparing against Fortran reference..." << std::endl;
    std::cout << std::endl;

    CompareResult tdt_cmp = compare_arrays(tdt, tdt_ref);
    CompareResult teq_cmp = compare_arrays(teq, teq_ref);
    CompareResult h_trop_cmp = compare_arrays(h_trop, h_trop_ref);
    CompareResult tg_new_cmp = compare_arrays(tg_new, tg_new_ref);

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

    std::cout << "h_trop comparison:" << std::endl;
    std::cout << "  Max absolute difference: " << std::scientific << std::setprecision(6)
              << h_trop_cmp.max_abs_diff << " at index " << h_trop_cmp.max_abs_idx << std::endl;
    std::cout << "  Max relative difference: " << h_trop_cmp.max_rel_diff
              << " at index " << h_trop_cmp.max_rel_idx << std::endl;
    std::cout << "  Status: " << (h_trop_cmp.passed ? "PASS" : "FAIL") << std::endl;
    std::cout << std::endl;

    std::cout << "tg_new comparison:" << std::endl;
    std::cout << "  Max absolute difference: " << std::scientific << std::setprecision(6)
              << tg_new_cmp.max_abs_diff << " at index " << tg_new_cmp.max_abs_idx << std::endl;
    std::cout << "  Max relative difference: " << tg_new_cmp.max_rel_diff
              << " at index " << tg_new_cmp.max_rel_idx << std::endl;
    std::cout << "  Status: " << (tg_new_cmp.passed ? "PASS" : "FAIL") << std::endl;
    std::cout << std::endl;

    //-------------------------------------------------------------------
    // Per-latitude h_trop comparison
    //-------------------------------------------------------------------
    std::cout << "Per-latitude h_trop comparison (km):" << std::endl;
    double lat_degrees[] = {-80.0, -48.0, -16.0, 16.0, 48.0, 80.0};
    for (int j = 0; j < params.nlat; ++j) {
        int idx = 0 + params.nlon * j;
        double diff = std::abs(h_trop[idx] - h_trop_ref[idx]);
        std::cout << "  lat=" << std::fixed << std::setprecision(1) << std::setw(7) << lat_degrees[j]
                  << " deg: C++=" << std::setprecision(3) << std::setw(8) << h_trop[idx]
                  << ", Fortran=" << std::setw(8) << h_trop_ref[idx]
                  << ", diff=" << std::scientific << std::setprecision(2) << diff << std::endl;
    }
    std::cout << std::endl;

    //-------------------------------------------------------------------
    // Overall result
    //-------------------------------------------------------------------
    bool all_passed = tdt_cmp.passed && teq_cmp.passed && h_trop_cmp.passed && tg_new_cmp.passed;

    std::cout << "======================================" << std::endl;
    std::cout << "OVERALL RESULT: " << (all_passed ? "PASS" : "FAIL") << std::endl;
    std::cout << "======================================" << std::endl;

    return all_passed ? 0 : 1;
}
