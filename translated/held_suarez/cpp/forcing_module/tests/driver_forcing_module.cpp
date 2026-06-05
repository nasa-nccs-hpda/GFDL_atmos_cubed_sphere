// ============================================================================
// Held-Suarez Forcing Module: Test Driver
//
// This test driver validates the unified C++ forcing module against
// Fortran baseline data. It tests both the C++ interface and the C API.
//
// Usage:
//   ./driver_forcing_module [data_dir] [config_name]
//
//   data_dir:    Path to Fortran baseline data (default: see DATA_DIR below)
//   config_name: "held_suarez" or "top_down" (default: "held_suarez")
// ============================================================================

#include "../include/held_suarez_forcing.hpp"
#include "../include/held_suarez_c_api.h"

#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <string>
#include <vector>

// Default data directory (relative to this file's compiled location)
const std::string DEFAULT_DATA_DIR = "../../../../../tests/fortran_baseline/";

// ============================================================================
// File I/O Utilities
// ============================================================================

std::vector<double> read_binary_array(const std::string& filename, size_t count) {
    std::vector<double> data(count);
    std::ifstream file(filename, std::ios::binary);
    if (!file) {
        std::cerr << "Error: Cannot open file " << filename << std::endl;
        return data;
    }
    file.read(reinterpret_cast<char*>(data.data()), count * sizeof(double));
    if (!file) {
        std::cerr << "Error: Failed to read " << count << " doubles from " << filename << std::endl;
    }
    return data;
}

bool file_exists(const std::string& filename) {
    std::ifstream file(filename);
    return file.good();
}

// ============================================================================
// Comparison Utilities
// ============================================================================

struct CompareResult {
    double max_abs_diff;
    double max_rel_diff;
    int max_abs_idx;
    int max_rel_idx;
    bool passed;
};

CompareResult compare_arrays(
    const std::vector<double>& computed,
    const std::vector<double>& reference,
    double rtol = 1e-14,
    double atol = 1e-20)
{
    CompareResult result = {0.0, 0.0, -1, -1, true};

    if (computed.size() != reference.size()) {
        result.passed = false;
        return result;
    }

    for (size_t i = 0; i < computed.size(); ++i) {
        double abs_diff = std::abs(computed[i] - reference[i]);
        double denom = std::max(std::abs(reference[i]), atol);
        double rel_diff = abs_diff / denom;

        if (abs_diff > result.max_abs_diff) {
            result.max_abs_diff = abs_diff;
            result.max_abs_idx = static_cast<int>(i);
        }
        if (rel_diff > result.max_rel_diff) {
            result.max_rel_diff = rel_diff;
            result.max_rel_idx = static_cast<int>(i);
        }

        if (abs_diff > atol && rel_diff > rtol) {
            result.passed = false;
        }
    }

    return result;
}

void print_array_stats(const std::string& name, const std::vector<double>& arr) {
    if (arr.empty()) {
        std::cout << "  " << name << ": [empty]" << std::endl;
        return;
    }

    double min_val = arr[0], max_val = arr[0];
    for (double v : arr) {
        if (v < min_val) min_val = v;
        if (v > max_val) max_val = v;
    }
    std::cout << "  " << name << " range: [" << std::scientific << std::setprecision(6)
              << min_val << ", " << max_val << "]" << std::endl;
}

void print_compare_result(const std::string& name, const CompareResult& cmp) {
    std::cout << name << " comparison:" << std::endl;
    std::cout << "  Max absolute diff: " << std::scientific << std::setprecision(6)
              << cmp.max_abs_diff << " at idx " << cmp.max_abs_idx << std::endl;
    std::cout << "  Max relative diff: " << cmp.max_rel_diff
              << " at idx " << cmp.max_rel_idx << std::endl;
    std::cout << "  Status: " << (cmp.passed ? "PASS" : "FAIL") << std::endl;
}

// ============================================================================
// Test: Standard Held-Suarez Mode
// ============================================================================

bool test_held_suarez_mode(const std::string& data_dir) {
    std::cout << "\n======================================" << std::endl;
    std::cout << "Test: Standard Held-Suarez Mode" << std::endl;
    std::cout << "======================================\n" << std::endl;

    // Use newtonian_damping baseline data
    std::string nd_dir = data_dir + "newtonian_damping/";
    std::string rd_dir = data_dir + "rayleigh_damping/";

    // Check if baseline data exists
    if (!file_exists(nd_dir + "params.bin")) {
        std::cerr << "Error: Newtonian damping baseline not found at " << nd_dir << std::endl;
        std::cerr << "Run the Fortran baseline first." << std::endl;
        return false;
    }

    // Read newtonian_damping parameters
    std::ifstream nd_params(nd_dir + "params.bin", std::ios::binary);
    int32_t nd_dims[3];
    nd_params.read(reinterpret_cast<char*>(nd_dims), 3 * sizeof(int32_t));
    int nlon = nd_dims[0];
    int nlat = nd_dims[1];
    int nlev = nd_dims[2];

    std::cout << "Grid dimensions: " << nlon << " x " << nlat << " x " << nlev << std::endl;

    size_t size_2d = nlon * nlat;
    size_t size_3d = nlon * nlat * nlev;

    // Read inputs from newtonian_damping baseline
    auto lat = read_binary_array(nd_dir + "input_lat.bin", size_2d);
    auto ps = read_binary_array(nd_dir + "input_ps.bin", size_2d);
    auto p_full = read_binary_array(nd_dir + "input_p_full.bin", size_3d);
    auto t = read_binary_array(nd_dir + "input_t.bin", size_3d);

    // Read inputs from rayleigh_damping baseline (if available)
    std::vector<double> u(size_3d, 10.0);  // Default wind values
    std::vector<double> v(size_3d, 2.0);
    if (file_exists(rd_dir + "input_u.bin")) {
        u = read_binary_array(rd_dir + "input_u.bin", size_3d);
        v = read_binary_array(rd_dir + "input_v.bin", size_3d);
    }

    // Read reference outputs
    auto tdt_ref = read_binary_array(nd_dir + "output_tdt.bin", size_3d);
    auto teq_ref = read_binary_array(nd_dir + "output_teq.bin", size_3d);

    std::vector<double> udt_ref(size_3d, 0.0);
    std::vector<double> vdt_ref(size_3d, 0.0);
    if (file_exists(rd_dir + "output_udt.bin")) {
        udt_ref = read_binary_array(rd_dir + "output_udt.bin", size_3d);
        vdt_ref = read_binary_array(rd_dir + "output_vdt.bin", size_3d);
    }

    std::cout << "\nInput statistics:" << std::endl;
    print_array_stats("lat", lat);
    print_array_stats("ps", ps);
    print_array_stats("t", t);

    // Allocate output arrays (initialized to zero for accumulation)
    std::vector<double> udt(size_3d, 0.0);
    std::vector<double> vdt(size_3d, 0.0);
    std::vector<double> tdt(size_3d, 0.0);
    std::vector<double> teq(size_3d, 0.0);

    // Create configuration
    hs_forcing::Config config = hs_forcing::Config::defaults();
    config.equilibrium_option = hs_forcing::EQUILIBRIUM_HELD_SUAREZ;
    config.do_conserve_energy = 0;  // Disable for this test

    // Create dummy lon array (unused in HS mode)
    std::vector<double> lon(size_2d, 0.0);

    std::cout << "\nCalling C++ hs_forcing_driver (Held-Suarez mode)..." << std::endl;

    // Call C++ driver
    hs_forcing::hs_forcing_driver(
        nlon, nlat, nlev,
        0,           // current_time (unused for HS)
        1200.0,      // dt
        lon.data(),
        lat.data(),
        ps.data(),
        p_full.data(),
        nullptr,     // p_half (unused)
        u.data(),
        v.data(),
        t.data(),
        nullptr,     // um (no energy conservation)
        nullptr,     // vm
        nullptr,     // zfull (HS mode)
        nullptr,     // tg_prev (HS mode)
        config,
        udt.data(),
        vdt.data(),
        tdt.data(),
        teq.data(),
        nullptr,     // h_trop (HS mode)
        nullptr,     // tg_new (HS mode)
        nullptr      // mask
    );

    std::cout << "Done.\n" << std::endl;

    std::cout << "C++ output statistics:" << std::endl;
    print_array_stats("udt", udt);
    print_array_stats("vdt", vdt);
    print_array_stats("tdt", tdt);
    print_array_stats("teq", teq);

    // Compare outputs
    std::cout << "\nComparison with Fortran reference:" << std::endl;

    auto tdt_cmp = compare_arrays(tdt, tdt_ref);
    auto teq_cmp = compare_arrays(teq, teq_ref);

    print_compare_result("tdt", tdt_cmp);
    print_compare_result("teq", teq_cmp);

    // Check wind tendencies if we have reference data
    bool wind_passed = true;
    if (file_exists(rd_dir + "output_udt.bin")) {
        auto udt_cmp = compare_arrays(udt, udt_ref);
        auto vdt_cmp = compare_arrays(vdt, vdt_ref);
        print_compare_result("udt", udt_cmp);
        print_compare_result("vdt", vdt_cmp);
        wind_passed = udt_cmp.passed && vdt_cmp.passed;
    }

    bool all_passed = tdt_cmp.passed && teq_cmp.passed && wind_passed;

    std::cout << "\n--------------------------------------" << std::endl;
    std::cout << "Held-Suarez Test: " << (all_passed ? "PASS" : "FAIL") << std::endl;
    std::cout << "--------------------------------------" << std::endl;

    return all_passed;
}

// ============================================================================
// Test: Top-Down Mode
// ============================================================================

bool test_top_down_mode(const std::string& data_dir) {
    std::cout << "\n======================================" << std::endl;
    std::cout << "Test: Top-Down Newtonian Damping Mode" << std::endl;
    std::cout << "======================================\n" << std::endl;

    std::string td_dir = data_dir + "top_down_newtonian_damping/";

    // Check if baseline data exists
    if (!file_exists(td_dir + "params.bin")) {
        std::cerr << "Error: Top-down baseline not found at " << td_dir << std::endl;
        std::cerr << "Run the Fortran baseline first." << std::endl;
        return false;
    }

    // Read parameters
    std::ifstream params_file(td_dir + "params.bin", std::ios::binary);

    int32_t dims[3];
    params_file.read(reinterpret_cast<char*>(dims), 3 * sizeof(int32_t));
    int nlon = dims[0];
    int nlat = dims[1];
    int nlev = dims[2];

    int32_t current_time;
    params_file.read(reinterpret_cast<char*>(&current_time), sizeof(int32_t));

    double dt;
    params_file.read(reinterpret_cast<char*>(&dt), sizeof(double));

    // Read physical constants and config
    double solar_const, stefan, pi_val;
    params_file.read(reinterpret_cast<char*>(&solar_const), sizeof(double));
    params_file.read(reinterpret_cast<char*>(&stefan), sizeof(double));
    params_file.read(reinterpret_cast<char*>(&pi_val), sizeof(double));

    double orbital_period, ecc, obliq, peri_time, smaxis;
    params_file.read(reinterpret_cast<char*>(&orbital_period), sizeof(double));
    params_file.read(reinterpret_cast<char*>(&ecc), sizeof(double));
    params_file.read(reinterpret_cast<char*>(&obliq), sizeof(double));
    params_file.read(reinterpret_cast<char*>(&peri_time), sizeof(double));
    params_file.read(reinterpret_cast<char*>(&smaxis), sizeof(double));

    double albedo, lapse, h_a, tau_s, heat_capacity, ml_depth;
    params_file.read(reinterpret_cast<char*>(&albedo), sizeof(double));
    params_file.read(reinterpret_cast<char*>(&lapse), sizeof(double));
    params_file.read(reinterpret_cast<char*>(&h_a), sizeof(double));
    params_file.read(reinterpret_cast<char*>(&tau_s), sizeof(double));
    params_file.read(reinterpret_cast<char*>(&heat_capacity), sizeof(double));
    params_file.read(reinterpret_cast<char*>(&ml_depth), sizeof(double));

    double t_strat, eps, sigma_b, tka, tks, P00;
    params_file.read(reinterpret_cast<char*>(&t_strat), sizeof(double));
    params_file.read(reinterpret_cast<char*>(&eps), sizeof(double));
    params_file.read(reinterpret_cast<char*>(&sigma_b), sizeof(double));
    params_file.read(reinterpret_cast<char*>(&tka), sizeof(double));
    params_file.read(reinterpret_cast<char*>(&tks), sizeof(double));
    params_file.read(reinterpret_cast<char*>(&P00), sizeof(double));

    int32_t strat_option;
    params_file.read(reinterpret_cast<char*>(&strat_option), sizeof(int32_t));

    params_file.close();

    std::cout << "Grid dimensions: " << nlon << " x " << nlat << " x " << nlev << std::endl;
    std::cout << "Current time: " << current_time << " seconds (" << current_time/86400 << " days)" << std::endl;
    std::cout << "Timestep: " << dt << " seconds" << std::endl;

    size_t size_2d = nlon * nlat;
    size_t size_3d = nlon * nlat * nlev;

    // Read inputs
    auto lat = read_binary_array(td_dir + "input_lat.bin", size_2d);
    auto ps = read_binary_array(td_dir + "input_ps.bin", size_2d);
    auto p_full = read_binary_array(td_dir + "input_p_full.bin", size_3d);
    auto zfull = read_binary_array(td_dir + "input_zfull.bin", size_3d);
    auto t = read_binary_array(td_dir + "input_t.bin", size_3d);
    auto tg_prev = read_binary_array(td_dir + "input_tg_prev.bin", size_2d);

    // Read reference outputs
    auto tdt_ref = read_binary_array(td_dir + "output_tdt.bin", size_3d);
    auto teq_ref = read_binary_array(td_dir + "output_teq.bin", size_3d);
    auto h_trop_ref = read_binary_array(td_dir + "output_h_trop.bin", size_2d);
    auto tg_new_ref = read_binary_array(td_dir + "output_tg_new.bin", size_2d);

    std::cout << "\nInput statistics:" << std::endl;
    print_array_stats("lat", lat);
    print_array_stats("zfull", zfull);
    print_array_stats("t", t);
    print_array_stats("tg_prev", tg_prev);

    // Allocate outputs
    std::vector<double> tdt(size_3d, 0.0);
    std::vector<double> teq(size_3d, 0.0);
    std::vector<double> h_trop(size_2d, 0.0);
    std::vector<double> tg_new(size_2d, 0.0);

    // Build config
    hs_forcing::Config config;
    config.t_strat = t_strat;
    config.eps = eps;
    config.sigma_b = sigma_b;
    config.tka = tka;
    config.tks = tks;
    config.P00 = P00;
    config.orbital_period = orbital_period;
    config.ecc = ecc;
    config.obliq = obliq;
    config.peri_time = peri_time;
    config.smaxis = smaxis;
    config.solar_const = solar_const;
    config.stefan = stefan;
    config.albedo = albedo;
    config.lapse = lapse;
    config.h_a = h_a;
    config.tau_s = tau_s;
    config.heat_capacity = heat_capacity;
    config.ml_depth = ml_depth;
    config.stratosphere_option = strat_option;

    std::cout << "\nCalling C++ top_down_newtonian_damping..." << std::endl;

    // Call the kernel directly (not through driver) to match baseline
    hs_forcing::top_down_newtonian_damping(
        nlon, nlat, nlev,
        current_time, dt,
        lat.data(),
        ps.data(),
        p_full.data(),
        zfull.data(),
        t.data(),
        tg_prev.data(),
        config,
        tdt.data(),
        teq.data(),
        h_trop.data(),
        tg_new.data(),
        nullptr  // mask
    );

    std::cout << "Done.\n" << std::endl;

    std::cout << "C++ output statistics:" << std::endl;
    print_array_stats("tdt", tdt);
    print_array_stats("teq", teq);
    print_array_stats("h_trop", h_trop);
    print_array_stats("tg_new", tg_new);

    // Compare outputs
    std::cout << "\nComparison with Fortran reference:" << std::endl;

    auto tdt_cmp = compare_arrays(tdt, tdt_ref);
    auto teq_cmp = compare_arrays(teq, teq_ref);
    auto h_trop_cmp = compare_arrays(h_trop, h_trop_ref);
    auto tg_new_cmp = compare_arrays(tg_new, tg_new_ref);

    print_compare_result("tdt", tdt_cmp);
    print_compare_result("teq", teq_cmp);
    print_compare_result("h_trop", h_trop_cmp);
    print_compare_result("tg_new", tg_new_cmp);

    bool all_passed = tdt_cmp.passed && teq_cmp.passed &&
                      h_trop_cmp.passed && tg_new_cmp.passed;

    std::cout << "\n--------------------------------------" << std::endl;
    std::cout << "Top-Down Test: " << (all_passed ? "PASS" : "FAIL") << std::endl;
    std::cout << "--------------------------------------" << std::endl;

    return all_passed;
}

// ============================================================================
// Test: C API
// ============================================================================

bool test_c_api(const std::string& data_dir) {
    std::cout << "\n======================================" << std::endl;
    std::cout << "Test: C API Wrapper" << std::endl;
    std::cout << "======================================\n" << std::endl;

    std::string nd_dir = data_dir + "newtonian_damping/";

    if (!file_exists(nd_dir + "params.bin")) {
        std::cerr << "Skipping C API test: baseline data not found" << std::endl;
        return true;  // Not a failure, just skip
    }

    // Read parameters
    std::ifstream params_file(nd_dir + "params.bin", std::ios::binary);
    int32_t dims[3];
    params_file.read(reinterpret_cast<char*>(dims), 3 * sizeof(int32_t));
    int nlon = dims[0];
    int nlat = dims[1];
    int nlev = dims[2];
    params_file.close();

    size_t size_2d = nlon * nlat;
    size_t size_3d = nlon * nlat * nlev;

    // Read inputs
    auto lat = read_binary_array(nd_dir + "input_lat.bin", size_2d);
    auto ps = read_binary_array(nd_dir + "input_ps.bin", size_2d);
    auto p_full = read_binary_array(nd_dir + "input_p_full.bin", size_3d);
    auto t = read_binary_array(nd_dir + "input_t.bin", size_3d);

    // Read reference
    auto tdt_ref = read_binary_array(nd_dir + "output_tdt.bin", size_3d);
    auto teq_ref = read_binary_array(nd_dir + "output_teq.bin", size_3d);

    // Allocate outputs
    std::vector<double> tdt(size_3d, 0.0);
    std::vector<double> teq(size_3d, 0.0);

    // Get defaults
    double t_zero, t_strat, delh, delv, eps, P00, kappa;
    double tka, tks, vkf, sigma_b;
    hs_get_defaults_c(&t_zero, &t_strat, &delh, &delv, &eps, &P00, &kappa,
                      &tka, &tks, &vkf, &sigma_b,
                      nullptr, nullptr, nullptr, nullptr, nullptr,
                      nullptr, nullptr, nullptr,
                      nullptr, nullptr, nullptr, nullptr, nullptr);

    std::cout << "Calling C API hs_newtonian_damping_c..." << std::endl;

    int result = hs_newtonian_damping_c(
        nlon, nlat, nlev,
        lat.data(),
        ps.data(),
        p_full.data(),
        t.data(),
        t_zero, t_strat, delh, delv, eps, P00, kappa,
        tka, tks, sigma_b,
        tdt.data(),
        teq.data(),
        nullptr
    );

    if (result != HS_SUCCESS) {
        std::cerr << "C API returned error code: " << result << std::endl;
        return false;
    }

    std::cout << "Done (returned HS_SUCCESS).\n" << std::endl;

    // Compare
    auto tdt_cmp = compare_arrays(tdt, tdt_ref);
    auto teq_cmp = compare_arrays(teq, teq_ref);

    print_compare_result("tdt (via C API)", tdt_cmp);
    print_compare_result("teq (via C API)", teq_cmp);

    bool all_passed = tdt_cmp.passed && teq_cmp.passed;

    std::cout << "\n--------------------------------------" << std::endl;
    std::cout << "C API Test: " << (all_passed ? "PASS" : "FAIL") << std::endl;
    std::cout << "--------------------------------------" << std::endl;

    return all_passed;
}

// ============================================================================
// Main
// ============================================================================

int main(int argc, char* argv[]) {
    std::string data_dir = DEFAULT_DATA_DIR;
    if (argc > 1) {
        data_dir = argv[1];
        if (data_dir.back() != '/') data_dir += '/';
    }

    std::cout << "=============================================" << std::endl;
    std::cout << "Held-Suarez Forcing Module Test Driver" << std::endl;
    std::cout << "=============================================" << std::endl;
    std::cout << "\nData directory: " << data_dir << std::endl;

    bool all_passed = true;

    // Test 1: Standard Held-Suarez mode
    bool hs_passed = test_held_suarez_mode(data_dir);
    all_passed = all_passed && hs_passed;

    // Test 2: Top-down mode
    bool td_passed = test_top_down_mode(data_dir);
    all_passed = all_passed && td_passed;

    // Test 3: C API
    bool api_passed = test_c_api(data_dir);
    all_passed = all_passed && api_passed;

    // Final summary
    std::cout << "\n=============================================" << std::endl;
    std::cout << "OVERALL RESULT: " << (all_passed ? "PASS" : "FAIL") << std::endl;
    std::cout << "=============================================" << std::endl;

    return all_passed ? 0 : 1;
}
