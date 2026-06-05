#include <iostream>
#include <fstream>
#include <vector>
#include <cmath>
#include <string>
#include <filesystem>
#include "../include/held_suarez_c_api.h"

std::vector<double> read_binary_array(const std::string &path, size_t count) {
    std::vector<double> a(count);
    std::ifstream ifs(path, std::ios::binary);
    if (!ifs) { std::cerr << "Cannot open " << path << std::endl; return a; }
    ifs.read(reinterpret_cast<char*>(a.data()), count * sizeof(double));
    return a;
}

void write_binary_array(const std::string &path, const std::vector<double> &a) {
    std::ofstream ofs(path, std::ios::binary);
    if (!ofs) { std::cerr << "Cannot write " << path << std::endl; return; }
    ofs.write(reinterpret_cast<const char*>(a.data()), a.size() * sizeof(double));
}

int main(int argc, char** argv) {
    std::string data_dir = "../../../../tests/fortran_baseline/forcing_module/inputs/";
    std::string out_dir = "outputs/"; // relative to this folder
    if (argc > 1) data_dir = argv[1];
    if (argc > 2) out_dir = argv[2];

    std::filesystem::create_directories(out_dir);

    // Read params.bin first to get dims
    std::string params_file = data_dir + "params.bin";
    std::ifstream pfs(params_file, std::ios::binary);
    if (!pfs) { std::cerr << "Cannot open params: "<<params_file<<std::endl; return 1; }
    int32_t dims[3];
    pfs.read(reinterpret_cast<char*>(dims), 3*sizeof(int32_t));
    int nlon = dims[0], nlat = dims[1], nlev = dims[2];
    double t_zero, t_strat, delh, delv, eps;
    double P00, KAPPA, tka, tks, sigma_b;
    pfs.read(reinterpret_cast<char*>(&t_zero), sizeof(double));
    pfs.read(reinterpret_cast<char*>(&t_strat), sizeof(double));
    pfs.read(reinterpret_cast<char*>(&delh), sizeof(double));
    pfs.read(reinterpret_cast<char*>(&delv), sizeof(double));
    pfs.read(reinterpret_cast<char*>(&eps), sizeof(double));
    pfs.read(reinterpret_cast<char*>(&P00), sizeof(double));
    pfs.read(reinterpret_cast<char*>(&KAPPA), sizeof(double));
    pfs.read(reinterpret_cast<char*>(&tka), sizeof(double));
    pfs.read(reinterpret_cast<char*>(&tks), sizeof(double));
    pfs.read(reinterpret_cast<char*>(&sigma_b), sizeof(double));
    pfs.close();

    size_t size2 = size_t(nlon) * nlat;
    size_t size3 = size2 * nlev;

    auto lat = read_binary_array(data_dir + "input_lat.bin", size2);
    auto ps = read_binary_array(data_dir + "input_ps.bin", size2);
    auto p_full = read_binary_array(data_dir + "input_p_full.bin", size3);
    auto t = read_binary_array(data_dir + "input_t.bin", size3);
    auto u = read_binary_array(data_dir + "input_u.bin", size3);
    auto v = read_binary_array(data_dir + "input_v.bin", size3);

    std::vector<double> udt(size3, 0.0), vdt(size3, 0.0), tdt(size3, 0.0), teq(size3, 0.0);

    // call rayleigh
    int rc = hs_rayleigh_damping_c(nlon, nlat, nlev,
                                   ps.data(), p_full.data(), u.data(), v.data(),
                                   /*vkf*/ 1.0/86400.0, sigma_b,
                                   udt.data(), vdt.data(), nullptr);
    if (rc != HS_SUCCESS) { std::cerr << "rayleigh returned "<<rc<<std::endl; }

    // call newtonian
    rc = hs_newtonian_damping_c(nlon, nlat, nlev,
                                lat.data(), ps.data(), p_full.data(), t.data(),
                                t_zero, t_strat, delh, delv, eps, P00, KAPPA,
                                tka, tks, sigma_b,
                                tdt.data(), teq.data(), nullptr);
    if (rc != HS_SUCCESS) { std::cerr << "newtonian returned "<<rc<<std::endl; }

    // write outputs into out_dir
    write_binary_array(out_dir + "output_udt.bin", udt);
    write_binary_array(out_dir + "output_vdt.bin", vdt);
    write_binary_array(out_dir + "output_tdt.bin", tdt);
    write_binary_array(out_dir + "output_teq.bin", teq);

    std::cout << "Candidate outputs written to "<< out_dir << std::endl;
    return 0;
}
