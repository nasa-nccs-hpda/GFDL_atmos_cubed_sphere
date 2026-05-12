module yppm_c_api_mod

  use, intrinsic :: iso_c_binding, only: c_int, c_float, c_bool
  use tp_core_mod, only: yppm

  implicit none

contains

  subroutine yppm_c_api(flux, q, c, jord, ifirst, ilast, isd, ied, js, je, jsd, jed, npx, npy, dya, nested, grid_type, lim_fac) bind(C, name="yppm_c_api")

    real(c_float), intent(out), target :: flux(*)
    real(c_float), intent(in),  target :: q(*)
    real(c_float), intent(in),  target :: c(*)
    integer(c_int), value, intent(in) :: jord
    integer(c_int), value, intent(in) :: ifirst, ilast, isd, ied, js, je, jsd, jed, npx, npy
    real(c_float), intent(in),  target :: dya(*)
    logical(c_bool), value, intent(in) :: nested
    integer(c_int), value, intent(in) :: grid_type
    real(c_float), value, intent(in) :: lim_fac

    real(c_float), pointer :: flux2d(:, :)
    real(c_float), pointer :: q2d(:, :)
    real(c_float), pointer :: c2d(:, :)
    real(c_float), pointer :: dya2d(:, :)
    logical :: nested_f
    integer :: ni_flux, nj_flux, ni_q, nj_q, ni_c, nj_c, ni_dya, nj_dya

    ni_flux = ilast - ifirst + 1
    nj_flux = je - js + 2
    ni_q = ilast - ifirst + 1
    nj_q = jed - jsd + 1
    ni_c = ied - isd + 1
    nj_c = je - js + 2
    ni_dya = ied - isd + 1
    nj_dya = jed - jsd + 1

    flux2d(1:ni_flux, 1:nj_flux) => flux(1:ni_flux*nj_flux)
    q2d(1:ni_q, 1:nj_q) => q(1:ni_q*nj_q)
    c2d(1:ni_c, 1:nj_c) => c(1:ni_c*nj_c)
    dya2d(1:ni_dya, 1:nj_dya) => dya(1:ni_dya*nj_dya)
    nested_f = nested

    call yppm(flux2d, q2d, c2d, jord, ifirst, ilast, isd, ied, js, je, jsd, jed, npx, npy, dya2d, nested_f, grid_type, lim_fac)

  end subroutine yppm_c_api

end module yppm_c_api_mod
