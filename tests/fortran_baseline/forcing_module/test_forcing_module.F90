program test_forcing_module

  use newtonian_damping_mod, only: newtonian_damping
  use rayleigh_damping_mod, only: rayleigh_damping

  implicit none

  integer, parameter :: nlon = 4
  integer, parameter :: nlat = 3
  integer, parameter :: nlev = 5

  real(8), parameter :: PI = 3.14159265358979323846d0
  real(8), parameter :: SECONDS_PER_DAY = 86400.0d0

  ! Held-Suarez parameters
  real(8), parameter :: t_zero = 315.0d0
  real(8), parameter :: t_strat = 200.0d0
  real(8), parameter :: delh = 60.0d0
  real(8), parameter :: delv = 10.0d0
  real(8), parameter :: eps = 0.0d0
  real(8), parameter :: P00 = 1.0d5
  real(8), parameter :: KAPPA = 2.0d0/7.0d0
  real(8), parameter :: sigma_b = 0.7d0

  real(8), parameter :: ka_days = 40.0d0
  real(8), parameter :: ks_days = 4.0d0
  real(8), parameter :: kf_days = 1.0d0

  real(8) :: tka, tks, vkf

  real(8) :: lat(nlon,nlat), lon(nlon,nlat)
  real(8) :: ps(nlon,nlat)
  real(8) :: p_full(nlon,nlat,nlev)
  real(8) :: t(nlon,nlat,nlev)
  real(8) :: u(nlon,nlat,nlev), v(nlon,nlat,nlev)

  real(8) :: tdt(nlon,nlat,nlev), teq(nlon,nlat,nlev)
  real(8) :: udt(nlon,nlat,nlev), vdt(nlon,nlat,nlev)

  integer :: i,j,k
  real(8) :: sigma_levels(nlev)

  ! Create folders for outputs
  call create_dirs()

  ! Derived params
  tka = 1.0d0 / (SECONDS_PER_DAY * ka_days)
  tks = 1.0d0 / (SECONDS_PER_DAY * ks_days)
  vkf = 1.0d0 / (SECONDS_PER_DAY * kf_days)

  ! simple sigma levels (top to bottom)
  sigma_levels = (/ 0.2d0, 0.4d0, 0.6d0, 0.8d0, 1.0d0 /)

  ! Build lat/lon arrays
  do j = 1, nlat
    do i = 1, nlon
      lat(i,j) = (-60.0d0 + 60.0d0*(j-1)) * PI/180.0d0
      lon(i,j) = 2.0d0*PI*(i-1)/nlon
    enddo
  enddo

  ! Surface pressure and p_full
  do j = 1, nlat
    do i = 1, nlon
      ps(i,j) = P00*(1.0d0 + 0.01d0*sin(2.0d0*PI*real(i-1)/real(nlon)))
      do k = 1, nlev
        p_full(i,j,k) = sigma_levels(k) * ps(i,j)
      enddo
    enddo
  enddo

  ! Initialize temperature and winds with simple patterns
  do k = 1, nlev
    do j = 1, nlat
      do i = 1, nlon
        t(i,j,k) = 280.0d0 - 30.0d0*(1.0d0 - sigma_levels(k)) + 5.0d0*sin(2.0d0*PI*real(i-1)/real(nlon))
        u(i,j,k) = 10.0d0 * cos(lat(i,j))
        v(i,j,k) = 2.0d0 * sin(lat(i,j))
      enddo
    enddo
  enddo

  ! Call kernels
  call rayleigh_damping(nlon, nlat, nlev, ps, p_full, u, v, vkf, sigma_b, udt, vdt)
  call newtonian_damping(nlon, nlat, nlev, lat, ps, p_full, t, &
                         t_zero, t_strat, delh, delv, eps, &
                         P00, KAPPA, tka, tks, sigma_b, &
                         tdt, teq)

  ! Write inputs and outputs
  call write_array_2d('inputs/input_lat.bin', lat, nlon, nlat)
  call write_array_2d('inputs/input_ps.bin', ps, nlon, nlat)
  call write_array_3d('inputs/input_p_full.bin', p_full, nlon, nlat, nlev)
  call write_array_3d('inputs/input_t.bin', t, nlon, nlat, nlev)
  call write_array_3d('inputs/input_u.bin', u, nlon, nlat, nlev)
  call write_array_3d('inputs/input_v.bin', v, nlon, nlat, nlev)

  call write_params('inputs/params.bin', nlon, nlat, nlev, &
                    t_zero, t_strat, delh, delv, eps, P00, KAPPA, tka, tks, sigma_b)

  call write_array_3d('outputs/output_tdt.bin', tdt, nlon, nlat, nlev)
  call write_array_3d('outputs/output_teq.bin', teq, nlon, nlat, nlev)
  call write_array_3d('outputs/output_udt.bin', udt, nlon, nlat, nlev)
  call write_array_3d('outputs/output_vdt.bin', vdt, nlon, nlat, nlev)

  write(*,*) 'Baseline generation complete. Files written to inputs/ and outputs/'

contains

  subroutine create_dirs()
    logical :: exist_inputs, exist_outputs
    inquire (file='inputs', exist=exist_inputs)
    if (.not. exist_inputs) then
      call execute_command_line('mkdir -p inputs')
    end if
    inquire (file='outputs', exist=exist_outputs)
    if (.not. exist_outputs) then
      call execute_command_line('mkdir -p outputs')
    end if
  end subroutine create_dirs

  subroutine write_array_2d(filename, arr, n1, n2)
    character(len=*), intent(in) :: filename
    integer, intent(in) :: n1, n2
    real(8), intent(in) :: arr(n1,n2)
    integer :: unit_num
    unit_num = 20
    open(unit=unit_num, file=filename, form='unformatted', access='stream', status='replace')
    write(unit_num) arr
    close(unit_num)
  end subroutine write_array_2d

  subroutine write_array_3d(filename, arr, n1, n2, n3)
    character(len=*), intent(in) :: filename
    integer, intent(in) :: n1, n2, n3
    real(8), intent(in) :: arr(n1,n2,n3)
    integer :: unit_num
    unit_num = 20
    open(unit=unit_num, file=filename, form='unformatted', access='stream', status='replace')
    write(unit_num) arr
    close(unit_num)
  end subroutine write_array_3d

  subroutine write_params(filename, n1, n2, n3, p_t_zero, p_t_strat, p_delh, p_delv, p_eps, p_P00, p_KAPPA, p_tka, p_tks, p_sigma_b)
    character(len=*), intent(in) :: filename
    integer, intent(in) :: n1, n2, n3
    real(8), intent(in) :: p_t_zero, p_t_strat, p_delh, p_delv, p_eps
    real(8), intent(in) :: p_P00, p_KAPPA, p_tka, p_tks, p_sigma_b
    integer :: unit_num
    unit_num = 21
    open(unit=unit_num, file=filename, form='unformatted', access='stream', status='replace')
    write(unit_num) n1, n2, n3
    write(unit_num) p_t_zero, p_t_strat, p_delh, p_delv, p_eps
    write(unit_num) p_P00, p_KAPPA, p_tka, p_tks, p_sigma_b
    close(unit_num)
  end subroutine write_params

end program test_forcing_module
