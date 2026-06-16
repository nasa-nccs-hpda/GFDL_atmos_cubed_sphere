! driver_yppm_fortran.f90 — original-Fortran yppm benchmark, for comparison
! against the C++ CPU and CUDA GPU drivers.
!
!   Usage: yppm-driver-fortran <resolution> <iterations> [levels]
!
! Calls the original tp_core_mod::yppm directly (not the full fv_tp_2d) over
! the SAME synthetic field and column count as driver_yppm_{cpu,gpu}:
! ncol = (n+6)*levels independent y-columns processed in one yppm call, in a
! timed loop. Single precision (default real), so the checksum cross-checks
! the C++/GPU drivers to floating-point tolerance.
program driver_yppm_fortran
  use tp_core_mod, only: yppm
  implicit none

  integer :: n, n_iter, levels, ncol
  integer :: ifirst, ilast, isd, ied, js, je, jsd, jed, npx, npy
  integer :: it, argc, i, j
  integer, parameter :: jord = 8, grid_type = 0
  logical, parameter :: nested = .false.
  real :: lim_fac
  real, allocatable :: q(:,:), cry(:,:), dya(:,:), flux(:,:)
  character(len=64) :: a1, a2, a3
  integer(8) :: c0, c1, crate
  real(8) :: secs, two_pi, csum

  argc = command_argument_count()
  if (argc < 2 .or. argc > 3) then
     write(*,*) 'Usage: yppm-driver-fortran <resolution> <iterations> [levels]'
     stop 2
  end if
  call get_command_argument(1, a1); read(a1,*) n
  call get_command_argument(2, a2); read(a2,*) n_iter
  levels = 1
  if (argc == 3) then
     call get_command_argument(3, a3); read(a3,*) levels
  end if

  lim_fac = 1.0
  js = 1; je = n; jsd = js - 3; jed = je + 3
  npx = n + 1; npy = n + 1
  ncol = (n + 6) * levels
  ifirst = 1; ilast = ncol; isd = ifirst - 3; ied = ilast + 3

  allocate(q   (ifirst:ilast, jsd:jed))
  allocate(flux(ifirst:ilast, js:je+1))
  allocate(cry (isd:ied,      js:je+1))
  allocate(dya (isd:ied,      jsd:jed))

  two_pi = 6.283185307179586d0
  do j = jsd, jed
     do i = ifirst, ilast
        q(i,j) = real(1.0d0 + 0.5d0 * cos(two_pi * real(j - jsd, 8) / real(jed - jsd + 1, 8)))
     end do
  end do
  cry  = 0.5
  dya  = 1.0
  flux = 0.0

  call system_clock(c0, crate)
  do it = 1, n_iter
     call yppm(flux, q, cry, jord, ifirst, ilast, isd, ied, &
               js, je, jsd, jed, npx, npy, dya, nested, grid_type, lim_fac)
  end do
  call system_clock(c1)
  secs = real(c1 - c0, 8) / real(crate, 8)

  csum = 0.0d0
  do j = js, je + 1
     do i = ifirst, ilast
        csum = csum + real(flux(i,j), 8)
     end do
  end do

  write(*,'(a,i0,a,i0,a,i0,a,i0)') 'yppm Fortran driver: resolution=', n, &
       ' iterations=', n_iter, ' levels=', levels, ' ncol=', ncol
  write(*,'(a,f12.6,a,f10.4,a,i0,a)') 'time taken: ', secs, ' s  (', &
       secs / real(n_iter,8) * 1000.0d0, ' ms/iter over ', n_iter, ' iters)'
  write(*,'(a,es18.10)') 'sum(flux): ', csum
end program driver_yppm_fortran
