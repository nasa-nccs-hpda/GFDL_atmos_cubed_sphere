! Thin Fortran wrapper that exposes xppm with C linkage so it can be
! called from C or C++ test code.  All scalar arguments are passed by
! value; array arguments are passed as explicit-shape pointers whose
! memory layout matches what C++ allocates (Fortran column-major order,
! first element at the lower-bound corner of each array).
!
! Fortran logical is not C-interoperable, so the caller passes
! nested_int (0 = false, non-zero = true) and the wrapper converts.
!
subroutine xppm_c(flux, q, c, iord, is, ie, isd, ied, &
                  jfirst, jlast, jsd, jed, npx, npy, dxa, nested_int, &
                  grid_type, lim_fac) &
    bind(C, name='xppm_c')

  use iso_c_binding, only: c_int, c_float
  use tp_core_mod,   only: xppm

  implicit none

  integer(c_int), intent(in), value :: iord
  integer(c_int), intent(in), value :: is, ie, isd, ied
  integer(c_int), intent(in), value :: jfirst, jlast, jsd, jed
  integer(c_int), intent(in), value :: npx, npy
  integer(c_int), intent(in), value :: nested_int, grid_type
  real(c_float),  intent(in), value :: lim_fac

  ! Arrays: explicit-shape so memory layout is determined by the
  ! scalar bounds above.  C++ passes pointers to the first element
  ! of each array (the lower-bound corner in Fortran index space).
  real(c_float), intent(out) :: flux(is:ie+1, jfirst:jlast)
  real(c_float), intent(in)  :: q(isd:ied, jfirst:jlast)
  real(c_float), intent(in)  :: c(is:ie+1, jfirst:jlast)
  real(c_float), intent(in)  :: dxa(isd:ied, jsd:jed)

  logical :: nested

  nested = (nested_int /= 0)

  call xppm(flux, q, c, iord, is, ie, isd, ied, &
            jfirst, jlast, jsd, jed, npx, npy, dxa, nested, grid_type, lim_fac)

end subroutine xppm_c
