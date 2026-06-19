#include "../../../cpp/fv_advection/semi_y_3d/include/semi_y_3d.hpp"
#include "semi_y_3d_cuda.h"

#include <algorithm>
#include <cerrno>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <sys/types.h>
#include <vector>

namespace {

struct Params {
    int nx;
    int js;
    int je;
    int nz;
    int qx_jlo;
    int qx_jhi;
    double dt;
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

Params read_params(const std::string& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        throw std::runtime_error("could not open " + path);
    }

    std::int32_t ints[6];
    double dt = 0.0;
    in.read(reinterpret_cast<char*>(ints), sizeof(ints));
    in.read(reinterpret_cast<char*>(&dt), sizeof(dt));
    if (!in) {
        throw std::runtime_error("could not read params from " + path);
    }

    return Params{ints[0], ints[1], ints[2], ints[3], ints[4], ints[5], dt};
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
    result.pass = (result.mismatches == 0);
    return result;
}

void write_json_report(const std::string& path,
                       const std::string& baseline_path,
                       const std::string& cuda_path,
                       const CompareResult& fortran_cuda,
                       const CompareResult& cpu_cuda,
                       double atol,
                       double rtol) {
    std::ofstream out(path);
    if (!out) {
        throw std::runtime_error("could not write report " + path);
    }

    out << std::setprecision(17);
    out << "{\n";
    out << "  \"kernel\": \"semi_y_3d\",\n";
    out << "  \"backend\": \"cuda\",\n";
    out << "  \"reference\": \"" << baseline_path << "\",\n";
    out << "  \"candidate\": \"" << cuda_path << "\",\n";
    out << "  \"comparisons\": {\n";
    out << "    \"fortran_vs_cuda\": {\n";
    out << "      \"pass\": " << (fortran_cuda.pass ? "true" : "false")
        << ",\n";
    out << "      \"count\": " << fortran_cuda.count << ",\n";
    out << "      \"max_abs_error\": " << fortran_cuda.max_abs << ",\n";
    out << "      \"max_rel_error\": " << fortran_cuda.max_rel << ",\n";
    out << "      \"rmse\": " << fortran_cuda.rmse << ",\n";
    out << "      \"mismatches_above_tolerance\": "
        << fortran_cuda.mismatches << "\n";
    out << "    },\n";
    out << "    \"cpu_cpp_vs_cuda\": {\n";
    out << "      \"pass\": " << (cpu_cuda.pass ? "true" : "false")
        << ",\n";
    out << "      \"count\": " << cpu_cuda.count << ",\n";
    out << "      \"max_abs_error\": " << cpu_cuda.max_abs << ",\n";
    out << "      \"max_rel_error\": " << cpu_cuda.max_rel << ",\n";
    out << "      \"rmse\": " << cpu_cuda.rmse << ",\n";
    out << "      \"mismatches_above_tolerance\": " << cpu_cuda.mismatches
        << "\n";
    out << "    }\n";
    out << "  },\n";
    out << "  \"atol\": " << atol << ",\n";
    out << "  \"rtol\": " << rtol << ",\n";
    out << "  \"overall_pass\": "
        << ((fortran_cuda.pass && cpu_cuda.pass) ? "true" : "false")
        << "\n";
    out << "}\n";
}

void print_result(const std::string& name, const CompareResult& result,
                  double atol, double rtol) {
    std::cout << name << ": pass=" << (result.pass ? "true" : "false")
              << " count=" << result.count << " max_abs=" << std::scientific
              << std::setprecision(6) << result.max_abs
              << " max_rel=" << result.max_rel << " rmse=" << result.rmse
              << " mismatches=" << result.mismatches << " atol=" << atol
              << " rtol=" << rtol << "\n";
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
        const std::string baseline_output =
            join_path(join_path(baseline_dir, "outputs"), "output_dq.bin");
        const std::string cuda_output = join_path(out_dir, "output_dq_cuda.bin");
        make_directory(out_dir);

        const Params p = read_params(join_path(input_dir, "params.bin"));
        const int ny = p.je - p.js + 1;
        const int qx_ny = p.qx_jhi - p.qx_jlo + 1;

        if (p.qx_jlo != p.js - 2 || p.qx_jhi != p.je + 2) {
            throw std::runtime_error("unexpected qx y bounds in fixture");
        }

        const std::size_t dyy_count = static_cast<std::size_t>(ny + 1);
        const std::size_t va_count =
            static_cast<std::size_t>(p.nx) * static_cast<std::size_t>(ny) *
            static_cast<std::size_t>(p.nz);
        const std::size_t qx_count =
            static_cast<std::size_t>(p.nx) * static_cast<std::size_t>(qx_ny) *
            static_cast<std::size_t>(p.nz);

        const std::vector<double> dyy =
            read_binary<double>(join_path(input_dir, "input_dyy.bin"),
                                dyy_count);
        const std::vector<double> va =
            read_binary<double>(join_path(input_dir, "input_va.bin"),
                                va_count);
        const std::vector<double> qx =
            read_binary<double>(join_path(input_dir, "input_qx.bin"),
                                qx_count);
        const std::vector<double> dq_fortran =
            read_binary<double>(baseline_output, va_count);

        std::vector<double> dq_cpu(va_count, -999.0);
        std::vector<double> dq_cuda(va_count, -999.0);

        fv_advection::semi_y_3d(p.nx, p.js, p.je, p.nz, p.dt, va.data(),
                                qx.data(), dyy.data(), dq_cpu.data());
        const int status = fv_advection::cuda_backend::semi_y_3d_cuda(
            p.nx, p.js, p.je, p.nz, p.dt, va.data(), qx.data(), dyy.data(),
            dq_cuda.data());
        if (status != 0) {
            std::cerr << "semi_y_3d CUDA backend failed with status " << status
                      << "\n";
            return 3;
        }

        write_binary(cuda_output, dq_cuda);

        const CompareResult fortran_cuda =
            compare_arrays(dq_fortran, dq_cuda, atol, rtol);
        const CompareResult cpu_cuda =
            compare_arrays(dq_cpu, dq_cuda, atol, rtol);

        print_result("fortran_vs_cuda", fortran_cuda, atol, rtol);
        print_result("cpu_cpp_vs_cuda", cpu_cuda, atol, rtol);
        write_json_report(report_path, baseline_output, cuda_output,
                          fortran_cuda, cpu_cuda, atol, rtol);

        const bool ok = fortran_cuda.pass && cpu_cuda.pass;
        std::cout << "semi_y_3d CUDA validation status: "
                  << (ok ? "PASS" : "FAIL") << "\n";
        return ok ? 0 : 4;
    } catch (const std::exception& exc) {
        std::cerr << "semi_y_3d CUDA validation error: " << exc.what()
                  << "\n";
        return 1;
    }
}
