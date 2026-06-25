module fv_advection_kernel_baseline_mod
  implicit none

  integer, parameter :: nx = 8
  integer, parameter :: ny = 8
  integer, parameter :: js = 2
  integer, parameter :: je = 6
  integer, parameter :: nz = 3

  logical :: monotone = .true.
  real :: dx = 1.25
  real, dimension(js:je) :: c
  real, dimension(js:je+1) :: cc
  real, dimension(js-1:je+1) :: dy
  real, dimension(js-1:je+1) :: dy_plus, dy_minus

contains

  subroutine init_metrics()
    integer :: j

    do j = js, je
      c(j) = 0.72 + 0.035*real(j)
    end do

    do j = js, je+1
      cc(j) = 0.81 + 0.025*real(j)
    end do

    do j = js-1, je+1
      dy(j) = 1.02 + 0.018*real(j)
      dy_plus(j) = 0.45 + 0.015*real(j)
      dy_minus(j) = 0.38 + 0.012*real(j)
    end do
  end subroutine init_metrics

  subroutine init_x_inputs(ua, uc, q)
    real, intent(out), dimension(nx,js:je,nz) :: ua, uc, q
    integer :: i, j, k

    do k = 1, nz
      do j = js, je
        do i = 1, nx
          q(i,j,k) = 230.0 + 0.17*real(i) - 0.11*real(j) + 0.07*real(k) &
                   + 0.013*real(mod(i*j + k, 5))
          ua(i,j,k) = -1.15 + 0.31*real(mod(i + 2*j + k, 7))
          uc(i,j,k) = -1.85 + 0.47*real(mod(2*i + j + 3*k, 9))
        end do
      end do
    end do
  end subroutine init_x_inputs

  subroutine init_sphere_inputs(vc, q)
    real, intent(out), dimension(nx,js:je+1,nz) :: vc
    real, intent(out), dimension(nx,js-2:je+2,nz) :: q
    integer :: i, j, k

    do k = 1, nz
      do j = js-2, je+2
        do i = 1, nx
          q(i,j,k) = 0.95 + 0.021*real(i*i) - 0.037*real(j) + 0.064*real(k) &
                   + 0.009*real(mod(i + j + 2*k, 6))
        end do
      end do

      do j = js, je+1
        do i = 1, nx
          vc(i,j,k) = -1.40 + 0.36*real(mod(i + 3*j + 2*k, 8))
        end do
      end do
    end do
  end subroutine init_sphere_inputs

  subroutine write_real_1d(path, values)
    character(len=*), intent(in) :: path
    real, intent(in), dimension(:) :: values
    integer :: unit

    open(newunit=unit, file=path, access='stream', form='unformatted', status='replace')
    write(unit) values
    close(unit)
  end subroutine write_real_1d

  subroutine write_real_3d(path, values)
    character(len=*), intent(in) :: path
    real, intent(in), dimension(:,:,:) :: values
    integer :: unit

    open(newunit=unit, file=path, access='stream', form='unformatted', status='replace')
    write(unit) values
    close(unit)
  end subroutine write_real_3d

  subroutine write_int_3d(path, values)
    character(len=*), intent(in) :: path
    integer, intent(in), dimension(:,:,:) :: values
    integer :: unit

    open(newunit=unit, file=path, access='stream', form='unformatted', status='replace')
    write(unit) values
    close(unit)
  end subroutine write_int_3d

  subroutine write_params(path, dt)
    character(len=*), intent(in) :: path
    real, intent(in) :: dt
    integer :: unit

    open(newunit=unit, file=path, status='replace', action='write')
    write(unit,'(A,I0)') 'nx=', nx
    write(unit,'(A,I0)') 'ny=', ny
    write(unit,'(A,I0)') 'js=', js
    write(unit,'(A,I0)') 'je=', je
    write(unit,'(A,I0)') 'nz=', nz
    write(unit,'(A,L1)') 'monotone=', monotone
    write(unit,'(A,ES24.16)') 'dx=', dx
    write(unit,'(A,ES24.16)') 'dt=', dt
    close(unit)
  end subroutine write_params

  subroutine vanleer_sphere_3d(dq_dt, vc, q, dt)
    real, intent(inout), dimension(:,js:,:) :: dq_dt
    real, intent(in), dimension(:,js:,:) :: vc
    real, intent(in), dimension(:,js-2:,:) :: q
    real, intent(in) :: dt

    real, dimension(nx,js-1:je+1,size(q,3)) :: slope
    real, dimension(nx,js:je+1,size(q,3)) :: flux
    integer :: j

    call slope_sphere(slope, q)

    do j = js, je+1
      where(vc(:,j,:) >= 0.0)
        flux(:,j,:) = vc(:,j,:)*cc(j) * &
          (q(:,j-1,:) + 0.5*slope(:,j-1,:)*(1.0 - vc(:,j,:)*dt/dy(j-1)))
      elsewhere
        flux(:,j,:) = vc(:,j,:)*cc(j) * &
          (q(:,j,:) - 0.5*slope(:,j,:)*(1.0 + vc(:,j,:)*dt/dy(j)))
      end where
    end do

    if(js == 1 ) flux(:,js  ,:) = 0.0
    if(je == ny) flux(:,je+1,:) = 0.0

    do j = js, je
      dq_dt(:,j,:) = dq_dt(:,j,:) - (flux(:,j+1,:) - flux(:,j,:))/(dy(j)*c(j))
    end do
  end subroutine vanleer_sphere_3d

  subroutine vanleer_x_3d(dq_dt, uc, q, dt)
    real, intent(inout), dimension(:,js:,:) :: dq_dt
    real, intent(in), dimension(:,js:,:) :: uc, q
    real, intent(in) :: dt

    real, dimension(nx,js:je,size(q,3)) :: b, bb, qq, ss, slope, int_flux
    real, dimension(nx+1,js:je,size(q,3)) :: flux
    integer, dimension(nx,js:je,size(q,3)) :: ii
    integer :: i, j, k, iii

    do j = js, je
      b(:,j,:) = uc(:,j,:)*dt/(dx*c(j))
    end do

    bb = b - int(b)
    int_flux = 0.0
    if(maxval(abs(b)) > 1.0) then
      call integer_flux_x(int_flux,b,q)
    end if

    call slope_x(slope, q)
    call find_cell_x(ii,b)

    do k = 1, size(q,3)
      do j = js, je
        do i = 1, nx
          iii = ii(i,j,k)
          qq(i,j,k) = q(iii,j,k)
          ss(i,j,k) = slope(iii,j,k)
        end do
      end do
    end do

    flux(1:nx,:,:) = int_flux + bb*(qq + 0.5*ss*(sign(1.0,bb) - bb))
    flux(nx+1,:,:) = flux(1,:,:)

    dq_dt = dq_dt - (flux(2:nx+1,:,:) - flux(1:nx,:,:))/dt

    do j = js, je
      flux(:,j,:) = flux(:,j,:)*dt/(dx*c(j))
    end do
  end subroutine vanleer_x_3d

  subroutine semi_x_3d(dq, ua, q, dt)
    real, intent(in), dimension(:,js:,:) :: ua, q
    real, intent(in) :: dt
    real, intent(out), dimension(:,js:,:) :: dq

    real, dimension(nx,js:je,size(q,3)) :: b, bb, q_left, q_right
    integer, dimension(nx,js:je,size(q,3)) :: ii, i_left, i_right
    integer :: i, j, k

    do j = js, je
      b(:,j,:) = ua(:,j,:)*dt/(dx*c(j))
    end do

    call find_cell_x(ii,b)

    i_left = ii
    i_right = i_left + 1
    where(i_right > nx) i_right = 1

    bb = b - floor(b)

    do k = 1, size(q,3)
      do j = js, je
        do i = 1, nx
          q_left (i,j,k) = q(i_left (i,j,k),j,k)
          q_right(i,j,k) = q(i_right(i,j,k),j,k)
        end do
      end do
    end do

    dq(:,js:je,:) = bb(:,js:je,:)*q_left(:,js:je,:) + (1.0 - bb(:,js:je,:))*q_right(:,js:je,:) &
                  - q(:,js:je,:)
  end subroutine semi_x_3d

  subroutine find_cell_x(ii,b)
    integer, intent(out), dimension(:,:,:) :: ii
    real, intent(in), dimension(:,:,:) :: b
    integer :: i

    do i = 1, nx
      ii(i,:,:) = i - 1
    end do

    ii = ii - floor(b)
    where(ii > nx) ii = ii - nx
    where(ii < 1 ) ii = ii + nx
  end subroutine find_cell_x

  subroutine slope_x(slope, q)
    real, intent(in), dimension(:,:,:) :: q
    real, intent(out), dimension(:,:,:) :: slope

    real, dimension(size(q,1),size(q,2),size(q,3)) :: grad, q_min, q_max
    integer :: n

    n = size(q,1)
    grad(2:n,:,:) = q(2:n,:,:) - q(1:n-1,:,:)
    grad(1,:,:) = q(1,:,:) - q(n,:,:)

    slope(1:n-1,:,:) = (grad(2:n,:,:) + grad(1:n-1,:,:))/2
    slope(n,:,:) = (grad(1,:,:) + grad(n,:,:))/2

    if(monotone) then
      q_min(2:n-1,:,:) = min(q(1:n-2,:,:),q(2:n-1,:,:),q(3:n,:,:))
      q_min(1,:,:) = min(q(n,:,:),q(1,:,:),q(2,:,:))
      q_min(n,:,:) = min(q(n-1,:,:),q(n,:,:),q(1,:,:))

      q_max(2:n-1,:,:) = max(q(1:n-2,:,:),q(2:n-1,:,:),q(3:n,:,:))
      q_max(1,:,:) = max(q(n,:,:),q(1,:,:),q(2,:,:))
      q_max(n,:,:) = max(q(n-1,:,:),q(n,:,:),q(1,:,:))

      slope = sign(1.0,slope) * min(abs(slope), 2.0*(q - q_min), 2.0*(q_max - q))
    else
      slope = sign(1.0,slope) * min(abs(slope), 2.0*q)
    end if
  end subroutine slope_x

  subroutine integer_flux_x(flux, c_in, q)
    real, intent(out), dimension(:,:,:) :: flux
    real, intent(in), dimension(:,:,:) :: c_in, q

    integer, dimension(size(c_in,1),size(c_in,2),size(c_in,3)) :: ii
    integer :: n, i, j, k

    n = size(c_in,1)
    ii = int(c_in)
    flux = 0.0

    do k = 1, size(c_in,3)
      do j = 1, size(c_in,2)
        do i = 1, size(c_in,1)
          if(ii(i,j,k) >= 1) then
            if(i-ii(i,j,k) >= 1) then
              flux(i,j,k) = sum(q(i-ii(i,j,k):i-1,j,k))
            else
              flux(i,j,k) = sum(q(1:i-1,j,k)) + sum(q(i-ii(i,j,k)+n:n,j,k))
            end if
          else if(ii(i,j,k) <= -1) then
            if(i-1-ii(i,j,k) <= n) then
              flux(i,j,k) = -sum(q(i:i-1-ii(i,j,k),j,k))
            else
              flux(i,j,k) = -sum(q(i:n,j,k)) - sum(q(1:i-1-ii(i,j,k)-n,j,k))
            end if
          end if
        end do
      end do
    end do
  end subroutine integer_flux_x

  subroutine slope_sphere(slope, q)
    real, intent(in), dimension(:,js-2:,:) :: q
    real, intent(out), dimension(:,js-1:,:) :: slope

    real, dimension(nx,js-1:je+1,size(q,3)) :: q_max, q_min
    integer :: j

    do j = js-1, je+1
      slope(:,j,:) = (q(:,j+1,:) - q(:,j,:))*dy_plus(j) &
                   + (q(:,j,:) - q(:,j-1,:))*dy_minus(j)
    end do

    if(monotone) then
      q_min = min(q(:,js-2:je,:),q(:,js-1:je+1,:),q(:,js:je+2,:))
      q_max = max(q(:,js-2:je,:),q(:,js-1:je+1,:),q(:,js:je+2,:))

      slope = sign(1.0,slope) * &
            min(abs(slope), 2.0*(q(:,js-1:je+1,:) - q_min), 2.0*(q_max - q(:,js-1:je+1,:)))
    else
      slope = sign(1.0,slope) * min(abs(slope), 2.0*q(:,js-1:je+1,:))
    end if
  end subroutine slope_sphere

end module fv_advection_kernel_baseline_mod

program test_fv_advection_kernels
  use fv_advection_kernel_baseline_mod
  implicit none

  real, parameter :: dt = 1.5
  real, dimension(nx,js:je,nz) :: ua, uc, q_x
  real, dimension(nx,js:je,nz) :: b_x, dq_semi_x, slope_x_out, integer_flux_out
  real, dimension(nx,js:je,nz) :: dq_vanleer_x
  real, dimension(nx,js-2:je+2,nz) :: q_sphere
  real, dimension(nx,js:je+1,nz) :: vc
  real, dimension(nx,js-1:je+1,nz) :: slope_sphere_out
  real, dimension(nx,js:je,nz) :: dq_vanleer_sphere
  integer, dimension(nx,js:je,nz) :: ii
  integer :: j

  call execute_command_line('mkdir -p inputs outputs')
  call init_metrics()
  call init_x_inputs(ua, uc, q_x)
  call init_sphere_inputs(vc, q_sphere)

  do j = js, je
    b_x(:,j,:) = ua(:,j,:)*dt/(dx*c(j))
  end do
  call find_cell_x(ii, b_x)
  call semi_x_3d(dq_semi_x, ua, q_x, dt)
  call slope_x(slope_x_out, q_x)
  call integer_flux_x(integer_flux_out, b_x, q_x)

  dq_vanleer_x = 0.013
  call vanleer_x_3d(dq_vanleer_x, uc, q_x, dt)

  call slope_sphere(slope_sphere_out, q_sphere)
  dq_vanleer_sphere = -0.021
  call vanleer_sphere_3d(dq_vanleer_sphere, vc, q_sphere, dt)

  call write_params('inputs/params.txt', dt)
  call write_real_1d('inputs/input_c.bin', c)
  call write_real_1d('inputs/input_cc.bin', cc)
  call write_real_1d('inputs/input_dy.bin', dy)
  call write_real_1d('inputs/input_dy_plus.bin', dy_plus)
  call write_real_1d('inputs/input_dy_minus.bin', dy_minus)
  call write_real_3d('inputs/input_ua.bin', ua)
  call write_real_3d('inputs/input_uc.bin', uc)
  call write_real_3d('inputs/input_q_x.bin', q_x)
  call write_real_3d('inputs/input_q_sphere.bin', q_sphere)
  call write_real_3d('inputs/input_vc.bin', vc)

  call write_real_3d('inputs/input_va.bin', vc(:,js:je,:))
  call write_real_1d('inputs/input_dyy.bin', dy(js:je+1))

  call write_int_3d('outputs/output_find_cell_x_ii.bin', ii)
  call write_real_3d('outputs/output_semi_x_dq.bin', dq_semi_x)
  call write_real_3d('outputs/output_slope_x.bin', slope_x_out)
  call write_real_3d('outputs/output_integer_flux_x.bin', integer_flux_out)
  call write_real_3d('outputs/output_vanleer_x_dq_dt.bin', dq_vanleer_x)
  call write_real_3d('outputs/output_slope_sphere.bin', slope_sphere_out)
  call write_real_3d('outputs/output_vanleer_sphere_dq_dt.bin', dq_vanleer_sphere)

  write(*,'(A)') 'fv_advection kernel Fortran baseline complete.'
  write(*,'(A,I0,A,I0,A,I0,A,I0,A,I0)') 'dims nx=', nx, ' ny=', ny, ' js=', js, ' je=', je, ' nz=', nz
end program test_fv_advection_kernels
