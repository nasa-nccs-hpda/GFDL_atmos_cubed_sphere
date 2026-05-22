! Unit tests for the yppm subroutine (Y-direction PPM flux computation).
!
! All tests use a doubly-periodic domain (nested=.true.) to avoid
! cubed-sphere boundary treatment, a single column in x, and uniform
! grid spacing (dya=1, lim_fac=1).
!
! Test summary:
!   1. Constant field, jord=8            -- flux == q
!   2. Constant field, jord=2            -- flux == q
!   3. Linear field, c=+0.5, jord=8     -- flux == j-0.75 (exact for linear)
!   4. Linear field, c=-0.5, jord=8     -- flux == j-0.25 (exact for linear)
!   5. Step function, jord=8            -- monotone limiter: no over/undershoot
!   6. Near-zero field, jord=-5         -- positive-definite: flux >= 0
!
program test_yppm

  use tp_core_mod, only: yppm

  implicit none

  integer :: n_failed = 0

  call test_constant_jord8(n_failed)
  call test_constant_jord2(n_failed)
  call test_linear_positive_courant(n_failed)
  call test_linear_negative_courant(n_failed)
  call test_monotone_bounds(n_failed)
  call test_positive_definite(n_failed)

  if (n_failed == 0) then
    print *, 'All tests PASSED'
    stop 0
  else
    print '(a,i0,a)', 'FAIL: ', n_failed, ' test(s) failed'
    stop 1
  end if

contains

  ! Print PASS/FAIL and accumulate failure count.
  subroutine assert(name, passed, n_failed)
    character(len=*), intent(in)    :: name
    logical,          intent(in)    :: passed
    integer,          intent(inout) :: n_failed
    if (passed) then
      print *, 'PASS: ', name
    else
      print *, 'FAIL: ', name
      n_failed = n_failed + 1
    end if
  end subroutine assert

  ! Compute index parameters for a doubly-periodic domain with one x-column.
  subroutine domain_params(n, ng, ifirst, ilast, isd, ied, js, je, jsd, jed, npx, npy)
    integer, intent(in)  :: n, ng
    integer, intent(out) :: ifirst, ilast, isd, ied, js, je, jsd, jed, npx, npy
    ifirst = 1;       ilast = 1
    isd    = ifirst - ng; ied = ilast + ng
    js     = 1;       je  = n
    jsd    = js - ng; jed = je + ng
    npx    = 2;       npy = n + 1
  end subroutine domain_params

  !---------------------------------------------------------------------------
  ! Test 1: Constant field, jord=8 (monotonic PPM).
  ! For q=const all reconstructed slopes are zero, so flux == q.
  !---------------------------------------------------------------------------
  subroutine test_constant_jord8(n_failed)
    integer, intent(inout) :: n_failed
    integer, parameter :: n=20, ng=3, jord=8
    integer :: ifirst, ilast, isd, ied, js, je, jsd, jed, npx, npy
    real, allocatable :: q(:,:), cry(:,:), flux(:,:), dya(:,:)
    logical :: nested = .true.
    integer :: grid_type = 0
    real    :: lim_fac = 1.0

    call domain_params(n, ng, ifirst, ilast, isd, ied, js, je, jsd, jed, npx, npy)
    allocate(q   (ifirst:ilast, jsd:jed),  source=1.0)
    allocate(cry (isd:ied,      js:je+1),  source=0.5)
    allocate(dya (isd:ied,      jsd:jed),  source=1.0)
    allocate(flux(ifirst:ilast, js:je+1))

    call yppm(flux, q, cry, jord, ifirst, ilast, isd, ied, &
              js, je, jsd, jed, npx, npy, dya, nested, grid_type, lim_fac)

    call assert('constant q=1, c=+0.5, jord=8: flux==1', &
                all(abs(flux - 1.0) < 1.e-6), n_failed)
    deallocate(q, cry, dya, flux)
  end subroutine test_constant_jord8

  !---------------------------------------------------------------------------
  ! Test 2: Constant field, jord=2 (perfectly linear scheme).
  ! For q=const the linear reconstruction also gives flux == q.
  !---------------------------------------------------------------------------
  subroutine test_constant_jord2(n_failed)
    integer, intent(inout) :: n_failed
    integer, parameter :: n=20, ng=3, jord=2
    integer :: ifirst, ilast, isd, ied, js, je, jsd, jed, npx, npy
    real, allocatable :: q(:,:), cry(:,:), flux(:,:), dya(:,:)
    logical :: nested = .true.
    integer :: grid_type = 0
    real    :: lim_fac = 1.0

    call domain_params(n, ng, ifirst, ilast, isd, ied, js, je, jsd, jed, npx, npy)
    allocate(q   (ifirst:ilast, jsd:jed),  source=1.0)
    allocate(cry (isd:ied,      js:je+1),  source=0.5)
    allocate(dya (isd:ied,      jsd:jed),  source=1.0)
    allocate(flux(ifirst:ilast, js:je+1))

    call yppm(flux, q, cry, jord, ifirst, ilast, isd, ied, &
              js, je, jsd, jed, npx, npy, dya, nested, grid_type, lim_fac)

    call assert('constant q=1, c=+0.5, jord=2: flux==1', &
                all(abs(flux - 1.0) < 1.e-6), n_failed)
    deallocate(q, cry, dya, flux)
  end subroutine test_constant_jord2

  !---------------------------------------------------------------------------
  ! Test 3: Linear field, jord=8, positive Courant number c=+0.5.
  ! PPM is exact on linear fields over a uniform grid.
  ! Analytical derivation (c > 0 branch, bl=-0.5, br=+0.5 everywhere):
  !   flux(j) = q(j-1) + (1-c)*(br(j-1) - c*(bl(j-1)+br(j-1)))
  !           = (j-1) + 0.5*(0.5 - 0)  =  j - 0.75
  !---------------------------------------------------------------------------
  subroutine test_linear_positive_courant(n_failed)
    integer, intent(inout) :: n_failed
    integer, parameter :: n=20, ng=3, jord=8
    integer :: ifirst, ilast, isd, ied, js, je, jsd, jed, npx, npy, i, j
    real, allocatable :: q(:,:), cry(:,:), flux(:,:), dya(:,:), expected(:,:)
    logical :: nested = .true.
    integer :: grid_type = 0
    real    :: lim_fac = 1.0

    call domain_params(n, ng, ifirst, ilast, isd, ied, js, je, jsd, jed, npx, npy)
    allocate(q       (ifirst:ilast, jsd:jed))
    allocate(cry     (isd:ied,      js:je+1), source=0.5)
    allocate(dya     (isd:ied,      jsd:jed), source=1.0)
    allocate(flux    (ifirst:ilast, js:je+1))
    allocate(expected(ifirst:ilast, js:je+1))

    do j = jsd, jed
      do i = ifirst, ilast
        q(i,j) = real(j)
      end do
    end do
    do j = js, je+1
      do i = ifirst, ilast
        expected(i,j) = real(j) - 0.75
      end do
    end do

    call yppm(flux, q, cry, jord, ifirst, ilast, isd, ied, &
              js, je, jsd, jed, npx, npy, dya, nested, grid_type, lim_fac)

    call assert('linear q=j, c=+0.5, jord=8: flux==j-0.75', &
                all(abs(flux - expected) < 1.e-5), n_failed)
    deallocate(q, cry, dya, flux, expected)
  end subroutine test_linear_positive_courant

  !---------------------------------------------------------------------------
  ! Test 4: Linear field, jord=8, negative Courant number c=-0.5.
  ! Analytical derivation (c < 0 branch, bl=-0.5, br=+0.5 everywhere):
  !   flux(j) = q(j) + (1+c)*(bl(j) + c*(bl(j)+br(j)))
  !           = j + 0.5*(-0.5 + 0)  =  j - 0.25
  !---------------------------------------------------------------------------
  subroutine test_linear_negative_courant(n_failed)
    integer, intent(inout) :: n_failed
    integer, parameter :: n=20, ng=3, jord=8
    integer :: ifirst, ilast, isd, ied, js, je, jsd, jed, npx, npy, i, j
    real, allocatable :: q(:,:), cry(:,:), flux(:,:), dya(:,:), expected(:,:)
    logical :: nested = .true.
    integer :: grid_type = 0
    real    :: lim_fac = 1.0

    call domain_params(n, ng, ifirst, ilast, isd, ied, js, je, jsd, jed, npx, npy)
    allocate(q       (ifirst:ilast, jsd:jed))
    allocate(cry     (isd:ied,      js:je+1), source=-0.5)
    allocate(dya     (isd:ied,      jsd:jed), source=1.0)
    allocate(flux    (ifirst:ilast, js:je+1))
    allocate(expected(ifirst:ilast, js:je+1))

    do j = jsd, jed
      do i = ifirst, ilast
        q(i,j) = real(j)
      end do
    end do
    do j = js, je+1
      do i = ifirst, ilast
        expected(i,j) = real(j) - 0.25
      end do
    end do

    call yppm(flux, q, cry, jord, ifirst, ilast, isd, ied, &
              js, je, jsd, jed, npx, npy, dya, nested, grid_type, lim_fac)

    call assert('linear q=j, c=-0.5, jord=8: flux==j-0.25', &
                all(abs(flux - expected) < 1.e-5), n_failed)
    deallocate(q, cry, dya, flux, expected)
  end subroutine test_linear_negative_courant

  !---------------------------------------------------------------------------
  ! Test 5: Step function, jord=8, c=+0.5.
  ! The monotone limiter prevents over- and undershoot.
  ! Checks:
  !   (a) all flux values are in [0, 1]
  !   (b) flux == 0 well below the step (upwind region is constant-0)
  !   (c) flux == 1 well above the step (upwind region is constant-1)
  !---------------------------------------------------------------------------
  subroutine test_monotone_bounds(n_failed)
    integer, intent(inout) :: n_failed
    integer, parameter :: n=20, ng=3, jord=8, mid=11
    integer :: ifirst, ilast, isd, ied, js, je, jsd, jed, npx, npy, i, j
    real, allocatable :: q(:,:), cry(:,:), flux(:,:), dya(:,:)
    logical :: nested = .true.
    integer :: grid_type = 0
    real    :: lim_fac = 1.0

    call domain_params(n, ng, ifirst, ilast, isd, ied, js, je, jsd, jed, npx, npy)
    allocate(q   (ifirst:ilast, jsd:jed))
    allocate(cry (isd:ied,      js:je+1), source=0.5)
    allocate(dya (isd:ied,      jsd:jed), source=1.0)
    allocate(flux(ifirst:ilast, js:je+1))

    do j = jsd, jed
      do i = ifirst, ilast
        q(i,j) = merge(0.0, 1.0, j < mid)
      end do
    end do

    call yppm(flux, q, cry, jord, ifirst, ilast, isd, ied, &
              js, je, jsd, jed, npx, npy, dya, nested, grid_type, lim_fac)

    call assert('step q, jord=8: 0 <= flux <= 1 (no overshoot)', &
                all(flux >= -1.e-6) .and. all(flux <= 1.0 + 1.e-6), n_failed)
    call assert('step q, jord=8: flux==0 far below step (faces 3..mid-3)', &
                all(abs(flux(ifirst:ilast, 3:mid-3)) < 1.e-6), n_failed)
    call assert('step q, jord=8: flux==1 far above step (faces mid+3..je+1)', &
                all(abs(flux(ifirst:ilast, mid+3:je+1) - 1.0) < 1.e-6), n_failed)
    deallocate(q, cry, dya, flux)
  end subroutine test_monotone_bounds

  !---------------------------------------------------------------------------
  ! Test 6: Near-zero positive field, jord=-5 (positive-definite limiter).
  ! The jord<0 branch enforces al>=0; the limiters preserve non-negativity.
  !---------------------------------------------------------------------------
  subroutine test_positive_definite(n_failed)
    integer, intent(inout) :: n_failed
    integer, parameter :: n=20, ng=3, jord=-5
    integer :: ifirst, ilast, isd, ied, js, je, jsd, jed, npx, npy
    real, allocatable :: q(:,:), cry(:,:), flux(:,:), dya(:,:)
    logical :: nested = .true.
    integer :: grid_type = 0
    real    :: lim_fac = 1.0

    call domain_params(n, ng, ifirst, ilast, isd, ied, js, je, jsd, jed, npx, npy)
    allocate(q   (ifirst:ilast, jsd:jed),  source=1.e-20)
    allocate(cry (isd:ied,      js:je+1),  source=0.5)
    allocate(dya (isd:ied,      jsd:jed),  source=1.0)
    allocate(flux(ifirst:ilast, js:je+1))

    call yppm(flux, q, cry, jord, ifirst, ilast, isd, ied, &
              js, je, jsd, jed, npx, npy, dya, nested, grid_type, lim_fac)

    call assert('near-zero q, jord=-5: all flux >= 0 (positive-definite)', &
                all(flux >= 0.0), n_failed)
    deallocate(q, cry, dya, flux)
  end subroutine test_positive_definite

end program test_yppm
