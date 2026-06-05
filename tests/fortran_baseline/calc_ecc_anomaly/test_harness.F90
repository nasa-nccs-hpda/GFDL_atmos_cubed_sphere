! Test harness for calc_ecc_anomaly
! Generates test cases, calls the routine, and writes results to files

program test_calc_ecc_anomaly
    use calc_ecc_anomaly_mod, only: calc_ecc_anomaly, dp
    implicit none

    integer, parameter :: n_tests = 12
    real(dp), parameter :: pi = 3.14159265358979323846_dp

    real(dp) :: mean_anomaly(n_tests)
    real(dp) :: ecc(n_tests)
    real(dp) :: ecc_anomaly(n_tests)
    real(dp) :: residual(n_tests)
    integer :: i
    character(len=256) :: input_file, output_file

    ! Define test cases
    ! Case 1: Zero eccentricity (E should equal M)
    mean_anomaly(1) = pi / 4.0
    ecc(1) = 0.0

    ! Case 2: Zero mean anomaly (E should be 0)
    mean_anomaly(2) = 0.0
    ecc(2) = 0.5

    ! Case 3: Circular orbit at pi
    mean_anomaly(3) = pi
    ecc(3) = 0.0

    ! Case 4: Earth-like eccentricity
    mean_anomaly(4) = 1.0
    ecc(4) = 0.0167

    ! Case 5: Mars-like eccentricity
    mean_anomaly(5) = 2.0
    ecc(5) = 0.0934

    ! Case 6: Mercury-like eccentricity
    mean_anomaly(6) = 1.5
    ecc(6) = 0.2056

    ! Case 7: High eccentricity
    mean_anomaly(7) = 0.5
    ecc(7) = 0.9

    ! Case 8: Negative mean anomaly (antisymmetry test)
    mean_anomaly(8) = -1.5
    ecc(8) = 0.3

    ! Case 9: Positive mean anomaly (pair for antisymmetry)
    mean_anomaly(9) = 1.5
    ecc(9) = 0.3

    ! Case 10: High eccentricity (e=0.95 converges; e=0.99 may not with E0=M)
    mean_anomaly(10) = 0.1_dp
    ecc(10) = 0.95_dp

    ! Case 11: M = 2*pi (full orbit)
    mean_anomaly(11) = 2.0 * pi
    ecc(11) = 0.5

    ! Case 12: Edge case - high ecc near perihelion
    mean_anomaly(12) = 3.0
    ecc(12) = 0.999

    ! Run all test cases
    do i = 1, n_tests
        call calc_ecc_anomaly(mean_anomaly(i), ecc(i), ecc_anomaly(i))
        ! Compute residual: should be ~0 if converged
        residual(i) = ecc_anomaly(i) - ecc(i) * sin(ecc_anomaly(i)) - mean_anomaly(i)
    enddo

    ! Write inputs to file
    input_file = 'inputs.dat'
    open(unit=10, file=trim(input_file), status='replace', action='write')
    write(10, '(A)') '# Test inputs for calc_ecc_anomaly'
    write(10, '(A)') '# Columns: test_id, mean_anomaly, ecc'
    do i = 1, n_tests
        write(10, '(I4, 2E25.16)') i, mean_anomaly(i), ecc(i)
    enddo
    close(10)
    print *, 'Wrote inputs to: ', trim(input_file)

    ! Write outputs to file
    output_file = 'outputs.dat'
    open(unit=11, file=trim(output_file), status='replace', action='write')
    write(11, '(A)') '# Test outputs for calc_ecc_anomaly'
    write(11, '(A)') '# Columns: test_id, ecc_anomaly, residual'
    do i = 1, n_tests
        write(11, '(I4, 2E25.16)') i, ecc_anomaly(i), residual(i)
    enddo
    close(11)
    print *, 'Wrote outputs to: ', trim(output_file)

    ! Print summary to stdout
    print *, ''
    print *, '===== calc_ecc_anomaly Test Results ====='
    print *, ''
    print '(A4, A16, A12, A20, A16)', 'ID', 'M (rad)', 'e', 'E (rad)', 'Residual'
    print *, '------------------------------------------------------------'
    do i = 1, n_tests
        print '(I4, F16.10, F12.6, F20.14, E16.6)', &
            i, mean_anomaly(i), ecc(i), ecc_anomaly(i), residual(i)
    enddo
    print *, ''

    ! Verify key test cases
    print *, '===== Verification ====='
    print *, ''

    ! Check e=0 case: E should equal M
    if (abs(ecc_anomaly(1) - mean_anomaly(1)) < 1.0d-10) then
        print *, 'PASS: e=0 case (E = M)'
    else
        print *, 'FAIL: e=0 case'
    endif

    ! Check M=0 case: E should be 0
    if (abs(ecc_anomaly(2)) < 1.0d-10) then
        print *, 'PASS: M=0 case (E = 0)'
    else
        print *, 'FAIL: M=0 case'
    endif

    ! Check antisymmetry: E(-M) = -E(M)
    if (abs(ecc_anomaly(8) + ecc_anomaly(9)) < 1.0d-10) then
        print *, 'PASS: Antisymmetry E(-M) = -E(M)'
    else
        print *, 'FAIL: Antisymmetry'
    endif

    ! Check all residuals are small
    if (maxval(abs(residual)) < 1.0d-8) then
        print *, 'PASS: All residuals < 1e-8'
    else
        print *, 'FAIL: Some residuals too large, max =', maxval(abs(residual))
    endif

    print *, ''
    print *, 'Done.'

end program test_calc_ecc_anomaly
