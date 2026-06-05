!-----------------------------------------------------------------------
! Test Harness for Newtonian Damping
!
! Generates synthetic test data, calls the kernel, and writes
! input/output arrays to binary files for validation against C++ port.
!-----------------------------------------------------------------------

program test_newtonian_damping

  use newtonian_damping_mod, only: newtonian_damping

  implicit none

  ! Grid dimensions (small for testing)
  integer, parameter :: nlon = 8
  integer, parameter :: nlat = 4
  integer, parameter :: nlev = 5

  ! Physical constants
  real(8), parameter :: PI = 3.14159265358979323846d0
  real(8), parameter :: SECONDS_PER_DAY = 86400.0d0

  ! Held-Suarez parameters (namelist defaults)
  real(8), parameter :: t_zero = 315.0d0    ! Equatorial equilibrium temperature (K)
  real(8), parameter :: t_strat = 200.0d0   ! Stratospheric temperature (K)
  real(8), parameter :: delh = 60.0d0       ! Equator-pole temperature difference (K)
  real(8), parameter :: delv = 10.0d0       ! Static stability parameter (K)
  real(8), parameter :: eps = 0.0d0         ! Hemispheric asymmetry (K)
  real(8), parameter :: P00 = 1.0d5         ! Reference pressure (Pa)
  real(8), parameter :: KAPPA = 2.0d0/7.0d0 ! R/cp
  real(8), parameter :: sigma_b = 0.7d0     ! Boundary layer top

  ! Damping timescales (days)
  real(8), parameter :: ka_days = 40.0d0    ! Atmospheric damping timescale
  real(8), parameter :: ks_days = 4.0d0     ! Surface damping timescale

  ! Derived parameters
  real(8) :: tka, tks  ! Damping rates (1/s)

  ! Arrays
  real(8) :: lat(nlon, nlat)
  real(8) :: ps(nlon, nlat)
  real(8) :: p_full(nlon, nlat, nlev)
  real(8) :: t(nlon, nlat, nlev)
  real(8) :: tdt(nlon, nlat, nlev)
  real(8) :: teq(nlon, nlat, nlev)

  ! Sigma levels (top to bottom)
  real(8) :: sigma_levels(nlev)

  ! Latitude values (radians)
  real(8) :: lat_values(nlat)

  ! Loop indices
  integer :: i, j, k

  !-----------------------------------------------------------------------
  ! Initialize parameters
  !-----------------------------------------------------------------------

  tka = 1.0d0 / (SECONDS_PER_DAY * ka_days)
  tks = 1.0d0 / (SECONDS_PER_DAY * ks_days)

  ! Sigma levels spanning above and below boundary layer
  ! sigma_b = 0.7, so levels 1-2 are above, levels 3-5 are in boundary layer
  sigma_levels = (/ 0.2d0, 0.5d0, 0.75d0, 0.9d0, 1.0d0 /)

  ! Latitude values from equator to near-pole (radians)
  ! -45, -15, 15, 45 degrees
  lat_values = (/ -PI/4.0d0, -PI/12.0d0, PI/12.0d0, PI/4.0d0 /)

  write(*,*) '======================================'
  write(*,*) 'Newtonian Damping Test Harness'
  write(*,*) '======================================'
  write(*,*) ''
  write(*,*) 'Grid dimensions:'
  write(*,*) '  nlon  =', nlon
  write(*,*) '  nlat  =', nlat
  write(*,*) '  nlev  =', nlev
  write(*,*) ''
  write(*,*) 'Held-Suarez parameters:'
  write(*,*) '  t_zero  (K)     =', t_zero
  write(*,*) '  t_strat (K)     =', t_strat
  write(*,*) '  delh    (K)     =', delh
  write(*,*) '  delv    (K)     =', delv
  write(*,*) '  eps     (K)     =', eps
  write(*,*) '  P00     (Pa)    =', P00
  write(*,*) '  KAPPA           =', KAPPA
  write(*,*) '  sigma_b         =', sigma_b
  write(*,*) ''
  write(*,*) 'Damping parameters:'
  write(*,*) '  ka (days)       =', ka_days
  write(*,*) '  ks (days)       =', ks_days
  write(*,*) '  tka (1/s)       =', tka
  write(*,*) '  tks (1/s)       =', tks
  write(*,*) ''
  write(*,*) 'Sigma levels:', sigma_levels
  write(*,*) 'Lat values (deg):', lat_values * 180.0d0 / PI
  write(*,*) ''

  !-----------------------------------------------------------------------
  ! Generate synthetic test data
  !-----------------------------------------------------------------------

  ! Latitude array: constant along longitude, varies along latitude
  do j = 1, nlat
    do i = 1, nlon
      lat(i,j) = lat_values(j)
    enddo
  enddo

  ! Surface pressure: slight variation around P00
  do j = 1, nlat
    do i = 1, nlon
      ps(i,j) = P00 * (1.0d0 + 0.01d0 * sin(2.0d0 * PI * real(i-1,8)/real(nlon,8)))
    enddo
  enddo

  ! Pressure at full levels: p_full = sigma * ps
  do k = 1, nlev
    do j = 1, nlat
      do i = 1, nlon
        p_full(i,j,k) = sigma_levels(k) * ps(i,j)
      enddo
    enddo
  enddo

  ! Temperature: realistic tropospheric profile with perturbation
  ! T decreases with height, varies with latitude
  do k = 1, nlev
    do j = 1, nlat
      do i = 1, nlon
        ! Base temperature: warm at equator, cold at poles
        ! Decreases with height (lower sigma = higher altitude = colder)
        t(i,j,k) = 250.0d0 + 40.0d0 * cos(lat(i,j)) * sigma_levels(k) &
                 + 10.0d0 * sin(2.0d0 * PI * real(i-1,8)/real(nlon,8))
      enddo
    enddo
  enddo

  !-----------------------------------------------------------------------
  ! Call the kernel
  !-----------------------------------------------------------------------

  write(*,*) 'Calling newtonian_damping...'

  call newtonian_damping(nlon, nlat, nlev, lat, ps, p_full, t, &
                          t_zero, t_strat, delh, delv, eps, &
                          P00, KAPPA, tka, tks, sigma_b, &
                          tdt, teq)

  write(*,*) 'Done.'
  write(*,*) ''

  !-----------------------------------------------------------------------
  ! Print summary statistics
  !-----------------------------------------------------------------------

  write(*,*) 'Results summary:'
  write(*,*) '  teq range: [', minval(teq), ',', maxval(teq), '] K'
  write(*,*) '  tdt range: [', minval(tdt), ',', maxval(tdt), '] K/s'
  write(*,*) ''

  ! Check expected behavior by level
  write(*,*) 'Per-level statistics:'
  do k = 1, nlev
    write(*,'(A,I2,A,F5.2,A,F7.2,A,F7.2,A,ES12.4,A,ES12.4)') &
      '  Level ', k, ' (sigma=', sigma_levels(k), &
      '): teq=[', minval(teq(:,:,k)), ',', maxval(teq(:,:,k)), &
      '], max|tdt|=', maxval(abs(tdt(:,:,k)))
  enddo
  write(*,*) ''

  ! Check latitude dependence at surface
  write(*,*) 'Latitude dependence at surface (k=5, sigma=1.0):'
  do j = 1, nlat
    write(*,'(A,F7.2,A,F7.2,A,F7.2,A,ES12.4)') &
      '  lat=', lat_values(j)*180.0d0/PI, ' deg: teq=', teq(1,j,nlev), &
      ' K, t=', t(1,j,nlev), ' K, tdt=', tdt(1,j,nlev)
  enddo
  write(*,*) ''

  !-----------------------------------------------------------------------
  ! Write arrays to binary files
  !-----------------------------------------------------------------------

  write(*,*) 'Writing input/output arrays to files...'

  ! Write inputs
  call write_array_2d('input_lat.bin', lat, nlon, nlat)
  call write_array_2d('input_ps.bin', ps, nlon, nlat)
  call write_array_3d('input_p_full.bin', p_full, nlon, nlat, nlev)
  call write_array_3d('input_t.bin', t, nlon, nlat, nlev)

  ! Write parameters
  call write_params('params.bin', nlon, nlat, nlev, &
                    t_zero, t_strat, delh, delv, eps, &
                    P00, KAPPA, tka, tks, sigma_b)

  ! Write outputs
  call write_array_3d('output_tdt.bin', tdt, nlon, nlat, nlev)
  call write_array_3d('output_teq.bin', teq, nlon, nlat, nlev)

  write(*,*) 'Done. Files written:'
  write(*,*) '  input_lat.bin, input_ps.bin, input_p_full.bin, input_t.bin'
  write(*,*) '  params.bin'
  write(*,*) '  output_tdt.bin, output_teq.bin'
  write(*,*) ''
  write(*,*) 'Test harness completed successfully.'

contains

  !-----------------------------------------------------------------------
  subroutine write_array_2d(filename, arr, n1, n2)
    character(len=*), intent(in) :: filename
    integer, intent(in) :: n1, n2
    real(8), intent(in) :: arr(n1, n2)
    integer :: unit_num

    unit_num = 20
    open(unit=unit_num, file=filename, form='unformatted', access='stream', status='replace')
    write(unit_num) arr
    close(unit_num)
  end subroutine write_array_2d

  !-----------------------------------------------------------------------
  subroutine write_array_3d(filename, arr, n1, n2, n3)
    character(len=*), intent(in) :: filename
    integer, intent(in) :: n1, n2, n3
    real(8), intent(in) :: arr(n1, n2, n3)
    integer :: unit_num

    unit_num = 20
    open(unit=unit_num, file=filename, form='unformatted', access='stream', status='replace')
    write(unit_num) arr
    close(unit_num)
  end subroutine write_array_3d

  !-----------------------------------------------------------------------
  subroutine write_params(filename, n1, n2, n3, &
                          p_t_zero, p_t_strat, p_delh, p_delv, p_eps, &
                          p_P00, p_KAPPA, p_tka, p_tks, p_sigma_b)
    character(len=*), intent(in) :: filename
    integer, intent(in) :: n1, n2, n3
    real(8), intent(in) :: p_t_zero, p_t_strat, p_delh, p_delv, p_eps
    real(8), intent(in) :: p_P00, p_KAPPA, p_tka, p_tks, p_sigma_b
    integer :: unit_num

    unit_num = 20
    open(unit=unit_num, file=filename, form='unformatted', access='stream', status='replace')
    write(unit_num) n1, n2, n3
    write(unit_num) p_t_zero, p_t_strat, p_delh, p_delv, p_eps
    write(unit_num) p_P00, p_KAPPA, p_tka, p_tks, p_sigma_b
    close(unit_num)
  end subroutine write_params

end program test_newtonian_damping
