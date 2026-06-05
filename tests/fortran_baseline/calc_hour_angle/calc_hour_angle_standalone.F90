!-----------------------------------------------------------------------
! Standalone Calc Hour Angle Kernel
!
! Extracted from: src/atmos_param/hs_forcing/hs_forcing.F90 (lines 842-860)
! No FMS dependencies - pure intrinsics only.
!-----------------------------------------------------------------------

module calc_hour_angle_mod

  implicit none
  private
  public :: calc_hour_angle

contains

  !---------------------------------------------------------------------
  ! calc_hour_angle
  !
  ! Compute solar hour angle from latitude and solar declination.
  !
  ! The hour angle H satisfies: cos(H) = -tan(lat) * tan(dec)
  ! Clamped to [-1, 1] for polar night/day cases.
  !
  ! Arguments:
  !   nlon, nlat  - Grid dimensions
  !   lat         - Latitude (radians)              [nlon, nlat]
  !   dec         - Solar declination (radians)     scalar
  !   hour_angle  - Output hour angle (radians)     [nlon, nlat]
  !---------------------------------------------------------------------
  subroutine calc_hour_angle(nlon, nlat, lat, dec, hour_angle)

    integer, intent(in) :: nlon, nlat
    real(8), intent(in) :: dec
    real(8), intent(in), dimension(nlon, nlat) :: lat
    real(8), intent(out), dimension(nlon, nlat) :: hour_angle

    real(8), dimension(nlon, nlat) :: inv_hour_angle

    ! Compute argument to acos
    inv_hour_angle = -tan(lat(:,:)) * tan(dec)

    ! Clamp to [-1, 1] for acos domain
    where (inv_hour_angle > 1.0d0)
      inv_hour_angle = 1.0d0
    endwhere
    where (inv_hour_angle < -1.0d0)
      inv_hour_angle = -1.0d0
    endwhere

    ! Compute hour angle
    hour_angle = acos(inv_hour_angle)

  end subroutine calc_hour_angle

end module calc_hour_angle_mod
