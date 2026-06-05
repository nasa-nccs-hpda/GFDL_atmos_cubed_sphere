! Standalone extraction of calc_ecc_anomaly from hs_forcing_mod
! For baseline testing - isolated from FMS dependencies

module calc_ecc_anomaly_mod
    implicit none
    private

    ! Use double precision for numerical accuracy
    ! This matches typical FMS compilation settings
    integer, parameter, public :: dp = selected_real_kind(15, 307)

    public :: calc_ecc_anomaly

contains

    subroutine calc_ecc_anomaly(mean_anomaly, ecc, ecc_anomaly)
        ! Solves Kepler's equation: E - e*sin(E) = M
        ! Using Newton-Raphson iteration
        !
        ! Inputs:
        !   mean_anomaly - Mean anomaly M (radians)
        !   ecc          - Orbital eccentricity e (dimensionless, 0 <= e < 1)
        !
        ! Outputs:
        !   ecc_anomaly  - Eccentric anomaly E (radians)

        real(dp), intent(in)  :: mean_anomaly, ecc
        real(dp), intent(out) :: ecc_anomaly
        real(dp) :: dE, d
        integer, parameter :: maxiter = 30
        real(dp), parameter :: tol = 1.0d-10
        integer :: k

        ecc_anomaly = mean_anomaly
        d = ecc_anomaly - ecc*sin(ecc_anomaly) - mean_anomaly

        do k = 1, maxiter
            dE = d / (1 - ecc*cos(ecc_anomaly))
            ecc_anomaly = ecc_anomaly - dE
            d = ecc_anomaly - ecc*sin(ecc_anomaly) - mean_anomaly
            if (abs(d) < tol) then
                exit
            endif
        enddo

        if (k > maxiter) then
            if (abs(d) > tol) then
                print *, '*** Warning: eccentric anomaly has not converged'
            endif
        endif

    end subroutine calc_ecc_anomaly

end module calc_ecc_anomaly_mod
