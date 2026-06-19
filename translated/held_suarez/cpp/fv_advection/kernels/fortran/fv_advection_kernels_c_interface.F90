module fv_advection_kernels_c_interface
  use, intrinsic :: iso_c_binding, only: c_double, c_int, c_loc, c_ptr
  implicit none
  private

  public :: semi_x_3d_cpp_wrapper
  public :: slope_x_cpp_wrapper
  public :: integer_flux_x_cpp_wrapper
  public :: vanleer_x_3d_cpp_wrapper
  public :: slope_sphere_cpp_wrapper
  public :: vanleer_sphere_3d_cpp_wrapper
#ifdef USE_CUDA_FV_ADVECTION_KERNELS
  public :: semi_x_3d_cuda_wrapper
  public :: slope_x_cuda_wrapper
  public :: integer_flux_x_cuda_wrapper
  public :: vanleer_x_3d_cuda_wrapper
  public :: slope_sphere_cuda_wrapper
  public :: vanleer_sphere_3d_cuda_wrapper
#endif

  interface
    subroutine fv_semi_x_3d_c(nx, js, je, nz, dt, dx, c, ua, q, dq) bind(C, name='fv_semi_x_3d_c')
      use, intrinsic :: iso_c_binding, only: c_double, c_int, c_ptr
      integer(c_int), value :: nx, js, je, nz
      real(c_double), value :: dt, dx
      type(c_ptr), value :: c, ua, q, dq
    end subroutine fv_semi_x_3d_c

    subroutine fv_slope_x_c(nx, js, je, nz, monotone, q, slope) bind(C, name='fv_slope_x_c')
      use, intrinsic :: iso_c_binding, only: c_int, c_ptr
      integer(c_int), value :: nx, js, je, nz, monotone
      type(c_ptr), value :: q, slope
    end subroutine fv_slope_x_c

    subroutine fv_integer_flux_x_c(nx, js, je, nz, courant, q, flux) bind(C, name='fv_integer_flux_x_c')
      use, intrinsic :: iso_c_binding, only: c_int, c_ptr
      integer(c_int), value :: nx, js, je, nz
      type(c_ptr), value :: courant, q, flux
    end subroutine fv_integer_flux_x_c

    subroutine fv_vanleer_x_3d_c(nx, js, je, nz, dt, dx, c, monotone, uc, q, dq_dt) &
        bind(C, name='fv_vanleer_x_3d_c')
      use, intrinsic :: iso_c_binding, only: c_double, c_int, c_ptr
      integer(c_int), value :: nx, js, je, nz, monotone
      real(c_double), value :: dt, dx
      type(c_ptr), value :: c, uc, q, dq_dt
    end subroutine fv_vanleer_x_3d_c

    subroutine fv_slope_sphere_c(nx, js, je, nz, monotone, dy_plus, dy_minus, q, slope) &
        bind(C, name='fv_slope_sphere_c')
      use, intrinsic :: iso_c_binding, only: c_int, c_ptr
      integer(c_int), value :: nx, js, je, nz, monotone
      type(c_ptr), value :: dy_plus, dy_minus, q, slope
    end subroutine fv_slope_sphere_c

    subroutine fv_vanleer_sphere_3d_c(nx, ny_total, js, je, nz, dt, monotone, c, cc, dy, &
        dy_plus, dy_minus, vc, q, dq_dt) bind(C, name='fv_vanleer_sphere_3d_c')
      use, intrinsic :: iso_c_binding, only: c_double, c_int, c_ptr
      integer(c_int), value :: nx, ny_total, js, je, nz, monotone
      real(c_double), value :: dt
      type(c_ptr), value :: c, cc, dy, dy_plus, dy_minus, vc, q, dq_dt
    end subroutine fv_vanleer_sphere_3d_c

#ifdef USE_CUDA_FV_ADVECTION_KERNELS
    function fv_semi_x_3d_cuda_c(nx, js, je, nz, dt, dx, c, ua, q, dq) bind(C, name='fv_semi_x_3d_cuda_c')
      use, intrinsic :: iso_c_binding, only: c_double, c_int, c_ptr
      integer(c_int), value :: nx, js, je, nz
      real(c_double), value :: dt, dx
      type(c_ptr), value :: c, ua, q, dq
      integer(c_int) :: fv_semi_x_3d_cuda_c
    end function fv_semi_x_3d_cuda_c

    function fv_slope_x_cuda_c(nx, js, je, nz, monotone, q, slope) bind(C, name='fv_slope_x_cuda_c')
      use, intrinsic :: iso_c_binding, only: c_int, c_ptr
      integer(c_int), value :: nx, js, je, nz, monotone
      type(c_ptr), value :: q, slope
      integer(c_int) :: fv_slope_x_cuda_c
    end function fv_slope_x_cuda_c

    function fv_integer_flux_x_cuda_c(nx, js, je, nz, courant, q, flux) bind(C, name='fv_integer_flux_x_cuda_c')
      use, intrinsic :: iso_c_binding, only: c_int, c_ptr
      integer(c_int), value :: nx, js, je, nz
      type(c_ptr), value :: courant, q, flux
      integer(c_int) :: fv_integer_flux_x_cuda_c
    end function fv_integer_flux_x_cuda_c

    function fv_vanleer_x_3d_cuda_c(nx, js, je, nz, dt, dx, c, monotone, uc, q, dq_dt) &
        bind(C, name='fv_vanleer_x_3d_cuda_c')
      use, intrinsic :: iso_c_binding, only: c_double, c_int, c_ptr
      integer(c_int), value :: nx, js, je, nz, monotone
      real(c_double), value :: dt, dx
      type(c_ptr), value :: c, uc, q, dq_dt
      integer(c_int) :: fv_vanleer_x_3d_cuda_c
    end function fv_vanleer_x_3d_cuda_c

    function fv_slope_sphere_cuda_c(nx, js, je, nz, monotone, dy_plus, dy_minus, q, slope) &
        bind(C, name='fv_slope_sphere_cuda_c')
      use, intrinsic :: iso_c_binding, only: c_int, c_ptr
      integer(c_int), value :: nx, js, je, nz, monotone
      type(c_ptr), value :: dy_plus, dy_minus, q, slope
      integer(c_int) :: fv_slope_sphere_cuda_c
    end function fv_slope_sphere_cuda_c

    function fv_vanleer_sphere_3d_cuda_c(nx, ny_total, js, je, nz, dt, monotone, c, cc, dy, &
        dy_plus, dy_minus, vc, q, dq_dt) bind(C, name='fv_vanleer_sphere_3d_cuda_c')
      use, intrinsic :: iso_c_binding, only: c_double, c_int, c_ptr
      integer(c_int), value :: nx, ny_total, js, je, nz, monotone
      real(c_double), value :: dt
      type(c_ptr), value :: c, cc, dy, dy_plus, dy_minus, vc, q, dq_dt
      integer(c_int) :: fv_vanleer_sphere_3d_cuda_c
    end function fv_vanleer_sphere_3d_cuda_c
#endif
  end interface

contains

  integer(c_int) function monotone_flag(monotone) result(flag)
    logical, intent(in) :: monotone
    if (monotone) then
      flag = 1_c_int
    else
      flag = 0_c_int
    end if
  end function monotone_flag

  subroutine semi_x_3d_cpp_wrapper(nx, js, je, nz, dt, dx, c, ua, q, dq)
    integer, intent(in) :: nx, js, je, nz
    real(c_double), intent(in) :: dt, dx
    real(c_double), intent(in), target :: c(js:je), ua(nx,js:je,nz), q(nx,js:je,nz)
    real(c_double), intent(out), target :: dq(nx,js:je,nz)
    call fv_semi_x_3d_c(int(nx,c_int), int(js,c_int), int(je,c_int), int(nz,c_int), &
      dt, dx, c_loc(c), c_loc(ua), c_loc(q), c_loc(dq))
  end subroutine semi_x_3d_cpp_wrapper

  subroutine slope_x_cpp_wrapper(nx, js, je, nz, monotone, q, slope)
    integer, intent(in) :: nx, js, je, nz
    logical, intent(in) :: monotone
    real(c_double), intent(in), target :: q(nx,js:je,nz)
    real(c_double), intent(out), target :: slope(nx,js:je,nz)
    call fv_slope_x_c(int(nx,c_int), int(js,c_int), int(je,c_int), int(nz,c_int), &
      monotone_flag(monotone), c_loc(q), c_loc(slope))
  end subroutine slope_x_cpp_wrapper

  subroutine integer_flux_x_cpp_wrapper(nx, js, je, nz, courant, q, flux)
    integer, intent(in) :: nx, js, je, nz
    real(c_double), intent(in), target :: courant(nx,js:je,nz), q(nx,js:je,nz)
    real(c_double), intent(out), target :: flux(nx,js:je,nz)
    call fv_integer_flux_x_c(int(nx,c_int), int(js,c_int), int(je,c_int), int(nz,c_int), &
      c_loc(courant), c_loc(q), c_loc(flux))
  end subroutine integer_flux_x_cpp_wrapper

  subroutine vanleer_x_3d_cpp_wrapper(nx, js, je, nz, dt, dx, c, monotone, uc, q, dq_dt)
    integer, intent(in) :: nx, js, je, nz
    real(c_double), intent(in) :: dt, dx
    logical, intent(in) :: monotone
    real(c_double), intent(in), target :: c(js:je), uc(nx,js:je,nz), q(nx,js:je,nz)
    real(c_double), intent(inout), target :: dq_dt(nx,js:je,nz)
    call fv_vanleer_x_3d_c(int(nx,c_int), int(js,c_int), int(je,c_int), int(nz,c_int), &
      dt, dx, c_loc(c), monotone_flag(monotone), c_loc(uc), c_loc(q), c_loc(dq_dt))
  end subroutine vanleer_x_3d_cpp_wrapper

  subroutine slope_sphere_cpp_wrapper(nx, js, je, nz, monotone, dy_plus, dy_minus, q, slope)
    integer, intent(in) :: nx, js, je, nz
    logical, intent(in) :: monotone
    real(c_double), intent(in), target :: dy_plus(js-1:je+1), dy_minus(js-1:je+1)
    real(c_double), intent(in), target :: q(nx,js-2:je+2,nz)
    real(c_double), intent(out), target :: slope(nx,js-1:je+1,nz)
    call fv_slope_sphere_c(int(nx,c_int), int(js,c_int), int(je,c_int), int(nz,c_int), &
      monotone_flag(monotone), c_loc(dy_plus), c_loc(dy_minus), c_loc(q), c_loc(slope))
  end subroutine slope_sphere_cpp_wrapper

  subroutine vanleer_sphere_3d_cpp_wrapper(nx, ny_total, js, je, nz, dt, monotone, c, cc, dy, &
      dy_plus, dy_minus, vc, q, dq_dt)
    integer, intent(in) :: nx, ny_total, js, je, nz
    real(c_double), intent(in) :: dt
    logical, intent(in) :: monotone
    real(c_double), intent(in), target :: c(js:je), cc(js:je+1)
    real(c_double), intent(in), target :: dy(js-1:je+1)
    real(c_double), intent(in), target :: dy_plus(js-1:je+1), dy_minus(js-1:je+1)
    real(c_double), intent(in), target :: vc(nx,js:je+1,nz), q(nx,js-2:je+2,nz)
    real(c_double), intent(inout), target :: dq_dt(nx,js:je,nz)
    call fv_vanleer_sphere_3d_c(int(nx,c_int), int(ny_total,c_int), int(js,c_int), &
      int(je,c_int), int(nz,c_int), dt, monotone_flag(monotone), c_loc(c), c_loc(cc), &
      c_loc(dy), c_loc(dy_plus), c_loc(dy_minus), c_loc(vc), c_loc(q), c_loc(dq_dt))
  end subroutine vanleer_sphere_3d_cpp_wrapper

#ifdef USE_CUDA_FV_ADVECTION_KERNELS
  subroutine semi_x_3d_cuda_wrapper(nx, js, je, nz, dt, dx, c, ua, q, dq, ierr)
    integer, intent(in) :: nx, js, je, nz
    real(c_double), intent(in) :: dt, dx
    real(c_double), intent(in), target :: c(js:je), ua(nx,js:je,nz), q(nx,js:je,nz)
    real(c_double), intent(out), target :: dq(nx,js:je,nz)
    integer, intent(out) :: ierr
    ierr = int(fv_semi_x_3d_cuda_c(int(nx,c_int), int(js,c_int), int(je,c_int), &
      int(nz,c_int), dt, dx, c_loc(c), c_loc(ua), c_loc(q), c_loc(dq)))
  end subroutine semi_x_3d_cuda_wrapper

  subroutine slope_x_cuda_wrapper(nx, js, je, nz, monotone, q, slope, ierr)
    integer, intent(in) :: nx, js, je, nz
    logical, intent(in) :: monotone
    real(c_double), intent(in), target :: q(nx,js:je,nz)
    real(c_double), intent(out), target :: slope(nx,js:je,nz)
    integer, intent(out) :: ierr
    ierr = int(fv_slope_x_cuda_c(int(nx,c_int), int(js,c_int), int(je,c_int), &
      int(nz,c_int), monotone_flag(monotone), c_loc(q), c_loc(slope)))
  end subroutine slope_x_cuda_wrapper

  subroutine integer_flux_x_cuda_wrapper(nx, js, je, nz, courant, q, flux, ierr)
    integer, intent(in) :: nx, js, je, nz
    real(c_double), intent(in), target :: courant(nx,js:je,nz), q(nx,js:je,nz)
    real(c_double), intent(out), target :: flux(nx,js:je,nz)
    integer, intent(out) :: ierr
    ierr = int(fv_integer_flux_x_cuda_c(int(nx,c_int), int(js,c_int), int(je,c_int), &
      int(nz,c_int), c_loc(courant), c_loc(q), c_loc(flux)))
  end subroutine integer_flux_x_cuda_wrapper

  subroutine vanleer_x_3d_cuda_wrapper(nx, js, je, nz, dt, dx, c, monotone, uc, q, dq_dt, ierr)
    integer, intent(in) :: nx, js, je, nz
    real(c_double), intent(in) :: dt, dx
    logical, intent(in) :: monotone
    real(c_double), intent(in), target :: c(js:je), uc(nx,js:je,nz), q(nx,js:je,nz)
    real(c_double), intent(inout), target :: dq_dt(nx,js:je,nz)
    integer, intent(out) :: ierr
    ierr = int(fv_vanleer_x_3d_cuda_c(int(nx,c_int), int(js,c_int), int(je,c_int), &
      int(nz,c_int), dt, dx, c_loc(c), monotone_flag(monotone), c_loc(uc), c_loc(q), c_loc(dq_dt)))
  end subroutine vanleer_x_3d_cuda_wrapper

  subroutine slope_sphere_cuda_wrapper(nx, js, je, nz, monotone, dy_plus, dy_minus, q, slope, ierr)
    integer, intent(in) :: nx, js, je, nz
    logical, intent(in) :: monotone
    real(c_double), intent(in), target :: dy_plus(js-1:je+1), dy_minus(js-1:je+1)
    real(c_double), intent(in), target :: q(nx,js-2:je+2,nz)
    real(c_double), intent(out), target :: slope(nx,js-1:je+1,nz)
    integer, intent(out) :: ierr
    ierr = int(fv_slope_sphere_cuda_c(int(nx,c_int), int(js,c_int), int(je,c_int), &
      int(nz,c_int), monotone_flag(monotone), c_loc(dy_plus), c_loc(dy_minus), c_loc(q), c_loc(slope)))
  end subroutine slope_sphere_cuda_wrapper

  subroutine vanleer_sphere_3d_cuda_wrapper(nx, ny_total, js, je, nz, dt, monotone, c, cc, dy, &
      dy_plus, dy_minus, vc, q, dq_dt, ierr)
    integer, intent(in) :: nx, ny_total, js, je, nz
    real(c_double), intent(in) :: dt
    logical, intent(in) :: monotone
    real(c_double), intent(in), target :: c(js:je), cc(js:je+1)
    real(c_double), intent(in), target :: dy(js-1:je+1)
    real(c_double), intent(in), target :: dy_plus(js-1:je+1), dy_minus(js-1:je+1)
    real(c_double), intent(in), target :: vc(nx,js:je+1,nz), q(nx,js-2:je+2,nz)
    real(c_double), intent(inout), target :: dq_dt(nx,js:je,nz)
    integer, intent(out) :: ierr
    ierr = int(fv_vanleer_sphere_3d_cuda_c(int(nx,c_int), int(ny_total,c_int), int(js,c_int), &
      int(je,c_int), int(nz,c_int), dt, monotone_flag(monotone), c_loc(c), c_loc(cc), &
      c_loc(dy), c_loc(dy_plus), c_loc(dy_minus), c_loc(vc), c_loc(q), c_loc(dq_dt)))
  end subroutine vanleer_sphere_3d_cuda_wrapper
#endif

end module fv_advection_kernels_c_interface
