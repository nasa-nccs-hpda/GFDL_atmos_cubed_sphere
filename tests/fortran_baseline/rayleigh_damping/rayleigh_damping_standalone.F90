!-----------------------------------------------------------------------
! Standalone Rayleigh Damping Kernel
!
! Extracted from hs_forcing_mod for isolated testing.
! This is the default Held-Suarez branch only (no relax_to_specified_wind).
!-----------------------------------------------------------------------

module rayleigh_damping_mod

  implicit none
  private

  public :: rayleigh_damping

contains

  subroutine rayleigh_damping(nlon, nlat, nlev, ps, p_full, u, v, &
                               vkf, sigma_b, udt, vdt, mask)
    !-----------------------------------------------------------------------
    ! Rayleigh damping of wind components near the surface
    !
    ! Standard Held-Suarez (1994) formulation:
    !   kv(sigma) = kf * max(0, (sigma - sigma_b) / (1 - sigma_b))
    !   du/dt = -kv * u
    !   dv/dt = -kv * v
    !-----------------------------------------------------------------------

    ! Arguments
    integer, intent(in) :: nlon, nlat, nlev
    real(8), intent(in) :: ps(nlon, nlat)           ! Surface pressure (Pa)
    real(8), intent(in) :: p_full(nlon, nlat, nlev) ! Pressure at full levels (Pa)
    real(8), intent(in) :: u(nlon, nlat, nlev)      ! Zonal wind (m/s)
    real(8), intent(in) :: v(nlon, nlat, nlev)      ! Meridional wind (m/s)
    real(8), intent(in) :: vkf                      ! Friction coefficient (1/s)
    real(8), intent(in) :: sigma_b                  ! Boundary layer top sigma
    real(8), intent(out) :: udt(nlon, nlat, nlev)   ! Zonal wind tendency (m/s^2)
    real(8), intent(out) :: vdt(nlon, nlat, nlev)   ! Meridional wind tendency (m/s^2)
    real(8), intent(in), optional :: mask(nlon, nlat, nlev)

    ! Local variables
    real(8) :: sigma(nlon, nlat)
    real(8) :: vfactr(nlon, nlat)
    real(8) :: rps(nlon, nlat)
    real(8) :: vcoeff
    integer :: k

    !-----------------------------------------------------------------------
    ! Compute damping
    !-----------------------------------------------------------------------

    vcoeff = -vkf / (1.0d0 - sigma_b)
    rps = 1.0d0 / ps

    do k = 1, nlev
      sigma(:,:) = p_full(:,:,k) * rps(:,:)

      where (sigma(:,:) <= 1.0d0 .and. sigma(:,:) > sigma_b)
        vfactr(:,:) = vcoeff * (sigma(:,:) - sigma_b)
        udt(:,:,k) = vfactr(:,:) * u(:,:,k)
        vdt(:,:,k) = vfactr(:,:) * v(:,:,k)
      elsewhere
        udt(:,:,k) = 0.0d0
        vdt(:,:,k) = 0.0d0
      endwhere
    enddo

    if (present(mask)) then
      udt = udt * mask
      vdt = vdt * mask
    endif

  end subroutine rayleigh_damping

end module rayleigh_damping_mod
