#include "semi_y_3d.hpp"

#include <cerrno>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <sys/types.h>
#include <vector>

struct Params {
    int nx;
    int js;
    int je;
    int nz;
    int qx_jlo;
    int qx_jhi;
    double dt;
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

int main(int argc, char** argv) {
    if (argc != 3) {
        std::cerr << "usage: " << argv[0]
                  << " <baseline_dir> <candidate_output_dir>\n";
        return 2;
    }

    try {
        const std::string baseline_dir(argv[1]);
        const std::string out_dir(argv[2]);
        const std::string input_dir = join_path(baseline_dir, "inputs");
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
        std::vector<double> dq(va_count, -999.0);

        fv_advection::semi_y_3d(
            p.nx, p.js, p.je, p.nz, p.dt, va.data(), qx.data(), dyy.data(),
            dq.data());

        const std::string output_path = join_path(out_dir, "output_dq_cpp.bin");
        write_binary(output_path, dq);

        std::cout << "semi_y_3d C++ candidate complete.\n";
        std::cout << "dims nx/js/je/nz=" << p.nx << " " << p.js << " "
                  << p.je << " " << p.nz << " qx_jlo=" << p.qx_jlo
                  << " qx_jhi=" << p.qx_jhi << " dt=" << p.dt << "\n";
        std::cout << "wrote " << output_path << "\n";
    } catch (const std::exception& exc) {
        std::cerr << "error: " << exc.what() << "\n";
        return 1;
    }

    return 0;
}
