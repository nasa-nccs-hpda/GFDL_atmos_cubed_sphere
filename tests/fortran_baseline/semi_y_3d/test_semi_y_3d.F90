module semi_y_3d_baseline_mod

  implicit none

  integer :: nx, js, je, nz
  real(8), allocatable :: dyy(:)

contains

  subroutine semi_y_3d_baseline_init(nx_in, js_in, je_in, nz_in, dyy_in)
    integer, intent(in) :: nx_in, js_in, je_in, nz_in
    real(8), intent(in) :: dyy_in(js_in:je_in+1)

    nx = nx_in
    js = js_in
    je = je_in
    nz = nz_in

    if (allocated(dyy)) deallocate(dyy)
    allocate(dyy(js:je+1))
    dyy(js:je+1) = dyy_in(js:je+1)
  end subroutine semi_y_3d_baseline_init

  ! Test-only copy of fv_advection_mod::semi_y_3d from
  ! src/atmos_spectral/model/fv_advection.F90.  The production routine is
  ! private, so this harness preserves the original local body without
  ! modifying or exposing production source.
  subroutine semi_y_3d(dq, va, qx, dt)

    real(8), intent(out), dimension(:,js  :,:) :: dq
    real(8), intent(in),  dimension(:,js  :,:) :: va
    real(8), intent(in),  dimension(:,js-2:,:) :: qx
    real(8), intent(in)                        :: dt

    integer :: j

    do j = js, je
      where (va(:,j,:) >= 0.0d0)
        dq(:,j,:) = va(:,j,:)*dt*(qx(:,j-1,:) - qx(:,j  ,:))/dyy(j)
      elsewhere
        dq(:,j,:) = va(:,j,:)*dt*(qx(:,j  ,:) - qx(:,j+1,:))/dyy(j+1)
      end where
    enddo

    return
  end subroutine semi_y_3d

end module semi_y_3d_baseline_mod

program test_semi_y_3d

  use semi_y_3d_baseline_mod, only: semi_y_3d_baseline_init, semi_y_3d

  implicit none

  integer, parameter :: nx_l = 8
  integer, parameter :: js_l = 2
  integer, parameter :: je_l = 6
  integer, parameter :: nz_l = 3
  integer, parameter :: qx_jlo = js_l - 2
  integer, parameter :: qx_jhi = je_l + 2

  real(8), parameter :: dt = 37.5d0

  real(8) :: va(nx_l, js_l:je_l, nz_l)
  real(8) :: qx(nx_l, qx_jlo:qx_jhi, nz_l)
  real(8) :: dyy(js_l:je_l+1)
  real(8) :: dq(nx_l, js_l:je_l, nz_l)

  integer :: i, j, k

  call create_dirs()

  do j = js_l, je_l + 1
    dyy(j) = 0.17d0 + 0.015d0 * dble(j - js_l)
  end do

  do k = 1, nz_l
    do j = qx_jlo, qx_jhi
      do i = 1, nx_l
        qx(i,j,k) = 10.0d0 + 0.7d0*dble(i) - 0.4d0*dble(j) + &
                    1.25d0*dble(k) + 0.03d0*dble(i*j) - 0.02d0*dble(j*k)
      end do
    end do
  end do

  do k = 1, nz_l
    do j = js_l, je_l
      do i = 1, nx_l
        va(i,j,k) = 0.08d0 * dble(i - 4) - 0.05d0 * dble(j - js_l) + &
                    0.03d0 * dble(k - 2)
      end do
    end do
  end do

  ! Force exact zeros to verify the Fortran >= 0.0 branch.
  va(4, js_l, 2) = 0.0d0
  va(7, je_l, 1) = 0.0d0

  dq = -999.0d0

  call semi_y_3d_baseline_init(nx_l, js_l, je_l, nz_l, dyy)
  call semi_y_3d(dq, va, qx, dt)

  call write_params('inputs/params.bin', nx_l, js_l, je_l, nz_l, qx_jlo, qx_jhi, dt)
  call write_array_1d_bounds('inputs/input_dyy.bin', dyy, js_l, je_l + 1)
  call write_array_3d_bounds('inputs/input_va.bin', va, nx_l, js_l, je_l, nz_l)
  call write_array_3d_bounds('inputs/input_qx.bin', qx, nx_l, qx_jlo, qx_jhi, nz_l)
  call write_array_3d_bounds('outputs/output_dq.bin', dq, nx_l, js_l, je_l, nz_l)

  write(*,'(a)') 'semi_y_3d Fortran baseline complete.'
  write(*,'(a,4(i0,1x),a,i0,a,i0,a,f8.3)') 'dims nx/js/je/nz=', nx_l, js_l, je_l, nz_l, &
       ' qx_jlo=', qx_jlo, ' qx_jhi=', qx_jhi, ' dt=', dt
  write(*,'(a,es18.10,a,es18.10)') 'dq min=', minval(dq), ' max=', maxval(dq)

contains

  subroutine create_dirs()
    logical :: exist_inputs, exist_outputs
    inquire(file='inputs', exist=exist_inputs)
    if (.not. exist_inputs) call execute_command_line('mkdir -p inputs')
    inquire(file='outputs', exist=exist_outputs)
    if (.not. exist_outputs) call execute_command_line('mkdir -p outputs')
  end subroutine create_dirs

  subroutine write_params(filename, nx_v, js_v, je_v, nz_v, qx_jlo_v, qx_jhi_v, dt_v)
    character(len=*), intent(in) :: filename
    integer, intent(in) :: nx_v, js_v, je_v, nz_v, qx_jlo_v, qx_jhi_v
    real(8), intent(in) :: dt_v
    integer :: unit_num

    unit_num = 20
    open(unit=unit_num, file=filename, form='unformatted', access='stream', status='replace')
    write(unit_num) nx_v, js_v, je_v, nz_v, qx_jlo_v, qx_jhi_v
    write(unit_num) dt_v
    close(unit_num)
  end subroutine write_params

  subroutine write_array_1d_bounds(filename, arr, lo, hi)
    character(len=*), intent(in) :: filename
    integer, intent(in) :: lo, hi
    real(8), intent(in) :: arr(lo:hi)
    integer :: unit_num

    unit_num = 21
    open(unit=unit_num, file=filename, form='unformatted', access='stream', status='replace')
    write(unit_num) arr
    close(unit_num)
  end subroutine write_array_1d_bounds

  subroutine write_array_3d_bounds(filename, arr, n1, jlo, jhi, n3)
    character(len=*), intent(in) :: filename
    integer, intent(in) :: n1, jlo, jhi, n3
    real(8), intent(in) :: arr(n1,jlo:jhi,n3)
    integer :: unit_num

    unit_num = 22
    open(unit=unit_num, file=filename, form='unformatted', access='stream', status='replace')
    write(unit_num) arr
    close(unit_num)
  end subroutine write_array_3d_bounds

end program test_semi_y_3d
