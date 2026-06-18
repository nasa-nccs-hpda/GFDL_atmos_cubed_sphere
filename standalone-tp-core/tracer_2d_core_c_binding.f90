! tracer_2d_core_c — single-tile, nsplt=1, unit-grid tracer transport core,
! callable from C++ as the correctness oracle for tracer_2d.hpp. Mirrors the
! inner body of tracer_2d (fv_tracer2d.F90) but without MPI halo exchange,
! Courant sub-cycling, or deln_flux: for each level k and tracer iq it calls
! the REAL fv_tp_2d (mass-flux variant) and applies the tracer update.
! Unit grid (area=dxa=dya=1 via the stub gridstruct, rarea=1), so xfx=cx, yfx=cy.
subroutine tracer_2d_core_c(q, dp1, cx, cy, mfx, mfy, n, npz, nq, hord, lim_fac) &
    bind(C, name='tracer_2d_core_c')

  use iso_c_binding, only: c_int, c_float
  use fv_arrays_mod, only: fv_grid_bounds_type, fv_grid_type
  use tp_core_mod,   only: fv_tp_2d

  implicit none

  integer(c_int), intent(in), value :: n, npz, nq, hord
  real(c_float),  intent(in), value :: lim_fac

  real(c_float), intent(inout) :: q  (1-3:n+3, 1-3:n+3, npz, nq)
  real(c_float), intent(in)    :: dp1(1-3:n+3, 1-3:n+3, npz)
  real(c_float), intent(in)    :: cx (1:n+1,   1-3:n+3, npz)
  real(c_float), intent(in)    :: cy (1-3:n+3, 1:n+1,   npz)
  real(c_float), intent(in)    :: mfx(1:n+1,   1:n,     npz)
  real(c_float), intent(in)    :: mfy(1:n,     1:n+1,   npz)

  type(fv_grid_bounds_type) :: bd
  type(fv_grid_type) :: gridstruct
  integer :: is, ie, js, je, isd, ied, jsd, jed, npx, npy, k, iq, i, j
  real(c_float) :: fx(1:n+1, 1:n), fy(1:n, 1:n+1)
  real(c_float) :: ra_x(1:n, 1-3:n+3), ra_y(1-3:n+3, 1:n), dp2(1:n, 1:n)

  is=1; ie=n; js=1; je=n; isd=1-3; ied=n+3; jsd=1-3; jed=n+3
  npx=n+1; npy=n+1
  bd = fv_grid_bounds_type(n)
  gridstruct = fv_grid_type(bd, npx, npy, .false., 0)

  do k=1,npz
     do j=jsd,jed
        do i=is,ie
           ra_x(i,j) = 1.0 + (cx(i,j,k) - cx(i+1,j,k))
        enddo
     enddo
     do j=js,je
        do i=isd,ied
           ra_y(i,j) = 1.0 + (cy(i,j,k) - cy(i,j+1,k))
        enddo
     enddo
     do j=js,je
        do i=is,ie
           dp2(i,j) = dp1(i,j,k) + ((mfx(i,j,k)-mfx(i+1,j,k)) + (mfy(i,j,k)-mfy(i,j+1,k)))
        enddo
     enddo

     do iq=1,nq
        call fv_tp_2d(q(isd,jsd,k,iq), cx(is,jsd,k), cy(isd,js,k), npx, npy, hord, &
                      fx, fy, cx(is,jsd,k), cy(isd,js,k), gridstruct, bd, ra_x, ra_y, &
                      lim_fac, mfx=mfx(is,js,k), mfy=mfy(is,js,k))
        do j=js,je
           do i=is,ie
              q(i,j,k,iq) = ( q(i,j,k,iq)*dp1(i,j,k) + &
                            ((fx(i,j)-fx(i+1,j)) + (fy(i,j)-fy(i,j+1))) ) / dp2(i,j)
           enddo
        enddo
     enddo
  enddo

end subroutine tracer_2d_core_c
