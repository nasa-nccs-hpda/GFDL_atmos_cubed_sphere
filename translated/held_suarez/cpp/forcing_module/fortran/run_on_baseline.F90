program run_on_baseline
  use, intrinsic :: iso_c_binding, only: c_double, c_int, c_int64_t, c_ptr, c_loc, c_null_ptr
  use hs_forcing_c_interface
  implicit none

  integer(c_int) :: nlon, nlat, nlev
  integer :: i, j, k, ierr
  real(c_double) :: dt
  real(c_double) :: t_zero, t_strat, delh, delv, eps, P00, kappa
  real(c_double) :: tka, tks, vkf, sigma_b
  real(c_double) :: orbital_period, ecc, obliq, peri_time, smaxis
  real(c_double) :: solar_const, stefan, albedo, lapse, h_a, tau_s
  real(c_double) :: heat_capacity, ml_depth
  integer(c_int) :: do_conserve_energy, equilibrium_option, stratosphere_option

  real(c_double), allocatable, target :: lon(:), lat(:)
  real(c_double), allocatable, target :: ps(:,:), p_full(:,:,:)
  real(c_double), allocatable, target :: lat2d(:,:)
  real(c_double), allocatable, target :: lon2d(:,:)
  real(c_double), allocatable, target :: u(:,:,:), v(:,:,:), t(:,:,:)
  real(c_double), allocatable, target :: udt(:,:,:), vdt(:,:,:), tdt(:,:,:), teq(:,:,:)

  character(len=*), parameter :: inputs_dir = '../../../../../tests/fortran_baseline/forcing_module/inputs/'
  character(len=*), parameter :: cand_dir = './candidate_outputs/'
  character(len=256) :: path

  integer :: unit
  integer(c_int64_t) :: file_size
  integer :: nd
  real(c_double), allocatable :: pvals(:)

  interface
    function hs_forcing_driver_c( &
        nlon, nlat, nlev, current_time, dt, &
        lon, lat, ps, p_full, p_half, u, v, t, um, vm, zfull, tg_prev, &
        t_zero, t_strat, delh, delv, eps, P00, kappa, tka, tks, vkf, &
        sigma_b, orbital_period, ecc, obliq, peri_time, smaxis, &
        solar_const, stefan, albedo, lapse, h_a, tau_s, heat_capacity, &
        ml_depth, do_conserve_energy, equilibrium_option, stratosphere_option, &
        udt, vdt, tdt, teq, h_trop, tg_new, mask) &
        bind(C, name='hs_forcing_driver_c')
      use, intrinsic :: iso_c_binding
      integer(c_int), value :: nlon, nlat, nlev, current_time
      real(c_double), value :: dt
      type(c_ptr), value :: lon, lat
      type(c_ptr), value :: ps, p_full, p_half
      type(c_ptr), value :: u, v, t
      type(c_ptr), value :: um, vm
      type(c_ptr), value :: zfull, tg_prev
      real(c_double), value :: t_zero, t_strat, delh, delv, eps, P00, kappa
      real(c_double), value :: tka, tks, vkf, sigma_b, orbital_period, ecc
      real(c_double), value :: obliq, peri_time, smaxis, solar_const, stefan
      real(c_double), value :: albedo, lapse, h_a, tau_s, heat_capacity, ml_depth
      integer(c_int), value :: do_conserve_energy, equilibrium_option, stratosphere_option
      type(c_ptr), value :: udt, vdt, tdt
      type(c_ptr), value :: teq, h_trop, tg_new
      type(c_ptr), value :: mask
      integer(c_int) :: hs_forcing_driver_c
    end function hs_forcing_driver_c

    subroutine hs_get_defaults_c( &
        t_zero, t_strat, delh, delv, eps, P00, kappa, tka, tks, vkf, &
        sigma_b, orbital_period, ecc, obliq, peri_time, smaxis, &
        solar_const, stefan, albedo, lapse, h_a, tau_s, heat_capacity, ml_depth) &
        bind(C, name='hs_get_defaults_c')
      use, intrinsic :: iso_c_binding
      real(c_double), intent(out) :: t_zero, t_strat, delh, delv, eps, P00, kappa
      real(c_double), intent(out) :: tka, tks, vkf, sigma_b, orbital_period
      real(c_double), intent(out) :: ecc, obliq, peri_time, smaxis, solar_const
      real(c_double), intent(out) :: stefan, albedo, lapse, h_a, tau_s
      real(c_double), intent(out) :: heat_capacity, ml_depth
    end subroutine hs_get_defaults_c
  end interface

  ! Read params (nlon, nlat, nlev) and optional config doubles
  character(len=256) :: params_path
  params_path = trim(inputs_dir)//'params.bin'
  inquire(file=trim(params_path), size=file_size)
  nd = int((file_size - 12) / 8)
  if (nd < 0) nd = 0
  allocate(pvals(0:nd-1))
  open(newunit=unit, file=trim(params_path), status='old', access='stream', form='unformatted')
  read(unit) nlon, nlat, nlev
  if (nd > 0) then
    read(unit) pvals
  end if
  close(unit)

  ! Initialize config from defaults then overwrite with provided params
  call hs_get_defaults_c(t_zero, t_strat, delh, delv, eps, P00, kappa, &
       tka, tks, vkf, sigma_b, &
       orbital_period, ecc, obliq, peri_time, smaxis, &
       solar_const, stefan, albedo, lapse, h_a, tau_s, heat_capacity, ml_depth)

  if (nd >= 1) t_zero = pvals(0)
  if (nd >= 2) t_strat = pvals(1)
  if (nd >= 3) delh = pvals(2)
  if (nd >= 4) delv = pvals(3)
  if (nd >= 5) eps = pvals(4)
  if (nd >= 6) P00 = pvals(5)
  if (nd >= 7) kappa = pvals(6)
  if (nd >= 8) tka = pvals(7)
  if (nd >= 9) tks = pvals(8)
  if (nd >= 10) sigma_b = pvals(9)

  ! kf (days) is not stored in params.bin for this baseline; use 1 day as in test harness
  vkf = 1.0d0 / 86400.0d0


  dt = 600.d0

  allocate(lon(nlon))
  allocate(ps(nlon,nlat))
  allocate(p_full(nlon,nlat,nlev))
  allocate(u(nlon,nlat,nlev), v(nlon,nlat,nlev), t(nlon,nlat,nlev))
  allocate(udt(nlon,nlat,nlev), vdt(nlon,nlat,nlev), tdt(nlon,nlat,nlev), teq(nlon,nlat,nlev))

  ! Read lat (stored as 2D [nlon,nlat] in baseline); extract 1D lat(j)=lat2d(1,j)
  allocate(lat2d(nlon,nlat))
  open(newunit=unit, file=trim(inputs_dir)//'input_lat.bin', status='old', access='stream', form='unformatted')
  read(unit) lat2d
  close(unit)
  allocate(lat(nlat))
  do j = 1, nlat
    lat(j) = lat2d(1, j)
  end do

  ! Generate lon uniformly (C implementation ignores lon for HS but keep 1D lon)
  do i = 1, nlon
    lon(i) = (i - 1) * (2.d0 * 3.14159265358979323846d0) / dble(nlon)
  end do
  ! Build 2D lon2d from 1D lon to match C API expectation
  allocate(lon2d(nlon,nlat))
  do j = 1, nlat
    do i = 1, nlon
      lon2d(i,j) = lon(i)
    end do
  end do

  ! Read ps
  open(newunit=unit, file=trim(inputs_dir)//'input_ps.bin', status='old', access='stream', form='unformatted')
  read(unit) ps
  close(unit)

  ! Read p_full
  open(newunit=unit, file=trim(inputs_dir)//'input_p_full.bin', status='old', access='stream', form='unformatted')
  read(unit) p_full
  close(unit)

  ! Read prognostic fields u, v, t
  open(newunit=unit, file=trim(inputs_dir)//'input_u.bin', status='old', access='stream', form='unformatted')
  read(unit) u
  close(unit)

  open(newunit=unit, file=trim(inputs_dir)//'input_v.bin', status='old', access='stream', form='unformatted')
  read(unit) v
  close(unit)

  open(newunit=unit, file=trim(inputs_dir)//'input_t.bin', status='old', access='stream', form='unformatted')
  read(unit) t
  close(unit)

  ! Initialize tendencies
  udt = 0.d0
  vdt = 0.d0
  tdt = 0.d0
  teq = 0.d0

  ! Call C driver directly with parameters populated from params.bin
  do_conserve_energy = 0_c_int
  equilibrium_option = HS_EQUILIBRIUM_HELD_SUAREZ
  stratosphere_option = HS_STRATOSPHERE_DEFAULT

    ierr = hs_forcing_driver_c( &
      int(nlon, c_int), int(nlat, c_int), int(nlev, c_int), 0_c_int, dt, &
      c_loc(lon2d), c_loc(lat2d), c_loc(ps), c_loc(p_full), c_null_ptr, &
      c_loc(u), c_loc(v), c_loc(t), c_null_ptr, c_null_ptr, c_null_ptr, c_null_ptr, &
      t_zero, t_strat, delh, delv, eps, P00, kappa, tka, tks, vkf, &
      sigma_b, orbital_period, ecc, obliq, peri_time, smaxis, &
      solar_const, stefan, albedo, lapse, h_a, tau_s, heat_capacity, ml_depth, &
      do_conserve_energy, equilibrium_option, stratosphere_option, &
      c_loc(udt), c_loc(vdt), c_loc(tdt), c_loc(teq), c_null_ptr, c_null_ptr, c_null_ptr)

  if (ierr /= HS_SUCCESS) then
    print *, 'hs_forcing_driver_c returned error code', ierr
    stop 1
  end if

  ! Ensure candidate output dir
  call execute_command_line('mkdir -p ' // trim(cand_dir))

  ! Write outputs as raw doubles
  path = trim(cand_dir)//'output_udt.bin'
  open(newunit=unit, file=trim(path), status='replace', access='stream', form='unformatted')
  write(unit) udt
  close(unit)

  path = trim(cand_dir)//'output_vdt.bin'
  open(newunit=unit, file=trim(path), status='replace', access='stream', form='unformatted')
  write(unit) vdt
  close(unit)

  path = trim(cand_dir)//'output_tdt.bin'
  open(newunit=unit, file=trim(path), status='replace', access='stream', form='unformatted')
  write(unit) tdt
  close(unit)

  path = trim(cand_dir)//'output_teq.bin'
  open(newunit=unit, file=trim(path), status='replace', access='stream', form='unformatted')
  write(unit) teq
  close(unit)

  print *, 'Wrote candidate outputs to', trim(cand_dir)
  stop 0
end program run_on_baseline
