!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2011  CP2K developers group                          !
!-----------------------------------------------------------------------------!

! *****************************************************************************
!> \brief   
!> \author VW
!>
!> <b>Modification history:</b>
!> - Created Feb 2010
! *****************************************************************************
MODULE dbcsr_error_handling

  USE dbcsr_kinds,                     ONLY: default_string_length
  USE dbcsr_machine,                   ONLY: default_output_unit,&
                                             m_flush
  USE dbcsr_message_passing,           ONLY: mp_abort

  IMPLICIT NONE
  PRIVATE

  ! procedures
  PUBLIC :: dbcsr_error_set, dbcsr_error_stop, dbcsr_error_print_stack
  PUBLIC :: dbcsr_assert
  ! types
  PUBLIC :: dbcsr_error_stack_type
  PUBLIC :: dbcsr_error_type
  ! parameters
  PUBLIC :: dbcsr_error_stack_size
  PUBLIC :: dbcsr_note_level, dbcsr_warning_level, dbcsr_failure_level, dbcsr_fatal_level
  PUBLIC :: dbcsr_no_error, dbcsr_caller_error, dbcsr_wrong_args_error,&
            dbcsr_precondition_failed, dbcsr_internal_error, dbcsr_postcondition_failed,&
            dbcsr_invariant_failed, dbcsr_assertion_failed, dbcsr_unimplemented_error_nr
  ! interfaces
  INTERFACE dbcsr_assert
     MODULE PROCEDURE dbcsr_int_assert
     MODULE PROCEDURE dbcsr_logical_assert
     MODULE PROCEDURE dbcsr_not_assert
     MODULE PROCEDURE dbcsr_char_assert
     MODULE PROCEDURE dbcsr_true_assert!bcsr_assert,
  END INTERFACE

  INTEGER, PARAMETER :: dbcsr_error_stack_size = 10
  !! level of an error
  INTEGER, PARAMETER :: dbcsr_fatal_level=3
  !! level of a failure
  INTEGER, PARAMETER :: dbcsr_failure_level=2
  !! level of a warning
  INTEGER, PARAMETER :: dbcsr_warning_level=1
  !! level of a note
  INTEGER, PARAMETER :: dbcsr_note_level=0
  !! error number: no error
  INTEGER, PARAMETER :: dbcsr_no_error = 0
  !! error number: generic error on the side of the caller
  INTEGER, PARAMETER :: dbcsr_caller_error = 1
  !! error number: one or more arguments have and invalid value
  INTEGER, PARAMETER :: dbcsr_wrong_args_error = 100
  !! error number: precondition failed
  INTEGER, PARAMETER :: dbcsr_precondition_failed = 200
  !! error number: generic error inside the routine
  INTEGER, PARAMETER :: dbcsr_internal_error = -1
  !! error number: postcondition failed
  INTEGER, PARAMETER :: dbcsr_postcondition_failed = -200
  !! error number: invariant failed
  INTEGER, PARAMETER :: dbcsr_invariant_failed = -100
  !! error number: assertion failure
  INTEGER, PARAMETER :: dbcsr_assertion_failed = -300
  !! error number: not implemented
  INTEGER, PARAMETER :: dbcsr_unimplemented_error_nr = -1000


  CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'dbcsr_error_handling'

! *****************************************************************************
!> \brief stack fo the error type (DBCSR library)
! *****************************************************************************
  TYPE dbcsr_error_stack_type
     INTEGER :: level = 0
     CHARACTER(default_string_length) :: pre = ''
     CHARACTER(default_string_length) :: post = ''
     CHARACTER(default_string_length), DIMENSION(dbcsr_error_stack_size) :: s = ''
     INTEGER, DIMENSION(dbcsr_error_stack_size) :: handler = 0
#if defined(__USE_CP2K_TRACE)
     INTEGER, DIMENSION(dbcsr_error_stack_size) :: cp2k_handler = 0
#endif
  END TYPE dbcsr_error_stack_type

! *****************************************************************************
!> \brief error type for the DBCSR library
! *****************************************************************************
  TYPE dbcsr_error_type
     INTEGER :: etype = 0
     INTEGER :: line = 0
     INTEGER :: level = 0
     CHARACTER(default_string_length) :: msg
     CHARACTER(default_string_length) :: routine
     TYPE(dbcsr_error_stack_type) :: stack
  END TYPE dbcsr_error_type

CONTAINS

! *****************************************************************************
!> \brief set the error
!> \param[in]    name    name of the routine
!> \param[inout] error   dbcsr error
! *****************************************************************************
  SUBROUTINE dbcsr_error_set(name, handler, error)
    CHARACTER(len=*), INTENT(in)             :: name
    INTEGER, INTENT(out)                     :: handler
    TYPE(dbcsr_error_type), INTENT(inout)    :: error

!$OMP MASTER
    error%stack%level = error%stack%level + 1
    IF(error%stack%level.GT.dbcsr_error_stack_size.OR.&
       error%stack%level.LT.1) STOP
    error%stack%s(error%stack%level) = name
    handler = error%stack%level
    error%stack%handler(error%stack%level) = handler
#if defined(__USE_CP2K_TRACE)
    CALL timeset_mp(name, error%stack%cp2k_handler(error%stack%level) )
#endif
!$OMP END MASTER
  END SUBROUTINE dbcsr_error_set

! *****************************************************************************
!> \brief stop the error
!> \param[inout] error   dbcsr error
! *****************************************************************************
  SUBROUTINE dbcsr_error_stop(handler, error)
    INTEGER, INTENT(inout)                   :: handler
    TYPE(dbcsr_error_type)                   :: error

!$OMP MASTER
    IF(error%stack%level.GT.dbcsr_error_stack_size.OR.&
       error%stack%level.LT.1) THEN
       WRITE(*,*) 'dbcsr_error_stop'
       WRITE(*,*) 'level=',error%stack%level
       WRITE(*,*) 'dbcsr_error_stack_size=',dbcsr_error_stack_size
       STOP
    ENDIF
    IF(handler.NE.error%stack%handler(error%stack%level)) THEN
       WRITE(*,*) 'get handler=',handler
       WRITE(*,*) 'expected handler=',error%stack%handler(error%stack%level)
       WRITE(*,*) 'you may have forget to call dbcsr_error_stop (may be a RETURN)...'
       STOP
    ENDIF
#if defined(__USE_CP2K_TRACE)
    CALL timestop_mp(error%stack%cp2k_handler(error%stack%level) )
#endif
    error%stack%s(error%stack%level) = ''
    error%stack%handler(error%stack%level) = 0
    error%stack%level = error%stack%level - 1
    ! destroy the handler for any case
    handler = -HUGE(0)
!$OMP END MASTER
  END SUBROUTINE dbcsr_error_stop

! *****************************************************************************
!> \brief stop the error
!> \param[inout] error   dbcsr error
! *****************************************************************************
  SUBROUTINE dbcsr_error_print_stack(error, output_unit)
    TYPE(dbcsr_error_type)                   :: error
    INTEGER, INTENT(in)                      :: output_unit

    INTEGER                                  :: ilevel

    IF(error%stack%level.GT.dbcsr_error_stack_size.OR.&
       error%stack%level.LT.1) THEN
       WRITE(*,*) 'dbcsr_error_print_stack'
       WRITE(*,*) 'error%msg=',error%msg
       WRITE(*,*) 'error%routine=',error%routine
       WRITE(*,*) 'error%etype=',error%etype
       WRITE(*,*) 'error%level=',error%level
       WRITE(*,*) 'error%line=',error%line
       WRITE(*,*) 'error%stack%level=',error%stack%level
       WRITE(*,*) 'dbcsr_error_stack_size=',dbcsr_error_stack_size
       RETURN
    ENDIF

    WRITE(output_unit,'(A)') ''
    WRITE(output_unit,'(A)') ''
    IF(LEN_TRIM(error%stack%pre).GT.0) &
         WRITE(output_unit,'(T3,A,A)') 'prestack: ',TRIM(error%stack%pre)
    WRITE(output_unit,'(T3,A)') 'stack: '

    WRITE(output_unit,'(T3,A,A,A,I5,A,I3)') 'error in ',&
         TRIM(error%routine),' at line ',error%line,' with error type ',error%etype
    IF(LEN_TRIM(error%msg).GT.0)WRITE(output_unit,'(T3,A,A)') 'message: ',TRIM(error%msg)
    WRITE(output_unit,'(T3,I3,3A,I5)') error%stack%level,' error in ',&
         TRIM(error%stack%s(error%stack%level)),' at line ',error%line
    DO ilevel = error%stack%level-1,1,-1
       WRITE(output_unit,'(T3,I3,A,A)') ilevel,' called from ',TRIM(error%stack%s(ilevel))
    ENDDO
    IF(LEN_TRIM(error%stack%post).GT.0) &
         WRITE(output_unit,'(T3,A,A)') 'poststack: ',TRIM(error%stack%post)
    WRITE(output_unit,'(A)') ''
    WRITE(output_unit,'(A)') ''
    CALL m_flush(output_unit)
  END SUBROUTINE dbcsr_error_print_stack


! *****************************************************************************
!> \brief 
!> \param[inout] 
! *****************************************************************************
  SUBROUTINE dbcsr_abort (level, etype, routine, msg, line, error)
    INTEGER, INTENT(in)                      :: level, etype
    CHARACTER(*), INTENT(in)                 :: routine, msg
    INTEGER, INTENT(in)                      :: line
    TYPE(dbcsr_error_type), INTENT(inout)    :: error

    INTEGER                                  :: output_unit

    error%msg = msg
    error%routine = routine
    error%etype = etype
    error%level = level
    error%line = line
    !
    ! set for the moment the output units to the default one
    output_unit = default_output_unit
    !
    ! print the stack
    CALL dbcsr_error_print_stack(error, output_unit)
    !
    ! abort if needed
    IF(error%level.NE.dbcsr_warning_level) THEN
       ! Segmentation faults can be handy for debugging.
       !WRITE(*,*)error%stack%handler(-line - 666)
       CALL mp_abort()
    ENDIF
    !
  END SUBROUTINE dbcsr_abort

! *****************************************************************************
!> \brief Assertion
!> \param[in] left            left value
!> \param[in] rel             relation
!> \param[in] right           right value
!> \param[in] level           error level
!> \param[in] etype           error type
!> \param[in] routine         Routine name
!> \param[in] msg   Message to display if the assertion fails
! *****************************************************************************
  SUBROUTINE dbcsr_int_assert(left, rel, right, level, etype, routine, msg, line, error)
    INTEGER, INTENT(IN)                      :: left
    CHARACTER(len=2), INTENT(IN)             :: rel
    INTEGER, INTENT(IN)                      :: right, level, etype
    CHARACTER(len=*), INTENT(IN)             :: routine, msg
    INTEGER, INTENT(IN)                      :: line
    TYPE(dbcsr_error_type), INTENT(inout)    :: error

    LOGICAL                                  :: l

!   ---------------------------------------------------------------------------

    SELECT CASE (rel)
    CASE ("EQ")
       l = left .EQ. right
    CASE ("LT")
       l = left .LT. right
    CASE ("LE")
       l = left .LE. right
    CASE ("GT")
       l = left .GT. right
    CASE ("GE")
       l = left .GE. right
    CASE ("NE")
       l = left .NE. right
    CASE default
       CALL dbcsr_assert (.FALSE., dbcsr_fatal_level, dbcsr_wrong_args_error,&
            "dbcsr_int_assert", "Invalid relation specified: "//rel, __LINE__, error)
       l = .FALSE.
    END SELECT
    IF (.NOT. l) THEN
       WRITE(*,'(1X,A,1X,I9,A4,I9)')"ASSERTION FAILED:",&
            left, "."//rel//".", right
       CALL dbcsr_abort (level, etype, routine, msg, line, error)
    ENDIF
  END SUBROUTINE dbcsr_int_assert

! *****************************************************************************
!> \brief Assertion
!> \param[in] left            left value
!> \param[in] rel             relation
!> \param[in] right           right value
!> \param[in] level           error level
!> \param[in] etype           error type
!> \param[in] routine         Routine name
!> \param[in] msg   Message to display if the assertion fails
! *****************************************************************************
  SUBROUTINE dbcsr_logical_assert(left, rel, right, level, etype, routine, msg, line, error)
    LOGICAL, INTENT(IN)                      :: left
    CHARACTER(len=*), INTENT(IN)             :: rel
    LOGICAL, INTENT(IN)                      :: right
    INTEGER, INTENT(IN)                      :: level, etype
    CHARACTER(len=*), INTENT(IN)             :: routine, msg
    INTEGER, INTENT(IN)                      :: line
    TYPE(dbcsr_error_type), INTENT(inout)    :: error

    LOGICAL                                  :: l

!   ---------------------------------------------------------------------------

    SELECT CASE (rel)
    CASE ("EQV")
       l = left .EQV. right
    CASE ("NEQV")
       l = left .NEQV. right
    CASE ("OR")
       l = left .OR. right
    CASE ("AND")
       l = left .AND. right
    CASE ("IMP")
       l = .NOT. left .OR. right
    CASE default
       CALL dbcsr_assert (.FALSE., dbcsr_fatal_level, dbcsr_wrong_args_error,&
            "dbcsr_int_assert", "Invalid relation specified: "//rel, __LINE__, error)
       l = .FALSE.
    END SELECT
    IF (.NOT. l) THEN
       WRITE(*,'(1X,A,1X,L1,A,L1)')"ASSERTION FAILED:",&
            left, "."//rel//".", right
       CALL dbcsr_abort (level, etype, routine, msg, line, error)
    ENDIF
  END SUBROUTINE dbcsr_logical_assert

! *****************************************************************************
!> \brief Assertion
!> \param[in] left            left value
!> \param[in] rel             relation
!> \param[in] right           right value
!> \param[in] level           error level
!> \param[in] etype           error type
!> \param[in] routine         Routine name
!> \param[in] msg   Message to display if the assertion fails
! *****************************************************************************
  SUBROUTINE dbcsr_char_assert(left, rel, right, level, etype, routine, msg, line, error)
    CHARACTER, INTENT(IN)                    :: left
    CHARACTER(len=2), INTENT(IN)             :: rel
    CHARACTER, INTENT(IN)                    :: right
    INTEGER, INTENT(IN)                      :: level, etype
    CHARACTER(len=*), INTENT(IN)             :: routine, msg
    INTEGER, INTENT(IN)                      :: line
    TYPE(dbcsr_error_type), INTENT(inout)    :: error

    LOGICAL                                  :: l

!   ---------------------------------------------------------------------------

    SELECT CASE (rel)
    CASE ("EQ")
       l = left .EQ. right
    CASE ("NE")
       l = left .NE. right
    CASE default
       CALL dbcsr_assert (.FALSE., dbcsr_fatal_level, dbcsr_wrong_args_error,&
            "dbcsr_char_assert", "Invalid relation specified: "//rel, __LINE__, error)
       l = .FALSE.
    END SELECT
    IF (.NOT. l) THEN
       WRITE(*,'(1X,A,1X,A1,1X,A4,1X,A1)')"ASSERTION FAILED:",&
            left, "."//rel//".", right
       CALL dbcsr_abort (level, etype, routine, msg, line, error)
    ENDIF
  END SUBROUTINE dbcsr_char_assert


! *****************************************************************************
!> \brief Assertion
!> \param[in] right           right value
!> \param[in] level           error level
!> \param[in] etype           error type
!> \param[in] routine         Routine name
!> \param[in] msg   Message to display if the assertion fails
! *****************************************************************************
  SUBROUTINE dbcsr_true_assert(right, level, etype, routine, msg, line, error)
    LOGICAL, INTENT(IN)                      :: right
    INTEGER, INTENT(IN)                      :: level, etype
    CHARACTER(len=*), INTENT(IN)             :: routine, msg
    INTEGER, INTENT(IN)                      :: line
    TYPE(dbcsr_error_type), INTENT(inout)    :: error

    LOGICAL                                  :: l

!   ---------------------------------------------------------------------------

    l = right
    IF (.NOT.l) THEN
       WRITE(*,'(1X,A,1X,L1)')"ASSERTION FAILED:",&
            right
       CALL dbcsr_abort (level, etype, routine, msg, line, error)
    ENDIF
    !CALL cp_assert(l, level, etype, routine, msg)
  END SUBROUTINE dbcsr_true_assert


! *****************************************************************************
!> \brief Assertion
!> \param[in] rel             relation
!> \param[in] right           right value
!> \param[in] level           error level
!> \param[in] etype           error type
!> \param[in] routine         Routine name
!> \param[in] msg   Message to display if the assertion fails
! *****************************************************************************
  SUBROUTINE dbcsr_not_assert(rel, right, level, etype, routine, msg, line, error)
    CHARACTER(len=3), INTENT(IN)             :: rel
    LOGICAL, INTENT(IN)                      :: right
    INTEGER, INTENT(IN)                      :: level, etype
    CHARACTER(len=*), INTENT(IN)             :: routine, msg
    INTEGER, INTENT(IN)                      :: line
    TYPE(dbcsr_error_type), INTENT(inout)    :: error

    LOGICAL                                  :: l

!   ---------------------------------------------------------------------------

    SELECT CASE (rel)
    CASE ("NOT")
       l = .NOT. right
    CASE default
       CALL dbcsr_assert (.FALSE., dbcsr_fatal_level, dbcsr_wrong_args_error,&
            "dbcsr_int_assert", "Invalid relation specified: "//rel, __LINE__, error)
       l = .FALSE.
    END SELECT
    IF (.NOT. l) THEN
       WRITE(*,'(1X,A,1X,A,L1)')"ASSERTION FAILED:",&
            "."//rel//".", right
       CALL dbcsr_abort (level, etype, routine, msg, line, error)
    ENDIF
  END SUBROUTINE dbcsr_not_assert

END MODULE dbcsr_error_handling
