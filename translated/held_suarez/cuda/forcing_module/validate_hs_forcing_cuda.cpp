#include "../../cpp/forcing_module/include/held_suarez_c_api.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

std::vector<double> read_binary_array(const std::string& filename, std::size_t count)
{
    std::vector<double> data(count);
    std::ifstream file(filename, std::ios::binary);
    if (!file) {
        throw std::runtime_error("cannot open " + filename);
    }
    file.read(reinterpret_cast<char*>(data.data()), static_cast<std::streamsize>(count * sizeof(double)));
    if (!file) {
        throw std::runtime_error("failed to read " + filename);
    }
    return data;
}

struct CompareResult {
    double max_abs = 0.0;
    double rms = 0.0;
    std::size_t mismatches = 0;
};

CompareResult compare_arrays(const std::vector<double>& a, const std::vector<double>& b, double tol)
{
    CompareResult result;
    double sum_sq = 0.0;
    for (std::size_t i = 0; i < a.size(); ++i) {
        const double diff = a[i] - b[i];
        const double abs_diff = std::abs(diff);
        result.max_abs = std::max(result.max_abs, abs_diff);
        sum_sq += diff * diff;
        if (abs_diff > tol) {
            result.mismatches += 1;
        }
    }
    result.rms = a.empty() ? 0.0 : std::sqrt(sum_sq / static_cast<double>(a.size()));
    return result;
}

bool print_compare(const std::string& name,
                   const std::vector<double>& cpu,
                   const std::vector<double>& cuda,
                   double tol)
{
    const CompareResult result = compare_arrays(cpu, cuda, tol);
    std::cout << name
              << ": max_abs=" << std::scientific << std::setprecision(6) << result.max_abs
              << " rms=" << result.rms
              << " mismatches=" << result.mismatches
              << " tolerance=" << tol
              << std::endl;
    return result.mismatches == 0;
}

int run_backend(const char* backend,
                int nlon,
                int nlat,
                int nlev,
                const std::vector<double>& lon,
                const std::vector<double>& lat,
                const std::vector<double>& ps,
                const std::vector<double>& p_full,
                const std::vector<double>& u,
                const std::vector<double>& v,
                const std::vector<double>& t,
                std::vector<double>& udt,
                std::vector<double>& vdt,
                std::vector<double>& tdt,
                std::vector<double>& teq)
{
    setenv("HS_FORCE_BACKEND", backend, 1);

    double t_zero, t_strat, delh, delv, eps, p00, kappa;
    double tka, tks, vkf, sigma_b, orbital_period;
    double ecc, obliq, peri_time, smaxis, solar_const;
    double stefan, albedo, lapse, h_a, tau_s, heat_capacity, ml_depth;
    hs_get_defaults_c(&t_zero, &t_strat, &delh, &delv, &eps, &p00, &kappa,
                      &tka, &tks, &vkf, &sigma_b, &orbital_period,
                      &ecc, &obliq, &peri_time, &smaxis, &solar_const,
                      &stefan, &albedo, &lapse, &h_a, &tau_s,
                      &heat_capacity, &ml_depth);

    return hs_forcing_driver_c(
        nlon, nlat, nlev,
        0, 1200.0,
        lon.data(), lat.data(),
        ps.data(), p_full.data(), nullptr,
        u.data(), v.data(), t.data(),
        nullptr, nullptr,
        nullptr, nullptr,
        t_zero, t_strat, delh, delv, eps, p00, kappa,
        tka, tks, vkf, sigma_b,
        orbital_period, ecc, obliq, peri_time, smaxis,
        solar_const, stefan, albedo, lapse, h_a, tau_s, heat_capacity, ml_depth,
        0, HS_EQUILIBRIUM_HELD_SUAREZ, HS_STRATOSPHERE_DEFAULT,
        udt.data(), vdt.data(), tdt.data(), teq.data(),
        nullptr, nullptr, nullptr);
}

} // namespace

int main(int argc, char** argv)
{
    std::string data_dir = argc > 1 ? argv[1] : "../../../../tests/fortran_baseline/";
    if (!data_dir.empty() && data_dir.back() != '/') {
        data_dir.push_back('/');
    }
    const std::string nd_dir = data_dir + "newtonian_damping/";
    const std::string rd_dir = data_dir + "rayleigh_damping/";
    const double tolerance = argc > 2 ? std::atof(argv[2]) : 1.0e-12;

    try {
        std::ifstream params(nd_dir + "params.bin", std::ios::binary);
        if (!params) {
            std::cerr << "Cannot open " << nd_dir << "params.bin" << std::endl;
            return 2;
        }
        int32_t dims[3];
        params.read(reinterpret_cast<char*>(dims), sizeof(dims));
        const int nlon = dims[0];
        const int nlat = dims[1];
        const int nlev = dims[2];
        const std::size_t size_2d = static_cast<std::size_t>(nlon) * nlat;
        const std::size_t size_3d = size_2d * nlev;

        std::cout << "CUDA forcing validation grid: "
                  << nlon << " x " << nlat << " x " << nlev << std::endl;

        std::vector<double> lon(size_2d, 0.0);
        auto lat = read_binary_array(nd_dir + "input_lat.bin", size_2d);
        auto ps = read_binary_array(nd_dir + "input_ps.bin", size_2d);
        auto p_full = read_binary_array(nd_dir + "input_p_full.bin", size_3d);
        auto t = read_binary_array(nd_dir + "input_t.bin", size_3d);
        auto u = read_binary_array(rd_dir + "input_u.bin", size_3d);
        auto v = read_binary_array(rd_dir + "input_v.bin", size_3d);

        std::vector<double> udt_cpu(size_3d, 0.0), vdt_cpu(size_3d, 0.0);
        std::vector<double> tdt_cpu(size_3d, 0.0), teq_cpu(size_3d, 0.0);
        std::vector<double> udt_cuda(size_3d, 0.0), vdt_cuda(size_3d, 0.0);
        std::vector<double> tdt_cuda(size_3d, 0.0), teq_cuda(size_3d, 0.0);

        int status = run_backend("cpu", nlon, nlat, nlev, lon, lat, ps, p_full, u, v, t,
                                 udt_cpu, vdt_cpu, tdt_cpu, teq_cpu);
        if (status != HS_SUCCESS) {
            std::cerr << "CPU backend failed with status " << status << std::endl;
            return 3;
        }

        status = run_backend("cuda", nlon, nlat, nlev, lon, lat, ps, p_full, u, v, t,
                             udt_cuda, vdt_cuda, tdt_cuda, teq_cuda);
        if (status != HS_SUCCESS) {
            std::cerr << "CUDA backend failed with status " << status << std::endl;
            return 4;
        }

        bool ok = true;
        ok = print_compare("udt", udt_cpu, udt_cuda, tolerance) && ok;
        ok = print_compare("vdt", vdt_cpu, vdt_cuda, tolerance) && ok;
        ok = print_compare("tdt", tdt_cpu, tdt_cuda, tolerance) && ok;
        ok = print_compare("teq", teq_cpu, teq_cuda, tolerance) && ok;

        std::cout << "CUDA forcing validation status: " << (ok ? "PASS" : "FAIL") << std::endl;
        return ok ? 0 : 5;
    } catch (const std::exception& ex) {
        std::cerr << "CUDA forcing validation error: " << ex.what() << std::endl;
        return 1;
    }
}
