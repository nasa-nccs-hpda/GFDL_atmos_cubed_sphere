! OpenACC residency port of fv_advection_mod::advection_sphere_3d and its leaf
! routines, direct Fortran->GPU (nvfortran, no C++/CUDA layer).
!
! Structure mirrors src/atmos_spectral/model/fv_advection.F90. The leaf kernels
! run on the device with data assumed present; advection_sphere_3d keeps all
! working arrays resident in one !$acc data region so no per-call host-device
! transfer occurs inside the chain.
!
! Single-tile assumption (js=1, je=ny): the mid-routine mpp_update_domains(q1)
! in the real code is a y-halo exchange. On one tile both poles are local, so
! the halo is filled by the polar fixups (done on device here). The real
! multi-rank model keeps this residency and brackets the exchange with
! !$acc update host(q1 halo) / !$acc update device(q1 halo) around the MPI call.
!
! Validation: the SAME annotated code runs once on the host device and once on
! the GPU (via acc_set_device_type); we compare max|host-device| (checks the
! parallelization is race-free and reorder-stable) and report CPU, per-call GPU,
! and resident GPU timing.
!
! Build + run (host GPU node):
!   module load nvidia/12.8
!   nvfortran -O2 -cpp -r8 -acc -gpu=ccnative -Minfo=accel \
!       acc_advection_sphere.F90 -o acc_advection_sphere && ./acc_advection_sphere

module adv_sphere_mod
  use openacc
  implicit none

  ! Problem size (single tile, js=1..je=ny).
  integer, parameter :: nx = 256
  integer, parameter :: ny = 256
  integer, parameter :: nz = 64
  logical, parameter :: monotone = .true.

  real, parameter :: pi = 3.14159265358979323846d0
  real, parameter :: radius = 6.371d6

  ! Grid metrics (mirror fv_advection_init).
  real :: c(ny), s(ny), cc(ny+1)
  real :: dy(-1:ny+2), dyy(ny+1)
  real :: dy_plus(0:ny+1), dy_minus(0:ny+1)
  real :: dx

contains

  subroutine init_metrics()
    real :: yy(ny+1), y(ny)
    integer :: j
    do j = 1, ny+1
      yy(j) = -0.5d0*pi + real(j-1)*pi/real(ny)
    end do
    y  = 0.5d0*(yy(2:ny+1) + yy(1:ny))
    c  = cos(y)
    s  = sin(y)
    cc = cos(yy)
    dy(1:ny) = yy(2:ny+1) - yy(1:ny)
    dy(-1) = dy(2); dy(0) = dy(1); dy(ny+1) = dy(ny); dy(ny+2) = dy(ny-1)
    dyy(2:ny) = y(2:ny) - y(1:ny-1)
    dyy(1)    = 2.d0*(y(1) - yy(1))
    dyy(ny+1) = 2.d0*(yy(ny+1) - y(ny))
    dy_plus (0:ny+1) = dy(0:ny+1)/(dy(0:ny+1) + dy(1:ny+2))
    dy_minus(0:ny+1) = dy(0:ny+1)/(dy(-1:ny) + dy(0:ny+1))
    y   = y*radius;  yy = yy*radius
    dy  = dy*radius; dyy = dyy*radius
    dx  = 2.d0*pi*radius/real(nx)
  end subroutine init_metrics

  ! ---- leaf kernels (device, data present) ----

  subroutine semi_x_3d(dq, ua, q, dt)
    real, intent(out) :: dq(nx,ny,nz)
    real, intent(in)  :: ua(nx,ny,nz), q(nx,ny,nz)
    real, intent(in)  :: dt
    integer :: i, j, k, il, ir
    real :: b, bb
    !$acc parallel loop collapse(3) present(dq,ua,q,c) private(b,bb,il,ir)
    do k = 1, nz
      do j = 1, ny
        do i = 1, nx
          b  = ua(i,j,k)*dt/(dx*c(j))
          il = i - 1 - floor(b)
          do while (il > nx); il = il - nx; end do
          do while (il < 1 ); il = il + nx; end do
          ir = il + 1; if (ir > nx) ir = 1
          bb = b - floor(b)
          dq(i,j,k) = bb*q(il,j,k) + (1.d0 - bb)*q(ir,j,k) - q(i,j,k)
        end do
      end do
    end do
  end subroutine semi_x_3d

  subroutine semi_y_3d(dq, va, qx, dt)
    real, intent(out) :: dq(nx,ny,nz)
    real, intent(in)  :: va(nx,ny,nz), qx(nx,-1:ny+2,nz)
    real, intent(in)  :: dt
    integer :: i, j, k
    !$acc parallel loop collapse(3) present(dq,va,qx,dyy)
    do k = 1, nz
      do j = 1, ny
        do i = 1, nx
          if (va(i,j,k) >= 0.d0) then
            dq(i,j,k) = va(i,j,k)*dt*(qx(i,j-1,k) - qx(i,j,k))/dyy(j)
          else
            dq(i,j,k) = va(i,j,k)*dt*(qx(i,j,k) - qx(i,j+1,k))/dyy(j+1)
          end if
        end do
      end do
    end do
  end subroutine semi_y_3d

  subroutine slope_x(slope, q)
    real, intent(out) :: slope(nx,ny,nz)
    real, intent(in)  :: q(nx,ny,nz)
    integer :: i, j, k, im, ip
    real :: sl, qmin, qmax
    !$acc parallel loop collapse(3) present(slope,q) private(sl,qmin,qmax,im,ip)
    do k = 1, nz
      do j = 1, ny
        do i = 1, nx
          im = i - 1; if (im < 1 ) im = nx
          ip = i + 1; if (ip > nx) ip = 1
          sl = 0.5d0*(q(ip,j,k) - q(im,j,k))
          if (monotone) then
            qmin = min(q(im,j,k), q(i,j,k), q(ip,j,k))
            qmax = max(q(im,j,k), q(i,j,k), q(ip,j,k))
            sl = sign(1.d0, sl)*min(abs(sl), 2.d0*(q(i,j,k)-qmin), 2.d0*(qmax-q(i,j,k)))
          else
            sl = sign(1.d0, sl)*min(abs(sl), 2.d0*q(i,j,k))
          end if
          slope(i,j,k) = sl
        end do
      end do
    end do
  end subroutine slope_x

  subroutine integer_flux_x(flux, cin, q)
    real, intent(out) :: flux(nx,ny,nz)
    real, intent(in)  :: cin(nx,ny,nz), q(nx,ny,nz)
    integer :: i, j, k, m, ic
    real :: acc
    !$acc parallel loop collapse(3) present(flux,cin,q) private(acc,ic,m)
    do k = 1, nz
      do j = 1, ny
        do i = 1, nx
          ic = int(cin(i,j,k))
          acc = 0.d0
          if (ic >= 1) then
            if (i - ic >= 1) then
              do m = i-ic, i-1; acc = acc + q(m,j,k); end do
            else
              do m = 1, i-1;      acc = acc + q(m,j,k); end do
              do m = i-ic+nx, nx; acc = acc + q(m,j,k); end do
            end if
          else if (ic <= -1) then
            if (i-1-ic <= nx) then
              do m = i, i-1-ic; acc = acc - q(m,j,k); end do
            else
              do m = i, nx;        acc = acc - q(m,j,k); end do
              do m = 1, i-1-ic-nx; acc = acc - q(m,j,k); end do
            end if
          end if
          flux(i,j,k) = acc
        end do
      end do
    end do
  end subroutine integer_flux_x

  subroutine vanleer_x_3d(dq_dt, uc, q, dt)
    real, intent(inout) :: dq_dt(nx,ny,nz)
    real, intent(in)    :: uc(nx,ny,nz), q(nx,ny,nz)
    real, intent(in)    :: dt
    real :: b(nx,ny,nz), bb(nx,ny,nz), s(nx,ny,nz), intf(nx,ny,nz)
    real :: fl(nx+1,ny,nz)
    integer :: i, j, k, ii
    !$acc data present(dq_dt,uc,q,c) create(b,bb,s,intf,fl)
    !$acc parallel loop collapse(3) present(b,bb,uc,c)
    do k = 1, nz
      do j = 1, ny
        do i = 1, nx
          b(i,j,k)  = uc(i,j,k)*dt/(dx*c(j))
          bb(i,j,k) = b(i,j,k) - int(b(i,j,k))
        end do
      end do
    end do
    call integer_flux_x(intf, b, q)   ! full array; 0 where int(b)=0
    call slope_x(s, q)
    !$acc parallel loop collapse(3) present(fl,intf,bb,q,s,b) private(ii)
    do k = 1, nz
      do j = 1, ny
        do i = 1, nx
          ii = i - 1 - floor(b(i,j,k))
          do while (ii > nx); ii = ii - nx; end do
          do while (ii < 1 ); ii = ii + nx; end do
          fl(i,j,k) = intf(i,j,k) + bb(i,j,k)*(q(ii,j,k) &
                    + 0.5d0*s(ii,j,k)*(sign(1.d0,bb(i,j,k)) - bb(i,j,k)))
        end do
      end do
    end do
    !$acc parallel loop collapse(2) present(fl)
    do k = 1, nz
      do j = 1, ny
        fl(nx+1,j,k) = fl(1,j,k)
      end do
    end do
    !$acc parallel loop collapse(3) present(dq_dt,fl)
    do k = 1, nz
      do j = 1, ny
        do i = 1, nx
          dq_dt(i,j,k) = dq_dt(i,j,k) - (fl(i+1,j,k) - fl(i,j,k))/dt
        end do
      end do
    end do
    !$acc end data
  end subroutine vanleer_x_3d

  subroutine slope_sphere(slope, q)
    real, intent(out) :: slope(nx,0:ny+1,nz)
    real, intent(in)  :: q(nx,-1:ny+2,nz)
    integer :: i, j, k
    real :: sl, qmin, qmax
    !$acc parallel loop collapse(3) present(slope,q,dy_plus,dy_minus) private(sl,qmin,qmax)
    do k = 1, nz
      do j = 0, ny+1
        do i = 1, nx
          sl = (q(i,j+1,k) - q(i,j,k))*dy_plus(j) &
             + (q(i,j,k) - q(i,j-1,k))*dy_minus(j)
          if (monotone) then
            qmin = min(q(i,j-1,k), q(i,j,k), q(i,j+1,k))
            qmax = max(q(i,j-1,k), q(i,j,k), q(i,j+1,k))
            sl = sign(1.d0, sl)*min(abs(sl), 2.d0*(q(i,j,k)-qmin), 2.d0*(qmax-q(i,j,k)))
          else
            sl = sign(1.d0, sl)*min(abs(sl), 2.d0*q(i,j,k))
          end if
          slope(i,j,k) = sl
        end do
      end do
    end do
  end subroutine slope_sphere

  subroutine vanleer_sphere_3d(dq_dt, vc, q, dt)
    real, intent(inout) :: dq_dt(nx,ny,nz)
    real, intent(in)    :: vc(nx,ny+1,nz), q(nx,-1:ny+2,nz)
    real, intent(in)    :: dt
    real :: sl(nx,0:ny+1,nz), fl(nx,ny+1,nz)
    integer :: i, j, k
    real :: dtdym1, dtdyj
    !$acc data present(dq_dt,vc,q,dy,c,cc) create(sl,fl)
    call slope_sphere(sl, q)
    !$acc parallel loop collapse(3) present(fl,vc,q,sl,dy,cc) private(dtdym1,dtdyj)
    do k = 1, nz
      do j = 1, ny+1
        do i = 1, nx
          dtdym1 = dt/dy(j-1)
          dtdyj  = dt/dy(j)
          if (vc(i,j,k) >= 0.d0) then
            fl(i,j,k) = vc(i,j,k)*cc(j)*(q(i,j-1,k) &
                      + 0.5d0*sl(i,j-1,k)*(1.d0 - dtdym1*vc(i,j,k)))
          else
            fl(i,j,k) = vc(i,j,k)*cc(j)*(q(i,j,k) &
                      - 0.5d0*sl(i,j,k)*(1.d0 + dtdyj*vc(i,j,k)))
          end if
        end do
      end do
    end do
    ! single tile: both poles local -> zero polar flux
    !$acc parallel loop collapse(2) present(fl)
    do k = 1, nz
      do i = 1, nx
        fl(i,1,k)    = 0.d0
        fl(i,ny+1,k) = 0.d0
      end do
    end do
    !$acc parallel loop collapse(3) present(dq_dt,fl,dy,c)
    do k = 1, nz
      do j = 1, ny
        do i = 1, nx
          dq_dt(i,j,k) = dq_dt(i,j,k) - (fl(i,j+1,k) - fl(i,j,k))/(dy(j)*c(j))
        end do
      end do
    end do
    !$acc end data
  end subroutine vanleer_sphere_3d

  ! ---- orchestration: residency across the whole chain ----

  subroutine advection_sphere_3d(dq_dt, dt, q, uc, vc, ua, va)
    real, intent(inout) :: dq_dt(nx,ny,nz)
    real, intent(in)    :: q(nx,-1:ny+2,nz)
    real, intent(in)    :: uc(nx,ny,nz), vc(nx,ny+1,nz), ua(nx,ny,nz), va(nx,ny,nz)
    real, intent(in)    :: dt
    real :: q1(nx,-1:ny+2,nz), q2(nx,ny,nz), tmp(nx,ny,nz)
    integer :: i, j, k, ii

    ! Working arrays resident for the whole routine. Inputs assumed present
    ! (caller's outer data region); create the temporaries here.
    !$acc data present(dq_dt,q,uc,vc,ua,va) create(q1,q2,tmp)

    call semi_x_3d(tmp, ua, q(:,1:ny,:), 0.5d0*dt)
    !$acc parallel loop collapse(3) present(q1,q,tmp)
    do k = 1, nz
      do j = 1, ny
        do i = 1, nx
          q1(i,j,k) = q(i,j,k) + tmp(i,j,k)
        end do
      end do
    end do

    call semi_y_3d(tmp, va, q, 0.5d0*dt)
    !$acc parallel loop collapse(3) present(q2,q,tmp)
    do k = 1, nz
      do j = 1, ny
        do i = 1, nx
          q2(i,j,k) = q(i,j,k) + tmp(i,j,k)
        end do
      end do
    end do

    ! mpp_update_domains(q1) stand-in for single tile: polar halo fixups
    ! (i -> i+nx/2 wrap). Real multi-rank model brackets the MPI exchange with
    ! !$acc update host/device on the q1 halo rows here instead.
    !$acc parallel loop collapse(2) present(q1) private(ii)
    do k = 1, nz
      do i = 1, nx
        ii = i + nx/2; if (ii > nx) ii = ii - nx
        q1(i, 0,k)    = q1(ii,1,k)
        q1(i,-1,k)    = q1(ii,2,k)
        q1(i,ny+1,k)  = q1(ii,ny,k)
        q1(i,ny+2,k)  = q1(ii,ny-1,k)
      end do
    end do

    call vanleer_x_3d(dq_dt, uc, q2, dt)
    call vanleer_sphere_3d(dq_dt, vc, q1, dt)

    !$acc end data
  end subroutine advection_sphere_3d

end module adv_sphere_mod

program acc_advection_sphere
  use adv_sphere_mod
  implicit none

  real :: dq_dt(nx,ny,nz), dq0(nx,ny,nz), dqh(nx,ny,nz)
  real :: q(nx,-1:ny+2,nz), uc(nx,ny,nz), vc(nx,ny+1,nz), ua(nx,ny,nz), va(nx,ny,nz)
  integer :: i, j, k, it, niters
  integer(8) :: t0, t1, rate
  real :: tcpu, tpc, tres, maxdiff

  niters = 50
  call init_metrics()

  do k = 1, nz
    do j = -1, ny+2
      do i = 1, nx
        q(i,j,k) = 230.d0 + 0.17d0*real(i) - 0.11d0*real(j) + 0.07d0*real(k) &
                 + 0.013d0*real(mod(i*max(j,1)+k,5))
      end do
    end do
  end do
  do k = 1, nz
    do j = 1, ny
      do i = 1, nx
        ua(i,j,k) = -1.15d0 + 0.31d0*real(mod(i+2*j+k,7))
        uc(i,j,k) = -1.85d0 + 0.47d0*real(mod(2*i+j+3*k,9))
        va(i,j,k) = -1.10d0 + 0.29d0*real(mod(2*i+j+3*k,7))
      end do
    end do
  end do
  do k = 1, nz
    do j = 1, ny+1
      do i = 1, nx
        vc(i,j,k) = -1.40d0 + 0.36d0*real(mod(i+3*j+2*k,8))
      end do
    end do
  end do
  dq0 = 0.013d0

  write(*,'(A,I0)') 'acc_get_num_devices(nvidia) = ', acc_get_num_devices(acc_device_nvidia)

  ! Reference on host device (same annotated code).
  call acc_set_device_type(acc_device_host)
  dq_dt = dq0
  call system_clock(t0, rate)
  do it = 1, niters
    dq_dt = dq0
    call advection_sphere_3d(dq_dt, 900.d0, q, uc, vc, ua, va)
  end do
  call system_clock(t1)
  tcpu = real(t1 - t0)/real(rate)
  dqh = dq_dt

  ! GPU, per-call transfer (no outer data region).
  call acc_set_device_type(acc_device_nvidia)
  call system_clock(t0, rate)
  do it = 1, niters
    dq_dt = dq0
    call advection_sphere_3d(dq_dt, 900.d0, q, uc, vc, ua, va)
  end do
  call system_clock(t1)
  tpc = real(t1 - t0)/real(rate)

  ! GPU, resident: inputs stay on device across all iterations.
  !$acc data copyin(q,uc,vc,ua,va,dq0) copyout(dq_dt)
  call system_clock(t0, rate)
  do it = 1, niters
    !$acc parallel loop collapse(3) present(dq_dt,dq0)
    do k = 1, nz
      do j = 1, ny
        do i = 1, nx
          dq_dt(i,j,k) = dq0(i,j,k)
        end do
      end do
    end do
    call advection_sphere_3d(dq_dt, 900.d0, q, uc, vc, ua, va)
  end do
  call system_clock(t1)
  !$acc end data
  tres = real(t1 - t0)/real(rate)

  maxdiff = 0.d0
  do k = 1, nz
    do j = 1, ny
      do i = 1, nx
        maxdiff = max(maxdiff, abs(dqh(i,j,k) - dq_dt(i,j,k)))
      end do
    end do
  end do

  write(*,'(A,I0,A,I0,A,I0,A,I0)') 'size nx=', nx, ' ny=', ny, ' nz=', nz, ' niters=', niters
  write(*,'(A,ES12.4,A)') 'host time            = ', tcpu, ' s'
  write(*,'(A,ES12.4,A)') 'gpu  time (per-call) = ', tpc,  ' s'
  write(*,'(A,ES12.4,A)') 'gpu  time (resident) = ', tres, ' s'
  write(*,'(A,F8.2)')     'host/gpu per-call    = ', tcpu/max(tpc, 1.d-30)
  write(*,'(A,F8.2)')     'host/gpu resident    = ', tcpu/max(tres,1.d-30)
  write(*,'(A,ES12.4)')   'max|host-gpu|        = ', maxdiff
end program acc_advection_sphere
