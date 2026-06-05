!-----------------------------------------------------------------------
! Standalone Top-Down Newtonian Damping Kernel
!
! Extracted from: src/atmos_param/hs_forcing/hs_forcing.F90 (lines 894-1026)
! Includes: update_orbit, calc_hour_angle, calc_ecc_anomaly
! No FMS dependencies - all constants passed as parameters.
!-----------------------------------------------------------------------

module top_down_newtonian_damping_mod

  implicit none
  private

  public :: top_down_newtonian_damping
  public :: update_orbit
  public :: calc_hour_angle
  public :: calc_ecc_anomaly

  ! Stratosphere temperature option enumeration
  integer, parameter, public :: STRAT_DEFAULT = 0
  integer, parameter, public :: STRAT_C_ABOVE_TP = 1
  integer, parameter, public :: STRAT_HS_LIKE = 2
  integer, parameter, public :: STRAT_EXTEND_TP = 3

contains

  !---------------------------------------------------------------------
  ! calc_ecc_anomaly
  !
  ! Newton-Raphson solver for Kepler's equation: E - e*sin(E) = M
  !---------------------------------------------------------------------
  subroutine calc_ecc_anomaly(mean_anomaly, ecc, ecc_anomaly)
    real(8), intent(in) :: mean_anomaly, ecc
    real(8), intent(out) :: ecc_anomaly

    real(8) :: dE, d
    integer, parameter :: maxiter = 30
    real(8), parameter :: tol = 1.0d-10
    integer :: k

    ecc_anomaly = mean_anomaly
    d = ecc_anomaly - ecc*sin(ecc_anomaly) - mean_anomaly

    do k = 1, maxiter
      dE = d / (1.0d0 - ecc*cos(ecc_anomaly))
      ecc_anomaly = ecc_anomaly - dE
      d = ecc_anomaly - ecc*sin(ecc_anomaly) - mean_anomaly
      if (abs(d) < tol) exit
    enddo

    if (k > maxiter .and. abs(d) > tol) then
      print *, '*** Warning: eccentric anomaly has not converged'
    endif

  end subroutine calc_ecc_anomaly

  !---------------------------------------------------------------------
  ! calc_hour_angle
  !
  ! Compute solar hour angle from latitude and solar declination
  !---------------------------------------------------------------------
  subroutine calc_hour_angle(nlon, nlat, lat, dec, hour_angle)
    integer, intent(in) :: nlon, nlat
    real(8), intent(in) :: dec
    real(8), intent(in), dimension(nlon, nlat) :: lat
    real(8), intent(out), dimension(nlon, nlat) :: hour_angle

    real(8), dimension(nlon, nlat) :: inv_hour_angle

    inv_hour_angle = -tan(lat(:,:)) * tan(dec)

    where (inv_hour_angle > 1.0d0)
      inv_hour_angle = 1.0d0
    endwhere
    where (inv_hour_angle < -1.0d0)
      inv_hour_angle = -1.0d0
    endwhere

    hour_angle = acos(inv_hour_angle)

  end subroutine calc_hour_angle

  !---------------------------------------------------------------------
  ! update_orbit
  !
  ! Compute solar declination and orbital distance from current time
  !---------------------------------------------------------------------
  subroutine update_orbit(current_time, orbital_period, ecc, obliq, peri_time, &
                          smaxis, pi, dec, orb_dist)
    integer, intent(in) :: current_time
    real(8), intent(in) :: orbital_period, ecc, obliq, peri_time, smaxis, pi
    real(8), intent(out) :: dec, orb_dist

    real(8) :: theta, mean_anomaly, ecc_anomaly, true_anomaly

    mean_anomaly = 2.0d0*pi/(orbital_period*86400.0d0) * &
                   (real(current_time,8) - peri_time*orbital_period*86400.0d0)

    call calc_ecc_anomaly(mean_anomaly, ecc, ecc_anomaly)

    true_anomaly = 2.0d0*atan(((1.0d0 + ecc)/(1.0d0 - ecc))**0.5d0 * tan(ecc_anomaly/2.0d0))
    orb_dist = smaxis * (1.0d0 - ecc**2) / (1.0d0 + ecc*cos(true_anomaly))

    theta = 2.0d0*pi*real(current_time,8) / (orbital_period*86400.0d0)
    dec = asin(sin(obliq*pi/180.0d0) * sin(theta))

  end subroutine update_orbit

  !---------------------------------------------------------------------
  ! top_down_newtonian_damping
  !
  ! Temperature relaxation with tropopause-aware vertical structure
  !
  ! Arguments:
  !   nlon, nlat, nlev - Grid dimensions
  !   current_time     - Time in seconds since epoch
  !   dt               - Timestep (seconds)
  !   lat              - Latitude (radians)                [nlon, nlat]
  !   ps               - Surface pressure (Pa)             [nlon, nlat]
  !   p_full           - Pressure at full levels (Pa)      [nlon, nlat, nlev]
  !   zfull            - Height at full levels (m)         [nlon, nlat, nlev]
  !   t                - Temperature (K)                   [nlon, nlat, nlev]
  !   tg_prev          - Previous ground temperature (K)   [nlon, nlat]
  !
  !   Physical parameters (passed explicitly):
  !   solar_const, stefan, pi_val, orbital_period, ecc, obliq, peri_time,
  !   smaxis, albedo, lapse, h_a, tau_s, heat_capacity, ml_depth,
  !   t_strat, eps, sigma_b, tka, tks, P00, strat_option
  !
  !   Outputs:
  !   tdt              - Temperature tendency (K/s)        [nlon, nlat, nlev]
  !   teq              - Equilibrium temperature (K)       [nlon, nlat, nlev]
  !   h_trop           - Tropopause height (km)            [nlon, nlat]
  !   tg_new           - New ground temperature (K)        [nlon, nlat]
  !---------------------------------------------------------------------
  subroutine top_down_newtonian_damping(nlon, nlat, nlev, current_time, dt, &
       lat, ps, p_full, zfull, t, tg_prev, &
       solar_const, stefan, pi_val, orbital_period, ecc, obliq, peri_time, &
       smaxis, albedo, lapse, h_a, tau_s, heat_capacity, ml_depth, &
       t_strat, eps, sigma_b, tka, tks, P00, strat_option, &
       tdt, teq, h_trop, tg_new, mask)

    integer, intent(in) :: nlon, nlat, nlev
    integer, intent(in) :: current_time
    real(8), intent(in) :: dt
    real(8), intent(in), dimension(nlon, nlat) :: lat, ps, tg_prev
    real(8), intent(in), dimension(nlon, nlat, nlev) :: p_full, zfull, t

    ! Physical parameters
    real(8), intent(in) :: solar_const, stefan, pi_val
    real(8), intent(in) :: orbital_period, ecc, obliq, peri_time, smaxis
    real(8), intent(in) :: albedo, lapse, h_a, tau_s, heat_capacity, ml_depth
    real(8), intent(in) :: t_strat, eps, sigma_b, tka, tks, P00
    integer, intent(in) :: strat_option

    ! Outputs
    real(8), intent(out), dimension(nlon, nlat, nlev) :: tdt, teq
    real(8), intent(out), dimension(nlon, nlat) :: h_trop, tg_new
    real(8), intent(in), dimension(nlon, nlat, nlev), optional :: mask

    ! Local variables
    real(8), dimension(nlon, nlat) :: sin_lat, cos_lat, sin_lat_2, cos_lat_2, cos_lat_4
    real(8), dimension(nlon, nlat) :: tstr, sigma, tfactr, rps
    real(8), dimension(nlon, nlat) :: hour_angle, s, t_radbal, t_trop, t_surf, tg
    real(8), dimension(nlon, nlat, nlev) :: tdamp

    real(8) :: dec, orb_dist, tcoeff
    integer :: i, j, k

    !-----------------------------------------------------------------------
    ! Latitudinal constants
    !-----------------------------------------------------------------------
    sin_lat(:,:) = sin(lat(:,:))
    cos_lat(:,:) = cos(lat(:,:))
    sin_lat_2(:,:) = sin_lat(:,:) * sin_lat(:,:)
    cos_lat_2(:,:) = 1.0d0 - sin_lat_2(:,:)
    cos_lat_4(:,:) = cos_lat_2(:,:) * cos_lat_2(:,:)

    !-----------------------------------------------------------------------
    ! Orbital calculations
    !-----------------------------------------------------------------------
    call update_orbit(current_time, orbital_period, ecc, obliq, peri_time, &
                      smaxis, pi_val, dec, orb_dist)

    call calc_hour_angle(nlon, nlat, lat, dec, hour_angle)

    !-----------------------------------------------------------------------
    ! Solar insolation
    !-----------------------------------------------------------------------
    s(:,:) = solar_const/pi_val * (hour_angle(:,:)*sin_lat(:,:)*sin(dec) + &
                                   cos_lat(:,:)*cos(dec)*sin(hour_angle(:,:)))

    !-----------------------------------------------------------------------
    ! Radiative balance temperature
    !-----------------------------------------------------------------------
    t_radbal(:,:) = ((1.0d0-albedo)*s(:,:)/stefan)**0.25d0

    !-----------------------------------------------------------------------
    ! Tropopause height
    !-----------------------------------------------------------------------
    t_trop(:,:) = t_radbal(:,:) / (2.0d0**0.25d0)
    h_trop(:,:) = 1.0d0/(16.0d0*lapse) * &
                  (1.3863d0*t_trop(:,:) + &
                   sqrt((1.3863d0*t_trop(:,:))**2 + 32.0d0*lapse*tau_s*h_a*t_trop(:,:)))

    !-----------------------------------------------------------------------
    ! Surface temperature with heat capacity
    !-----------------------------------------------------------------------
    t_surf(:,:) = t_trop(:,:) + h_trop(:,:)*lapse
    tg(:,:) = stefan*dt/(ml_depth*heat_capacity) * &
              (t_surf(:,:)**4 - tg_prev(:,:)**4) + tg_prev(:,:)
    tg_new(:,:) = tg(:,:)
    t_trop(:,:) = tg(:,:) - h_trop(:,:)*lapse

    !-----------------------------------------------------------------------
    ! Stratosphere temperature
    !-----------------------------------------------------------------------
    tstr(:,:) = t_strat - eps*sin_lat(:,:)

    !-----------------------------------------------------------------------
    ! Damping coefficient setup
    !-----------------------------------------------------------------------
    tcoeff = (tks - tka) / (1.0d0 - sigma_b)
    rps(:,:) = 1.0d0 / ps(:,:)

    !-----------------------------------------------------------------------
    ! Vertical loop: equilibrium temperature and damping
    !-----------------------------------------------------------------------
    do k = 1, nlev
      ! Equilibrium temperature
      teq(:,:,k) = t_trop(:,:) + lapse*(h_trop(:,:) - zfull(:,:,k)/1000.0d0)

      ! Apply stratosphere option
      if (strat_option == STRAT_C_ABOVE_TP) then
        do j = 1, nlat
          do i = 1, nlon
            if (zfull(i,j,k)/1000.0d0 >= h_trop(i,j)) then
              teq(i,j,k) = tstr(i,j)
            endif
          enddo
        enddo
      elseif (strat_option == STRAT_HS_LIKE) then
        teq(:,:,k) = max(teq(:,:,k), tstr(:,:))
      elseif (strat_option == STRAT_EXTEND_TP) then
        do j = 1, nlat
          do i = 1, nlon
            if (zfull(i,j,k)/1000.0d0 >= h_trop(i,j)) then
              teq(i,j,k) = t_trop(i,j)
            endif
          enddo
        enddo
      else
        teq(:,:,k) = max(teq(:,:,k), 0.0d0)
      endif

      ! Damping coefficient
      sigma(:,:) = p_full(:,:,k) * rps(:,:)
      where (sigma(:,:) <= 1.0d0 .and. sigma(:,:) > sigma_b)
        tfactr(:,:) = tcoeff * (sigma(:,:) - sigma_b)
        tdamp(:,:,k) = tka + cos_lat_4(:,:) * tfactr(:,:)
      elsewhere
        tdamp(:,:,k) = tka
      endwhere
    enddo

    !-----------------------------------------------------------------------
    ! Temperature tendency
    !-----------------------------------------------------------------------
    do k = 1, nlev
      tdt(:,:,k) = -tdamp(:,:,k) * (t(:,:,k) - teq(:,:,k))
    enddo

    !-----------------------------------------------------------------------
    ! Apply mask if present
    !-----------------------------------------------------------------------
    if (present(mask)) then
      tdt(:,:,:) = tdt(:,:,:) * mask(:,:,:)
      teq(:,:,:) = teq(:,:,:) * mask(:,:,:)
    endif

  end subroutine top_down_newtonian_damping

end module top_down_newtonian_damping_mod
