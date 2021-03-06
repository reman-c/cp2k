!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2011  CP2K developers group                          !
!-----------------------------------------------------------------------------!

! *****************************************************************************
!> \brief Util mixed_environment
!> \author Teodoro Laino [tlaino] - 02.2011
! *****************************************************************************
MODULE mixed_environment_utils

  USE cp_output_handling,              ONLY: cp_p_file,&
                                             cp_print_key_should_output
  USE cp_result_methods,               ONLY: cp_results_erase,&
                                             get_results,&
                                             put_results
  USE cp_result_types,                 ONLY: cp_result_p_type,&
                                             cp_result_type
  USE f77_blas
  USE input_section_types,             ONLY: section_vals_get,&
                                             section_vals_get_subs_vals,&
                                             section_vals_type,&
                                             section_vals_val_get
  USE kinds,                           ONLY: default_string_length,&
                                             dp
  USE mixed_energy_types,              ONLY: mixed_force_type
  USE particle_list_types,             ONLY: particle_list_type
  USE virial_types,                    ONLY: virial_p_type,&
                                             virial_type,&
                                             zero_virial
#include "cp_common_uses.h"

  IMPLICIT NONE

  PRIVATE

  CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'mixed_environment_utils'

  PUBLIC :: mixed_map_forces,&
            get_subsys_map_index

CONTAINS

! *****************************************************************************
!> \brief Maps forces between the different force_eval sections/environments
!> \param force_env the force env to shake
!> \param error variable to control error logging, stopping,...
!>        see module cp_error_handling
!> \author Teodoro Laino - University of Zurich [tlaino] - 05.2007
! *****************************************************************************
  SUBROUTINE mixed_map_forces(particles_mix, virial_mix, results_mix, global_forces,&
      virials, results, factor, iforce_eval, nforce_eval, map_index, mixed_section,&
      mapping_section, overwrite, error)

    TYPE(particle_list_type), POINTER        :: particles_mix
    TYPE(virial_type), POINTER               :: virial_mix
    TYPE(cp_result_type), POINTER            :: results_mix
    TYPE(mixed_force_type), DIMENSION(:), &
      POINTER                                :: global_forces
    TYPE(virial_p_type), DIMENSION(:), &
      POINTER                                :: virials
    TYPE(cp_result_p_type), DIMENSION(:), &
      POINTER                                :: results
    REAL(KIND=dp), INTENT(IN)                :: factor
    INTEGER, INTENT(IN)                      :: iforce_eval, nforce_eval
    INTEGER, DIMENSION(:), POINTER           :: map_index
    TYPE(section_vals_type), POINTER         :: mixed_section, mapping_section
    LOGICAL, INTENT(IN)                      :: overwrite
    TYPE(cp_error_type), INTENT(inout)       :: error

    CHARACTER(len=*), PARAMETER :: routineN = 'mixed_map_forces', &
      routineP = moduleN//':'//routineN

    CHARACTER(LEN=default_string_length)     :: description
    INTEGER                                  :: iparticle, jparticle, natom, &
                                                nres, stat
    LOGICAL                                  :: failure
    REAL(KIND=dp), DIMENSION(3)              :: dip_mix, dip_tmp
    TYPE(cp_logger_type), POINTER            :: logger
    TYPE(section_vals_type), POINTER         :: print_key

    failure = .FALSE.
    NULLIFY(logger, print_key)
    logger => cp_error_get_logger(error)
    ! Get Mapping index array
    natom = SIZE(global_forces(iforce_eval)%forces,2)
    CALL get_subsys_map_index(mapping_section, natom, iforce_eval, nforce_eval, map_index, error)
    DO iparticle = 1, natom
       jparticle = map_index(iparticle)
       IF (overwrite) THEN
          particles_mix%els(jparticle)%f(:)= factor* global_forces(iforce_eval)%forces(:,iparticle)
       ELSE
          particles_mix%els(jparticle)%f(:)= particles_mix%els(jparticle)%f(:) + &
               factor* global_forces(iforce_eval)%forces(:,iparticle)
       END IF
    END DO
    ! Mixing Virial
    IF (virial_mix%pv_availability) THEN
       IF (overwrite) CALL zero_virial(virial_mix,reset=.FALSE.)
       virial_mix%pv_total      = virial_mix%pv_total + factor*virials(iforce_eval)%virial%pv_total
       virial_mix%pv_kinetic    = virial_mix%pv_kinetic + factor*virials(iforce_eval)%virial%pv_kinetic
       virial_mix%pv_virial     = virial_mix%pv_virial + factor*virials(iforce_eval)%virial%pv_virial
       virial_mix%pv_xc         = virial_mix%pv_xc + factor*virials(iforce_eval)%virial%pv_xc
       virial_mix%pv_fock_4c    = virial_mix%pv_fock_4c + factor*virials(iforce_eval)%virial%pv_fock_4c
       virial_mix%pv_constraint = virial_mix%pv_constraint + factor*virials(iforce_eval)%virial%pv_constraint
    END IF
    ! Deallocate map_index array
    IF (ASSOCIATED(map_index)) THEN
       DEALLOCATE(map_index, stat=stat)
       CPPrecondition(stat==0,cp_failure_level,routineP,error,failure)
    END IF
    ! Collect Requested Results info
    print_key => section_vals_get_subs_vals(mixed_section,"PRINT%DIPOLE",error=error)
    IF (BTEST(cp_print_key_should_output(logger%iter_info,print_key,error=error),&
         cp_p_file)) THEN
       description ='[DIPOLE]'
       IF (overwrite) CALL cp_results_erase(results_mix, error=error)
       CALL get_results(results=results_mix,description=description,n_rep=nres,error=error)
       CPPrecondition(nres<=1,cp_failure_level,routineP,error,failure)
       dip_mix = 0.0_dp
       IF (nres==1) CALL get_results(results=results_mix,description=description,values=dip_mix,error=error)
       CALL get_results(results=results(iforce_eval)%results,description=description,n_rep=nres,error=error)
       CALL get_results(results=results(iforce_eval)%results,description=description,&
            values=dip_tmp,nval=nres,error=error)
       dip_mix = dip_mix + factor*dip_tmp
       CALL cp_results_erase(results=results_mix,description=description,error=error)
       CALL put_results(results=results_mix,description=description,values=dip_mix,error=error)
    END IF

  END SUBROUTINE mixed_map_forces

! *****************************************************************************
!> \brief performs mapping of the subsystems of different force_eval
!> \param force_env the force env to shake
!> \param error variable to control error logging, stopping,...
!>        see module cp_error_handling
!> \author Teodoro Laino - University of Zurich [tlaino] - 05.2007
! *****************************************************************************
  SUBROUTINE get_subsys_map_index(mapping_section, natom, iforce_eval, nforce_eval, map_index, error)

    TYPE(section_vals_type), POINTER         :: mapping_section
    INTEGER, INTENT(IN)                      :: natom, iforce_eval, &
                                                nforce_eval
    INTEGER, DIMENSION(:), POINTER           :: map_index
    TYPE(cp_error_type), INTENT(inout)       :: error

    CHARACTER(len=*), PARAMETER :: routineN = 'get_subsys_map_index', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: i, iatom, ival, j, jval, k, &
                                                n_rep, n_rep_loc, n_rep_map, &
                                                n_rep_sys, stat, tmp
    INTEGER, DIMENSION(:), POINTER           :: index_glo, index_loc, list
    LOGICAL                                  :: check, explicit, failure
    TYPE(section_vals_type), POINTER         :: fragments_loc, fragments_sys, &
                                                map_force_ev, map_full_sys

    failure = .FALSE.
    CPPrecondition(.NOT.ASSOCIATED(map_index),cp_failure_level,routineP,error,failure)
    ALLOCATE(map_index(natom),stat=stat)
    CPPrecondition(stat==0,cp_failure_level,routineP,error,failure)
    CALL section_vals_get(mapping_section, explicit=explicit, error=error)
    IF (.NOT.explicit) THEN
       ! Standard Mapping.. subsys are assumed to have the same structure
       DO i = 1, natom
          map_index(i) = i
       END DO
    ELSE
       ! Mapping systems with different structures
       map_full_sys => section_vals_get_subs_vals(mapping_section,"FORCE_EVAL_MIXED",error=error)
       map_force_ev => section_vals_get_subs_vals(mapping_section,"FORCE_EVAL",error=error)
       CALL section_vals_get(map_full_sys, explicit=explicit, error=error)
       CPPrecondition(explicit,cp_failure_level,routineP,error,failure)
       CALL section_vals_get(map_force_ev, explicit=explicit, n_repetition=n_rep, error=error)
       CPPrecondition(explicit,cp_failure_level,routineP,error,failure)
       CPPrecondition(n_rep==nforce_eval,cp_failure_level,routineP,error,failure)
       DO i = 1, n_rep
          CALL section_vals_val_get(map_force_ev,"_SECTION_PARAMETERS_",i_rep_section=i,i_val=ival,error=error)
          IF (ival==iforce_eval) EXIT
       END DO
       CPPrecondition(i<=nforce_eval,cp_failure_level,routineP,error,failure)
       fragments_sys => section_vals_get_subs_vals(map_full_sys,"FRAGMENT",error=error)
       fragments_loc => section_vals_get_subs_vals(map_force_ev,"FRAGMENT",i_rep_section=i,error=error)
       !Perform few check on the structure of the input mapping section. as provided by the user
       CALL section_vals_get(fragments_loc, n_repetition=n_rep_loc, error=error)
       CALL section_vals_get(fragments_sys, explicit=explicit, n_repetition=n_rep_sys, error=error)
       CPPrecondition(explicit,cp_failure_level,routineP,error,failure)
       CPPrecondition(n_rep_sys>=n_rep_loc,cp_failure_level,routineP,error,failure)
       IF (n_rep_loc==0) THEN
          NULLIFY(list)
          ! We expect an easier syntax in this case..
          CALL section_vals_val_get(map_force_ev,"DEFINE_FRAGMENTS",i_rep_section=i,n_rep_val=n_rep_map,&
               error=error)
          check = (n_rep_map/=0)
          CPPrecondition(check,cp_failure_level,routineP,error,failure)
          CALL section_vals_val_get(map_force_ev,"DEFINE_FRAGMENTS",i_rep_section=i,i_vals=list,&
               error=error)
          CPPrecondition(SIZE(list)>0,cp_failure_level,routineP,error,failure)
          iatom = 0
          DO i = 1, SIZE(list)
             jval = list(i)
             DO j = 1, n_rep_sys
                CALL section_vals_val_get(fragments_sys,"_SECTION_PARAMETERS_",i_rep_section=j,i_val=tmp,error=error)
                IF (tmp==jval) EXIT
             END DO
             CALL section_vals_val_get(fragments_sys,"_DEFAULT_KEYWORD_",i_rep_section=j,i_vals=index_glo,error=error)
             DO k = 0, index_glo(2)-index_glo(1)
                iatom = iatom + 1
 CPPrecondition(iatom<=natom,cp_failure_level,routineP,error,failure)
                map_index(iatom) = index_glo(1)+k
             END DO
          END DO
          check = (iatom==natom)
          CPPrecondition(check,cp_failure_level,routineP,error,failure)
       ELSE
          ! General syntax..
          !Loop over the fragment of the force_eval
          DO i = 1, n_rep_loc
             CALL section_vals_val_get(fragments_loc,"_SECTION_PARAMETERS_",i_rep_section=i,i_val=ival,error=error)
             CALL section_vals_val_get(fragments_loc,"MAP",i_rep_section=i,i_val=jval,error=error)
             ! Index corresponding to the mixed_force_eval fragment
             DO j = 1, n_rep_sys
                CALL section_vals_val_get(fragments_sys,"_SECTION_PARAMETERS_",i_rep_section=j,i_val=tmp,error=error)
                IF (tmp==jval) EXIT
             END DO
             CPPrecondition(j<=n_rep_sys,cp_failure_level,routineP,error,failure)
             CALL section_vals_val_get(fragments_loc,"_DEFAULT_KEYWORD_",i_rep_section=i,i_vals=index_loc,error=error)
             CALL section_vals_val_get(fragments_sys,"_DEFAULT_KEYWORD_",i_rep_section=j,i_vals=index_glo,error=error)
             check = ((index_loc(2)-index_loc(1))==(index_glo(2)-index_glo(1)))
             CPPrecondition(check,cp_failure_level,routineP,error,failure)
             ! Now let's build the real mapping
             DO k = 0, index_loc(2)-index_loc(1)
                map_index(index_loc(1)+k) = index_glo(1)+k
             END DO
          END DO
       END IF
    END IF

  END SUBROUTINE get_subsys_map_index

END MODULE mixed_environment_utils
