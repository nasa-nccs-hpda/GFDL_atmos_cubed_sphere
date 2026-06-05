!-----------------------------------------------------------------------
! Test Harness for Rayleigh Damping
!
! Generates synthetic test data, calls the kernel, and writes
! input/output arrays to binary files for validation against C++ port.
!-----------------------------------------------------------------------

program test_rayleigh_damping

  use rayleigh_damping_mod, only: rayleigh_damping

  implicit none

  ! Grid dimensions (small for testing)
  integer, parameter :: nlon = 8
  integer, parameter :: nlat = 4
  integer, parameter :: nlev = 5

  ! Physical constants
  real(8), parameter :: SECONDS_PER_DAY = 86400.0d0
  real(8), parameter :: P0 = 1.0d5  ! Reference pressure (Pa)

  ! Held-Suarez parameters
  real(8), parameter :: kf = 1.0d0  ! Friction timescale (days)
  real(8), parameter :: sigma_b = 0.7d0  ! Boundary layer top

  ! Derived parameter
  real(8) :: vkf  ! Friction coefficient (1/s)

  ! Arrays
  real(8) :: ps(nlon, nlat)
  real(8) :: p_full(nlon, nlat, nlev)
  real(8) :: u(nlon, nlat, nlev)
  real(8) :: v(nlon, nlat, nlev)
  real(8) :: udt(nlon, nlat, nlev)
  real(8) :: vdt(nlon, nlat, nlev)
  real(8) :: mask(nlon, nlat, nlev)

  ! Sigma levels (top to bottom)
  real(8) :: sigma_levels(nlev)

  ! Loop indices
  integer :: i, j, k

  !-----------------------------------------------------------------------
  ! Initialize parameters
  !-----------------------------------------------------------------------

  vkf = 1.0d0 / (SECONDS_PER_DAY * kf)

  ! Sigma levels spanning above and below boundary layer
  ! sigma_b = 0.7, so levels 1-2 are above, levels 3-5 are in boundary layer
  sigma_levels = (/ 0.2d0, 0.5d0, 0.75d0, 0.9d0, 1.0d0 /)

  write(*,*) '======================================'
  write(*,*) 'Rayleigh Damping Test Harness'
  write(*,*) '======================================'
  write(*,*) ''
  write(*,*) 'Grid dimensions:'
  write(*,*) '  nlon  =', nlon
  write(*,*) '  nlat  =', nlat
  write(*,*) '  nlev  =', nlev
  write(*,*) ''
  write(*,*) 'Parameters:'
  write(*,*) '  kf (days)    =', kf
  write(*,*) '  vkf (1/s)    =', vkf
  write(*,*) '  sigma_b      =', sigma_b
  write(*,*) ''
  write(*,*) 'Sigma levels:', sigma_levels
  write(*,*) ''

  !-----------------------------------------------------------------------
  ! Generate synthetic test data
  !-----------------------------------------------------------------------

  ! Surface pressure: slight variation around P0
  do j = 1, nlat
    do i = 1, nlon
      ps(i,j) = P0 * (1.0d0 + 0.01d0 * sin(2.0d0 * 3.14159d0 * real(i-1)/real(nlon)))
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

  ! Zonal wind: varies with latitude (jet-like structure)
  do k = 1, nlev
    do j = 1, nlat
      do i = 1, nlon
        u(i,j,k) = 20.0d0 * sin(3.14159d0 * real(j-1)/real(nlat-1))
      enddo
    enddo
  enddo

  ! Meridional wind: small perturbation
  do k = 1, nlev
    do j = 1, nlat
      do i = 1, nlon
        v(i,j,k) = 2.0d0 * cos(2.0d0 * 3.14159d0 * real(i-1)/real(nlon))
      enddo
    enddo
  enddo

  ! Mask: all ones (no masking for baseline test)
  mask = 1.0d0

  !-----------------------------------------------------------------------
  ! Call the kernel
  !-----------------------------------------------------------------------

  write(*,*) 'Calling rayleigh_damping...'

  call rayleigh_damping(nlon, nlat, nlev, ps, p_full, u, v, &
                        vkf, sigma_b, udt, vdt)

  write(*,*) 'Done.'
  write(*,*) ''

  !-----------------------------------------------------------------------
  ! Print summary statistics
  !-----------------------------------------------------------------------

  write(*,*) 'Results summary:'
  write(*,*) '  udt range: [', minval(udt), ',', maxval(udt), ']'
  write(*,*) '  vdt range: [', minval(vdt), ',', maxval(vdt), ']'
  write(*,*) ''

  ! Check expected behavior by level
  write(*,*) 'Per-level statistics:'
  do k = 1, nlev
    write(*,'(A,I2,A,F5.2,A,ES12.4,A,ES12.4)') &
      '  Level ', k, ' (sigma=', sigma_levels(k), &
      '): max|udt|=', maxval(abs(udt(:,:,k))), &
      ', max|vdt|=', maxval(abs(vdt(:,:,k)))
  enddo
  write(*,*) ''

  !-----------------------------------------------------------------------
  ! Write arrays to binary files
  !-----------------------------------------------------------------------

  write(*,*) 'Writing input/output arrays to files...'

  ! Write inputs
  call write_array_2d('input_ps.bin', ps, nlon, nlat)
  call write_array_3d('input_p_full.bin', p_full, nlon, nlat, nlev)
  call write_array_3d('input_u.bin', u, nlon, nlat, nlev)
  call write_array_3d('input_v.bin', v, nlon, nlat, nlev)

  ! Write parameters
  call write_params('params.bin', vkf, sigma_b, nlon, nlat, nlev)

  ! Write outputs
  call write_array_3d('output_udt.bin', udt, nlon, nlat, nlev)
  call write_array_3d('output_vdt.bin', vdt, nlon, nlat, nlev)

  write(*,*) 'Done. Files written:'
  write(*,*) '  input_ps.bin, input_p_full.bin, input_u.bin, input_v.bin'
  write(*,*) '  params.bin'
  write(*,*) '  output_udt.bin, output_vdt.bin'
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
  subroutine write_params(filename, vkf_val, sigma_b_val, n1, n2, n3)
    character(len=*), intent(in) :: filename
    real(8), intent(in) :: vkf_val, sigma_b_val
    integer, intent(in) :: n1, n2, n3
    integer :: unit_num

    unit_num = 20
    open(unit=unit_num, file=filename, form='unformatted', access='stream', status='replace')
    write(unit_num) n1, n2, n3
    write(unit_num) vkf_val, sigma_b_val
    close(unit_num)
  end subroutine write_params

end program test_rayleigh_damping
