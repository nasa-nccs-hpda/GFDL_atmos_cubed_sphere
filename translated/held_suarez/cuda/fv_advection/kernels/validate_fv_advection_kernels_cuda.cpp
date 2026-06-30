#include "../../../cpp/fv_advection/kernels/include/fv_advection_kernels.hpp"
#include "fv_advection_kernels_cuda.h"

#include <algorithm>
#include <cerrno>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <sys/types.h>
#include <utility>
#include <vector>

namespace {

struct Params {
    int nx = 0;
    int ny = 0;
    int js = 0;
    int je = 0;
    int nz = 0;
    bool monotone = true;
    double dx = 0.0;
    double dt = 0.0;
};

struct CompareResult {
    bool pass = false;
    std::size_t count = 0;
    double max_abs = 0.0;
    double max_rel = 0.0;
    double rmse = 0.0;
    std::size_t mismatches = 0;
};

std::string join_path(const std::string& lhs, const std::string& rhs) {
    if (lhs.empty()) {
        return rhs;
    }
    if (lhs[lhs.size() - 1] == '/') {
        return lhs + rhs;
    }
    return lhs + "/" + rhs;
}

void make_directory(const std::string& path) {
    if (::mkdir(path.c_str(), 0775) == 0 || errno == EEXIST) {
        return;
    }
    throw std::runtime_error("could not create directory " + path + ": " +
                             std::strerror(errno));
}

std::string trim(const std::string& value) {
    const std::string whitespace = " \t\r\n";
    const std::size_t first = value.find_first_not_of(whitespace);
    if (first == std::string::npos) {
        return "";
    }
    const std::size_t last = value.find_last_not_of(whitespace);
    return value.substr(first, last - first + 1);
}

Params read_params(const std::string& path) {
    std::ifstream in(path);
    if (!in) {
        throw std::runtime_error("could not open " + path);
    }

    Params params;
    std::string line;
    while (std::getline(in, line)) {
        const std::size_t eq = line.find('=');
        if (eq == std::string::npos) {
            continue;
        }
        const std::string key = trim(line.substr(0, eq));
        const std::string value = trim(line.substr(eq + 1));
        if (key == "nx") {
            params.nx = std::stoi(value);
        } else if (key == "ny") {
            params.ny = std::stoi(value);
        } else if (key == "js") {
            params.js = std::stoi(value);
        } else if (key == "je") {
            params.je = std::stoi(value);
        } else if (key == "nz") {
            params.nz = std::stoi(value);
        } else if (key == "monotone") {
            params.monotone = value == "T" || value == "true" || value == "1";
        } else if (key == "dx") {
            params.dx = std::stod(value);
        } else if (key == "dt") {
            params.dt = std::stod(value);
        }
    }

    if (params.nx <= 0 || params.ny <= 0 || params.nz <= 0 ||
        params.je < params.js || params.dx == 0.0 || params.dt == 0.0) {
        throw std::runtime_error("invalid params in " + path);
    }
    return params;
}

template <typename T>
std::vector<T> read_binary(const std::string& path, std::size_t count) {
    std::vector<T> values(count);
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        throw std::runtime_error("could not open " + path);
    }
    in.read(reinterpret_cast<char*>(values.data()),
            static_cast<std::streamsize>(count * sizeof(T)));
    if (static_cast<std::size_t>(in.gcount()) != count * sizeof(T)) {
        throw std::runtime_error("short read from " + path);
    }
    return values;
}

template <typename T>
void write_binary(const std::string& path, const std::vector<T>& values) {
    std::ofstream out(path, std::ios::binary);
    if (!out) {
        throw std::runtime_error("could not write " + path);
    }
    out.write(reinterpret_cast<const char*>(values.data()),
              static_cast<std::streamsize>(values.size() * sizeof(T)));
}

CompareResult compare_arrays(const std::vector<double>& reference,
                             const std::vector<double>& candidate,
                             double atol,
                             double rtol) {
    if (reference.size() != candidate.size()) {
        throw std::runtime_error("array sizes differ");
    }

    CompareResult result;
    result.count = reference.size();
    double sum_sq = 0.0;

    for (std::size_t i = 0; i < reference.size(); ++i) {
        const double diff = candidate[i] - reference[i];
        const double abs_diff = std::abs(diff);
        const double denom = std::max(std::abs(reference[i]), 1.0e-300);
        const double rel = abs_diff / denom;
        result.max_abs = std::max(result.max_abs, abs_diff);
        result.max_rel = std::max(result.max_rel, rel);
        sum_sq += diff * diff;
        if (abs_diff > atol && rel > rtol) {
            result.mismatches += 1;
        }
    }

    result.rmse =
        reference.empty() ? 0.0
                          : std::sqrt(sum_sq /
                                      static_cast<double>(reference.size()));
    result.pass = result.mismatches == 0;
    return result;
}

template <typename T>
CompareResult exact_compare(const std::vector<T>& reference,
                            const std::vector<T>& candidate) {
    if (reference.size() != candidate.size()) {
        throw std::runtime_error("array sizes differ");
    }

    CompareResult result;
    result.count = reference.size();
    for (std::size_t i = 0; i < reference.size(); ++i) {
        if (reference[i] != candidate[i]) {
            result.mismatches += 1;
        }
    }
    result.pass = result.mismatches == 0;
    return result;
}

void print_result(const std::string& name, const CompareResult& result) {
    std::cout << name << ": pass=" << (result.pass ? "true" : "false")
              << " count=" << result.count << " max_abs=" << std::scientific
              << std::setprecision(6) << result.max_abs
              << " max_rel=" << result.max_rel << " rmse=" << result.rmse
              << " mismatches=" << result.mismatches << "\n";
}

void write_result_json(std::ofstream& out, const std::string& name,
                       const CompareResult& result, bool last) {
    out << "    {\n";
    out << "      \"name\": \"" << name << "\",\n";
    out << "      \"pass\": " << (result.pass ? "true" : "false") << ",\n";
    out << "      \"count\": " << result.count << ",\n";
    out << "      \"max_abs_error\": " << result.max_abs << ",\n";
    out << "      \"max_rel_error\": " << result.max_rel << ",\n";
    out << "      \"rmse\": " << result.rmse << ",\n";
    out << "      \"mismatches_above_tolerance\": " << result.mismatches << "\n";
    out << "    }" << (last ? "\n" : ",\n");
}

void write_json_report(const std::string& path,
                       const std::vector<std::pair<std::string, CompareResult>>& results,
                       double atol,
                       double rtol) {
    std::ofstream out(path);
    if (!out) {
        throw std::runtime_error("could not write report " + path);
    }

    bool overall_pass = true;
    for (const auto& item : results) {
        overall_pass = overall_pass && item.second.pass;
    }

    out << std::setprecision(17);
    out << "{\n";
    out << "  \"kernel_bundle\": \"fv_advection_kernels\",\n";
    out << "  \"backend\": \"cuda\",\n";
    out << "  \"atol\": " << atol << ",\n";
    out << "  \"rtol\": " << rtol << ",\n";
    out << "  \"overall_pass\": " << (overall_pass ? "true" : "false") << ",\n";
    out << "  \"results\": [\n";
    for (std::size_t i = 0; i < results.size(); ++i) {
        write_result_json(out, results[i].first, results[i].second,
                          i + 1 == results.size());
    }
    out << "  ]\n";
    out << "}\n";
}

void require_success(int ierr, const std::string& name) {
    if (ierr != 0) {
        throw std::runtime_error(name + " CUDA call failed with code " +
                                 std::to_string(ierr));
    }
}

}  // namespace

int main(int argc, char** argv) {
    if (argc < 4 || argc > 6) {
        std::cerr << "usage: " << argv[0]
                  << " <baseline_dir> <candidate_output_dir> <report_path> "
                     "[atol] [rtol]\n";
        return 2;
    }

    const std::string baseline_dir(argv[1]);
    const std::string out_dir(argv[2]);
    const std::string report_path(argv[3]);
    const double atol = argc > 4 ? std::atof(argv[4]) : 1.0e-13;
    const double rtol = argc > 5 ? std::atof(argv[5]) : 1.0e-13;

    try {
        const std::string input_dir = join_path(baseline_dir, "inputs");
        const std::string reference_dir = join_path(baseline_dir, "outputs");
        make_directory(out_dir);

        const Params p = read_params(join_path(input_dir, "params.txt"));
        const int active_ny = p.je - p.js + 1;
        const std::size_t x_count =
            static_cast<std::size_t>(p.nx) * active_ny * p.nz;
        const std::size_t sphere_q_count =
            static_cast<std::size_t>(p.nx) * (active_ny + 4) * p.nz;
        const std::size_t slope_sphere_count =
            static_cast<std::size_t>(p.nx) * (active_ny + 2) * p.nz;
        const std::size_t vc_count =
            static_cast<std::size_t>(p.nx) * (active_ny + 1) * p.nz;

        const std::vector<double> c =
            read_binary<double>(join_path(input_dir, "input_c.bin"), active_ny);
        const std::vector<double> cc = read_binary<double>(
            join_path(input_dir, "input_cc.bin"), active_ny + 1);
        const std::vector<double> dy = read_binary<double>(
            join_path(input_dir, "input_dy.bin"), active_ny + 2);
        const std::vector<double> dy_plus = read_binary<double>(
            join_path(input_dir, "input_dy_plus.bin"), active_ny + 2);
        const std::vector<double> dy_minus = read_binary<double>(
            join_path(input_dir, "input_dy_minus.bin"), active_ny + 2);
        const std::vector<double> va =
            read_binary<double>(join_path(input_dir, "input_va.bin"), x_count);
        const std::vector<double> dyy = read_binary<double>(
            join_path(input_dir, "input_dyy.bin"), active_ny + 1);
        const std::vector<double> ua =
            read_binary<double>(join_path(input_dir, "input_ua.bin"), x_count);
        const std::vector<double> uc =
            read_binary<double>(join_path(input_dir, "input_uc.bin"), x_count);
        const std::vector<double> q_x =
            read_binary<double>(join_path(input_dir, "input_q_x.bin"), x_count);
        const std::vector<double> q_sphere = read_binary<double>(
            join_path(input_dir, "input_q_sphere.bin"), sphere_q_count);
        const std::vector<double> vc =
            read_binary<double>(join_path(input_dir, "input_vc.bin"), vc_count);

        std::vector<double> b_x(x_count);
        for (int k0 = 0; k0 < p.nz; ++k0) {
            for (int j0 = 0; j0 < active_ny; ++j0) {
                for (int i0 = 0; i0 < p.nx; ++i0) {
                    const std::size_t idx =
                        static_cast<std::size_t>(i0) +
                        static_cast<std::size_t>(p.nx) *
                            (static_cast<std::size_t>(j0) +
                             static_cast<std::size_t>(active_ny) * k0);
                    b_x[idx] = ua[idx] * p.dt / (p.dx * c[j0]);
                }
            }
        }

        std::vector<double> semi_x_dq(x_count, -999.0);
        std::vector<double> slope_x_out(x_count, -999.0);
        std::vector<double> integer_flux_out(x_count, -999.0);
        std::vector<double> vanleer_x_dq_dt(x_count, 0.013);
        std::vector<double> slope_sphere_out(slope_sphere_count, -999.0);
        std::vector<double> vanleer_sphere_dq_dt(x_count, -0.021);
        std::vector<double> resident_q1(x_count, -999.0);
        std::vector<double> resident_q1_expected(x_count, -999.0);
        std::vector<double> resident_dq_dt(x_count, 0.013);
        std::vector<double> resident_dq_dt_expected(x_count, 0.013);

        require_success(fv_advection_kernels::cuda_backend::semi_x_3d_cuda(
                            p.nx, active_ny, p.nz, p.dt, p.dx, c.data(),
                            ua.data(), q_x.data(), semi_x_dq.data()),
                        "semi_x_3d_cuda");
        require_success(fv_advection_kernels::cuda_backend::slope_x_cuda(
                            p.nx, active_ny, p.nz, p.monotone, q_x.data(),
                            slope_x_out.data()),
                        "slope_x_cuda");
        require_success(fv_advection_kernels::cuda_backend::integer_flux_x_cuda(
                            p.nx, active_ny, p.nz, b_x.data(), q_x.data(),
                            integer_flux_out.data()),
                        "integer_flux_x_cuda");
        require_success(fv_advection_kernels::cuda_backend::vanleer_x_3d_cuda(
                            p.nx, active_ny, p.nz, p.dt, p.dx, c.data(),
                            p.monotone, uc.data(), q_x.data(),
                            vanleer_x_dq_dt.data()),
                        "vanleer_x_3d_cuda");
        require_success(fv_advection_kernels::cuda_backend::slope_sphere_cuda(
                            p.nx, active_ny + 2, p.nz, p.monotone,
                            dy_plus.data(), dy_minus.data(), q_sphere.data(),
                            slope_sphere_out.data()),
                        "slope_sphere_cuda");
        require_success(fv_advection_kernels::cuda_backend::vanleer_sphere_3d_cuda(
                            p.nx, active_ny, p.nz, p.dt, p.monotone,
                            p.js == 1, p.je == p.ny, c.data(), cc.data(),
                            dy.data(), dy_plus.data(), dy_minus.data(), vc.data(),
                            q_sphere.data(), vanleer_sphere_dq_dt.data()),
                        "vanleer_sphere_3d_cuda");

        if (fv_advection_kernels::cuda_backend::resident_boundary_enabled()) {
            fv_advection_kernels::semi_x_3d(
                p.nx, active_ny, p.nz, p.dt, p.dx, c.data(), ua.data(),
                q_x.data(), resident_q1_expected.data());
            for (std::size_t i = 0; i < x_count; ++i) {
                resident_q1_expected[i] += q_x[i];
            }

            // Halo-only residency: finish reuses the device interior produced by
            // begin (== resident_q1_expected); only the halo rows arrive from the
            // host. The q1 the device actually sees is q_sphere's halo plus that
            // begin-computed interior.
            std::vector<double> q1_combined = q_sphere;
            for (int k = 0; k < p.nz; ++k) {
                for (int j = 0; j < active_ny; ++j) {
                    for (int i = 0; i < p.nx; ++i) {
                        const std::size_t halo_idx =
                            (static_cast<std::size_t>(k) * (active_ny + 4) + (j + 2)) * p.nx + i;
                        const std::size_t int_idx =
                            (static_cast<std::size_t>(k) * active_ny + j) * p.nx + i;
                        q1_combined[halo_idx] = resident_q1_expected[int_idx];
                    }
                }
            }

            require_success(
                fv_advection_kernels::cuda_backend::resident_advection_begin(
                    p.nx, active_ny, p.nz, p.dt, p.dx, c.data(), ua.data(),
                    q_x.data(), resident_q1.data(), va.data(), dyy.data()),
                "resident_advection_begin");

            fv_advection_kernels::vanleer_x_3d(
                p.nx, active_ny, p.nz, p.dt, p.dx, c.data(), p.monotone,
                uc.data(), q_x.data(), resident_dq_dt_expected.data());
            fv_advection_kernels::vanleer_sphere_3d(
                p.nx, active_ny, p.nz, p.dt, p.monotone, p.js == 1,
                p.je == p.ny, c.data(), cc.data(), dy.data(), dy_plus.data(),
                dy_minus.data(), vc.data(), q1_combined.data(),
                resident_dq_dt_expected.data());

            require_success(
                fv_advection_kernels::cuda_backend::resident_advection_finish(
                    p.nx, active_ny, p.nz, p.dt, p.dx, p.monotone,
                    p.js == 1, p.je == p.ny, c.data(), cc.data(), dy.data(),
                    dy_plus.data(), dy_minus.data(), uc.data(), vc.data(),
                    q1_combined.data(), resident_dq_dt.data()),
                "resident_advection_finish");
        }

        write_binary(join_path(out_dir, "output_semi_x_dq_cuda.bin"), semi_x_dq);
        write_binary(join_path(out_dir, "output_slope_x_cuda.bin"), slope_x_out);
        write_binary(join_path(out_dir, "output_integer_flux_x_cuda.bin"),
                     integer_flux_out);
        write_binary(join_path(out_dir, "output_vanleer_x_dq_dt_cuda.bin"),
                     vanleer_x_dq_dt);
        write_binary(join_path(out_dir, "output_slope_sphere_cuda.bin"),
                     slope_sphere_out);
        write_binary(join_path(out_dir, "output_vanleer_sphere_dq_dt_cuda.bin"),
                     vanleer_sphere_dq_dt);
        if (fv_advection_kernels::cuda_backend::resident_boundary_enabled()) {
            write_binary(join_path(out_dir, "output_resident_q1_cuda.bin"), resident_q1);
            write_binary(join_path(out_dir, "output_resident_dq_dt_cuda.bin"), resident_dq_dt);
        }

        std::vector<std::pair<std::string, CompareResult>> results;
        results.push_back({"semi_x_dq",
                           compare_arrays(read_binary<double>(
                                              join_path(reference_dir, "output_semi_x_dq.bin"),
                                              x_count),
                                          semi_x_dq, atol, rtol)});
        results.push_back({"slope_x",
                           compare_arrays(read_binary<double>(
                                              join_path(reference_dir, "output_slope_x.bin"),
                                              x_count),
                                          slope_x_out, atol, rtol)});
        results.push_back({"integer_flux_x",
                           compare_arrays(read_binary<double>(
                                              join_path(reference_dir, "output_integer_flux_x.bin"),
                                              x_count),
                                          integer_flux_out, atol, rtol)});
        results.push_back({"vanleer_x_dq_dt",
                           compare_arrays(read_binary<double>(
                                              join_path(reference_dir, "output_vanleer_x_dq_dt.bin"),
                                              x_count),
                                          vanleer_x_dq_dt, atol, rtol)});
        results.push_back({"slope_sphere",
                           compare_arrays(read_binary<double>(
                                              join_path(reference_dir, "output_slope_sphere.bin"),
                                              slope_sphere_count),
                                          slope_sphere_out, atol, rtol)});
        results.push_back({"vanleer_sphere_dq_dt",
                           compare_arrays(read_binary<double>(
                                              join_path(reference_dir, "output_vanleer_sphere_dq_dt.bin"),
                                              x_count),
                                          vanleer_sphere_dq_dt, atol, rtol)});
        if (fv_advection_kernels::cuda_backend::resident_boundary_enabled()) {
            // Halo-only residency: begin transfers only the two edge interior rows
            // per side ({0,1} and {ny-2,ny-1}) back to the host; the deep interior
            // stays resident on the device. Validate exactly those edge rows.
            const int edge_rows[] = {0, 1, active_ny - 2, active_ny - 1};
            std::vector<double> q1_edge, q1_edge_expected;
            for (int k = 0; k < p.nz; ++k) {
                for (int r : edge_rows) {
                    const std::size_t base =
                        (static_cast<std::size_t>(k) * active_ny + r) * p.nx;
                    for (int i = 0; i < p.nx; ++i) {
                        q1_edge.push_back(resident_q1[base + i]);
                        q1_edge_expected.push_back(resident_q1_expected[base + i]);
                    }
                }
            }
            results.push_back({"resident_q1_edges",
                               compare_arrays(q1_edge_expected, q1_edge, atol, rtol)});
            results.push_back({"resident_combined_dq_dt",
                               compare_arrays(resident_dq_dt_expected,
                                              resident_dq_dt, atol, rtol)});
        }

        bool overall_pass = true;
        for (const auto& item : results) {
            print_result(item.first, item.second);
            overall_pass = overall_pass && item.second.pass;
        }
        write_json_report(report_path, results, atol, rtol);
        std::cout << "Wrote JSON report: " << report_path << "\n";
        std::cout << "overall status: " << (overall_pass ? "PASS" : "FAIL")
                  << "\n";
        return overall_pass ? 0 : 1;
    } catch (const std::exception& exc) {
        std::cerr << "error: " << exc.what() << "\n";
        return 1;
    }
}
