module semi_y_3d_c_interface
  use, intrinsic :: iso_c_binding, only: c_double, c_int, c_loc, c_ptr
  implicit none
  private

  public :: semi_y_3d_cpp_wrapper
#ifdef USE_CUDA_SEMI_Y_3D
  public :: semi_y_3d_cuda_wrapper
#endif

  interface
    subroutine fv_semi_y_3d_c(nx, js, je, nz, dt, va, qx, dyy, dq) &
        bind(C, name='fv_semi_y_3d_c')
      use, intrinsic :: iso_c_binding, only: c_double, c_int, c_ptr
      integer(c_int), value :: nx, js, je, nz
      real(c_double), value :: dt
      type(c_ptr), value :: va, qx, dyy, dq
    end subroutine fv_semi_y_3d_c

#ifdef USE_CUDA_SEMI_Y_3D
    function fv_semi_y_3d_cuda_c(nx, js, je, nz, dt, va, qx, dyy, dq) &
        bind(C, name='fv_semi_y_3d_cuda_c')
      use, intrinsic :: iso_c_binding, only: c_double, c_int, c_ptr
      integer(c_int), value :: nx, js, je, nz
      real(c_double), value :: dt
      type(c_ptr), value :: va, qx, dyy, dq
      integer(c_int) :: fv_semi_y_3d_cuda_c
    end function fv_semi_y_3d_cuda_c
#endif
  end interface

contains

  subroutine semi_y_3d_cpp_wrapper(nx, js, je, nz, dt, va, qx, dyy, dq)
    integer, intent(in) :: nx, js, je, nz
    real(c_double), intent(in) :: dt
    real(c_double), intent(in), target :: va(nx, js:je, nz)
    real(c_double), intent(in), target :: qx(nx, js-2:je+2, nz)
    real(c_double), intent(in), target :: dyy(js:je+1)
    real(c_double), intent(out), target :: dq(nx, js:je, nz)

    call fv_semi_y_3d_c( &
      int(nx, c_int), int(js, c_int), int(je, c_int), int(nz, c_int), dt, &
      c_loc(va), c_loc(qx), c_loc(dyy), c_loc(dq))
  end subroutine semi_y_3d_cpp_wrapper

#ifdef USE_CUDA_SEMI_Y_3D
  subroutine semi_y_3d_cuda_wrapper(nx, js, je, nz, dt, va, qx, dyy, dq, ierr)
    integer, intent(in) :: nx, js, je, nz
    real(c_double), intent(in) :: dt
    real(c_double), intent(in), target :: va(nx, js:je, nz)
    real(c_double), intent(in), target :: qx(nx, js-2:je+2, nz)
    real(c_double), intent(in), target :: dyy(js:je+1)
    real(c_double), intent(out), target :: dq(nx, js:je, nz)
    integer, intent(out) :: ierr

    ierr = int(fv_semi_y_3d_cuda_c( &
      int(nx, c_int), int(js, c_int), int(je, c_int), int(nz, c_int), dt, &
      c_loc(va), c_loc(qx), c_loc(dyy), c_loc(dq)))
  end subroutine semi_y_3d_cuda_wrapper
#endif

end module semi_y_3d_c_interface
