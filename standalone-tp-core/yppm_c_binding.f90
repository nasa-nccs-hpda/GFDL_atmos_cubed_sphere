! Thin Fortran wrapper that exposes yppm with C linkage so it can be
! called from C or C++ test code.  All scalar arguments are passed by
! value; array arguments are passed as explicit-shape pointers whose
! memory layout matches what C++ allocates (Fortran column-major order,
! first element at the lower-bound corner of each array).
!
! Fortran logical is not C-interoperable, so the caller passes
! nested_int (0 = false, non-zero = true) and the wrapper converts.
!
subroutine yppm_c(flux, q, cry, jord, ifirst, ilast, isd, ied, &
                  js, je, jsd, jed, npx, npy, dya, nested_int, &
                  grid_type, lim_fac) &
    bind(C, name='yppm_c')

  use iso_c_binding, only: c_int, c_float
  use tp_core_mod,   only: yppm

  implicit none

  integer(c_int), intent(in), value :: jord
  integer(c_int), intent(in), value :: ifirst, ilast, isd, ied
  integer(c_int), intent(in), value :: js, je, jsd, jed
  integer(c_int), intent(in), value :: npx, npy
  integer(c_int), intent(in), value :: nested_int, grid_type
  real(c_float),  intent(in), value :: lim_fac

  ! Arrays: explicit-shape so memory layout is determined by the
  ! scalar bounds above.  C++ passes pointers to the first element
  ! of each array (the lower-bound corner in Fortran index space).
  real(c_float), intent(out) :: flux(ifirst:ilast, js:je+1)
  real(c_float), intent(in)  :: q(ifirst:ilast, jsd:jed)
  real(c_float), intent(in)  :: cry(isd:ied, js:je+1)
  real(c_float), intent(in)  :: dya(isd:ied, jsd:jed)

  logical :: nested

  nested = (nested_int /= 0)

  call yppm(flux, q, cry, jord, ifirst, ilast, isd, ied, &
            js, je, jsd, jed, npx, npy, dya, nested, grid_type, lim_fac)

end subroutine yppm_c
