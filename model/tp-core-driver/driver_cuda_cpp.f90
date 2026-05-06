module driver_cuda_cpp_mod

  use iso_c_binding, only: c_float, c_int
  use tp_core_mod, only: fv_tp_2d
  use fv_arrays_mod, only: fv_grid_bounds_type, fv_grid_type
  use input_arrays_mod, only: InputArrays_T
  use output_arrays_mod, only: OutputArrays_T

  implicit none

  private
  public :: run_driver_cuda_cpp

  integer, parameter :: hord = 8
  real, parameter :: lim_fac = 1.0
  real, parameter :: validation_tol = 1.0e-4

  interface
    subroutine fv_tp_2d_cuda_cpp(q, crx, cry, xfx, yfx, dxa, dya, area, ra_x, ra_y, fx, fy, &
                                 npx, npy, is, ie, js, je, isd, ied, jsd, jed, n_iterations) &
        bind(C, name='fv_tp_2d_cuda_cpp')
      import :: c_float, c_int
      real(c_float) :: q(*)
      real(c_float), intent(in) :: crx(*), cry(*), xfx(*), yfx(*)
      real(c_float), intent(in) :: dxa(*), dya(*), area(*), ra_x(*), ra_y(*)
      real(c_float) :: fx(*), fy(*)
      integer(c_int), value :: npx, npy, is, ie, js, je, isd, ied, jsd, jed, n_iterations
    end subroutine fv_tp_2d_cuda_cpp
  end interface

contains

  subroutine run_driver_cuda_cpp() bind(C, name='run_driver_cuda_cpp')

    type(fv_grid_bounds_type) :: bd
    type(fv_grid_type) :: gridstruct
    type(InputArrays_T) :: in_arrays
    type(OutputArrays_T) :: cpu_arrays, gpu_arrays
    real, allocatable :: q_cpu(:, :), q_gpu(:, :)
    real, allocatable :: crx_full(:, :), cry_full(:, :)
    real, allocatable :: xfx_full(:, :), yfx_full(:, :)
    real, allocatable :: ra_x_full(:, :), ra_y_full(:, :)
    integer :: npx, npy, iter
    integer :: n, n_iterations
    integer :: clock_start, clock_finish, clock_rate
    real :: cpu_time_s, gpu_time_s
    real :: max_fx, max_fy

    call get_cmdline_args_(n, n_iterations)

    bd = fv_grid_bounds_type(n)
    npx = n + 1
    npy = n + 1
    gridstruct = fv_grid_type(bd, npx, npy, .false., 0)
    in_arrays = InputArrays_T(bd, npx, npy, gridstruct)
    cpu_arrays = OutputArrays_T(bd)
    gpu_arrays = OutputArrays_T(bd)

    allocate(q_cpu(bd%isd:bd%ied, bd%jsd:bd%jed))
    allocate(q_gpu(bd%isd:bd%ied, bd%jsd:bd%jed))
    allocate(crx_full(bd%isd:bd%ied, bd%jsd:bd%jed), source=0.0)
    allocate(cry_full(bd%isd:bd%ied, bd%jsd:bd%jed), source=0.0)
    allocate(xfx_full(bd%isd:bd%ied, bd%jsd:bd%jed), source=0.0)
    allocate(yfx_full(bd%isd:bd%ied, bd%jsd:bd%jed), source=0.0)
    allocate(ra_x_full(bd%isd:bd%ied, bd%jsd:bd%jed), source=1.0)
    allocate(ra_y_full(bd%isd:bd%ied, bd%jsd:bd%jed), source=1.0)

    crx_full(bd%is:bd%ie+1, bd%jsd:bd%jed) = in_arrays%crx
    cry_full(bd%isd:bd%ied, bd%js:bd%je+1) = in_arrays%cry
    xfx_full(bd%is:bd%ie+1, bd%jsd:bd%jed) = in_arrays%xfx
    yfx_full(bd%isd:bd%ied, bd%js:bd%je+1) = in_arrays%yfx
    ra_x_full(bd%is:bd%ie, bd%jsd:bd%jed) = in_arrays%ra_x
    ra_y_full(bd%isd:bd%ied, bd%js:bd%je) = in_arrays%ra_y

    q_cpu = in_arrays%q
    q_gpu = in_arrays%q

    call system_clock(count_rate=clock_rate)
    call system_clock(clock_start)
    do iter = 1, n_iterations
      call fv_tp_2d(q_cpu, in_arrays%crx, in_arrays%cry, npx, npy, hord, &
           cpu_arrays%fx, cpu_arrays%fy, in_arrays%xfx, in_arrays%yfx, &
           gridstruct, bd, in_arrays%ra_x, in_arrays%ra_y, lim_fac)
    end do
    call system_clock(clock_finish)
    cpu_time_s = real(clock_finish - clock_start) / real(clock_rate)

    call system_clock(clock_start)
    call fv_tp_2d_cuda_cpp(q_gpu, crx_full, cry_full, xfx_full, yfx_full, &
         gridstruct%dxa, gridstruct%dya, gridstruct%area, ra_x_full, ra_y_full, &
         gpu_arrays%fx, gpu_arrays%fy, npx, npy, bd%is, bd%ie, bd%js, bd%je, &
         bd%isd, bd%ied, bd%jsd, bd%jed, n_iterations)
    call system_clock(clock_finish)
    gpu_time_s = real(clock_finish - clock_start) / real(clock_rate)

    max_fx = maxval(abs(cpu_arrays%fx - gpu_arrays%fx))
    max_fy = maxval(abs(cpu_arrays%fy - gpu_arrays%fy))

    print *, 'CPU time: ', cpu_time_s, 's'
    print *, 'CUDA C++ time: ', gpu_time_s, 's'
    print *, 'speedup: ', cpu_time_s / gpu_time_s
    print *, 'CPU sum(fx): ', sum(cpu_arrays%fx), ', sum(fy): ', sum(cpu_arrays%fy)
    print *, 'CUDA C++ sum(fx): ', sum(gpu_arrays%fx), ', sum(fy): ', sum(gpu_arrays%fy)
    print *, 'max abs diff fx: ', max_fx
    print *, 'max abs diff fy: ', max_fy
    print *, 'validation tolerance: ', validation_tol

    if (max_fx > validation_tol .or. max_fy > validation_tol) then
      error stop 'CUDA C++ validation failed'
    end if

  end subroutine run_driver_cuda_cpp

  subroutine usage(program_name)
    character(len=256), intent(in) :: program_name

    print *, 'Usage: ', trim(program_name), ' <resolution> <number-of-iterations>'
  end subroutine usage

  subroutine get_cmdline_args_(resolution, n_iterations)
    integer, intent(out) :: resolution
    integer, intent(out) :: n_iterations
    integer :: argc
    character(len=256) :: program_name, res_char, niter_char

    call get_command_argument(0, program_name)
    argc = command_argument_count()
    if (argc /= 2) then
      call usage(program_name)
      error stop 'ERROR: cmdline argument count is incorrect'
    end if
    call get_command_argument(1, res_char)
    read(res_char, *) resolution
    call get_command_argument(2, niter_char)
    read(niter_char, *) n_iterations
  end subroutine get_cmdline_args_

end module driver_cuda_cpp_mod

