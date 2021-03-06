!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2011  CP2K developers group                          !
!-----------------------------------------------------------------------------!

! *****************************************************************************
!> \brief Routines to handle the external control of CP2K
!> \par History
!>      - Moved from MODULE termination to here (18.02.2011,MK)
!> \author Marcella Iannuzzi (10.03.2005,MI)
! *****************************************************************************
MODULE cp_external_control

  USE cp_files,                        ONLY: close_file,&
                                             open_file
  USE f77_blas
  USE global_types,                    ONLY: global_environment_type
  USE kinds,                           ONLY: default_string_length,&
                                             dp
  USE machine,                         ONLY: m_walltime
  USE message_passing,                 ONLY: mp_bcast
  USE timings,                         ONLY: timeset,&
                                             timestop
#include "cp_common_uses.h"

  IMPLICIT NONE

  PRIVATE

  CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'cp_external_control'

  INTEGER :: error_unit

  PUBLIC :: external_control

CONTAINS

! *****************************************************************************
!> \brief External manipulations during a run : when the <PROJECT_NAME>.EXIT_$runtype
!>      command is sent the program stops at the level of $runtype
!>      when a general <PROJECT_NAME>.EXIT command is sent the program is stopped
!>      at all levels (at least those that call this function)
!>      if the file WAIT exists, the program waits here till it disappears
!> \author MI (10.03.2005)
! *****************************************************************************
  SUBROUTINE external_control(should_stop,flag,globenv,target_time,start_time,error)

    LOGICAL, INTENT(OUT)                     :: should_stop
    CHARACTER(LEN=*), INTENT(IN)             :: flag
    TYPE(global_environment_type), &
      OPTIONAL, POINTER                      :: globenv
    REAL(dp), OPTIONAL                       :: target_time, start_time
    TYPE(cp_error_type), INTENT(inout)       :: error

    CHARACTER(LEN=*), PARAMETER :: routineN = 'external_control', &
      routineP = moduleN//':'//routineN

    CHARACTER(LEN=default_string_length)     :: exit_fname, exit_fname_level, &
                                                exit_gname, exit_gname_level
    INTEGER                                  :: handle, i, unit_number
    LOGICAL                                  :: failure, should_wait
    LOGICAL, SAVE                            :: check_always = .FALSE.
    REAL(KIND=dp)                            :: my_start_time, &
                                                my_target_time, t1, t2, &
                                                time_check
    REAL(KIND=dp), SAVE                      :: t_last_file_check = 0.0_dp
    TYPE(cp_logger_type), POINTER            :: logger

    CALL timeset(routineN,handle)

    failure=.FALSE.
    logger => cp_error_get_logger(error)
    should_stop = .FALSE.

    exit_gname       = "EXIT"
    exit_gname_level = TRIM(exit_gname)//"_"//TRIM(flag)
    exit_fname       = TRIM(logger%iter_info%project_name)//"."//TRIM(exit_gname)
    exit_fname_level = TRIM(logger%iter_info%project_name)//"."//TRIM(exit_gname_level)

    IF (logger%para_env%source==logger%para_env%mepos) THEN
       ! files will only be checked every 20 seconds, or if the clock wraps/does not exist,
       ! otherwise 64 waters on 64 cores can spend up to 10% of time here, on lustre
       ! however, if should_stop has been true, we should always check
       ! (at each level scf, md, ... the file must be there to guarantee termination)
       t1=m_walltime()
       IF (t1>t_last_file_check+20.0_dp .OR. t1 <= t_last_file_check .OR. check_always) THEN
          t_last_file_check=t1
          ! allows for halting execution for a while
          ! this is useful to copy a consistent snapshot of the output
          ! while a simulation is running
          INQUIRE (FILE="WAIT",EXIST=should_wait)
          IF (should_wait) THEN
             CALL open_file(file_name="WAITING",file_status="UNKNOWN",&
                  file_form="FORMATTED",file_action="WRITE",&
                  unit_number=unit_number)
             WRITE (UNIT=cp_logger_get_default_unit_nr(logger),FMT="(/,T2,A,/)")&
                  "*** waiting till the file WAIT has been removed ***"
             DO
                ! sleep a bit (to save the file system)
                t1=m_walltime()
                DO I=1,100000000
                   t2=m_walltime()
                   IF (t2-t1>1.0_dp) EXIT
                ENDDO
                ! and ask again
                INQUIRE (FILE="WAIT",EXIST=should_wait)
                IF (.NOT.should_wait) EXIT
             ENDDO
             CALL close_file(unit_number=unit_number,file_status="DELETE")
          ENDIF
          ! EXIT control sequence
          ! Check for <PROJECT_NAME>.EXIT_<FLAG>
          IF (.NOT.should_stop) THEN
             INQUIRE (FILE=exit_fname_level,EXIST=should_stop)
             IF (should_stop) THEN
                CALL open_file(file_name=exit_fname_level,unit_number=unit_number)
                CALL close_file(unit_number=unit_number,file_status="DELETE")
                WRITE (UNIT=cp_logger_get_default_unit_nr(logger),FMT="(/,T2,A,/)")&
                     "*** "//flag//" run terminated by external request ***"
             END IF
          END IF
          ! Check for <PROJECT_NAME>.EXIT
          IF (.NOT.should_stop) THEN
             INQUIRE (FILE=exit_fname,EXIST=should_stop)
             IF(should_stop) THEN
                WRITE (UNIT=cp_logger_get_default_unit_nr(logger),FMT="(/,T2,A,/)")&
                     "*** "//TRIM(flag)//" run terminated by external request ***"
             ENDIF
          END IF
          ! Check for EXIT_<FLAG>
          IF (.NOT.should_stop) THEN
             INQUIRE (FILE=exit_gname_level,EXIST=should_stop)
             IF (should_stop) THEN
                CALL open_file(file_name=exit_gname_level,unit_number=unit_number)
                CALL close_file(unit_number=unit_number,file_status="DELETE")
                WRITE (UNIT=cp_logger_get_default_unit_nr(logger),FMT="(/,T2,A,/)")&
                     "*** "//flag//" run terminated by external request ***"
             END IF
          END IF
          ! Check for EXIT
          IF (.NOT.should_stop) THEN
             INQUIRE (FILE=exit_gname,EXIST=should_stop)
             IF(should_stop) THEN
                WRITE (UNIT=cp_logger_get_default_unit_nr(logger),FMT="(/,T2,A,/)")&
                     "*** "//TRIM(flag)//" run terminated by external request ***"
             ENDIF
          END IF
       ENDIF

       IF(PRESENT(target_time)) THEN
          my_target_time = target_time
          my_start_time = start_time
       ELSEIF(PRESENT(globenv)) THEN
          my_target_time=globenv%cp2k_target_time
          my_start_time=globenv%cp2k_start_time
       ELSE
          ! If none of the two arguments is present abort.. This routine should always check about time.
          CPPrecondition(.FALSE.,cp_fatal_level,routineP,error,failure)
       END IF

       IF ( (.NOT.should_stop).AND.(my_target_time > 0.0_dp)) THEN
          ! Check for execution time
          time_check  = m_walltime() - my_start_time
          IF (time_check .GT. my_target_time) THEN
             should_stop = .TRUE.
             WRITE (UNIT=cp_logger_get_default_unit_nr(logger),FMT="(/,T2,A,f12.3,A)")&
                  "*** "//TRIM(flag)//" run terminated - exceeded requested execution time:",&
                  my_target_time," seconds.",&
                  "*** Execution time now: ",time_check," seconds."
          END IF
       END IF
    END IF
    CALL mp_bcast(should_stop,logger%para_env%source,logger%para_env%group)

    check_always=should_stop

    CALL timestop(handle)

  END SUBROUTINE external_control

END MODULE cp_external_control

