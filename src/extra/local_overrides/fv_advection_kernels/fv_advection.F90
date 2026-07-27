!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!                                                                   !!
!!                   GNU General Public License                      !!
!!                                                                   !!
!! This file is part of the Flexible Modeling System (FMS).          !!
!!                                                                   !!
!! FMS is free software; you can redistribute it and/or modify it    !!
!! under the terms of the GNU General Public License as published by !!
!! the Free Software Foundation, either version 3 of the License, or !!
!! (at your option) any later version.                               !!
!!                                                                   !!
!! FMS is distributed in the hope that it will be useful,            !!
!! but WITHOUT ANY WARRANTY; without even the implied warranty of    !!
!! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the      !!
!! GNU General Public License for more details.                      !!
!!                                                                   !!
!! You should have received a copy of the GNU General Public License !!
!! along with FMS. if not, see: http://www.gnu.org/licenses/gpl.txt  !!
!!                                                                   !!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

module fv_advection_mod

use         fms_mod, only: mpp_pe, mpp_npes, mpp_root_pe, error_mesg, FATAL, write_version_number

use   constants_mod, only : radius, pi

use mpp_domains_mod, only : mpp_define_domains, mpp_update_domains, &
                            mpp_get_compute_domain, domain2D

#ifdef USE_CPP_SEMI_Y_3D
use semi_y_3d_c_interface, only : semi_y_3d_cpp_wrapper
#endif
#ifdef USE_CUDA_SEMI_Y_3D
use semi_y_3d_c_interface, only : semi_y_3d_cuda_wrapper
#endif
#ifdef USE_CPP_FV_ADVECTION_KERNELS
use fv_advection_kernels_c_interface, only : semi_x_3d_cpp_wrapper, slope_x_cpp_wrapper, &
  integer_flux_x_cpp_wrapper, vanleer_x_3d_cpp_wrapper, slope_sphere_cpp_wrapper, &
  vanleer_sphere_3d_cpp_wrapper
#endif
#ifdef USE_CUDA_FV_ADVECTION_KERNELS
use fv_advection_kernels_c_interface, only : semi_x_3d_cuda_wrapper, slope_x_cuda_wrapper, &
  integer_flux_x_cuda_wrapper, vanleer_x_3d_cuda_wrapper, slope_sphere_cuda_wrapper, &
  vanleer_sphere_3d_cuda_wrapper, fv_advection_resident_enabled, &
  fv_advection_resident_begin_wrapper, fv_advection_resident_finish_wrapper, &
  fv_advection_nccl_init, fv_advection_nccl_halo_enabled
#endif

implicit none
private

character(len=128), parameter :: version = '$Id: fv_advection.F90,v 13.0 2006/03/28 21:17:47 fms Exp $'
character(len=128), parameter :: tagname = '$Name: siena_201211 $'

type(domain2D), save, public :: advection_domain

logical :: module_is_initialized = .FALSE.
logical :: monotone      = .true.
integer :: is, ie, js, je, pe, npes, nx, ny, nz

real, allocatable, dimension(:) :: y, yy, c, s, cc, dy, dyy, dyyy, dy_plus, dy_minus
real :: dx

! Transfer PoC (addition 3): accumulate wall time spent in the neighbor halo
! exchange (mpp_update_domains). Reported per-rank at fv_advection_end so the
! current host-routed halo cost has a baseline before the GPU-to-GPU version.
integer(kind=8) :: halo_t0 = 0_8, halo_t1 = 0_8, halo_rate = 1_8
real(kind=8)    :: halo_seconds = 0.0d0
integer         :: halo_calls = 0

public :: fv_advection_init, fv_advection_end
public :: a_grid_horiz_advection

interface a_grid_horiz_advection
   module procedure a_grid_horiz_advection_3d
   module procedure a_grid_horiz_advection_2d
end interface

!===========================================================================================
contains
!===========================================================================================


subroutine fv_advection_init(nx_in, ny_in, yy_in, degrees_lon, advection_layout)

  integer, intent(in) ::  nx_in, ny_in
  real   , intent(in), dimension(:) :: yy_in
  real   , intent(in) :: degrees_lon
  integer, intent(in), optional :: advection_layout(2)


  integer :: layout(2)
#ifdef USE_CUDA_FV_ADVECTION_KERNELS
  integer :: nccl_ierr
#endif

  if (module_is_initialized) return

  call write_version_number(version, tagname)

  pe   = mpp_pe()
  npes = mpp_npes()

  nx = nx_in
  ny = ny_in

  allocate( y(ny), c(ny), s(ny), yy(ny+1), cc(ny+1), dy(-1:ny+2), dyy(ny+1), dyyy(0:ny+1) )
  allocate( dy_plus(0:ny+1), dy_minus(0:ny+1) )

  yy = yy_in

  y  = 0.5*(yy(2:ny+1) + yy(1:ny))

  c  = cos(y)
  s  = sin(y)
  cc = cos(yy)

  dy(1:ny) = yy(2:ny+1) - yy(1:ny)  ! distance between half level points (size of grid boxes)
  dy(-1)    = dy(2)
  dy(0)     = dy(1)
  dy(ny+1) = dy(ny)
  dy(ny+2) = dy(ny-1)

  dyy(2:ny) = y(2:ny) - y(1:ny-1)  ! distance between full points 
  dyy(1)    = 2*(y(1) - yy(1))
  dyy(ny+1) = 2*(yy(ny+1) - y(ny))

  dy_plus (0:ny+1) = dy(0:ny+1)/(dy( 0:ny+1) + dy(1:ny+2))
  dy_minus(0:ny+1) = dy(0:ny+1)/(dy(-1:ny  ) + dy(0:ny+1))

  y    =    y*radius
  yy   =   yy*radius
  dy   =   dy*radius
  dyy  =  dyy*radius

  dx = (degrees_lon/360.)*2.0*pi*radius/float(nx)

!1D decomposition along Y only
  layout = (/1,npes/)    
    
  if( present (advection_layout) ) layout = advection_layout

  call mpp_define_domains( (/1,nx,1,ny/), layout, advection_domain, yhalo=2 )

  module_is_initialized=.TRUE.

  call mpp_get_compute_domain( advection_domain, is, ie, js, je )

#ifdef USE_CUDA_FV_ADVECTION_KERNELS
  ! Level 1 (FV transfer PoC): when the resident CUDA path is active, build the
  ! NCCL communicator once at startup so the GPU-to-GPU halo exchange is ready
  ! and any misconfiguration (for example more MPI ranks than GPUs) is reported
  ! here rather than mid-run.
  if ( fv_advection_resident_enabled() ) then
    call fv_advection_nccl_init(nccl_ierr)
    if ( nccl_ierr /= 0 ) then
      call error_mesg( 'fv_advection_init', &
        'NCCL communicator setup failed; see the preceding message', FATAL )
    end if
  end if
#endif

return
end subroutine fv_advection_init

!===========================================================================================

subroutine a_grid_horiz_advection_3d(ua, va, q, dt, dq_dt, flux)


real, intent(in)   , dimension(:,js:,:) :: ua, va, q
real, intent(in)                        :: dt
real, intent(inout), dimension(:,js:,:) :: dq_dt
logical, optional, intent(in) :: flux

real, dimension(nx,js-2:je+2,size(q,3)) :: vx, qx
real, dimension(nx,js  :je+1,size(q,3)) :: vc
real, dimension(nx,js  :je  ,size(q,3)) :: uc, div

integer :: i, j, k
integer, dimension(nx) :: ii

logical :: flux_local
logical :: use_resident_boundary

if(.not.module_is_initialized) then
  call error_mesg('a_grid_horiz_advection','fv_advection_mod is not initialized', FATAL)
endif

flux_local = .false.
if(present(flux)) flux_local = flux

#ifdef USE_CUDA_FV_ADVECTION_KERNELS
use_resident_boundary = fv_advection_resident_enabled()
#else
use_resident_boundary = .false.
#endif

vx = 0.0
qx = 0.0

do i = 1,nx
  ii(i) = i + nx/2
  if (ii(i) > nx) ii(i) = ii(i) - nx
end do

vx(:, js:je, :) = va(:, js:je, :)
qx(:, js:je, :) = q (:, js:je, :)

call system_clock(halo_t0, halo_rate)
call mpp_update_domains(vx, advection_domain)
call mpp_update_domains(qx, advection_domain)
call system_clock(halo_t1)
halo_seconds = halo_seconds + real(halo_t1 - halo_t0, 8) / real(halo_rate, 8)
halo_calls = halo_calls + 2

if(js == 1) then
  do i = 1,nx
    vx(i, 0,:) = - vx(ii(i),1,:)
    qx(i, 0,:) =   qx(ii(i),1,:)
    qx(i,-1,:) =   qx(ii(i),2,:)
  end do
endif

if(je == ny) then
  do i = 1,nx
    vx(i,ny+1,:) = - vx(ii(i),ny  ,:)
    qx(i,ny+1,:) =   qx(ii(i),ny  ,:)
    qx(i,ny+2,:) =   qx(ii(i),ny-1,:)
  end do
endif

! Resident scope-B folds uc/vc and the divergence term onto the device in
! resident_advection_begin, so the host skips them entirely. vx (haloed va) is
! handed to advection_sphere_3d for the device to derive vc.
if (.not. use_resident_boundary) then
  uc(2:nx,js:je,:)   = 0.5*(ua(1:nx-1, js:je  ,:) + ua(2:nx,js:je,:))
  uc(1   ,js:je,:)   = 0.5*(ua(nx    , js:je  ,:) + ua(1   ,js:je,:))

   do k=1,size(vc,3)
     do j=js,je+1
       do i=1,nx
         vc(i,j,k) = 0.5*(vx(i,j-1,k) + vx(i,j,k))
       enddo
     enddo
   enddo

  if(.not.flux_local) then
    do j = js,je
      div(:,j,:) = (vc(:,j+1,:)*cc(j+1) - vc(:,j,:)*cc(j))/(c(j)*dy(j))
    enddo

    do j = js, je
      div(1:nx-1,j,:) = div(1:nx-1,j,:) + (uc(2:nx,j,:) - uc(1:nx-1,j,:))/(c(j)*dx)
      div(nx    ,j,:) = div(nx    ,j,:) + (uc(1   ,j,:) - uc(nx    ,j,:))/(c(j)*dx)
    enddo

    dq_dt = dq_dt + q*div
  endif
endif

call advection_sphere_3d(dq_dt, dt, qx, uc, vc, ua, va, vx, .not.flux_local)

return
end subroutine a_grid_horiz_advection_3d

!===========================================================================================

subroutine a_grid_horiz_advection_2d(ua, va, q, dt, dq_dt, flux)

real, intent(in),    dimension(:,js:) :: ua, va, q
real, intent(in)                      :: dt
real, intent(inout), dimension(:,js:) :: dq_dt
logical, intent(in), optional :: flux

real, dimension(nx,js:je ,1) :: ua_3d, va_3d, q_3d, dq_dt_3d

q_3d     (:,js:je,1)   = q     (:,js:je)
ua_3d    (:,js:je,1)   = ua    (:,js:je)
va_3d    (:,js:je,1)   = va    (:,js:je)
dq_dt_3d (:,js:je,1)   = dq_dt (:,js:je)

if(present(flux)) then
  call a_grid_horiz_advection_3d(ua_3d, va_3d, q_3d, dt, dq_dt_3d, flux = flux)
else 
  call a_grid_horiz_advection_3d(ua_3d, va_3d, q_3d, dt, dq_dt_3d)
endif

dq_dt  =  dq_dt_3d(:,:,1)

return
end subroutine a_grid_horiz_advection_2d

!===========================================================================================

subroutine advection_sphere_3d(dq_dt, dt, q, uc, vc, ua, va, vx, fold_div)

real, intent(in)   , dimension(:,js-2:,:) :: q
real, intent(in)   , dimension(:,js  :,:) :: vc
real, intent(in)   , dimension(:,js  :,:) :: uc, ua, va
real, intent(in)   , dimension(:,js-2:,:) :: vx
logical, intent(in)                       :: fold_div
real, intent(in)                          :: dt
real, intent(inout), dimension(:,js  :,:) :: dq_dt

real, dimension(nx, js  :je  , size(q,3)) :: q2
real, dimension(nx, js-2:je+2, size(q,3)) :: q1

integer, dimension(nx) :: ii
integer :: i, ierr
logical :: use_resident_boundary
logical :: use_device_halo

#ifdef USE_CUDA_FV_ADVECTION_KERNELS
use_resident_boundary = fv_advection_resident_enabled()
use_device_halo = use_resident_boundary .and. fv_advection_nccl_halo_enabled()
#else
use_resident_boundary = .false.
use_device_halo = .false.
#endif

if (use_resident_boundary) then
#ifdef USE_CUDA_FV_ADVECTION_KERNELS
  ! Resident scope-B: begin computes q1 (semi_x), q2 (semi_y), uc, vc, and the
  ! divergence term dq = q*div on the device. uc/vc/q2 stay resident for finish,
  ! so they are not recomputed or transferred host-side. The divergence fold
  ! overwrites dq, which is valid because the grid-tracer caller enters with
  ! dq_dt = 0 (see update_tracers); fold_div is .false. only for flux mode.
  call fv_advection_resident_begin_wrapper(nx, js, je, size(q,3), 0.5*dt, dx, fold_div, &
    c(js:je), cc(js:je+1), dy(js-1:je+1), dy_plus(js-1:je+1), dy_minus(js-1:je+1), &
    dyy(js:je+1), ua(:,js:je,:), q(:,js-2:je+2,:), vx(:,js-2:je+2,:), q1(:,js:je,:), ierr)
  if (ierr /= 0) call error_mesg('fv_advection_mod', &
    'resident CUDA advection begin failed', FATAL)
#endif
else
  call semi_x_3d(q1(:,js:je,:), ua(:,js:je,:), q(:,js :je ,:), 0.5*dt)
  q1(:,js:je,:) = q(:,js:je,:) + q1(:,js:je,:)

  call semi_y_3d(q2(:,js:je,:), va(:,js:je,:), q(:,js-2:je+2,:), 0.5*dt)
  q2(:,js:je,:) = q(:,js:je,:) + q2(:,js:je,:)
endif

! Host-routed q1 halo: neighbor exchange (mpp_update_domains) then the polar
! fold. Skipped when the GPU-to-GPU path is on, since the resident finish does
! both on the device; the deep interior stays resident on the GPU throughout.
if (.not. use_device_halo) then
  call system_clock(halo_t0, halo_rate)
  call mpp_update_domains(q1, advection_domain)
  call system_clock(halo_t1)
  halo_seconds = halo_seconds + real(halo_t1 - halo_t0, 8) / real(halo_rate, 8)
  halo_calls = halo_calls + 1

  do i = 1,nx
    ii(i) = i + nx/2
    if (ii(i) > nx) ii(i) = ii(i) - nx
  end do

  if(js == 1) then
    do i = 1,nx
      q1(i, 0,:) =   q1(ii(i),1,:)
      q1(i,-1,:) =   q1(ii(i),2,:)
    end do
  endif

  if(je == ny) then
    do i = 1,nx
      q1(i,ny+1,:) =   q1(ii(i),ny  ,:)
      q1(i,ny+2,:) =   q1(ii(i),ny-1,:)
    end do
  endif
endif

if (use_resident_boundary) then
#ifdef USE_CUDA_FV_ADVECTION_KERNELS
  call fv_advection_resident_finish_wrapper(nx, ny, js, je, size(q,3), dt, dx, monotone, &
    q1(:,js-2:je+2,:), dq_dt(:,js:je,:), ierr)
  if (ierr /= 0) call error_mesg('fv_advection_mod', &
    'resident CUDA advection finish failed', FATAL)
#endif
else
  call vanleer_x_3d     (dq_dt(:,js:je,:), uc(:,js:je,:)  , q2(:,js:je,:)    , dt)
  call vanleer_sphere_3d(dq_dt(:,js:je,:), vc(:,js:je+1,:), q1(:,js-2:je+2,:), dt)
endif

return
end subroutine advection_sphere_3d

!===========================================================================================

subroutine vanleer_sphere_3d(dq_dt, vc, q, dt)

real, intent(in),    dimension(:,js-2:,:) :: q
real, intent(in),    dimension(:,js  :,:) :: vc
real, intent(in)                          :: dt
real, intent(inout), dimension(:,js  :,:) :: dq_dt

real, dimension(nx, js  :je+1, size(q,3)) :: flux
real, dimension(nx ,js-1:je+1, size(q,3)) :: s

real, dimension(js-1:je+1) :: dtdy 
real, dimension(js  :je) :: dyc
integer :: j
#ifdef USE_CUDA_FV_ADVECTION_KERNELS
integer :: ierr
#endif

#if !defined(USE_CPP_FV_ADVECTION_KERNELS) && !defined(USE_CUDA_FV_ADVECTION_KERNELS)
dtdy(js-1:je+1) = dt/(dy(js-1:je+1)) 
dyc (js  :je) = 1.0/(dy(js:je)*c(js:je))

call slope_sphere(s(:,js-1:je+1,:), q(:,js-2:je+2,:))

do j = js,je+1
  where (vc(:,j,:) >= 0.0) 
    flux(:,j,:) = vc(:,j,:)*cc(j) * &
             (q(:,j-1,:) + 0.5*s(:,j-1,:)*(1.0 - dtdy(j-1)*vc(:,j,:)))
  elsewhere
    flux(:,j,:) = vc(:,j,:)*cc(j) * &
             (q(:,j,:)   - 0.5*s(:,j,:)  *(1.0 + dtdy(j)  *vc(:,j,:)))
  end where
end do

if(js == 1) flux(:,js,: ) = 0.0
if(je == ny) flux(:,je+1,:) = 0.0

do j = js,je
  dq_dt(:,j,:) = dq_dt(:,j,:) - dyc(j)*(flux(:,j+1,:) - flux(:,j,:))
end do
#elif defined(USE_CUDA_FV_ADVECTION_KERNELS)
call vanleer_sphere_3d_cuda_wrapper(nx, ny, js, je, size(q,3), dt, monotone, &
  c(js:je), cc(js:je+1), dy(js-1:je+1), dy_plus(js-1:je+1), dy_minus(js-1:je+1), &
  vc, q, dq_dt, ierr)
if (ierr /= 0) call error_mesg('fv_advection_mod', 'vanleer_sphere_3d CUDA wrapper failed', FATAL)
#else
call vanleer_sphere_3d_cpp_wrapper(nx, ny, js, je, size(q,3), dt, monotone, &
  c(js:je), cc(js:je+1), dy(js-1:je+1), dy_plus(js-1:je+1), dy_minus(js-1:je+1), &
  vc, q, dq_dt)
#endif

return
end subroutine vanleer_sphere_3d

!===========================================================================================

subroutine vanleer_x_3d(dq_dt, uc, q, dt)

real, intent(in),  dimension(:,js:,:)   :: uc, q
real, intent(in)                        :: dt
real, intent(inout), dimension(:,js:,:) :: dq_dt

real   , dimension(nx+1,js:je,size(q,3)) :: flux
real   , dimension(nx  ,js:je,size(q,3)) :: b, bb, qq, ss, s
integer, dimension(nx  ,js:je,size(q,3)) :: ii

integer :: i, j, k
#ifdef USE_CUDA_FV_ADVECTION_KERNELS
integer :: ierr
#endif

#if !defined(USE_CPP_FV_ADVECTION_KERNELS) && !defined(USE_CUDA_FV_ADVECTION_KERNELS)
do j = js,je
  b(:,j,:)  = uc(:,j,:)*dt/(dx*c(j))
end do
bb = b - int(b)

flux = 0.0
do j = js, je   ! try doing one row at a time to avoid unecessary computations
  if(maxval(abs(b(:,j:j,:))) > 1.0 ) &
      call integer_flux_x(flux(1:nx,j:j,:), b(:,j:j,:), q(:,j:j,:))
end do
call slope_x(s, q)
call find_cell_x(ii, b)

do k = 1, size(q,3)
  do j = js,je
    do i = 1, nx
      qq(i,j,k)  = q(ii(i,j,k),j,k)
      ss(i,j,k)  = s(ii(i,j,k),j,k)
    end do
  end do
end do

flux(1:nx,:,:) = flux(1:nx,:,:) + bb*(qq + 0.5*ss*(sign(1.0,bb) - bb))
flux(nx+1,:,:) = flux(1,:,:)

dq_dt = dq_dt - (flux(2:nx+1,:,:) - flux(1:nx,:,:))/dt

do j = js,je
  flux(:,j,:)  = flux(:,j,:)*dt/(dx*c(j))
end do

#elif defined(USE_CUDA_FV_ADVECTION_KERNELS)
call vanleer_x_3d_cuda_wrapper(nx, js, je, size(q,3), dt, dx, c(js:je), monotone, &
  uc, q, dq_dt, ierr)
if (ierr /= 0) call error_mesg('fv_advection_mod', 'vanleer_x_3d CUDA wrapper failed', FATAL)
#else
call vanleer_x_3d_cpp_wrapper(nx, js, je, size(q,3), dt, dx, c(js:je), monotone, &
  uc, q, dq_dt)
#endif

return
end subroutine vanleer_x_3d

!===========================================================================================

subroutine semi_x_3d(dq, ua, q, dt)

real, intent(in),  dimension(:,js:,:) :: ua, q
real, intent(in)                      :: dt
real, intent(out), dimension(:,js:,:) :: dq

real   , dimension(nx,js:je,size(q,3)) :: b, bb, q_left, q_right
integer, dimension(nx,js:je,size(q,3)) :: ii, i_left, i_right

integer :: i, j, k
#ifdef USE_CUDA_FV_ADVECTION_KERNELS
integer :: ierr
#endif

#if !defined(USE_CPP_FV_ADVECTION_KERNELS) && !defined(USE_CUDA_FV_ADVECTION_KERNELS)
do j = js,je
  b(:,j,:)  = ua(:,j,:)*dt/(dx*c(j))
end do

call find_cell_x(ii, b)

i_left  = ii
i_right = i_left + 1
where(i_right.gt.nx) i_right = 1

bb = b - floor(b)

do k = 1, size(q,3)
  do j = js,je
    do i = 1, nx
      q_left (i,j,k) = q(i_left (i,j,k),j,k)
      q_right(i,j,k) = q(i_right(i,j,k),j,k)
    end do
  end do
end do

dq(:,js:je,:) = bb(:,js:je,:)*q_left (:,js:je,:) + (1.0 - bb(:,js:je,:))*q_right(:,js:je,:) &
               - q(:,js:je,:)
#elif defined(USE_CUDA_FV_ADVECTION_KERNELS)
call semi_x_3d_cuda_wrapper(nx, js, je, size(q,3), dt, dx, c(js:je), ua, q, dq, ierr)
if (ierr /= 0) call error_mesg('fv_advection_mod', 'semi_x_3d CUDA wrapper failed', FATAL)
#else
call semi_x_3d_cpp_wrapper(nx, js, je, size(q,3), dt, dx, c(js:je), ua, q, dq)
#endif

return
end subroutine semi_x_3d

!===========================================================================================

subroutine semi_y_3d(dq, va, qx, dt)

real, intent(out), dimension(:,js  :,:) :: dq
real, intent(in),  dimension(:,js  :,:) :: va
real, intent(in),  dimension(:,js-2:,:) :: qx
real, intent(in)                        :: dt

#ifdef USE_CUDA_SEMI_Y_3D
integer :: ierr
#endif
#if !defined(USE_CPP_SEMI_Y_3D) && !defined(USE_CUDA_SEMI_Y_3D)
integer :: j

do j = js, je
  where (va(:,j,:) >= 0.0) 
    dq(:,j,:) = va(:,j,:)*dt*(qx(:,j-1,:) - qx(:,j  ,:))/dyy(j)
  elsewhere
    dq(:,j,:) = va(:,j,:)*dt*(qx(:,j  ,:) - qx(:,j+1,:))/dyy(j+1)
  end where
enddo
#elif defined(USE_CUDA_SEMI_Y_3D)
call semi_y_3d_cuda_wrapper(nx, js, je, size(qx,3), dt, va, qx, dyy(js:je+1), dq, ierr)
if (ierr /= 0) call error_mesg('fv_advection_mod', 'semi_y_3d CUDA wrapper failed', FATAL)
#else
call semi_y_3d_cpp_wrapper(nx, js, je, size(qx,3), dt, va, qx, dyy(js:je+1), dq)
#endif

return
end subroutine semi_y_3d

!===========================================================================================

subroutine find_cell_x(ii,b)
!!dir$ INLINEALWAYS find_cell_x
integer, intent(out),  dimension(:,:,:) :: ii
real   , intent(in) ,  dimension(:,:,:) :: b

integer :: i

do i = 1,nx
  ii(i,:,:) = i-1 
end do

ii = ii - floor(b)

where(ii.gt.nx) ii = ii - nx
where(ii.lt.1 ) ii = ii + nx

return
end subroutine find_cell_x

!===========================================================================================

subroutine slope_x(slope, q)

real, intent(in),  dimension(:,:,:) :: q
real, intent(out), dimension(:,:,:) :: slope

real, dimension(size(q,1),size(q,2),size(q,3)) :: grad, q_min, q_max
integer :: n
#ifdef USE_CUDA_FV_ADVECTION_KERNELS
integer :: ierr
#endif

#if !defined(USE_CPP_FV_ADVECTION_KERNELS) && !defined(USE_CUDA_FV_ADVECTION_KERNELS)
n = size(q,1)

grad(2:n,:,:)  = q(2:n,:,:)-q(1:n-1,:,:)
grad(1,:,:)    = q(1,:,:)-q(n,:,:)

slope(1:n-1,:,:) = (grad(2:n,:,:) + grad(1:n-1,:,:))/2
slope(n,:,:) = (grad(1,:,:) + grad(n,:,:))/2

if(monotone) then

  q_min(2:n-1,:,:) = min(q(1:n-2,:,:),q(2:n-1,:,:),q(3:n,:,:))
  q_min(1,:,:)     = min(q(n,:,:)    ,q(1,:,:)    ,q(2,:,:)  )
  q_min(n,:,:)     = min(q(n-1,:,:)  ,q(n,:,:)    ,q(1,:,:)  )

  q_max(2:n-1,:,:) = max(q(1:n-2,:,:),q(2:n-1,:,:),q(3:n,:,:))
  q_max(1,:,:)     = max(q(n,:,:)    ,q(1,:,:)    ,q(2,:,:)  )
  q_max(n,:,:)     = max(q(n-1,:,:)  ,q(n,:,:)    ,q(1,:,:)  )

  slope = sign(1.0,slope) * min( abs(slope), 2.0*(q - q_min), 2.0*(q_max - q))
else
  slope = sign(1.0,slope) * min( abs(slope), 2.0*q )
end if
#elif defined(USE_CUDA_FV_ADVECTION_KERNELS)
call slope_x_cuda_wrapper(size(q,1), js, js + size(q,2) - 1, size(q,3), monotone, q, slope, ierr)
if (ierr /= 0) call error_mesg('fv_advection_mod', 'slope_x CUDA wrapper failed', FATAL)
#else
call slope_x_cpp_wrapper(size(q,1), js, js + size(q,2) - 1, size(q,3), monotone, q, slope)
#endif

return
end subroutine slope_x

!===========================================================================================

subroutine integer_flux_x(flux, c, q)

real, intent(out),  dimension(:,:,:) :: flux
real, intent(in) ,  dimension(:,:,:) :: c, q

integer, dimension(size(c,1),size(c,2),size(c,3)) :: ii
integer :: n, i, j, k
#ifdef USE_CUDA_FV_ADVECTION_KERNELS
integer :: ierr
#endif

#if !defined(USE_CPP_FV_ADVECTION_KERNELS) && !defined(USE_CUDA_FV_ADVECTION_KERNELS)
n = size(c,1)
ii = int(c)

flux = 0.0

do k = 1, size(c,3)
  do j = 1, size(c,2)

      do i = 1, size(c,1)
        if(ii(i,j,k) >= 1) then
          if(i-ii(i,j,k) >= 1) then
             flux(i,j,k) = sum(q(i-ii(i,j,k):i-1,j,k))
          else
             flux(i,j,k) = sum(q(1:i-1,j,k)) + sum(q(i-ii(i,j,k)+n:n,j,k))
          end if
        else if (ii(i,j,k) <= -1) then
          if(i-1-ii(i,j,k) <= n) then
            flux(i,j,k) = -sum(q(i:i-1-ii(i,j,k),j,k))
          else
            flux(i,j,k) = -sum(q(i:n,j,k)) - sum(q(1:i-1-ii(i,j,k)-n,j,k))
          end if
        end if
      end do

  end do
end do
#elif defined(USE_CUDA_FV_ADVECTION_KERNELS)
call integer_flux_x_cuda_wrapper(size(c,1), 1, size(c,2), size(c,3), c, q, flux, ierr)
if (ierr /= 0) call error_mesg('fv_advection_mod', 'integer_flux_x CUDA wrapper failed', FATAL)
#else
call integer_flux_x_cpp_wrapper(size(c,1), 1, size(c,2), size(c,3), c, q, flux)
#endif
return
end subroutine integer_flux_x

!===========================================================================================

subroutine slope_sphere(slope, q)

real, intent(in),  dimension(:,js-2:,:) :: q
real, intent(out), dimension(:,js-1:,:) :: slope

real, dimension(nx,js-1:je+1,size(q,3)) :: q_max, q_min
integer :: j
#ifdef USE_CUDA_FV_ADVECTION_KERNELS
integer :: ierr
#endif

#if !defined(USE_CPP_FV_ADVECTION_KERNELS) && !defined(USE_CUDA_FV_ADVECTION_KERNELS)
do j = js-1, je+1
  slope(:,j,:) = (q(:,j+1,:) - q(:,j  ,:))*dy_plus (j) &
               + (q(:,j  ,:) - q(:,j-1,:))*dy_minus(j)
end do

if(monotone) then
  q_min = min(q(:,js-2:je,:),q(:,js-1:je+1,:),q(:,js:je+2,:))
  q_max = max(q(:,js-2:je,:),q(:,js-1:je+1,:),q(:,js:je+2,:))

  slope = sign(1.0,slope) * &
        min( abs(slope), 2.0*(q(:,js-1:je+1,:) - q_min), 2.0*(q_max - q(:,js-1:je+1,:)) )
else
  slope = sign(1.0,slope) * min( abs(slope), 2.0*q(:,js-1:je+1,:) )
end if
#elif defined(USE_CUDA_FV_ADVECTION_KERNELS)
call slope_sphere_cuda_wrapper(nx, js, je, size(q,3), monotone, dy_plus(js-1:je+1), &
  dy_minus(js-1:je+1), q, slope, ierr)
if (ierr /= 0) call error_mesg('fv_advection_mod', 'slope_sphere CUDA wrapper failed', FATAL)
#else
call slope_sphere_cpp_wrapper(nx, js, je, size(q,3), monotone, dy_plus(js-1:je+1), &
  dy_minus(js-1:je+1), q, slope)
#endif
return
end subroutine slope_sphere

!===========================================================================================

subroutine solid_body(u, v)

!  used for check-out only

real, intent(out), dimension(nx,ny) :: u,v
real :: beta
integer :: i,j

beta = 45.0

do j = 1, ny
  do i = 1, nx
    v(i,j) = - sin(beta*pi/180.0)*sin(2.*pi*float(i)/float(nx))
    u(i,j) =   cos(beta*pi/180.0)*c(j)        &
             + sin(beta*pi/180.0)*cos(2.*pi*float(i)/float(nx))*s(j)
  end do
end do

end subroutine solid_body

!===========================================================================================
subroutine fv_advection_end

if(.not.module_is_initialized) return

! Transfer PoC (addition 3): report the per-rank host-routed halo-exchange cost.
if (halo_calls > 0) then
  write(*,'(a,i0,a,i0,a,es16.9,a,es16.9)') &
    'PROFILE_FV_ADVECTION_HALO rank=', mpp_pe(), &
    ' calls=', halo_calls, &
    ' time=', halo_seconds, &
    ' avg=', halo_seconds / real(halo_calls, 8)
end if

deallocate(y, yy, c, s, cc, dy, dyy, dyyy, dy_plus, dy_minus)
module_is_initialized = .false.

return
end subroutine fv_advection_end
!===========================================================================================

end module fv_advection_mod
