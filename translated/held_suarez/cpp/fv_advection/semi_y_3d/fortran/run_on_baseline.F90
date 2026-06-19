program run_on_baseline
  use, intrinsic :: iso_c_binding, only: c_double, c_int
  use semi_y_3d_c_interface, only: semi_y_3d_cpp_wrapper
#ifdef USE_CUDA_SEMI_Y_3D
  use semi_y_3d_c_interface, only: semi_y_3d_cuda_wrapper
#endif
  implicit none

  integer(c_int) :: dims(6)
  integer :: nx, js, je, nz, qx_jlo, qx_jhi
  real(c_double) :: dt
  real(c_double), allocatable :: dyy(:)
  real(c_double), allocatable :: va(:,:,:)
  real(c_double), allocatable :: qx(:,:,:)
  real(c_double), allocatable :: dq(:,:,:)
  character(len=32) :: backend
  integer :: status

  call get_environment_variable('SEMI_Y_3D_BACKEND', backend, status=status)
  if (status /= 0 .or. len_trim(backend) == 0) backend = 'cpu'

  call read_params('inputs/params.bin', dims, dt)
  nx = int(dims(1))
  js = int(dims(2))
  je = int(dims(3))
  nz = int(dims(4))
  qx_jlo = int(dims(5))
  qx_jhi = int(dims(6))

  if (qx_jlo /= js - 2 .or. qx_jhi /= je + 2) then
    write(*,'(a)') 'Unexpected qx bounds in fixture.'
    stop 2
  end if

  allocate(dyy(js:je+1))
  allocate(va(nx, js:je, nz))
  allocate(qx(nx, qx_jlo:qx_jhi, nz))
  allocate(dq(nx, js:je, nz))

  call read_array_1d('inputs/input_dyy.bin', dyy, js, je + 1)
  call read_array_3d('inputs/input_va.bin', va, nx, js, je, nz)
  call read_array_3d('inputs/input_qx.bin', qx, nx, qx_jlo, qx_jhi, nz)

  dq = -999.0_c_double
  select case (trim(backend))
  case ('cpu')
    call semi_y_3d_cpp_wrapper(nx, js, je, nz, dt, va, qx, dyy, dq)
    call write_array_3d('outputs/output_dq_fortran_c.bin', dq, nx, js, je, nz)
  case ('cuda')
#ifdef USE_CUDA_SEMI_Y_3D
    call semi_y_3d_cuda_wrapper(nx, js, je, nz, dt, va, qx, dyy, dq, status)
    if (status /= 0) then
      write(*,'(a,i0)') 'semi_y_3d CUDA wrapper failed with status ', status
      stop 3
    end if
    call write_array_3d('outputs/output_dq_fortran_cuda_c.bin', dq, nx, js, je, nz)
#else
    write(*,'(a)') 'SEMI_Y_3D_BACKEND=cuda requires BACKEND=cuda at build time.'
    stop 5
#endif
  case default
    write(*,'(a,a)') 'Unknown SEMI_Y_3D_BACKEND=', trim(backend)
    stop 4
  end select

  write(*,'(a,a)') 'semi_y_3d Fortran C-wrapper fixture complete. backend=', trim(backend)
  write(*,'(a,4(i0,1x),a,i0,a,i0,a,f8.3)') 'dims nx/js/je/nz=', nx, js, je, nz, &
       ' qx_jlo=', qx_jlo, ' qx_jhi=', qx_jhi, ' dt=', dt
  write(*,'(a,es18.10,a,es18.10)') 'dq min=', minval(dq), ' max=', maxval(dq)

contains

  subroutine read_params(filename, dims_out, dt_out)
    character(len=*), intent(in) :: filename
    integer(c_int), intent(out) :: dims_out(6)
    real(c_double), intent(out) :: dt_out
    integer :: unit_num

    unit_num = 31
    open(unit=unit_num, file=filename, form='unformatted', access='stream', status='old')
    read(unit_num) dims_out
    read(unit_num) dt_out
    close(unit_num)
  end subroutine read_params

  subroutine read_array_1d(filename, arr, lo, hi)
    character(len=*), intent(in) :: filename
    integer, intent(in) :: lo, hi
    real(c_double), intent(out) :: arr(lo:hi)
    integer :: unit_num

    unit_num = 32
    open(unit=unit_num, file=filename, form='unformatted', access='stream', status='old')
    read(unit_num) arr
    close(unit_num)
  end subroutine read_array_1d

  subroutine read_array_3d(filename, arr, n1, jlo, jhi, n3)
    character(len=*), intent(in) :: filename
    integer, intent(in) :: n1, jlo, jhi, n3
    real(c_double), intent(out) :: arr(n1, jlo:jhi, n3)
    integer :: unit_num

    unit_num = 33
    open(unit=unit_num, file=filename, form='unformatted', access='stream', status='old')
    read(unit_num) arr
    close(unit_num)
  end subroutine read_array_3d

  subroutine write_array_3d(filename, arr, n1, jlo, jhi, n3)
    character(len=*), intent(in) :: filename
    integer, intent(in) :: n1, jlo, jhi, n3
    real(c_double), intent(in) :: arr(n1, jlo:jhi, n3)
    integer :: unit_num

    unit_num = 34
    open(unit=unit_num, file=filename, form='unformatted', access='stream', status='replace')
    write(unit_num) arr
    close(unit_num)
  end subroutine write_array_3d

end program run_on_baseline
