program test_hs_forcing_integration
  !! Synthetic-grid test for hs_forcing_driver_c integration
  use, intrinsic :: iso_c_binding, only: c_double, c_int
  use hs_forcing_c_interface
  implicit none

  integer, parameter :: nlon = 4, nlat = 3, nlev = 5
  real(c_double), parameter :: dt = 600.d0  ! 10 minutes in seconds
  integer :: k, i, j, idx
  integer :: ierr

  ! Synthetic grid arrays
  real(c_double) :: lon(nlon), lat(nlat)
  real(c_double) :: ps(nlon, nlat)
  real(c_double) :: p_full(nlon, nlat, nlev)
  real(c_double) :: u(nlon, nlat, nlev), v(nlon, nlat, nlev)
  real(c_double) :: t(nlon, nlat, nlev)
  real(c_double) :: udt(nlon, nlat, nlev), vdt(nlon, nlat, nlev)
  real(c_double) :: tdt(nlon, nlat, nlev), teq(nlon, nlat, nlev)

  ! Create synthetic grid
  print *, "=== Held-Suarez Forcing Integration Test ==="
  print *, "Grid dimensions: nlon=", nlon, ", nlat=", nlat, ", nlev=", nlev
  print *, "Timestep: dt=", dt, " seconds"
  print *, ""

  ! Longitude: uniform spacing 0 to 2*pi
  do i = 1, nlon
    lon(i) = (i - 1) * (2.d0 * 3.14159265358979323846d0) / dble(nlon)
  end do

  ! Latitude: uniform spacing -pi/2 to pi/2
  do j = 1, nlat
    lat(j) = -1.57079632679489661923d0 + (j - 1) * 3.14159265358979323846d0 / dble(nlat - 1)
  end do

  ! Surface pressure: 101325 Pa
  ps(:, :) = 101325.d0

  ! Pressure at full levels: uniform distribution
  do k = 1, nlev
    p_full(:, :, k) = ps(:, :) * (1.d0 - dble(k - 1) / dble(nlev))
  end do

  ! Synthetic wind field: small perturbations
  do k = 1, nlev
    do j = 1, nlat
      do i = 1, nlon
        u(i, j, k) = 0.1d0 * sin(lon(i)) * cos(lat(j))
        v(i, j, k) = 0.05d0 * cos(lon(i))
      end do
    end do
  end do

  ! Synthetic temperature: decreases with height
  do k = 1, nlev
    do j = 1, nlat
      do i = 1, nlon
        t(i, j, k) = 288.d0 - 6.5d0 * dble(k - 1) * 1000.d0 / dble(nlev)
      end do
    end do
  end do

  ! Initialize tendencies to zero
  udt = 0.d0
  vdt = 0.d0
  tdt = 0.d0
  teq = 0.d0

  print *, "Input field ranges:"
  print *, "  u: [", minval(u), ", ", maxval(u), "] m/s"
  print *, "  v: [", minval(v), ", ", maxval(v), "] m/s"
  print *, "  t: [", minval(t), ", ", maxval(t), "] K"
  print *, "  ps: [", minval(ps), ", ", maxval(ps), "] Pa"
  print *, ""

  ! Call forcing driver
  print *, "Calling hs_forcing_driver_c_wrapper..."
  call hs_forcing_driver_c_wrapper(nlon, nlat, nlev, dt, &
      lon, lat, ps, p_full, u, v, t, &
      udt, vdt, tdt, teq, ierr)

  print *, "Return code: ", ierr
  print *, ""

  if (ierr /= 0) then
    print *, "ERROR: hs_forcing_driver_c_wrapper returned error code", ierr
    stop 1
  end if

  ! Verify outputs
  print *, "Output tendency ranges:"
  print *, "  udt: [", minval(udt), ", ", maxval(udt), "] m/s^2"
  print *, "  vdt: [", minval(vdt), ", ", maxval(vdt), "] m/s^2"
  print *, "  tdt: [", minval(tdt), ", ", maxval(tdt), "] K/s"
  print *, "  teq: [", minval(teq), ", ", maxval(teq), "] K"
  print *, ""

  ! Check for NaN (basic sanity check)
  if (any(udt /= udt) .or. any(vdt /= vdt) .or. any(tdt /= tdt) .or. any(teq /= teq)) then
    print *, "ERROR: NaN detected in output arrays"
    stop 1
  end if

  print *, "=== TEST PASSED ==="
  stop 0

end program test_hs_forcing_integration
