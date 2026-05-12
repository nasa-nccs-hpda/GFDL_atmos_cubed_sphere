#include <cmath>
#include <iostream>
#include <vector>

extern "C" void yppm_c_api(float* flux, const float* q, const float* c, int jord,
                           int ifirst, int ilast, int isd, int ied,
                           int js, int je, int jsd, int jed,
                           int npx, int npy, const float* dya,
                           bool nested, int grid_type, float lim_fac);

namespace {

int idx_2d(const int i, const int j, const int i_lo, const int i_hi, const int j_lo) {
  const int ni = i_hi - i_lo + 1;
  return (i - i_lo) + ni * (j - j_lo);
}

bool assert_constant_field_flux(const int jord,
                                const std::vector<float>& q,
                                const std::vector<float>& c,
                                const std::vector<float>& dya,
                                std::vector<float>& flux,
                                const float tol,
                                const float constant_field,
                                const int ifirst, const int ilast,
                                const int isd, const int ied,
                                const int js, const int je,
                                const int jsd, const int jed,
                                const int npx, const int npy,
                                const bool nested,
                                const int grid_type,
                                const float lim_fac) {
  yppm_c_api(flux.data(), q.data(), c.data(), jord, ifirst, ilast, isd, ied, js, je, jsd, jed, npx, npy,
             dya.data(), nested, grid_type, lim_fac);

  float max_err = 0.0f;
  for (int j = js; j <= je + 1; ++j) {
    for (int i = ifirst; i <= ilast; ++i) {
      const float err = std::fabs(flux[idx_2d(i, j, ifirst, ilast, js)] - constant_field);
      if (err > max_err) {
        max_err = err;
      }
    }
  }
  if (max_err > tol) {
    std::cerr << "FAIL: yppm constant-field check failed for jord=" << jord
              << " max_err=" << max_err << '\n';
    return false;
  }
  return true;
}

}  // namespace

int main() {
  constexpr int n = 8;
  constexpr int ng = 3;
  constexpr int is = 1;
  constexpr int ie = n;
  constexpr int js = 1;
  constexpr int je = n;
  constexpr int isd = is - ng;
  constexpr int ied = ie + ng;
  constexpr int jsd = js - ng;
  constexpr int jed = je + ng;
  constexpr int ifirst = is;
  constexpr int ilast = ie;
  constexpr int npx = n + 1;
  constexpr int npy = n + 1;
  constexpr bool nested = true;
  constexpr int grid_type = 0;
  constexpr float lim_fac = 1.0f;
  constexpr float tolerance = 1.0e-6f;
  constexpr float constant_field = 2.5f;

  std::vector<float> q((ilast - ifirst + 1) * (jed - jsd + 1), constant_field);
  std::vector<float> c((ied - isd + 1) * (je - js + 2), 0.0f);
  std::vector<float> dya((ied - isd + 1) * (jed - jsd + 1), 1.0f);
  std::vector<float> flux((ilast - ifirst + 1) * (je - js + 2), 0.0f);

  for (int j = js; j <= je + 1; ++j) {
    for (int i = isd; i <= ied; ++i) {
      c[idx_2d(i, j, isd, ied, js)] = ((i + j) % 2 == 0) ? 0.25f : -0.35f;
    }
  }

  const bool pass5 = assert_constant_field_flux(5, q, c, dya, flux, tolerance, constant_field,
                                                 ifirst, ilast, isd, ied, js, je, jsd, jed,
                                                 npx, npy, nested, grid_type, lim_fac);
  const bool pass8 = assert_constant_field_flux(8, q, c, dya, flux, tolerance, constant_field,
                                                 ifirst, ilast, isd, ied, js, je, jsd, jed,
                                                 npx, npy, nested, grid_type, lim_fac);

  if (!pass5 || !pass8) {
    return 1;
  }

  std::cout << "PASS: yppm constant-field invariance for jord=5 and jord=8\n";
  return 0;
}
