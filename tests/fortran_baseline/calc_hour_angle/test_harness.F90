!-----------------------------------------------------------------------
! Test Harness for Calc Hour Angle
!
! Generates synthetic test data, calls the kernel, and writes
! input/output arrays to binary files for validation against C++ port.
!-----------------------------------------------------------------------

program test_calc_hour_angle

  use calc_hour_angle_mod, only: calc_hour_angle

  implicit none

  ! Grid dimensions
  integer, parameter :: nlon = 8
  integer, parameter :: nlat = 6

  ! Mathematical constant
  real(8), parameter :: PI = 3.14159265358979323846d0

  ! Solar declination for summer solstice (~23.44 degrees)
  real(8), parameter :: dec = 23.44d0 * PI / 180.0d0

  ! Arrays
  real(8) :: lat(nlon, nlat)
  real(8) :: hour_angle(nlon, nlat)

  ! Latitude values (radians) - spanning -80 to +80 degrees
  real(8) :: lat_degrees(nlat)

  ! Loop indices
  integer :: i, j

  !-----------------------------------------------------------------------
  ! Initialize latitude array
  !-----------------------------------------------------------------------

  ! Latitude values in degrees: -80, -48, -16, 16, 48, 80
  ! This covers polar, mid-latitude, and tropical regions
  lat_degrees = (/ -80.0d0, -48.0d0, -16.0d0, 16.0d0, 48.0d0, 80.0d0 /)

  write(*,*) '======================================'
  write(*,*) 'Calc Hour Angle Test Harness'
  write(*,*) '======================================'
  write(*,*) ''
  write(*,*) 'Grid dimensions:'
  write(*,*) '  nlon  =', nlon
  write(*,*) '  nlat  =', nlat
  write(*,*) ''
  write(*,*) 'Solar declination:'
  write(*,*) '  dec (degrees) =', dec * 180.0d0 / PI
  write(*,*) '  dec (radians) =', dec
  write(*,*) ''
  write(*,*) 'Latitude values (degrees):', lat_degrees
  write(*,*) ''

  !-----------------------------------------------------------------------
  ! Generate latitude field
  ! Each longitude has same latitude (zonal symmetry)
  !-----------------------------------------------------------------------

  do j = 1, nlat
    do i = 1, nlon
      lat(i,j) = lat_degrees(j) * PI / 180.0d0
    enddo
  enddo

  !-----------------------------------------------------------------------
  ! Call the kernel
  !-----------------------------------------------------------------------

  write(*,*) 'Calling calc_hour_angle...'

  call calc_hour_angle(nlon, nlat, lat, dec, hour_angle)

  write(*,*) 'Done.'
  write(*,*) ''

  !-----------------------------------------------------------------------
  ! Print results
  !-----------------------------------------------------------------------

  write(*,*) 'Results summary:'
  write(*,*) '  hour_angle range: [', minval(hour_angle), ',', maxval(hour_angle), '] rad'
  write(*,*) '  hour_angle range: [', minval(hour_angle)*180.0d0/PI, ',', &
             maxval(hour_angle)*180.0d0/PI, '] deg'
  write(*,*) ''

  write(*,*) 'Per-latitude results (hour angle in degrees):'
  do j = 1, nlat
    write(*,'(A,F7.2,A,F10.4,A)') '  lat=', lat_degrees(j), ' deg: hour_angle=', &
         hour_angle(1,j)*180.0d0/PI, ' deg'
  enddo
  write(*,*) ''

  ! Physical interpretation
  write(*,*) 'Day length (hours) = 2 * hour_angle / (15 deg/hour):'
  do j = 1, nlat
    write(*,'(A,F7.2,A,F6.2,A)') '  lat=', lat_degrees(j), ' deg: day_length=', &
         2.0d0 * hour_angle(1,j) * 180.0d0 / PI / 15.0d0, ' hours'
  enddo
  write(*,*) ''

  !-----------------------------------------------------------------------
  ! Write arrays to binary files
  !-----------------------------------------------------------------------

  write(*,*) 'Writing input/output arrays to files...'

  ! Write inputs
  call write_array_2d('input_lat.bin', lat, nlon, nlat)
  call write_scalar('input_dec.bin', dec)

  ! Write parameters
  call write_params('params.bin', nlon, nlat)

  ! Write outputs
  call write_array_2d('output_hour_angle.bin', hour_angle, nlon, nlat)

  write(*,*) 'Done. Files written:'
  write(*,*) '  input_lat.bin, input_dec.bin'
  write(*,*) '  params.bin'
  write(*,*) '  output_hour_angle.bin'
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
  subroutine write_scalar(filename, val)
    character(len=*), intent(in) :: filename
    real(8), intent(in) :: val
    integer :: unit_num

    unit_num = 20
    open(unit=unit_num, file=filename, form='unformatted', access='stream', status='replace')
    write(unit_num) val
    close(unit_num)
  end subroutine write_scalar

  !-----------------------------------------------------------------------
  subroutine write_params(filename, n1, n2)
    character(len=*), intent(in) :: filename
    integer, intent(in) :: n1, n2
    integer :: unit_num

    unit_num = 20
    open(unit=unit_num, file=filename, form='unformatted', access='stream', status='replace')
    write(unit_num) n1, n2
    close(unit_num)
  end subroutine write_params

end program test_calc_hour_angle
