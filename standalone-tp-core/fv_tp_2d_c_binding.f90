! Thin Fortran wrapper exposing fv_tp_2d with C linkage for C/C++ test code.
! It builds the grid-bounds and grid-struct derived types from scalar args
! (uniform grid: dxa=dya=area=1 via the stub constructor), then calls
! fv_tp_2d for the non-mass / no-divergence-damping path (optional mass/damp
! arguments omitted). Scalars are passed by value; arrays are explicit-shape
! so their layout is fixed by n (ng=3 halo), matching what C++ allocates.
subroutine fv_tp_2d_c(q, crx, cry, xfx, yfx, ra_x, ra_y, fx, fy, &
                      n, npx, npy, hord, lim_fac, nested_int, grid_type) &
    bind(C, name='fv_tp_2d_c')

  use iso_c_binding, only: c_int, c_float
  use fv_arrays_mod, only: fv_grid_bounds_type, fv_grid_type
  use tp_core_mod,   only: fv_tp_2d

  implicit none

  integer(c_int), intent(in), value :: n, npx, npy, hord
  integer(c_int), intent(in), value :: nested_int, grid_type
  real(c_float),  intent(in), value :: lim_fac

  ! Adjustable-shape arrays (ng = 3), matching fv_tp_2d's bounds with is=js=1.
  real(c_float), intent(inout) :: q   (1-3:n+3, 1-3:n+3)
  real(c_float), intent(in)    :: crx (1:n+1,   1-3:n+3)
  real(c_float), intent(in)    :: cry (1-3:n+3, 1:n+1)
  real(c_float), intent(in)    :: xfx (1:n+1,   1-3:n+3)
  real(c_float), intent(in)    :: yfx (1-3:n+3, 1:n+1)
  real(c_float), intent(in)    :: ra_x(1:n,     1-3:n+3)
  real(c_float), intent(in)    :: ra_y(1-3:n+3, 1:n)
  real(c_float), intent(out)   :: fx  (1:n+1,   1:n)
  real(c_float), intent(out)   :: fy  (1:n,     1:n+1)

  type(fv_grid_bounds_type) :: bd
  type(fv_grid_type) :: gridstruct
  logical :: nested

  nested = (nested_int /= 0)
  bd = fv_grid_bounds_type(n)
  gridstruct = fv_grid_type(bd, npx, npy, nested, grid_type)

  call fv_tp_2d(q, crx, cry, npx, npy, hord, fx, fy, xfx, yfx, &
                gridstruct, bd, ra_x, ra_y, lim_fac)

end subroutine fv_tp_2d_c
