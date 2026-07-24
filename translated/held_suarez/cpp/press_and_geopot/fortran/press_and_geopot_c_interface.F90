module press_and_geopot_c_interface
  use, intrinsic :: iso_c_binding, only: c_int, c_double, c_ptr, c_loc, c_null_ptr
  implicit none
  private

  public :: PRESS_GEOPOT_OPTION_SIMMONS_BURRIDGE
  public :: PRESS_GEOPOT_OPTION_MCM
  public :: press_geopot_cuda_init_wrapper
  public :: press_geopot_pressure_variables_cuda_wrapper
  public :: press_geopot_compute_geopotential_cuda_wrapper
  public :: press_geopot_cuda_finalize_wrapper
  public :: press_geopot_cuda_profile_print_wrapper

  integer(c_int), parameter :: PRESS_GEOPOT_OPTION_SIMMONS_BURRIDGE = 1_c_int
  integer(c_int), parameter :: PRESS_GEOPOT_OPTION_MCM = 2_c_int

  interface
    function press_geopot_cuda_init_c(nlev, pk, bk, rdgas, rvgas, use_virtual_temperature, vert_difference_option) &
        bind(C, name="press_geopot_cuda_init_c")
      use, intrinsic :: iso_c_binding
      integer(c_int), value :: nlev
      type(c_ptr), value :: pk, bk
      real(c_double), value :: rdgas, rvgas
      integer(c_int), value :: use_virtual_temperature
      integer(c_int), value :: vert_difference_option
      integer(c_int) :: press_geopot_cuda_init_c
    end function press_geopot_cuda_init_c

    function press_geopot_pressure_variables_cuda_c( &
        ni, nj, nlev, p_half, ln_p_half, p_full, ln_p_full, surface_p) &
        bind(C, name="press_geopot_pressure_variables_cuda_c")
      use, intrinsic :: iso_c_binding
      integer(c_int), value :: ni, nj, nlev
      type(c_ptr), value :: p_half, ln_p_half, p_full, ln_p_full, surface_p
      integer(c_int) :: press_geopot_pressure_variables_cuda_c
    end function press_geopot_pressure_variables_cuda_c

    function press_geopot_compute_geopotential_cuda_c( &
        ni, nj, nlev, t_grid, ln_p_half, ln_p_full, surf_geopotential, &
        geopot_full, geopot_half, q_grid, has_q_grid) &
        bind(C, name="press_geopot_compute_geopotential_cuda_c")
      use, intrinsic :: iso_c_binding
      integer(c_int), value :: ni, nj, nlev
      type(c_ptr), value :: t_grid, ln_p_half, ln_p_full, surf_geopotential
      type(c_ptr), value :: geopot_full, geopot_half, q_grid
      integer(c_int), value :: has_q_grid
      integer(c_int) :: press_geopot_compute_geopotential_cuda_c
    end function press_geopot_compute_geopotential_cuda_c

    subroutine press_geopot_cuda_finalize_c() bind(C, name="press_geopot_cuda_finalize_c")
      use, intrinsic :: iso_c_binding
    end subroutine press_geopot_cuda_finalize_c

    subroutine press_geopot_cuda_profile_print_c() bind(C, name="press_geopot_cuda_profile_print_c")
      use, intrinsic :: iso_c_binding
    end subroutine press_geopot_cuda_profile_print_c
  end interface

contains

  subroutine press_geopot_cuda_init_wrapper(pk, bk, rdgas, rvgas, use_virtual_temperature, vert_difference_option, ierr)
    real(c_double), intent(in), target :: pk(:), bk(:)
    real(c_double), intent(in) :: rdgas, rvgas
    logical, intent(in) :: use_virtual_temperature
    integer, intent(in) :: vert_difference_option
    integer, intent(out) :: ierr

    integer(c_int) :: use_virtual_temperature_c

    if (use_virtual_temperature) then
      use_virtual_temperature_c = 1_c_int
    else
      use_virtual_temperature_c = 0_c_int
    endif

    ierr = press_geopot_cuda_init_c( &
      int(size(pk) - 1, c_int), c_loc(pk(1)), c_loc(bk(1)), &
      rdgas, rvgas, use_virtual_temperature_c, int(vert_difference_option, c_int))
  end subroutine press_geopot_cuda_init_wrapper

  subroutine press_geopot_pressure_variables_cuda_wrapper( &
      p_half, ln_p_half, p_full, ln_p_full, surface_p, ierr)
    real(c_double), intent(out), target :: p_half(:,:,:), ln_p_half(:,:,:)
    real(c_double), intent(out), target :: p_full(:,:,:), ln_p_full(:,:,:)
    real(c_double), intent(in), target :: surface_p(:,:)
    integer, intent(out) :: ierr

    ierr = press_geopot_pressure_variables_cuda_c( &
      int(size(surface_p, 1), c_int), int(size(surface_p, 2), c_int), &
      int(size(p_full, 3), c_int), c_loc(p_half(1,1,1)), c_loc(ln_p_half(1,1,1)), &
      c_loc(p_full(1,1,1)), c_loc(ln_p_full(1,1,1)), c_loc(surface_p(1,1)))
  end subroutine press_geopot_pressure_variables_cuda_wrapper

  subroutine press_geopot_compute_geopotential_cuda_wrapper( &
      t_grid, ln_p_half, ln_p_full, surf_geopotential, geopot_full, geopot_half, ierr, q_grid)
    real(c_double), intent(in), target :: t_grid(:,:,:), ln_p_half(:,:,:), ln_p_full(:,:,:)
    real(c_double), intent(in), target :: surf_geopotential(:,:)
    real(c_double), intent(out), target :: geopot_full(:,:,:), geopot_half(:,:,:)
    integer, intent(out) :: ierr
    real(c_double), intent(in), optional, target :: q_grid(:,:,:)

    type(c_ptr) :: q_ptr
    integer(c_int) :: has_q_grid

    if (present(q_grid)) then
      q_ptr = c_loc(q_grid(1,1,1))
      has_q_grid = 1_c_int
    else
      q_ptr = c_null_ptr
      has_q_grid = 0_c_int
    endif

    ierr = press_geopot_compute_geopotential_cuda_c( &
      int(size(t_grid, 1), c_int), int(size(t_grid, 2), c_int), &
      int(size(t_grid, 3), c_int), c_loc(t_grid(1,1,1)), c_loc(ln_p_half(1,1,1)), &
      c_loc(ln_p_full(1,1,1)), c_loc(surf_geopotential(1,1)), &
      c_loc(geopot_full(1,1,1)), c_loc(geopot_half(1,1,1)), q_ptr, has_q_grid)
  end subroutine press_geopot_compute_geopotential_cuda_wrapper

  subroutine press_geopot_cuda_finalize_wrapper()
    call press_geopot_cuda_finalize_c()
  end subroutine press_geopot_cuda_finalize_wrapper

  subroutine press_geopot_cuda_profile_print_wrapper()
    call press_geopot_cuda_profile_print_c()
  end subroutine press_geopot_cuda_profile_print_wrapper

end module press_and_geopot_c_interface
