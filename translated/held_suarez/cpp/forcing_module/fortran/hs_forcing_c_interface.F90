module hs_forcing_c_interface
  !! Fortran iso_c_binding interface for C++ Held-Suarez forcing module
  use, intrinsic :: iso_c_binding, only: c_int, c_double, c_ptr, c_loc, c_null_ptr
  implicit none
  private

  ! Public interface and constants
  public :: hs_forcing_driver_c_wrapper
  public :: HS_SUCCESS, HS_ERROR_NULL_POINTER, HS_ERROR_INVALID_DIMS
  public :: HS_EQUILIBRIUM_HELD_SUAREZ, HS_EQUILIBRIUM_TOP_DOWN
  public :: HS_STRATOSPHERE_DEFAULT

  ! Error codes (match C API)
  integer(c_int), parameter :: HS_SUCCESS = 0
  integer(c_int), parameter :: HS_ERROR_NULL_POINTER = -1
  integer(c_int), parameter :: HS_ERROR_INVALID_DIMS = -2
  integer(c_int), parameter :: HS_ERROR_INVALID_CONFIG = -3
  integer(c_int), parameter :: HS_ERROR_TOPDOWN_MISSING = -4

  ! Equilibrium temperature options
  integer(c_int), parameter :: HS_EQUILIBRIUM_HELD_SUAREZ = 0
  integer(c_int), parameter :: HS_EQUILIBRIUM_TOP_DOWN = 1

  ! Stratosphere options
  integer(c_int), parameter :: HS_STRATOSPHERE_DEFAULT = 0
  integer(c_int), parameter :: HS_STRATOSPHERE_C_ABOVE_TP = 1
  integer(c_int), parameter :: HS_STRATOSPHERE_HS_LIKE = 2
  integer(c_int), parameter :: HS_STRATOSPHERE_EXTEND_TP = 3

  ! C function interfaces
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

    subroutine hs_convert_timescales_c(ka_days, ks_days, kf_days, tka, tks, vkf) &
        bind(C, name='hs_convert_timescales_c')
      use, intrinsic :: iso_c_binding
      real(c_double), value :: ka_days, ks_days, kf_days
      real(c_double), intent(out) :: tka, tks, vkf
    end subroutine hs_convert_timescales_c

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

contains

  subroutine hs_forcing_driver_c_wrapper(nlon, nlat, nlev, dt, &
      lon, lat, ps, p_full, u, v, t, &
      udt, vdt, tdt, teq, ierr)
    !! Simplified wrapper for basic Held-Suarez forcing (no energy conservation, top-down)
    integer, intent(in) :: nlon, nlat, nlev
    real(c_double), intent(in) :: dt
    real(c_double), intent(in), target :: lon(:), lat(:)
    real(c_double), intent(in), target :: ps(:,:)
    real(c_double), intent(in), target :: p_full(:,:,:)
    real(c_double), intent(in), target :: u(:,:,:), v(:,:,:), t(:,:,:)
    real(c_double), intent(inout), target :: udt(:,:,:), vdt(:,:,:), tdt(:,:,:)
    real(c_double), intent(inout), target :: teq(:,:,:)
    integer, intent(out) :: ierr

    real(c_double) :: t_zero, t_strat, delh, delv, eps, P00, kappa
    real(c_double) :: tka, tks, vkf, sigma_b
    real(c_double) :: orbital_period, ecc, obliq, peri_time, smaxis
    real(c_double) :: solar_const, stefan, albedo, lapse, h_a, tau_s
    real(c_double) :: heat_capacity, ml_depth
    integer(c_int) :: status
    real(c_double), allocatable, target :: lon2d(:,:), lat2d(:,:)
    integer :: i, j

    ! Get defaults (provide variables for all OUT args)
    call hs_get_defaults_c(t_zero, t_strat, delh, delv, eps, P00, kappa, &
      tka, tks, vkf, sigma_b, &
      orbital_period, ecc, obliq, peri_time, smaxis, &
      solar_const, stefan, albedo, lapse, h_a, tau_s, heat_capacity, ml_depth)

    ! Build 2D coordinate arrays expected by C API (size nlon x nlat)
    allocate(lon2d(nlon, nlat))
    allocate(lat2d(nlon, nlat))
    do j = 1, nlat
      do i = 1, nlon
        lon2d(i, j) = lon(i)
        lat2d(i, j) = lat(j)
      end do
    end do

    ! Call C driver (HS mode, no energy conservation)
    status = hs_forcing_driver_c( &
      int(nlon, c_int), int(nlat, c_int), int(nlev, c_int), 0_c_int, dt, &
      c_loc(lon2d), c_loc(lat2d), c_loc(ps), c_loc(p_full), c_null_ptr, &
      c_loc(u), c_loc(v), c_loc(t), c_null_ptr, c_null_ptr, c_null_ptr, c_null_ptr, &
      t_zero, t_strat, delh, delv, eps, P00, kappa, tka, tks, vkf, &
      sigma_b, orbital_period, ecc, obliq, peri_time, smaxis, &
      solar_const, stefan, albedo, lapse, h_a, tau_s, heat_capacity, ml_depth, &
      0_c_int, HS_EQUILIBRIUM_HELD_SUAREZ, HS_STRATOSPHERE_DEFAULT, &
      c_loc(udt), c_loc(vdt), c_loc(tdt), c_loc(teq), c_null_ptr, c_null_ptr, c_null_ptr)

    deallocate(lon2d)
    deallocate(lat2d)

    ierr = int(status)
  end subroutine hs_forcing_driver_c_wrapper

end module hs_forcing_c_interface
