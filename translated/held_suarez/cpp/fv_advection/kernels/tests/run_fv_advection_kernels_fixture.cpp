#include "fv_advection_kernels.hpp"

#include <cerrno>
#include <cstring>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <sys/types.h>
#include <vector>

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

        const Params p = read_params(join_path(input_dir, "params.txt"));
        const int active_ny = p.je - p.js + 1;
        if (active_ny != p.ny - 3) {
            throw std::runtime_error("fixture expected ny = active_ny + 3");
        }

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

        std::vector<int> ii(x_count, 0);
        std::vector<double> semi_x_dq(x_count, -999.0);
        std::vector<double> slope_x_out(x_count, -999.0);
        std::vector<double> integer_flux_out(x_count, -999.0);
        std::vector<double> vanleer_x_dq_dt(x_count, 0.013);
        std::vector<double> slope_sphere_out(slope_sphere_count, -999.0);
        std::vector<double> vanleer_sphere_dq_dt(x_count, -0.021);

        fv_advection_kernels::find_cell_x(
            p.nx, active_ny, p.nz, b_x.data(), ii.data());
        fv_advection_kernels::semi_x_3d(
            p.nx, active_ny, p.nz, p.dt, p.dx, c.data(), ua.data(), q_x.data(),
            semi_x_dq.data());
        fv_advection_kernels::slope_x(
            p.nx, active_ny, p.nz, p.monotone, q_x.data(), slope_x_out.data());
        fv_advection_kernels::integer_flux_x(
            p.nx, active_ny, p.nz, b_x.data(), q_x.data(),
            integer_flux_out.data());
        fv_advection_kernels::vanleer_x_3d(
            p.nx, active_ny, p.nz, p.dt, p.dx, c.data(), p.monotone, uc.data(),
            q_x.data(), vanleer_x_dq_dt.data());
        fv_advection_kernels::slope_sphere(
            p.nx, active_ny + 2, p.nz, p.monotone, dy_plus.data(),
            dy_minus.data(), q_sphere.data(), slope_sphere_out.data());
        fv_advection_kernels::vanleer_sphere_3d(
            p.nx, active_ny, p.nz, p.dt, p.monotone, p.js == 1,
            p.je == p.ny, c.data(), cc.data(), dy.data(), dy_plus.data(), dy_minus.data(),
            vc.data(), q_sphere.data(), vanleer_sphere_dq_dt.data());

        write_binary(join_path(out_dir, "output_find_cell_x_ii_cpp.bin"), ii);
        write_binary(join_path(out_dir, "output_semi_x_dq_cpp.bin"), semi_x_dq);
        write_binary(join_path(out_dir, "output_slope_x_cpp.bin"), slope_x_out);
        write_binary(join_path(out_dir, "output_integer_flux_x_cpp.bin"),
                     integer_flux_out);
        write_binary(join_path(out_dir, "output_vanleer_x_dq_dt_cpp.bin"),
                     vanleer_x_dq_dt);
        write_binary(join_path(out_dir, "output_slope_sphere_cpp.bin"),
                     slope_sphere_out);
        write_binary(join_path(out_dir, "output_vanleer_sphere_dq_dt_cpp.bin"),
                     vanleer_sphere_dq_dt);

        std::cout << "fv_advection kernel C++ fixture complete.\n";
        std::cout << "dims nx/active_ny/nz=" << p.nx << " " << active_ny
                  << " " << p.nz << " dt=" << p.dt << "\n";
    } catch (const std::exception& exc) {
        std::cerr << "error: " << exc.what() << "\n";
        return 1;
    }

    return 0;
}
