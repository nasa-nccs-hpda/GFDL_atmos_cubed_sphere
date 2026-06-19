program run_on_baseline
  use, intrinsic :: iso_c_binding, only: c_double
  use fv_advection_kernels_c_interface
  implicit none

  integer :: nx, ny, js, je, nz
  real(c_double) :: dx, dt
  logical :: monotone
  real(c_double), allocatable :: c(:), cc(:), dy(:), dy_plus(:), dy_minus(:)
  real(c_double), allocatable :: ua(:,:,:), uc(:,:,:), q_x(:,:,:), b_x(:,:,:)
  real(c_double), allocatable :: vc(:,:,:), q_sphere(:,:,:)
  real(c_double), allocatable :: semi_x_dq(:,:,:), slope_x_out(:,:,:)
  real(c_double), allocatable :: integer_flux_out(:,:,:), vanleer_x_dq_dt(:,:,:)
  real(c_double), allocatable :: slope_sphere_out(:,:,:), vanleer_sphere_dq_dt(:,:,:)
  character(len=32) :: backend
  character(len=32) :: suffix
  integer :: status
  integer :: j

  call get_environment_variable('FV_ADVECTION_KERNELS_BACKEND', backend, status=status)
  if (status /= 0 .or. len_trim(backend) == 0) backend = 'cpu'

  call read_params_text('inputs/params.txt', nx, ny, js, je, nz, monotone, dx, dt)

  allocate(c(js:je), cc(js:je+1), dy(js-1:je+1), dy_plus(js-1:je+1), dy_minus(js-1:je+1))
  allocate(ua(nx,js:je,nz), uc(nx,js:je,nz), q_x(nx,js:je,nz), b_x(nx,js:je,nz))
  allocate(vc(nx,js:je+1,nz), q_sphere(nx,js-2:je+2,nz))
  allocate(semi_x_dq(nx,js:je,nz), slope_x_out(nx,js:je,nz))
  allocate(integer_flux_out(nx,js:je,nz), vanleer_x_dq_dt(nx,js:je,nz))
  allocate(slope_sphere_out(nx,js-1:je+1,nz), vanleer_sphere_dq_dt(nx,js:je,nz))

  call read_array_1d('inputs/input_c.bin', c, js, je)
  call read_array_1d('inputs/input_cc.bin', cc, js, je + 1)
  call read_array_1d('inputs/input_dy.bin', dy, js - 1, je + 1)
  call read_array_1d('inputs/input_dy_plus.bin', dy_plus, js - 1, je + 1)
  call read_array_1d('inputs/input_dy_minus.bin', dy_minus, js - 1, je + 1)
  call read_array_3d('inputs/input_ua.bin', ua, nx, js, je, nz)
  call read_array_3d('inputs/input_uc.bin', uc, nx, js, je, nz)
  call read_array_3d('inputs/input_q_x.bin', q_x, nx, js, je, nz)
  call read_array_3d('inputs/input_q_sphere.bin', q_sphere, nx, js - 2, je + 2, nz)
  call read_array_3d('inputs/input_vc.bin', vc, nx, js, je + 1, nz)

  do j = js, je
    b_x(:,j,:) = ua(:,j,:)*dt/(dx*c(j))
  end do

  semi_x_dq = -999.0_c_double
  slope_x_out = -999.0_c_double
  integer_flux_out = -999.0_c_double
  vanleer_x_dq_dt = 0.013_c_double
  slope_sphere_out = -999.0_c_double
  vanleer_sphere_dq_dt = -0.021_c_double

  select case (trim(backend))
  case ('cpu')
    suffix = 'fortran_c'
    call semi_x_3d_cpp_wrapper(nx, js, je, nz, dt, dx, c, ua, q_x, semi_x_dq)
    call slope_x_cpp_wrapper(nx, js, je, nz, monotone, q_x, slope_x_out)
    call integer_flux_x_cpp_wrapper(nx, js, je, nz, b_x, q_x, integer_flux_out)
    call vanleer_x_3d_cpp_wrapper(nx, js, je, nz, dt, dx, c, monotone, uc, q_x, vanleer_x_dq_dt)
    call slope_sphere_cpp_wrapper(nx, js, je, nz, monotone, dy_plus, dy_minus, q_sphere, slope_sphere_out)
    call vanleer_sphere_3d_cpp_wrapper(nx, ny, js, je, nz, dt, monotone, c, cc, dy, &
      dy_plus, dy_minus, vc, q_sphere, vanleer_sphere_dq_dt)
  case ('cuda')
#ifdef USE_CUDA_FV_ADVECTION_KERNELS
    suffix = 'fortran_cuda_c'
    call semi_x_3d_cuda_wrapper(nx, js, je, nz, dt, dx, c, ua, q_x, semi_x_dq, status)
    call require_success(status, 'semi_x_3d_cuda_wrapper')
    call slope_x_cuda_wrapper(nx, js, je, nz, monotone, q_x, slope_x_out, status)
    call require_success(status, 'slope_x_cuda_wrapper')
    call integer_flux_x_cuda_wrapper(nx, js, je, nz, b_x, q_x, integer_flux_out, status)
    call require_success(status, 'integer_flux_x_cuda_wrapper')
    call vanleer_x_3d_cuda_wrapper(nx, js, je, nz, dt, dx, c, monotone, uc, q_x, vanleer_x_dq_dt, status)
    call require_success(status, 'vanleer_x_3d_cuda_wrapper')
    call slope_sphere_cuda_wrapper(nx, js, je, nz, monotone, dy_plus, dy_minus, q_sphere, slope_sphere_out, status)
    call require_success(status, 'slope_sphere_cuda_wrapper')
    call vanleer_sphere_3d_cuda_wrapper(nx, ny, js, je, nz, dt, monotone, c, cc, dy, &
      dy_plus, dy_minus, vc, q_sphere, vanleer_sphere_dq_dt, status)
    call require_success(status, 'vanleer_sphere_3d_cuda_wrapper')
#else
    write(*,'(a)') 'FV_ADVECTION_KERNELS_BACKEND=cuda requires BACKEND=cuda at build time.'
    stop 5
#endif
  case default
    write(*,'(a,a)') 'Unknown FV_ADVECTION_KERNELS_BACKEND=', trim(backend)
    stop 4
  end select

  call write_array_3d('outputs/output_semi_x_dq_' // trim(suffix) // '.bin', semi_x_dq, nx, js, je, nz)
  call write_array_3d('outputs/output_slope_x_' // trim(suffix) // '.bin', slope_x_out, nx, js, je, nz)
  call write_array_3d('outputs/output_integer_flux_x_' // trim(suffix) // '.bin', integer_flux_out, nx, js, je, nz)
  call write_array_3d('outputs/output_vanleer_x_dq_dt_' // trim(suffix) // '.bin', vanleer_x_dq_dt, nx, js, je, nz)
  call write_array_3d('outputs/output_slope_sphere_' // trim(suffix) // '.bin', slope_sphere_out, nx, js - 1, je + 1, nz)
  call write_array_3d('outputs/output_vanleer_sphere_dq_dt_' // trim(suffix) // '.bin', &
    vanleer_sphere_dq_dt, nx, js, je, nz)

  write(*,'(a,a)') 'fv_advection kernel Fortran C-wrapper fixture complete. backend=', trim(backend)
  write(*,'(a,5(i0,1x),a,f8.3)') 'dims nx/ny/js/je/nz=', nx, ny, js, je, nz, ' dt=', dt

contains

  subroutine require_success(ierr, name)
    integer, intent(in) :: ierr
    character(len=*), intent(in) :: name
    if (ierr /= 0) then
      write(*,'(a,a,a,i0)') trim(name), ' failed with status ', '', ierr
      stop 7
    end if
  end subroutine require_success

  subroutine read_params_text(filename, nx_out, ny_out, js_out, je_out, nz_out, monotone_out, dx_out, dt_out)
    character(len=*), intent(in) :: filename
    integer, intent(out) :: nx_out, ny_out, js_out, je_out, nz_out
    logical, intent(out) :: monotone_out
    real(c_double), intent(out) :: dx_out, dt_out
    character(len=256) :: line, key, value
    integer :: unit_num, eq_pos

    open(newunit=unit_num, file=filename, status='old', action='read')
    do
      read(unit_num, '(A)', end=100) line
      eq_pos = index(line, '=')
      if (eq_pos <= 0) cycle
      key = adjustl(line(1:eq_pos-1))
      value = adjustl(line(eq_pos+1:))
      select case (trim(key))
      case ('nx')
        read(value,*) nx_out
      case ('ny')
        read(value,*) ny_out
      case ('js')
        read(value,*) js_out
      case ('je')
        read(value,*) je_out
      case ('nz')
        read(value,*) nz_out
      case ('monotone')
        read(value,*) monotone_out
      case ('dx')
        read(value,*) dx_out
      case ('dt')
        read(value,*) dt_out
      end select
    end do
100 continue
    close(unit_num)
  end subroutine read_params_text

  subroutine read_array_1d(filename, arr, lo, hi)
    character(len=*), intent(in) :: filename
    integer, intent(in) :: lo, hi
    real(c_double), intent(out) :: arr(lo:hi)
    integer :: unit_num
    open(newunit=unit_num, file=filename, form='unformatted', access='stream', status='old')
    read(unit_num) arr
    close(unit_num)
  end subroutine read_array_1d

  subroutine read_array_3d(filename, arr, n1, jlo, jhi, n3)
    character(len=*), intent(in) :: filename
    integer, intent(in) :: n1, jlo, jhi, n3
    real(c_double), intent(out) :: arr(n1,jlo:jhi,n3)
    integer :: unit_num
    open(newunit=unit_num, file=filename, form='unformatted', access='stream', status='old')
    read(unit_num) arr
    close(unit_num)
  end subroutine read_array_3d

  subroutine write_array_3d(filename, arr, n1, jlo, jhi, n3)
    character(len=*), intent(in) :: filename
    integer, intent(in) :: n1, jlo, jhi, n3
    real(c_double), intent(in) :: arr(n1,jlo:jhi,n3)
    integer :: unit_num
    open(newunit=unit_num, file=filename, form='unformatted', access='stream', status='replace')
    write(unit_num) arr
    close(unit_num)
  end subroutine write_array_3d

end program run_on_baseline
