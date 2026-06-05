!-----------------------------------------------------------------------
! Test Harness for Top-Down Newtonian Damping
!
! Generates synthetic test data, calls the kernel, and writes
! input/output arrays to binary files for validation against C++ port.
!-----------------------------------------------------------------------

program test_top_down_newtonian_damping

  use top_down_newtonian_damping_mod

  implicit none

  ! Grid dimensions
  integer, parameter :: nlon = 8
  integer, parameter :: nlat = 6
  integer, parameter :: nlev = 5

  ! Physical constants
  real(8), parameter :: PI = 3.14159265358979323846d0
  real(8), parameter :: SECONDS_PER_DAY = 86400.0d0
  real(8), parameter :: STEFAN = 5.670374419d-8  ! Stefan-Boltzmann constant
  real(8), parameter :: SOLAR_CONST = 1360.0d0   ! Solar constant W/m^2

  ! Orbital parameters (Earth-like)
  real(8), parameter :: orbital_period = 365.25d0  ! days
  real(8), parameter :: ecc = 0.0167d0             ! eccentricity
  real(8), parameter :: obliq = 23.44d0            ! obliquity (degrees)
  real(8), parameter :: peri_time = 0.25d0         ! perihelion fraction
  real(8), parameter :: smaxis = 1.496d11          ! semi-major axis (m)

  ! Thermal parameters
  real(8), parameter :: albedo = 0.3d0
  real(8), parameter :: lapse = 6.5d0              ! K/km
  real(8), parameter :: h_a = 2.0d0
  real(8), parameter :: tau_s = 5.0d0
  real(8), parameter :: heat_capacity = 4.2d6     ! J/m^3/K
  real(8), parameter :: ml_depth = 1.0d0          ! m

  ! Held-Suarez parameters
  real(8), parameter :: t_strat = 200.0d0         ! K
  real(8), parameter :: eps = 10.0d0              ! K (latitude variation)
  real(8), parameter :: sigma_b = 0.7d0
  real(8), parameter :: P00 = 1.0d5               ! Pa

  ! Timescales (converted to 1/s)
  real(8), parameter :: ka_days = 40.0d0
  real(8), parameter :: ks_days = 4.0d0
  real(8) :: tka, tks

  ! Time parameters
  integer, parameter :: current_time = 90 * 86400  ! 90 days in seconds (spring)
  real(8), parameter :: dt = 1200.0d0              ! 20 minute timestep

  ! Latitude values (degrees)
  real(8), parameter :: lat_degrees(nlat) = (/ -80.0d0, -48.0d0, -16.0d0, 16.0d0, 48.0d0, 80.0d0 /)

  ! Sigma levels (top to bottom)
  real(8), parameter :: sigma_levels(nlev) = (/ 0.1d0, 0.3d0, 0.5d0, 0.7d0, 0.9d0 /)

  ! Arrays
  real(8) :: lat(nlon, nlat)
  real(8) :: ps(nlon, nlat)
  real(8) :: p_full(nlon, nlat, nlev)
  real(8) :: zfull(nlon, nlat, nlev)
  real(8) :: t(nlon, nlat, nlev)
  real(8) :: tg_prev(nlon, nlat)
  real(8) :: tdt(nlon, nlat, nlev)
  real(8) :: teq(nlon, nlat, nlev)
  real(8) :: h_trop(nlon, nlat)
  real(8) :: tg_new(nlon, nlat)

  ! Loop indices
  integer :: i, j, k

  !-----------------------------------------------------------------------
  ! Initialize timescale parameters
  !-----------------------------------------------------------------------
  tka = 1.0d0 / (SECONDS_PER_DAY * ka_days)
  tks = 1.0d0 / (SECONDS_PER_DAY * ks_days)

  write(*,*) '======================================'
  write(*,*) 'Top-Down Newtonian Damping Test Harness'
  write(*,*) '======================================'
  write(*,*) ''
  write(*,*) 'Grid dimensions:'
  write(*,*) '  nlon  =', nlon
  write(*,*) '  nlat  =', nlat
  write(*,*) '  nlev  =', nlev
  write(*,*) ''
  write(*,*) 'Time parameters:'
  write(*,*) '  current_time =', current_time, 'seconds (', current_time/86400, 'days)'
  write(*,*) '  dt           =', dt, 'seconds'
  write(*,*) ''
  write(*,*) 'Orbital parameters:'
  write(*,*) '  orbital_period =', orbital_period, 'days'
  write(*,*) '  ecc            =', ecc
  write(*,*) '  obliq          =', obliq, 'degrees'
  write(*,*) ''
  write(*,*) 'Relaxation timescales:'
  write(*,*) '  tka (1/s) =', tka
  write(*,*) '  tks (1/s) =', tks
  write(*,*) ''

  !-----------------------------------------------------------------------
  ! Generate synthetic test data
  !-----------------------------------------------------------------------

  ! Latitude field (radians)
  do j = 1, nlat
    do i = 1, nlon
      lat(i,j) = lat_degrees(j) * PI / 180.0d0
    enddo
  enddo

  ! Surface pressure with slight variation
  do j = 1, nlat
    do i = 1, nlon
      ps(i,j) = P00 * (1.0d0 + 0.02d0 * sin(2.0d0 * PI * real(i-1)/real(nlon)))
    enddo
  enddo

  ! Pressure at full levels
  do k = 1, nlev
    do j = 1, nlat
      do i = 1, nlon
        p_full(i,j,k) = sigma_levels(k) * ps(i,j)
      enddo
    enddo
  enddo

  ! Height field (approximate scale height of 8km)
  do k = 1, nlev
    do j = 1, nlat
      do i = 1, nlon
        zfull(i,j,k) = -8000.0d0 * log(sigma_levels(k))  ! meters
      enddo
    enddo
  enddo

  ! Temperature field (simple profile)
  do k = 1, nlev
    do j = 1, nlat
      do i = 1, nlon
        ! Start with 288K at surface, decrease with height
        t(i,j,k) = 288.0d0 - 6.5d0 * zfull(i,j,k)/1000.0d0
        t(i,j,k) = max(t(i,j,k), 200.0d0)  ! Cap at tropopause
      enddo
    enddo
  enddo

  ! Previous ground temperature (uniform initial condition)
  tg_prev(:,:) = 280.0d0

  write(*,*) 'Input data generated:'
  write(*,*) '  lat range (deg): [', minval(lat)*180.0d0/PI, ',', maxval(lat)*180.0d0/PI, ']'
  write(*,*) '  ps range (Pa):   [', minval(ps), ',', maxval(ps), ']'
  write(*,*) '  zfull range (m): [', minval(zfull), ',', maxval(zfull), ']'
  write(*,*) '  t range (K):     [', minval(t), ',', maxval(t), ']'
  write(*,*) '  tg_prev (K):     ', tg_prev(1,1)
  write(*,*) ''

  !-----------------------------------------------------------------------
  ! Call the kernel (using hs_like stratosphere option)
  !-----------------------------------------------------------------------

  write(*,*) 'Calling top_down_newtonian_damping (strat_option=hs_like)...'

  call top_down_newtonian_damping(nlon, nlat, nlev, current_time, dt, &
       lat, ps, p_full, zfull, t, tg_prev, &
       SOLAR_CONST, STEFAN, PI, orbital_period, ecc, obliq, peri_time, &
       smaxis, albedo, lapse, h_a, tau_s, heat_capacity, ml_depth, &
       t_strat, eps, sigma_b, tka, tks, P00, STRAT_HS_LIKE, &
       tdt, teq, h_trop, tg_new)

  write(*,*) 'Done.'
  write(*,*) ''

  !-----------------------------------------------------------------------
  ! Print results
  !-----------------------------------------------------------------------

  write(*,*) 'Results summary:'
  write(*,*) '  h_trop range (km): [', minval(h_trop), ',', maxval(h_trop), ']'
  write(*,*) '  tg_new range (K):  [', minval(tg_new), ',', maxval(tg_new), ']'
  write(*,*) '  teq range (K):     [', minval(teq), ',', maxval(teq), ']'
  write(*,*) '  tdt range (K/s):   [', minval(tdt), ',', maxval(tdt), ']'
  write(*,*) ''

  write(*,*) 'Per-latitude tropopause height (km):'
  do j = 1, nlat
    write(*,'(A,F7.2,A,F8.3,A)') '  lat=', lat_degrees(j), ' deg: h_trop=', h_trop(1,j), ' km'
  enddo
  write(*,*) ''

  write(*,*) 'Per-level teq statistics:'
  do k = 1, nlev
    write(*,'(A,I2,A,F6.3,A,F8.2,A,F8.2,A)') '  Level ', k, ' (sigma=', sigma_levels(k), &
         '): teq range=[', minval(teq(:,:,k)), ',', maxval(teq(:,:,k)), '] K'
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
  call write_array_3d('input_zfull.bin', zfull, nlon, nlat, nlev)
  call write_array_3d('input_t.bin', t, nlon, nlat, nlev)
  call write_array_2d('input_tg_prev.bin', tg_prev, nlon, nlat)

  ! Write parameters
  call write_params('params.bin', nlon, nlat, nlev, current_time, dt, &
       SOLAR_CONST, STEFAN, PI, orbital_period, ecc, obliq, peri_time, &
       smaxis, albedo, lapse, h_a, tau_s, heat_capacity, ml_depth, &
       t_strat, eps, sigma_b, tka, tks, P00, STRAT_HS_LIKE)

  ! Write outputs
  call write_array_3d('output_tdt.bin', tdt, nlon, nlat, nlev)
  call write_array_3d('output_teq.bin', teq, nlon, nlat, nlev)
  call write_array_2d('output_h_trop.bin', h_trop, nlon, nlat)
  call write_array_2d('output_tg_new.bin', tg_new, nlon, nlat)

  write(*,*) 'Done. Files written:'
  write(*,*) '  Inputs: input_lat.bin, input_ps.bin, input_p_full.bin,'
  write(*,*) '          input_zfull.bin, input_t.bin, input_tg_prev.bin'
  write(*,*) '  Params: params.bin'
  write(*,*) '  Outputs: output_tdt.bin, output_teq.bin, output_h_trop.bin, output_tg_new.bin'
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
  subroutine write_params(filename, n1, n2, n3, ctime, dt_val, &
       sc, stef, pi_v, op, ec, ob, pt, sm, al, la, ha, ts, hc, ml, &
       tst, ep, sb, tka_v, tks_v, p00_v, strat_opt)
    character(len=*), intent(in) :: filename
    integer, intent(in) :: n1, n2, n3, ctime, strat_opt
    real(8), intent(in) :: dt_val, sc, stef, pi_v, op, ec, ob, pt, sm
    real(8), intent(in) :: al, la, ha, ts, hc, ml, tst, ep, sb, tka_v, tks_v, p00_v
    integer :: unit_num

    unit_num = 20
    open(unit=unit_num, file=filename, form='unformatted', access='stream', status='replace')
    ! Grid dimensions
    write(unit_num) n1, n2, n3
    ! Time
    write(unit_num) ctime
    write(unit_num) dt_val
    ! Physical constants
    write(unit_num) sc, stef, pi_v
    ! Orbital parameters
    write(unit_num) op, ec, ob, pt, sm
    ! Thermal parameters
    write(unit_num) al, la, ha, ts, hc, ml
    ! Held-Suarez parameters
    write(unit_num) tst, ep, sb, tka_v, tks_v, p00_v
    ! Stratosphere option
    write(unit_num) strat_opt
    close(unit_num)
  end subroutine write_params

end program test_top_down_newtonian_damping
