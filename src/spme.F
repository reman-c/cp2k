!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2011  CP2K developers group                          !
!-----------------------------------------------------------------------------!

! *****************************************************************************
!> \brief Calculate the electrostatic energy by the Smooth Particle Ewald method
!> \par History
!>      JGH (03-May-2001) : first correctly working version
!> \author JGH (21-Mar-2001)
! *****************************************************************************
MODULE spme

  USE atomic_kind_types,               ONLY: get_atomic_kind
  USE atprop_types,                    ONLY: atprop_type
  USE bibliography,                    ONLY: Essmann1995,&
                                             cite_reference
  USE cell_types,                      ONLY: cell_type,&
                                             real_to_scaled
  USE dgs,                             ONLY: dg_sum_patch,&
                                             dg_sum_patch_force_1d,&
                                             dg_sum_patch_force_3d
  USE ewald_environment_types,         ONLY: ewald_env_get,&
                                             ewald_environment_type
  USE ewald_pw_types,                  ONLY: ewald_pw_get,&
                                             ewald_pw_type
  USE f77_blas
  USE kinds,                           ONLY: dp
  USE mathconstants,                   ONLY: fourpi
  USE particle_types,                  ONLY: particle_type
  USE pme_tools,                       ONLY: get_center,&
                                             set_list
  USE pw_grid_types,                   ONLY: pw_grid_type
  USE pw_grids,                        ONLY: get_pw_grid_info
  USE pw_methods,                      ONLY: pw_integral_a2b,&
                                             pw_transfer
  USE pw_poisson_methods,              ONLY: pw_poisson_rebuild,&
                                             pw_poisson_solve
  USE pw_poisson_types,                ONLY: greens_fn_type,&
                                             pw_poisson_type
  USE pw_pool_types,                   ONLY: pw_pool_create_pw,&
                                             pw_pool_give_back_pw,&
                                             pw_pool_type
  USE pw_types,                        ONLY: COMPLEXDATA1D,&
                                             REALDATA3D,&
                                             REALSPACE,&
                                             RECIPROCALSPACE,&
                                             pw_p_type,&
                                             pw_type
  USE realspace_grid_types,            ONLY: &
       pw2rs, realspace_grid_desc_type, realspace_grid_p_type, &
       realspace_grid_type, rs2pw, rs_grid_create, rs_grid_release, &
       rs_grid_set_box, rs_grid_zero, rs_pw_transfer
  USE shell_potential_types,           ONLY: shell_kind_type
  USE termination,                     ONLY: stop_program
  USE timings,                         ONLY: timeset,&
                                             timestop
#include "cp_common_uses.h"

  IMPLICIT NONE

  PRIVATE
  PUBLIC :: spme_evaluate, get_patch

  CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'spme'

CONTAINS

! *****************************************************************************
!> \par History
!>      JGH (03-May-2001) : SPME with charge definition
!> \author JGH (21-Mar-2001)
! *****************************************************************************
  SUBROUTINE spme_evaluate ( ewald_env, ewald_pw, box, particle_set, &
       fg_coulomb, vg_coulomb, pv_g, shell_particle_set, core_particle_set,&
       fgshell_coulomb, fgcore_coulomb, use_virial, charges, atprop, error )

    TYPE(ewald_environment_type), POINTER    :: ewald_env
    TYPE(ewald_pw_type), POINTER             :: ewald_pw
    TYPE(cell_type), POINTER                 :: box
    TYPE(particle_type), DIMENSION(:), &
      INTENT(IN)                             :: particle_set
    REAL(KIND=dp), DIMENSION(:, :), &
      INTENT(OUT)                            :: fg_coulomb
    REAL(KIND=dp), INTENT(OUT)               :: vg_coulomb
    REAL(KIND=dp), DIMENSION(:, :), &
      INTENT(OUT)                            :: pv_g
    TYPE(particle_type), DIMENSION(:), &
      OPTIONAL, POINTER                      :: shell_particle_set, &
                                                core_particle_set
    REAL(KIND=dp), DIMENSION(:, :), &
      INTENT(OUT), OPTIONAL                  :: fgshell_coulomb, &
                                                fgcore_coulomb
    LOGICAL, INTENT(IN)                      :: use_virial
    REAL(KIND=dp), DIMENSION(:), OPTIONAL, &
      POINTER                                :: charges
    TYPE(atprop_type), POINTER               :: atprop
    TYPE(cp_error_type), INTENT(inout)       :: error

    CHARACTER(len=*), PARAMETER :: routineN = 'spme_evaluate', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: group, handle, i, ipart, j, &
                                                n, ncore, npart, nshell, &
                                                o_spline, p1, p1_shell, stat
    INTEGER, ALLOCATABLE, DIMENSION(:, :)    :: center, core_center, &
                                                shell_center
    INTEGER, DIMENSION(3)                    :: npts
    LOGICAL                                  :: do_shell, failure
    REAL(KIND=dp)                            :: alpha, dvols, ffa, fat1
    REAL(KIND=dp), ALLOCATABLE, &
      DIMENSION(:, :, :)                     :: rhos
    REAL(KIND=dp), DIMENSION(3)              :: fat
    REAL(KIND=dp), DIMENSION(3, 3)           :: f_stress, h_stress
    TYPE(greens_fn_type), POINTER            :: green
    TYPE(pw_grid_type), POINTER              :: grid_spme
    TYPE(pw_p_type), DIMENSION(3)            :: dphi_g
    TYPE(pw_poisson_type), POINTER           :: poisson_env
    TYPE(pw_pool_type), POINTER              :: pw_pool
    TYPE(pw_type), POINTER                   :: phi_g, rhob_g, rhob_r
    TYPE(realspace_grid_desc_type), POINTER  :: rs_desc
    TYPE(realspace_grid_p_type), &
      DIMENSION(:), POINTER                  :: drpot
    TYPE(realspace_grid_type), POINTER       :: rden, rpot

    failure = .FALSE.
    NULLIFY(drpot, grid_spme, green, poisson_env, phi_g, rhob_g, rhob_r, pw_pool, rden, rpot)
    CALL timeset ( routineN, handle )
    CALL cite_reference(Essmann1995)

    !-------------- INITIALISATION ---------------------
    CALL ewald_env_get ( ewald_env, alpha=alpha, o_spline = o_spline,&
         group = group, error=error)
    CALL ewald_pw_get ( ewald_pw, pw_big_pool=pw_pool, rs_desc=rs_desc,&
         poisson_env=poisson_env)
    CALL pw_poisson_rebuild(poisson_env,error=error)
    green => poisson_env%green_fft
    grid_spme => pw_pool % pw_grid

    npart = SIZE ( particle_set )
    
    CALL get_pw_grid_info(grid_spme,npts=npts,dvol=dvols,error=error)

    n = o_spline
    ALLOCATE ( rhos(n,n,n), STAT = stat )
    CPPostcondition(stat==0,cp_failure_level,routineP,error,failure)
    CALL rs_grid_create (rden, rs_desc, error=error)
    CALL rs_grid_set_box ( grid_spme, rs=rden, error=error )
    CALL rs_grid_zero ( rden )

    ALLOCATE ( center(3, npart), STAT = stat )
    CPPostcondition(stat==0,cp_failure_level,routineP,error,failure)
    CALL get_center ( particle_set, box, center, npts, n )
    IF(PRESENT(shell_particle_set).AND.(PRESENT(core_particle_set))) THEN
       CPPostcondition(ASSOCIATED(shell_particle_set),cp_failure_level,routineP,error,failure)
       CPPostcondition(ASSOCIATED(core_particle_set),cp_failure_level,routineP,error,failure)
       nshell=SIZE(shell_particle_set)
       ncore =SIZE(core_particle_set)
       CPPostcondition(nshell==ncore,cp_failure_level,routineP,error,failure)
       ALLOCATE ( shell_center ( 3, nshell ), STAT = stat )
       CPPostcondition(stat==0,cp_failure_level,routineP,error,failure)
       CALL get_center ( shell_particle_set, box, shell_center, npts, n )
       ALLOCATE ( core_center ( 3, nshell ), STAT = stat )
       CPPostcondition(stat==0,cp_failure_level,routineP,error,failure)
       CALL get_center ( core_particle_set, box, core_center, npts, n )
    END IF

    !-------------- DENSITY CALCULATION ----------------
    ipart = 0
    ! Particles
    DO
       CALL set_list ( particle_set, npart, center, p1, rden, ipart )
       IF (p1 == 0) EXIT

       do_shell  = (particle_set(p1)%shell_index/=0)
       IF(do_shell) CYCLE
       ! calculate function on small boxes
       CALL get_patch ( particle_set, box, green, npts, p1, rhos, is_core=.FALSE.,&
            is_shell=.FALSE., unit_charge=.FALSE., charges=charges)

       ! add boxes to real space grid (big box)
       CALL dg_sum_patch ( rden, rhos, center(:,p1) )
    END DO
    ! Shell-Model
    IF(PRESENT(shell_particle_set).AND.PRESENT(core_particle_set)) THEN
       ipart = 0
       DO
          ! calculate function on small boxes
          CALL set_list ( shell_particle_set, nshell, shell_center, p1_shell,&
                          rden, ipart )
          IF (p1_shell == 0) EXIT
          CALL get_patch(shell_particle_set, box, green, npts, p1_shell, rhos,&
               is_core=.FALSE., is_shell=.TRUE., unit_charge=.FALSE.)
 
          ! add boxes to real space grid (big box)
          CALL dg_sum_patch ( rden, rhos, shell_center(:,p1_shell) )
       END DO
       ipart = 0
       DO
          ! calculate function on small boxes
          CALL set_list ( core_particle_set, nshell, core_center, p1_shell,&
                          rden, ipart )
          IF ( p1_shell == 0 ) EXIT
          CALL get_patch ( core_particle_set, box, green, npts, p1_shell, rhos,&
               is_core=.TRUE., is_shell=.FALSE., unit_charge=.FALSE.)

          ! add boxes to real space grid (big box)
          CALL dg_sum_patch ( rden, rhos, core_center(:,p1_shell) )
       END DO
    END IF
    !----------- END OF DENSITY CALCULATION -------------

    CALL pw_pool_create_pw ( pw_pool, rhob_r, use_data = REALDATA3D, &
                             in_space = REALSPACE ,error=error)
    CALL rs_pw_transfer ( rden, rhob_r, rs2pw, error=error)
    ! transform density to G space and add charge function
    CALL pw_pool_create_pw ( pw_pool, rhob_g,  &
                             use_data = COMPLEXDATA1D, &
                             in_space = RECIPROCALSPACE ,error=error)
    CALL pw_transfer ( rhob_r, rhob_g, error=error)
    ! update charge function
    rhob_g % cc = rhob_g % cc * green % p3m_charge % cr

    !-------------- ELECTROSTATIC CALCULATION -----------
    ! allocate intermediate arrays
    DO i = 1, 3
       NULLIFY(dphi_g(i)%pw)
       CALL pw_pool_create_pw ( pw_pool, dphi_g ( i )%pw,&
                                use_data = COMPLEXDATA1D,&
                                in_space = RECIPROCALSPACE,&
                                error=error)
    END DO
    CALL pw_pool_create_pw ( pw_pool, phi_g,  &
                             use_data = COMPLEXDATA1D,&
                             in_space = RECIPROCALSPACE,&
                             error=error)
    CALL pw_poisson_solve ( poisson_env, rhob_g, vg_coulomb, phi_g, dphi_g, &
                            h_stress ,error=error)
    ! Atomic Energy 
    IF (atprop%energy) THEN
       CALL rs_grid_create (rpot, rs_desc, error=error)
       phi_g%cc = phi_g%cc * green%p3m_charge%cr
       CALL pw_transfer ( phi_g, rhob_r, error=error)
       CALL rs_pw_transfer (rpot, rhob_r, pw2rs, error=error)
       ipart = 0
       DO
          CALL set_list ( particle_set, npart, center, p1, rden, ipart )
          IF ( p1 == 0 ) EXIT

          do_shell = (particle_set(p1)%shell_index/=0)
          IF(do_shell) CYCLE
          ! calculate function on small boxes
          CALL get_patch ( particle_set, box, green, grid_spme % npts, p1, rhos, is_core=.FALSE.,&
               is_shell=.FALSE., unit_charge=.FALSE., charges=charges)

          ! integrate box and potential
          CALL dg_sum_patch_force_1d ( rpot, rhos, center(:,p1), fat1 )
          atprop%atener(p1) = atprop%atener(p1) + 0.5_dp*fat1*dvols
       END DO
       CALL rs_grid_release ( rpot, error=error)
    END IF

    CALL pw_pool_give_back_pw ( pw_pool, phi_g ,error=error)
    CALL pw_pool_give_back_pw ( pw_pool, rhob_g ,error=error)
    !---------- END OF ELECTROSTATIC CALCULATION --------

    !------------- STRESS TENSOR CALCULATION ------------
    IF (use_virial) THEN
       DO i = 1, 3
          DO j = i, 3
             f_stress ( i, j ) = pw_integral_a2b ( dphi_g ( i ) % pw, &
                  dphi_g ( j ) % pw, error=error)
             f_stress ( j, i ) = f_stress ( i, j )
          END DO
       END DO
       ffa = ( 1.0_dp / fourpi ) * ( 0.5_dp / alpha ) ** 2
       f_stress = -ffa * f_stress
       pv_g = h_stress + f_stress
    END IF
    !--------END OF STRESS TENSOR CALCULATION -----------
    ! move derivative of potential to real space grid and
    ! multiply by charge function in g-space
    ALLOCATE ( drpot(1:3), STAT=stat )
    CPPostcondition(stat==0,cp_failure_level,routineP,error,failure)
    DO i = 1, 3
       CALL rs_grid_create( drpot(i)%rs_grid, rs_desc, error=error )
       CALL rs_grid_set_box ( grid_spme, rs=drpot(i)%rs_grid, error=error )
       dphi_g ( i ) % pw % cc = dphi_g ( i ) % pw % cc * green % p3m_charge % cr
       CALL pw_transfer ( dphi_g ( i )%pw, rhob_r, error=error)
       CALL pw_pool_give_back_pw ( pw_pool, dphi_g ( i )%pw ,error=error)
       CALL rs_pw_transfer ( drpot ( i ) % rs_grid, rhob_r, pw2rs,error=error)
    END DO

    CALL pw_pool_give_back_pw ( pw_pool, rhob_r ,error=error)
    !----------------- FORCE CALCULATION ----------------
    ! initialize the forces
    fg_coulomb = 0.0_dp
    ! Particles
    ipart = 0
    DO
       CALL set_list ( particle_set, npart, center, p1, rden, ipart )
       IF ( p1 == 0 ) EXIT

       do_shell = (particle_set(p1)%shell_index/=0)
       IF(do_shell) CYCLE
       ! calculate function on small boxes
       CALL get_patch ( particle_set, box, green, grid_spme % npts, p1, rhos, is_core=.FALSE.,&
            is_shell=.FALSE., unit_charge=.FALSE., charges=charges)
       
       ! add boxes to real space grid (big box)
       CALL dg_sum_patch_force_3d ( drpot, rhos, center(:,p1), fat )
       fg_coulomb ( 1, p1 ) = fg_coulomb ( 1, p1 ) - fat ( 1 ) * dvols
       fg_coulomb ( 2, p1 ) = fg_coulomb ( 2, p1 ) - fat ( 2 ) * dvols
       fg_coulomb ( 3, p1 ) = fg_coulomb ( 3, p1 ) - fat ( 3 ) * dvols
    END DO
    ! Shell-Model
    IF(PRESENT(shell_particle_set).AND.(PRESENT(core_particle_set))) THEN
       IF(PRESENT(fgshell_coulomb)) THEN
          ipart = 0
          fgshell_coulomb = 0.0_dp
          DO
             ! calculate function on small boxes
             CALL set_list ( shell_particle_set, nshell, shell_center, p1_shell,&
                             rden, ipart )
             IF ( p1_shell == 0 ) EXIT

             CALL get_patch ( shell_particle_set, box, green, grid_spme % npts, &
                  p1_shell, rhos, is_core=.FALSE., is_shell=.TRUE., unit_charge=.FALSE.)

             ! add boxes to real space grid (big box)
             CALL dg_sum_patch_force_3d ( drpot, rhos, shell_center(:,p1_shell), fat )
             fgshell_coulomb ( 1, p1_shell ) = fgshell_coulomb ( 1, p1_shell ) - fat ( 1 ) * dvols
             fgshell_coulomb ( 2, p1_shell ) = fgshell_coulomb ( 2, p1_shell ) - fat ( 2 ) * dvols
             fgshell_coulomb ( 3, p1_shell ) = fgshell_coulomb ( 3, p1_shell ) - fat ( 3 ) * dvols

          END DO
       END IF
       IF(PRESENT(fgcore_coulomb)) THEN
          ipart = 0
          fgcore_coulomb = 0.0_dp
          DO
             ! calculate function on small boxes
             CALL set_list ( core_particle_set, nshell, core_center, p1_shell,&
                             rden, ipart )
             IF ( p1_shell == 0 ) EXIT

             CALL get_patch ( core_particle_set, box, green, grid_spme % npts, &
                  p1_shell, rhos, is_core=.TRUE., is_shell=.FALSE., unit_charge=.FALSE.)

             ! add boxes to real space grid (big box)
             CALL dg_sum_patch_force_3d ( drpot, rhos, core_center(:,p1_shell), fat )
             fgcore_coulomb ( 1, p1_shell ) = fgcore_coulomb ( 1, p1_shell ) - fat ( 1 ) * dvols
             fgcore_coulomb ( 2, p1_shell ) = fgcore_coulomb ( 2, p1_shell ) - fat ( 2 ) * dvols
             fgcore_coulomb ( 3, p1_shell ) = fgcore_coulomb ( 3, p1_shell ) - fat ( 3 ) * dvols
          END DO
       END IF

    END IF
    !--------------END OF FORCE CALCULATION -------------

    !------------------CLEANING UP ----------------------
    CALL rs_grid_release (rden, error=error)
    IF (ASSOCIATED(drpot)) THEN
      DO i = 1, 3
         CALL rs_grid_release ( drpot(i)%rs_grid, error=error)
      END DO
      DEALLOCATE ( drpot, STAT = stat )
      CPPostcondition(stat==0,cp_failure_level,routineP,error,failure)
    END IF

    DEALLOCATE ( rhos, STAT = stat )
    CPPostcondition(stat==0,cp_failure_level,routineP,error,failure)
    DEALLOCATE ( center, STAT = stat )
    CPPostcondition(stat==0,cp_failure_level,routineP,error,failure)
    IF(ALLOCATED(shell_center)) THEN
       DEALLOCATE ( shell_center, STAT = stat )
       CPPostcondition(stat==0,cp_failure_level,routineP,error,failure)
    END IF
    IF(ALLOCATED(core_center)) THEN
       DEALLOCATE ( core_center, STAT = stat )
       CPPostcondition(stat==0,cp_failure_level,routineP,error,failure)
    END IF
    CALL timestop(handle)

  END SUBROUTINE spme_evaluate

! *****************************************************************************
!> \brief Calculates local density in a small box
!> \par History
!>      none
!> \author JGH (21-Mar-2001)
! *****************************************************************************
  SUBROUTINE get_patch ( part, box, green, npts, p, rhos, is_core, is_shell,&
                         unit_charge, charges )

    TYPE(particle_type), DIMENSION(:), &
      INTENT(IN)                             :: part
    TYPE(cell_type), POINTER                 :: box
    TYPE(greens_fn_type), POINTER            :: green
    INTEGER, DIMENSION(3), INTENT(IN)        :: npts
    INTEGER, INTENT(IN)                      :: p
    REAL(KIND=dp), DIMENSION(:, :, :), &
      INTENT(OUT)                            :: rhos
    LOGICAL, INTENT(IN)                      :: is_core, is_shell, unit_charge
    REAL(KIND=dp), DIMENSION(:), OPTIONAL, &
      POINTER                                :: charges

    CHARACTER(len=*), PARAMETER :: routineN = 'get_patch', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: nbox
    LOGICAL                                  :: use_charge_array
    REAL(KIND=dp)                            :: q
    REAL(KIND=dp), DIMENSION(3)              :: delta, r
    TYPE(shell_kind_type), POINTER           :: shell

    NULLIFY(shell)
    use_charge_array=PRESENT(charges)
    IF (use_charge_array) use_charge_array=ASSOCIATED(charges)
    IF(is_core .AND. is_shell) THEN
       CALL stop_program(routineN,moduleN,__LINE__,&
                         "Shell-model: cannot be core and shell simultaneously")
    END IF

    nbox = SIZE ( rhos, 1 )
    r = part(p)% r
    q = 1.0_dp
    IF (.NOT.unit_charge) THEN
       IF      (is_core) THEN
          CALL get_atomic_kind ( atomic_kind=part(p)%atomic_kind, shell=shell)
          q = shell%charge_core
       ELSE IF (is_shell) THEN
          CALL get_atomic_kind ( atomic_kind=part(p)%atomic_kind, shell=shell)
          q = shell%charge_shell
       ELSE
          CALL get_atomic_kind ( atomic_kind=part(p)%atomic_kind, qeff=q)
       END IF
       IF (use_charge_array) q=charges(p)
    END IF
    CALL get_delta ( box, r, npts, delta, nbox )
    CALL spme_get_patch ( rhos, nbox, delta, q, green % p3m_coeff )

  END SUBROUTINE get_patch

! *****************************************************************************
!> \brief Calculates SPME charge assignment
!> \par History
!>      DG (29-Mar-2001) : code implemented
!> \author JGH (22-Mar-2001)
! *****************************************************************************
  SUBROUTINE spme_get_patch ( rhos, n, delta, q, coeff )

    REAL(KIND=dp), DIMENSION(:, :, :), &
      INTENT(OUT)                            :: rhos
    INTEGER, INTENT(IN)                      :: n
    REAL(KIND=dp), DIMENSION(3), INTENT(IN)  :: delta
    REAL(KIND=dp), INTENT(IN)                :: q
    REAL(KIND=dp), &
      DIMENSION(-(n-1):n-1, 0:n-1), &
      INTENT(IN)                             :: coeff

    CHARACTER(len=*), PARAMETER :: routineN = 'spme_get_patch', &
      routineP = moduleN//':'//routineN
    INTEGER, PARAMETER                       :: nmax = 12

    INTEGER                                  :: i, i1, i2, i3, j, l
    REAL(KIND=dp)                            :: r2, r3
    REAL(KIND=dp), DIMENSION(3, -nmax:nmax)  :: w_assign
    REAL(KIND=dp), DIMENSION(3, 0:nmax-1)    :: deltal
    REAL(KIND=dp), DIMENSION(3, 1:nmax)      :: f_assign

    IF ( n > nmax ) THEN
       CALL stop_program(routineN,moduleN,__LINE__,"nmax value too small")
    END IF
    ! calculate the assignment function values and
    ! the charges on the grid (small box)

    deltal ( 1, 0 ) = 1.0_dp
    deltal ( 2, 0 ) = 1.0_dp
    deltal ( 3, 0 ) = 1.0_dp
    DO l = 1, n-1
       deltal ( 1, l ) = deltal ( 1, l-1 ) * delta ( 1 )
       deltal ( 2, l ) = deltal ( 2, l-1 ) * delta ( 2 )
       deltal ( 3, l ) = deltal ( 3, l-1 ) * delta ( 3 )
    END DO

    w_assign = 0.0_dp
    DO j = -(n-1), n-1, 2
       DO l = 0, n-1
          w_assign ( 1, j ) =  w_assign ( 1, j ) + coeff ( j, l ) * deltal ( 1, l )
          w_assign ( 2, j ) =  w_assign ( 2, j ) + coeff ( j, l ) * deltal ( 2, l )
          w_assign ( 3, j ) =  w_assign ( 3, j ) + coeff ( j, l ) * deltal ( 3, l )
       END DO
    END DO
    DO i = 1, n
       j = n + 1 - 2 * i
       f_assign (1, i ) = w_assign ( 1, j )
       f_assign (2, i ) = w_assign ( 2, j )
       f_assign (3, i ) = w_assign ( 3, j )
    END DO

    DO i3 = 1, n
       r3 = q * f_assign ( 3, i3 )
       DO i2 = 1, n
          r2 = r3 * f_assign ( 2, i2 )
          DO i1 = 1, n
             rhos ( i1, i2, i3 ) = r2 * f_assign ( 1, i1 )
          END DO
       END DO
    END DO

  END SUBROUTINE spme_get_patch

! *****************************************************************************
  SUBROUTINE get_delta ( box, r, npts, delta, n )

    TYPE(cell_type), POINTER                 :: box
    REAL(KIND=dp), DIMENSION(3), INTENT(IN)  :: r
    INTEGER, DIMENSION(3), INTENT(IN)        :: npts
    REAL(KIND=dp), DIMENSION(3), INTENT(OUT) :: delta
    INTEGER, INTENT(IN)                      :: n

    CHARACTER(len=*), PARAMETER :: routineN = 'get_delta', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: mp
    INTEGER, DIMENSION(3)                    :: center
    REAL(KIND=dp)                            :: rmp
    REAL(KIND=dp), DIMENSION(3)              :: ca, grid_i, s

    mp = MAXVAL ( npts(:) )
    rmp = REAL ( mp,KIND=dp)
    ! compute the scaled coordinate of atomi
    CALL real_to_scaled(s,r,box)
    s = s - REAL ( NINT ( s ),KIND=dp)

    ! find the continuous ``grid'' point
    grid_i ( 1:3 ) = REAL ( npts ( 1:3 ),KIND=dp) * s ( 1:3 )

    ! find the closest grid point

    IF ( MOD ( n, 2 ) == 0 ) THEN
       center ( : ) = INT ( grid_i ( : ) + rmp ) - mp
       ca ( : ) = REAL ( center ( : ) ) + 0.5_dp
    ELSE
       center ( : ) = NINT ( grid_i ( : ) )
       ca ( : ) = REAL ( center ( : ) )
    END IF

    ! find the distance vector
    delta ( : ) = grid_i ( : ) - ca ( : )

  END SUBROUTINE get_delta

END MODULE spme

