!-----------------------------------------------------------------------
! Standalone Newtonian Damping Kernel
!
! Extracted from hs_forcing_mod for isolated testing.
! This is the default Held-Suarez branch only (equilibrium_t_option = 'Held_Suarez').
!-----------------------------------------------------------------------

module newtonian_damping_mod

  implicit none
  private

  public :: newtonian_damping

contains

  subroutine newtonian_damping(nlon, nlat, nlev, lat, ps, p_full, t, &
                                t_zero, t_strat, delh, delv, eps, &
                                P00, KAPPA, tka, tks, sigma_b, &
                                tdt, teq, mask)
    !-----------------------------------------------------------------------
    ! Newtonian damping (thermal relaxation) for Held-Suarez benchmark
    !
    ! Implements Held-Suarez (1994) Equations 1-2:
    !   Teq = max(T* - delv*cos^2(lat)*ln(p/P00)) * (p/P00)^kappa, T_strat)
    !   dT/dt = -kT * (T - Teq)
    !
    ! where kT varies with latitude and sigma level.
    !-----------------------------------------------------------------------

    ! Arguments
    integer, intent(in) :: nlon, nlat, nlev
    real(8), intent(in) :: lat(nlon, nlat)            ! Latitude (radians)
    real(8), intent(in) :: ps(nlon, nlat)             ! Surface pressure (Pa)
    real(8), intent(in) :: p_full(nlon, nlat, nlev)   ! Pressure at full levels (Pa)
    real(8), intent(in) :: t(nlon, nlat, nlev)        ! Temperature (K)

    ! Held-Suarez parameters
    real(8), intent(in) :: t_zero    ! Equatorial equilibrium temperature (K)
    real(8), intent(in) :: t_strat   ! Stratospheric temperature (K)
    real(8), intent(in) :: delh      ! Equator-pole temperature difference (K)
    real(8), intent(in) :: delv      ! Static stability parameter (K)
    real(8), intent(in) :: eps       ! Hemispheric asymmetry (K)
    real(8), intent(in) :: P00       ! Reference pressure (Pa)
    real(8), intent(in) :: KAPPA     ! R/cp (dimensionless)
    real(8), intent(in) :: tka       ! Atmospheric damping rate (1/s)
    real(8), intent(in) :: tks       ! Surface damping rate (1/s)
    real(8), intent(in) :: sigma_b   ! Boundary layer top sigma level

    ! Outputs
    real(8), intent(out) :: tdt(nlon, nlat, nlev)     ! Temperature tendency (K/s)
    real(8), intent(out) :: teq(nlon, nlat, nlev)     ! Equilibrium temperature (K)

    ! Optional mask
    real(8), intent(in), optional :: mask(nlon, nlat, nlev)

    ! Local variables
    real(8) :: sin_lat(nlon, nlat)
    real(8) :: sin_lat_2(nlon, nlat)
    real(8) :: cos_lat_2(nlon, nlat)
    real(8) :: cos_lat_4(nlon, nlat)
    real(8) :: t_star(nlon, nlat)
    real(8) :: tstr(nlon, nlat)
    real(8) :: p_norm(nlon, nlat)
    real(8) :: the(nlon, nlat)
    real(8) :: sigma(nlon, nlat)
    real(8) :: tfactr(nlon, nlat)
    real(8) :: tdamp(nlon, nlat, nlev)
    real(8) :: rps(nlon, nlat)
    real(8) :: tcoeff
    integer :: k

    !-----------------------------------------------------------------------
    ! Precompute latitudinal constants (Fortran lines 539-546)
    !-----------------------------------------------------------------------

    ! Fortran: sin_lat(:,:) = sin(lat(:,:))
    sin_lat(:,:) = sin(lat(:,:))

    ! Fortran: sin_lat_2(:,:) = sin_lat(:,:)*sin_lat(:,:)
    sin_lat_2(:,:) = sin_lat(:,:) * sin_lat(:,:)

    ! Fortran: cos_lat_2(:,:) = 1.0-sin_lat_2(:,:)
    cos_lat_2(:,:) = 1.0d0 - sin_lat_2(:,:)

    ! Fortran: cos_lat_4(:,:) = cos_lat_2(:,:)*cos_lat_2(:,:)
    cos_lat_4(:,:) = cos_lat_2(:,:) * cos_lat_2(:,:)

    ! Fortran: t_star(:,:) = t_zero - delh*sin_lat_2(:,:) - eps*sin_lat(:,:)
    t_star(:,:) = t_zero - delh * sin_lat_2(:,:) - eps * sin_lat(:,:)

    ! Fortran: tstr(:,:) = t_strat - eps*sin_lat(:,:)
    tstr(:,:) = t_strat - eps * sin_lat(:,:)

    !-----------------------------------------------------------------------
    ! Compute coefficients (Fortran lines 552-554)
    !-----------------------------------------------------------------------

    ! Fortran: tcoeff = (tks-tka)/(1.0-sigma_b)
    tcoeff = (tks - tka) / (1.0d0 - sigma_b)

    ! Fortran: rps = 1./ps
    rps(:,:) = 1.0d0 / ps(:,:)

    !-----------------------------------------------------------------------
    ! Loop over levels (Fortran lines 556-598)
    !-----------------------------------------------------------------------

    do k = 1, nlev

      !---------------------------------------------------------------------
      ! Compute equilibrium temperature (Held_Suarez option, lines 566-570)
      !---------------------------------------------------------------------

      ! Fortran: p_norm(:,:) = p_full(:,:,k)/pref
      p_norm(:,:) = p_full(:,:,k) / P00

      ! Fortran: the(:,:) = t_star(:,:) - delv*cos_lat_2(:,:)*log(p_norm(:,:))
      the(:,:) = t_star(:,:) - delv * cos_lat_2(:,:) * log(p_norm(:,:))

      ! Fortran: teq(:,:,k) = the(:,:)*(p_norm(:,:))**KAPPA
      teq(:,:,k) = the(:,:) * (p_norm(:,:))**KAPPA

      ! Fortran: teq(:,:,k) = max( teq(:,:,k), tstr(:,:) )
      teq(:,:,k) = max(teq(:,:,k), tstr(:,:))

      !---------------------------------------------------------------------
      ! Compute damping coefficient (Fortran lines 590-596)
      !---------------------------------------------------------------------

      ! Fortran: sigma(:,:) = p_full(:,:,k)*rps(:,:)
      sigma(:,:) = p_full(:,:,k) * rps(:,:)

      ! Fortran: where (sigma(:,:) <= 1.0 .and. sigma(:,:) > sigma_b)
      !            tfactr(:,:) = tcoeff*(sigma(:,:)-sigma_b)
      !            tdamp(:,:,k) = tka + cos_lat_4(:,:)*tfactr(:,:)
      !          elsewhere
      !            tdamp(:,:,k) = tka
      !          endwhere
      where (sigma(:,:) <= 1.0d0 .and. sigma(:,:) > sigma_b)
        tfactr(:,:) = tcoeff * (sigma(:,:) - sigma_b)
        tdamp(:,:,k) = tka + cos_lat_4(:,:) * tfactr(:,:)
      elsewhere
        tdamp(:,:,k) = tka
      endwhere

    enddo

    !-----------------------------------------------------------------------
    ! Apply temperature tendency (Fortran lines 600-602)
    !-----------------------------------------------------------------------

    ! Fortran: do k=1,size(t,3)
    !            tdt(:,:,k) = -tdamp(:,:,k)*(t(:,:,k)-teq(:,:,k))
    !          enddo
    do k = 1, nlev
      tdt(:,:,k) = -tdamp(:,:,k) * (t(:,:,k) - teq(:,:,k))
    enddo

    !-----------------------------------------------------------------------
    ! Apply mask if present (Fortran lines 604-607)
    !-----------------------------------------------------------------------

    ! Fortran: if (present(mask)) then
    !            tdt = tdt * mask
    !            teq = teq * mask
    !          endif
    if (present(mask)) then
      tdt = tdt * mask
      teq = teq * mask
    endif

  end subroutine newtonian_damping

end module newtonian_damping_mod
