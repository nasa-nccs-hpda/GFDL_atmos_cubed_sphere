! OpenACC offload trial for the direct Fortran->GPU path (no C++/CUDA layer).
!
! Purpose: prove that the container's offload-enabled gfortran can (a) execute a
! real fv_advection kernel on the GPU and (b) reproduce the CPU result to
! rounding, and to report GPU-vs-CPU time at a realistic problem size.
!
! The compute in slope_sphere_* is lifted verbatim from
! src/atmos_spectral/model/fv_advection.F90 :: slope_sphere (the monotone
! limited-slope stencil), generalized to runtime sizes. For slope output index
! j (1..ny), it reads q at j-1, j, j+1, so q carries a one-cell halo (0..ny+1).
!
! Build (inside the container, on a GPU node):
!   source /isca/src/extra/env/ubuntu_conda
!   mpifort -O2 -cpp -ffree-line-length-none -fdefault-real-8 -fdefault-double-8 \
!           -fopenacc -foffload=nvptx-none \
!           acc_trial_slope_sphere.F90 -o acc_trial_slope_sphere
!   ACC_DEVICE_TYPE=nvidia ./acc_trial_slope_sphere

module slope_trial_mod
  use openacc
  implicit none

  integer :: nx = 256      ! i extent (periodic dimension, not used in stencil)
  integer :: ny = 256      ! j extent (stencil dimension), slope defined 1..ny
  integer :: nz = 64       ! k extent (levels)
  logical :: monotone = .true.

contains

  ! CPU reference: exact slope_sphere computation.
  subroutine slope_sphere_cpu(slope, q, dyp, dym)
    real, intent(out) :: slope(:,:,:)     ! (nx, ny,   nz)
    real, intent(in)  :: q(:,:,:)         ! (nx, 0:ny+1 stored as 1..ny+2, nz)
    real, intent(in)  :: dyp(:), dym(:)   ! (ny)
    integer :: i, j, k
    real :: s, qm, qp, qc, qmin, qmax

    do k = 1, nz
      do j = 1, ny
        do i = 1, nx
          qm = q(i,j,  k)      ! q(j-1) in halo-shifted storage
          qc = q(i,j+1,k)      ! q(j)
          qp = q(i,j+2,k)      ! q(j+1)
          s  = (qp - qc)*dyp(j) + (qc - qm)*dym(j)
          if (monotone) then
            qmin = min(qm, qc, qp)
            qmax = max(qm, qc, qp)
            s = sign(1.0, s) * min(abs(s), 2.0*(qc - qmin), 2.0*(qmax - qc))
          else
            s = sign(1.0, s) * min(abs(s), 2.0*qc)
          end if
          slope(i,j,k) = s
        end do
      end do
    end do
  end subroutine slope_sphere_cpu

  ! Same computation, offloaded with OpenACC. Per-call data movement (copyin/
  ! copyout every call): the worst case, transfer-bound for a light kernel.
  subroutine slope_sphere_acc(slope, q, dyp, dym)
    real, intent(out) :: slope(:,:,:)
    real, intent(in)  :: q(:,:,:)
    real, intent(in)  :: dyp(:), dym(:)
    integer :: i, j, k
    real :: s, qm, qp, qc, qmin, qmax

    !$acc parallel loop collapse(3) copyin(q, dyp, dym) copyout(slope) &
    !$acc   private(s, qm, qp, qc, qmin, qmax)
    do k = 1, nz
      do j = 1, ny
        do i = 1, nx
          qm = q(i,j,  k)
          qc = q(i,j+1,k)
          qp = q(i,j+2,k)
          s  = (qp - qc)*dyp(j) + (qc - qm)*dym(j)
          if (monotone) then
            qmin = min(qm, qc, qp)
            qmax = max(qm, qc, qp)
            s = sign(1.0, s) * min(abs(s), 2.0*(qc - qmin), 2.0*(qmax - qc))
          else
            s = sign(1.0, s) * min(abs(s), 2.0*qc)
          end if
          slope(i,j,k) = s
        end do
      end do
    end do
  end subroutine slope_sphere_acc

  ! Same kernel, but assumes the arrays are already resident on the device
  ! (present). The caller keeps them there across calls with an !$acc data
  ! region, so no per-call transfer. This is the residency scenario.
  subroutine slope_sphere_acc_resident(slope, q, dyp, dym)
    real, intent(out) :: slope(:,:,:)
    real, intent(in)  :: q(:,:,:)
    real, intent(in)  :: dyp(:), dym(:)
    integer :: i, j, k
    real :: s, qm, qp, qc, qmin, qmax

    !$acc parallel loop collapse(3) present(q, dyp, dym, slope) &
    !$acc   private(s, qm, qp, qc, qmin, qmax)
    do k = 1, nz
      do j = 1, ny
        do i = 1, nx
          qm = q(i,j,  k)
          qc = q(i,j+1,k)
          qp = q(i,j+2,k)
          s  = (qp - qc)*dyp(j) + (qc - qm)*dym(j)
          if (monotone) then
            qmin = min(qm, qc, qp)
            qmax = max(qm, qc, qp)
            s = sign(1.0, s) * min(abs(s), 2.0*(qc - qmin), 2.0*(qmax - qc))
          else
            s = sign(1.0, s) * min(abs(s), 2.0*qc)
          end if
          slope(i,j,k) = s
        end do
      end do
    end do
  end subroutine slope_sphere_acc_resident

end module slope_trial_mod

program acc_trial_slope_sphere
  use slope_trial_mod
  implicit none

  real, allocatable :: q(:,:,:), slope_cpu(:,:,:), slope_acc(:,:,:)
  real, allocatable :: dyp(:), dym(:)
  integer :: i, j, k, it, niters
  integer(8) :: t0, t1, rate
  real :: tcpu, tacc, tacc_res, maxdiff
  integer :: dev

  niters = 50

  allocate(q(nx, ny+2, nz), slope_cpu(nx, ny, nz), slope_acc(nx, ny, nz))
  allocate(dyp(ny), dym(ny))

  ! Deterministic synthetic inputs.
  do k = 1, nz
    do j = 1, ny+2
      do i = 1, nx
        q(i,j,k) = 0.95 + 0.021*real(mod(i*i,17)) - 0.037*real(j) + 0.064*real(k) &
                 + 0.009*real(mod(i + j + 2*k, 6))
      end do
    end do
  end do
  do j = 1, ny
    dyp(j) = 0.45 + 0.015*real(j)
    dym(j) = 0.38 + 0.012*real(j)
  end do

  ! Which device will the offload use? (Definitive: nvidia => running on GPU.)
  dev = acc_get_device_type()
  write(*,'(A,I0)') 'acc_get_device_type() = ', dev
  write(*,'(A,I0)') 'acc_device_nvidia constant = ', acc_device_nvidia
  write(*,'(A,I0)') 'acc_get_num_devices(nvidia) = ', acc_get_num_devices(acc_device_nvidia)

  ! Time CPU.
  call system_clock(t0, rate)
  do it = 1, niters
    call slope_sphere_cpu(slope_cpu, q, dyp, dym)
  end do
  call system_clock(t1)
  tcpu = real(t1 - t0)/real(rate)

  ! Time OpenACC (includes per-call data movement, as written).
  call system_clock(t0, rate)
  do it = 1, niters
    call slope_sphere_acc(slope_acc, q, dyp, dym)
  end do
  call system_clock(t1)
  tacc = real(t1 - t0)/real(rate)

  ! Time OpenACC with data resident on the device: copyin/copyout happen once
  ! at the data-region boundaries (outside the timed loop), so this measures
  ! kernel launch + compute only, as in a resident kernel-chain design.
  !$acc data copyin(q, dyp, dym) copyout(slope_acc)
  call system_clock(t0, rate)
  do it = 1, niters
    call slope_sphere_acc_resident(slope_acc, q, dyp, dym)
  end do
  call system_clock(t1)
  !$acc end data
  tacc_res = real(t1 - t0)/real(rate)

  ! Correctness.
  maxdiff = 0.0
  do k = 1, nz
    do j = 1, ny
      do i = 1, nx
        maxdiff = max(maxdiff, abs(slope_cpu(i,j,k) - slope_acc(i,j,k)))
      end do
    end do
  end do

  write(*,'(A,I0,A,I0,A,I0,A,I0)') 'size nx=', nx, ' ny=', ny, ' nz=', nz, ' niters=', niters
  write(*,'(A,ES12.4,A)') 'CPU  time            = ', tcpu, ' s'
  write(*,'(A,ES12.4,A)') 'ACC  time (per-call) = ', tacc, ' s'
  write(*,'(A,ES12.4,A)') 'ACC  time (resident) = ', tacc_res, ' s'
  write(*,'(A,F8.2)')     'CPU/ACC per-call     = ', tcpu/max(tacc, 1.0e-30)
  write(*,'(A,F8.2)')     'CPU/ACC resident     = ', tcpu/max(tacc_res, 1.0e-30)
  write(*,'(A,ES12.4)')   'max|cpu-acc|         = ', maxdiff
end program acc_trial_slope_sphere
