program yppm_unit_test

  use tp_core_mod, only: yppm
  use fv_mp_mod, only: ng

  implicit none

  integer, parameter :: n = 8
  integer :: is, ie, isd, ied
  integer :: js, je, jsd, jed
  integer :: ifirst, ilast
  integer :: npx, npy
  integer :: i, j
  real :: tolerance
  logical :: nested
  integer :: grid_type
  real :: lim_fac
  real, allocatable :: q(:, :)
  real, allocatable :: c(:, :)
  real, allocatable :: dya(:, :)
  real, allocatable :: flux(:, :)

  is = 1
  ie = n
  js = 1
  je = n
  isd = is - ng
  ied = ie + ng
  jsd = js - ng
  jed = je + ng
  ifirst = is
  ilast = ie
  npx = n + 1
  npy = n + 1
  nested = .true.
  grid_type = 0
  lim_fac = 1.0
  tolerance = 1.0e-6

  allocate(q(ifirst:ilast, jsd:jed), source=2.5)
  allocate(c(isd:ied, js:je+1))
  allocate(dya(isd:ied, jsd:jed), source=1.0)
  allocate(flux(ifirst:ilast, js:je+1))

  do j = js, je+1
    do i = isd, ied
      if (mod(i+j, 2) == 0) then
        c(i,j) = 0.25
      else
        c(i,j) = -0.35
      end if
    end do
  end do

  call assert_constant_field_flux_(5, q, c, dya, flux, tolerance, ifirst, ilast, isd, ied, js, je, jsd, jed, npx, npy, nested, grid_type, lim_fac)
  call assert_constant_field_flux_(8, q, c, dya, flux, tolerance, ifirst, ilast, isd, ied, js, je, jsd, jed, npx, npy, nested, grid_type, lim_fac)

  print *, 'PASS: yppm constant-field invariance for jord=5 and jord=8'

contains

  subroutine assert_constant_field_flux_(jord, q, c, dya, flux, tol, ifirst, ilast, isd, ied, js, je, jsd, jed, npx, npy, nested, grid_type, lim_fac)

    integer, intent(in) :: jord
    integer, intent(in) :: ifirst, ilast, isd, ied, js, je, jsd, jed, npx, npy, grid_type
    logical, intent(in) :: nested
    real, intent(in) :: tol, lim_fac
    real, intent(in) :: q(ifirst:ilast, jsd:jed)
    real, intent(in) :: c(isd:ied, js:je+1)
    real, intent(in) :: dya(isd:ied, jsd:jed)
    real, intent(inout) :: flux(ifirst:ilast, js:je+1)
    real :: max_err

    call yppm(flux, q, c, jord, ifirst, ilast, isd, ied, js, je, jsd, jed, npx, npy, dya, nested, grid_type, lim_fac)

    max_err = maxval(abs(flux - 2.5))
    if (max_err > tol) then
      print *, 'FAIL: yppm constant-field check failed for jord=', jord, ' max_err=', max_err
      error stop 1
    end if

  end subroutine assert_constant_field_flux_

end program yppm_unit_test
