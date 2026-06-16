! driver_xppm_fortran.f90 — original-Fortran xppm benchmark, for comparison
! against the C++ CPU and CUDA GPU drivers.
!
!   Usage: xppm-driver-fortran <resolution> <iterations> [levels]
!
! Calls the original tp_core_mod::xppm directly (not the full fv_tp_2d) over
! the SAME synthetic field and row count as driver_xppm_{cpu,gpu}:
! ncol = n*levels independent x-rows processed in one xppm call, in a timed
! loop. Single precision (default real), so the checksum cross-checks the
! C++/GPU drivers to floating-point tolerance.
program driver_xppm_fortran
  use tp_core_mod, only: xppm
  implicit none

  integer :: n, n_iter, levels, ncol
  integer :: is, ie, isd, ied, jfirst, jlast, jsd, jed, npx, npy
  integer :: it, argc, i, j
  integer, parameter :: iord = 8, grid_type = 0
  logical, parameter :: nested = .false.
  real :: lim_fac
  real, allocatable :: q(:,:), cc(:,:), dxa(:,:), flux(:,:)
  character(len=64) :: a1, a2, a3
  integer(8) :: c0, c1, crate
  real(8) :: secs, two_pi, csum

  argc = command_argument_count()
  if (argc < 2 .or. argc > 3) then
     write(*,*) 'Usage: xppm-driver-fortran <resolution> <iterations> [levels]'
     stop 2
  end if
  call get_command_argument(1, a1); read(a1,*) n
  call get_command_argument(2, a2); read(a2,*) n_iter
  levels = 1
  if (argc == 3) then
     call get_command_argument(3, a3); read(a3,*) levels
  end if

  lim_fac = 1.0
  is = 1; ie = n; isd = is - 3; ied = ie + 3
  ncol = n * levels
  jfirst = 1; jlast = ncol; jsd = jfirst - 3; jed = jlast + 3
  npx = n + 1; npy = n + 1

  allocate(q   (isd:ied,   jfirst:jlast))
  allocate(flux(is:ie+1,   jfirst:jlast))
  allocate(cc  (is:ie+1,   jfirst:jlast))
  allocate(dxa (isd:ied,   jsd:jed))

  two_pi = 6.283185307179586d0
  do j = jfirst, jlast
     do i = isd, ied
        q(i,j) = real(1.0d0 + 0.5d0 * cos(two_pi * real(i - isd, 8) / real(ied - isd + 1, 8)))
     end do
  end do
  cc   = 0.5
  dxa  = 1.0
  flux = 0.0

  call system_clock(c0, crate)
  do it = 1, n_iter
     call xppm(flux, q, cc, iord, is, ie, isd, ied, &
               jfirst, jlast, jsd, jed, npx, npy, dxa, nested, grid_type, lim_fac)
  end do
  call system_clock(c1)
  secs = real(c1 - c0, 8) / real(crate, 8)

  csum = 0.0d0
  do j = jfirst, jlast
     do i = is, ie + 1
        csum = csum + real(flux(i,j), 8)
     end do
  end do

  write(*,'(a,i0,a,i0,a,i0,a,i0)') 'xppm Fortran driver: resolution=', n, &
       ' iterations=', n_iter, ' levels=', levels, ' ncol=', ncol
  write(*,'(a,f12.6,a,f10.4,a,i0,a)') 'time taken: ', secs, ' s  (', &
       secs / real(n_iter,8) * 1000.0d0, ' ms/iter over ', n_iter, ' iters)'
  write(*,'(a,es18.10)') 'sum(flux): ', csum
end program driver_xppm_fortran
