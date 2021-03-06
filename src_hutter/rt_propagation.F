!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2011  CP2K developers group                          !
!-----------------------------------------------------------------------------!

! *****************************************************************************
!> \brief Routines for the real time propagation.
!> \author Florian Schiffmann (02.09)
! *****************************************************************************
MODULE rt_propagation
  USE cp_control_types,                ONLY: rtp_control_type
  USE cp_external_control,             ONLY: external_control
  USE cp_fm_types,                     ONLY: cp_fm_p_type,&
                                             cp_fm_set_all,&
                                             cp_fm_to_fm,&
                                             cp_fm_type
  USE cp_output_handling,              ONLY: cp_add_iter_level,&
                                             cp_iterate,&
                                             cp_rm_iter_level
  USE efield_utils,                    ONLY: calculate_ecore_efield
  USE force_env_methods,               ONLY: force_env_calc_energy_force
  USE force_env_types,                 ONLY: force_env_get,&
                                             force_env_type
  USE global_types,                    ONLY: global_environment_type
  USE input_constants,                 ONLY: extr_s_ks,&
                                             real_time_propagation,&
                                             use_restart_wfn,&
                                             use_rt_restart,&
                                             use_scf_wfn
  USE input_cp2k_restarts,             ONLY: write_restart
  USE input_section_types,             ONLY: section_vals_get_subs_vals,&
                                             section_vals_type,&
                                             section_vals_val_get,&
                                             section_vals_val_set
  USE kinds,                           ONLY: dp
  USE machine,                         ONLY: m_walltime
  USE md_environment_types,            ONLY: md_environment_type
  USE qs_energy_types,                 ONLY: qs_energy_type
  USE qs_environment_types,            ONLY: get_qs_env,&
                                             qs_environment_type
  USE qs_external_potential,           ONLY: external_c_potential,&
                                             external_e_potential
  USE qs_ks_methods,                   ONLY: qs_ks_did_change,&
                                             qs_ks_update_qs_env
  USE qs_mo_types,                     ONLY: get_mo_set,&
                                             init_mo_set,&
                                             mo_set_p_type
  USE rt_propagation_methods,          ONLY: calc_update_rho,&
                                             propagation_step,&
                                             put_data_to_history,&
                                             update_core_and_matrices
  USE rt_propagation_output,           ONLY: rt_prop_output
  USE rt_propagation_types,            ONLY: get_rtp,&
                                             rt_prop_create,&
                                             rt_prop_type,&
                                             rtp_history_create
  USE rt_propagation_utils,            ONLY: get_restart_wfn
  USE rt_propagator_init,              ONLY: init_propagators
  USE timings,                         ONLY: timeset,&
                                             timestop
#include "cp_common_uses.h"

  IMPLICIT NONE


  CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'rt_propagation'

  PUBLIC :: rt_prop_setup,&
       init_ehrenfest_md,&
       run_propagation


CONTAINS

! *****************************************************************************
!> \brief creates rtp_type, gets the initial state, either by reading MO's
!>        from file or calling SCF run
!> \author Florian Schiffmann (02.09)
! *****************************************************************************

  SUBROUTINE rt_prop_setup(force_env,error)
    TYPE(force_env_type), POINTER            :: force_env
    TYPE(cp_error_type), INTENT(inout)       :: error

    CHARACTER(len=*), PARAMETER :: routineN = 'rt_prop_setup', &
      routineP = moduleN//':'//routineN
    REAL(KIND=dp), PARAMETER                 :: one = 1.0_dp , zero = 0.0_dp

    INTEGER                                  :: aspc_order, homo, ispin, stat
    LOGICAL                                  :: extrapolate_H, failure
    TYPE(cp_fm_type), POINTER                :: mo_coeff
    TYPE(global_environment_type), POINTER   :: globenv
    TYPE(qs_environment_type), POINTER       :: qs_env
    TYPE(rt_prop_type), POINTER              :: rtp
    TYPE(rtp_control_type), POINTER          :: rtp_control
    TYPE(section_vals_type), POINTER         :: md_section, motion_section

    failure=.FALSE.
    NULLIFY(qs_env,rtp_control)
    
    CALL force_env_get(force_env=force_env,qs_env=qs_env,globenv=globenv,error=error)
    rtp_control=>qs_env%dft_control%rtp_control

    SELECT CASE(rtp_control%initial_wfn)
    CASE(use_scf_wfn)
       qs_env%sim_time=0.0_dp
       qs_env%sim_step=0
       CALL force_env_calc_energy_force(force_env,calc_force=.FALSE.,&
            consistent_energies=.TRUE.,error=error)
       qs_env%run_rtp=.TRUE.
       ALLOCATE(qs_env%rtp, stat=stat)
       CPPostcondition(stat==0,cp_failure_level,routineP,error,failure)       
       CALL rt_prop_create(qs_env%rtp,qs_env%mos,qs_env%mpools,qs_env%dft_control,error)

    CASE(use_restart_wfn,use_rt_restart)
       CALL update_core_and_matrices(qs_env,error)       
       DO ispin=1,SIZE(qs_env%mos)
          CALL get_mo_set(qs_env%mos(ispin)%mo_set,mo_coeff=mo_coeff,homo=homo)
          IF (.NOT.ASSOCIATED(mo_coeff)) THEN
             CALL init_mo_set(qs_env%mos(ispin)%mo_set,&
                  qs_env%mpools%ao_mo_fm_pools(ispin)%pool,&
                  name="qs_env"//TRIM(ADJUSTL(cp_to_string(qs_env%id_nr)))//&
                  "%mo"//TRIM(ADJUSTL(cp_to_string(ispin))),&
                  error=error)
          END IF
       END DO
       ALLOCATE(qs_env%rtp, stat=stat)
       CPPostcondition(stat==0,cp_failure_level,routineP,error,failure)
       
       CALL rt_prop_create(qs_env%rtp,qs_env%mos,qs_env%mpools,qs_env%dft_control,error)
       
       CALL get_restart_wfn(qs_env,error)
       qs_env%run_rtp=.TRUE.
    END SELECT

    CALL get_qs_env(qs_env=qs_env,rtp=rtp,error=error)
    aspc_order=rtp_control%aspc_order
    extrapolate_H=(rtp_control%extrapolation==extr_s_ks)
    CALL rtp_history_create(qs_env%rtp,extrapolate_H,aspc_order,error)

    motion_section => section_vals_get_subs_vals(force_env%root_section,"MOTION",error=error)
    md_section     => section_vals_get_subs_vals(motion_section,"MD",error=error)
    CALL section_vals_val_get(md_section,"TIMESTEP",r_val=qs_env%rtp%dt,error=error)      
    CALL section_vals_val_get(md_section,"STEP_START_VAL",i_val=qs_env%rtp%i_start,error=error)
    CALL section_vals_val_get(md_section,"STEPS",i_val=rtp%nsteps,error=error)
    

    IF(rtp_control%fixed_ions)THEN
       CALL init_propagation_run(qs_env,error)
       CALL run_propagation(qs_env,force_env,globenv,error)
    ELSE
       CALL init_ehrenfest_md(force_env,qs_env,error)
    END IF


  END SUBROUTINE rt_prop_setup

! *****************************************************************************
!> \brief calculates the matrices needed in the first step of RTP
!> \author Florian Schiffmann (02.09)
! *****************************************************************************

  SUBROUTINE init_propagation_run(qs_env,error)
    TYPE(qs_environment_type), POINTER       :: qs_env
    TYPE(cp_error_type), INTENT(inout)       :: error

    REAL(KIND=dp), PARAMETER                 :: one = 1.0_dp , zero = 0.0_dp

    INTEGER                                  :: i
    TYPE(cp_fm_p_type), DIMENSION(:), &
      POINTER                                :: mos_new, mos_old
    TYPE(mo_set_p_type), DIMENSION(:), &
      POINTER                                :: mos
    TYPE(rt_prop_type), POINTER              :: rtp
    TYPE(rtp_control_type), POINTER          :: rtp_control

    CALL get_qs_env(qs_env,&
         mos=mos,&
         rtp=rtp,&
         error=error)
    rtp_control=>qs_env%dft_control%rtp_control 
    CALL get_rtp(rtp=rtp,mos_old=mos_old,mos_new=mos_new,error=error)
    
    IF(rtp_control%initial_wfn==use_scf_wfn)THEN
       DO i=1,SIZE(mos)
           CALL cp_fm_to_fm(mos(i)%mo_set%mo_coeff,mos_old(2*i-1)%matrix,error)
           CALL cp_fm_set_all(mos_old(2*i)%matrix,zero,zero,error)
       END DO
    END IF

    DO i=1,SIZE(mos_old)
       CALL cp_fm_to_fm(mos_old(i)%matrix,mos_new(i)%matrix,error)
    END DO

    IF(rtp_control%initial_wfn==use_restart_wfn.OR.rtp_control%initial_wfn==use_rt_restart)THEN
       CALL calc_update_rho(qs_env,error)
       CALL qs_ks_update_qs_env(qs_env%ks_env,qs_env=qs_env,calculate_forces=.FALSE.,&
            error=error)
    END IF

    CALL init_propagators(qs_env,error)

  END SUBROUTINE init_propagation_run


! *****************************************************************************
!> \brief calculates the matrices needed in the first step of EMD
!> \author Florian Schiffmann (02.09)
! *****************************************************************************

  SUBROUTINE init_ehrenfest_md(force_env,qs_env,error)

    TYPE(force_env_type), POINTER            :: force_env
    TYPE(qs_environment_type), POINTER       :: qs_env
    TYPE(cp_error_type), INTENT(inout)       :: error

    REAL(KIND=dp), PARAMETER                 :: one = 1.0_dp , zero = 0.0_dp

    INTEGER                                  :: i
    TYPE(cp_fm_p_type), DIMENSION(:), &
      POINTER                                :: mos_new, mos_old
    TYPE(mo_set_p_type), DIMENSION(:), &
      POINTER                                :: mos
    TYPE(qs_energy_type), POINTER            :: energy
    TYPE(rt_prop_type), POINTER              :: rtp
    TYPE(rtp_control_type), POINTER          :: rtp_control

     CALL get_qs_env(qs_env,&
         mos=mos,&
         rtp=rtp,&
         energy=energy,&
         error=error)
     rtp_control=>qs_env%dft_control%rtp_control
     CALL get_rtp(rtp=rtp,mos_old=mos_old,mos_new=mos_new,error=error)

     IF(rtp_control%initial_wfn==use_scf_wfn)THEN
        DO i=1,SIZE(mos)
            CALL cp_fm_to_fm(mos(i)%mo_set%mo_coeff,mos_old(2*i-1)%matrix,error)
            CALL cp_fm_set_all(mos_old(2*i)%matrix,zero,zero,error)
        END DO
     END IF

     DO i=1,SIZE(mos_old)
        CALL cp_fm_to_fm(mos_old(i)%matrix,mos_new(i)%matrix,error)
     END DO

     qs_env%dft_control%rtp_control%initial_step=.TRUE.

     CALL force_env_calc_energy_force(force_env,calc_force=.TRUE.,&
          error=error)

     qs_env%dft_control%rtp_control%initial_step=.FALSE.
     rtp%energy_old=energy%total
     
    
  END SUBROUTINE init_ehrenfest_md

! *****************************************************************************
!> \brief performes the real RTP run, gets information from MD section
!>        uses MD as iteration level 
!> \author Florian Schiffmann (02.09)
! *****************************************************************************

  SUBROUTINE run_propagation(qs_env,force_env,globenv,error)
    TYPE(qs_environment_type), POINTER       :: qs_env
    TYPE(force_env_type), POINTER            :: force_env
    TYPE(global_environment_type), POINTER   :: globenv
    TYPE(cp_error_type), INTENT(inout)       :: error

    CHARACTER(len=*), PARAMETER :: routineN = 'run_propagation', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: aspc_order, handle, i, &
                                                i_iter, i_step, ihist, &
                                                max_iter, max_steps
    LOGICAL                                  :: failure, should_stop
    REAL(Kind=dp)                            :: delta_iter, eps_ener, &
                                                time_iter_start, &
                                                time_iter_stop, used_time
    TYPE(cp_fm_p_type), DIMENSION(:), &
      POINTER                                :: exp_H_new, exp_H_old, &
                                                mos_new, mos_old
    TYPE(cp_logger_type), POINTER            :: logger
    TYPE(qs_energy_type), POINTER            :: energy
    TYPE(rt_prop_type), POINTER              :: rtp

    failure=.FALSE.
    should_stop=.FALSE.
    CALL timeset(routineN,handle)
    logger   => cp_error_get_logger(error) 
    max_steps=qs_env%rtp%nsteps
    max_iter=qs_env%dft_control%rtp_control%max_iter
    eps_ener=qs_env%dft_control%rtp_control%eps_ener
   
 
    CALL get_qs_env(qs_env=qs_env,rtp=rtp,energy=energy,error=error)
    aspc_order=qs_env%dft_control%rtp_control%aspc_order

    CALL get_rtp(rtp=rtp,&
                 exp_H_old=exp_H_old,&
                 exp_H_new=exp_H_new,&
                 mos_old=mos_old,&
                 mos_new=mos_new,&
                 error=error)
                 
    rtp%energy_old=energy%total
    time_iter_start=m_walltime()
    CALL cp_add_iter_level(logger%iter_info,"MD",error=error)
    CALL cp_iterate(logger%iter_info,iter_nr=0,error=error)
    DO i_step=rtp%i_start+1,max_steps
       qs_env%energy%efield_core=0.0_dp

       qs_env%sim_time=REAL(i_step,dp)*rtp%dt
       qs_env%sim_step=i_step
       rtp%istep=i_step-rtp%i_start
       CALL calculate_ecore_efield(qs_env,.FALSE.,error)
       CALL external_c_potential(qs_env,calculate_forces=.FALSE.,error=error)
       CALL external_e_potential(qs_env,error=error)

       CALL cp_iterate(logger%iter_info,last=(i_step==max_steps),iter_nr=i_step,error=error)
       rtp%converged=.FALSE.
       DO i_iter=1,max_iter
          IF(i_step==rtp%i_start+1.AND.i_iter==2.AND.qs_env%dft_control%rtp_control%hfx_redistribute)&
              CALL qs_ks_did_change(qs_env%ks_env,s_mstruct_changed=.TRUE., error=error)
          rtp%iter=i_iter
          CALL propagation_step(qs_env,delta_iter, error)
          rtp%energy_new=energy%total
          rtp%converged=(delta_iter.LT.eps_ener)

          IF(rtp%converged)EXIT
          CALL rt_prop_output(qs_env,real_time_propagation,delta_iter,error=error)
          
       END DO

       IF(rtp%converged)THEN
          ihist=MOD(rtp%istep,aspc_order)+1
          DO i=1,SIZE(mos_new)
             CALL cp_fm_to_fm(mos_new(i)%matrix,mos_old(i)%matrix,error)
             CALL cp_fm_to_fm(exp_H_new(i)%matrix,exp_H_old(i)%matrix,error)
          END DO
          IF(rtp%history%mos_or_H==2)&
             CALL  put_data_to_history(qs_env,exp_H=exp_H_new,ihist=ihist,error=error)
          IF(rtp%history%mos_or_H==1)&
             CALL put_data_to_history(qs_env,mos=mos_new,ihist=ihist,error=error)
          CALL external_control(should_stop,"MD",globenv=globenv,error=error)
          IF (should_stop)CALL cp_iterate(logger%iter_info,last=.TRUE.,iter_nr=i_step,error=error)
          time_iter_stop=m_walltime()
          used_time= time_iter_stop - time_iter_start
          time_iter_start=time_iter_stop
          CALL rt_prop_output(qs_env,real_time_propagation,delta_iter=delta_iter,used_time=used_time,error=error)
          CALL rt_write_input_restart(force_env=force_env,error=error)
          IF (should_stop)EXIT
       ELSE
          EXIT
       END IF


    END DO
    CALL cp_rm_iter_level(logger%iter_info,"MD",error=error)
    IF(.NOT.rtp%converged)&
         CALL cp_assert(.FALSE.,cp_failure_level,cp_assertion_failed,&
         routineP,"propagation did not converge, either increase MAX_ITER or use a smaller TIMESTEP",&
         error,failure)
    CALL timestop(handle)

  END SUBROUTINE run_propagation

  SUBROUTINE rt_write_input_restart(md_env,force_env,error)
    TYPE(md_environment_type), OPTIONAL, &
      POINTER                                :: md_env
    TYPE(force_env_type), POINTER            :: force_env
    TYPE(cp_error_type), INTENT(inout)       :: error

    CHARACTER(len=*), PARAMETER :: routineN = 'rt_write_input_restart', &
      routineP = moduleN//':'//routineN

    TYPE(section_vals_type), POINTER         :: motion_section, root_section, &
                                                rt_section

    root_section => force_env%root_section
    motion_section => section_vals_get_subs_vals(root_section,"MOTION",error=error)
    rt_section => section_vals_get_subs_vals(root_section,"FORCE_EVAL%DFT%REAL_TIME_PROPAGATION",error=error)
    CALL section_vals_val_set(rt_section,"INITIAL_WFN",i_val=use_rt_restart,error=error) 
    ! coming from RTP
    IF (.NOT. PRESENT(md_env)) THEN
     CALL section_vals_val_set(motion_section,"MD%STEP_START_VAL",i_val=force_env%qs_env%sim_step,error=error) 
    ENDIF

    CALL write_restart(md_env=md_env,root_section=root_section,error=error)

  END SUBROUTINE rt_write_input_restart

    


END MODULE rt_propagation



      

 


