!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2011  CP2K developers group                          !
!-----------------------------------------------------------------------------!

! *****************************************************************************
!> \brief Perform an abnormal program termination.
!> \note These routines are low-level and thus provide also an error recovery
!>       when dependencies do not allow the use of the error logger. Only
!>       the master (root) process will dump, if para_env is available and
!>       properly specified. Otherwise (without any information about the
!>       parallel environment) most likely more than one process or even all
!>       processes will send their error dump to the default output unit.
!> \par History
!>      - Routine external_control moved to a separate module
!> \author Matthias Krack (12.02.2001)
! *****************************************************************************
MODULE termination

  USE cp_para_types,                   ONLY: cp_para_env_type
  USE f77_blas
  USE kinds,                           ONLY: default_path_length
  USE machine,                         ONLY: default_output_unit,&
                                             m_flush_internal
  USE message_passing,                 ONLY: mp_abort
  USE timings,                         ONLY: print_stack

  IMPLICIT NONE

  PRIVATE

  CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'termination'

  INTEGER :: error_unit = default_output_unit

  PUBLIC :: print_message,&
            set_error_unit,&
            stop_memory,&
            stop_program,&
            stop_read,&
            stop_write

  INTERFACE stop_memory
    MODULE PROCEDURE stop_allocate,&
                     stop_deallocate
  END INTERFACE

CONTAINS

! *****************************************************************************
!> \brief Perform a basic blocking of the text in message and print it
!>        optionally decorated with a frame of stars as defined by declev. 
!> \note
!>       after      : Number of empty lines after the message.
!>       before     : Number of empty lines before the message.
!>       declev     : Decoration level (0,1,2, ... star lines).
!>       message    : String with the message text.
!>       output_unit: Logical unit number of output unit.
!> \par History
!>      - Translated to Fortran 90/95 (07.10.1999, Matthias Krack)
!>      - CP2K by JH 21.08.2000
!>      - Bugs in the dynamic format generation removed (09.02.2001, MK)
!>      - Revised (26.01.2011,MK)
!> \author Matthias Krack (MK)
!> \date 28.08.1996
! *****************************************************************************
  SUBROUTINE print_message(message,output_unit,declev,before,after)

    CHARACTER(LEN=*), INTENT(IN)             :: message
    INTEGER, INTENT(IN)                      :: output_unit
    INTEGER, INTENT(IN), OPTIONAL            :: declev, before, after

    INTEGER :: blank_lines_after, blank_lines_before, decoration_level, i, &
      ibreak, ipos1, ipos2, maxrowlen, msglen, nrow, rowlen

    IF (PRESENT(after)) THEN
       blank_lines_after = MAX(after,0)
    ELSE
       blank_lines_after = 1
    END IF

    IF (PRESENT(before)) THEN
       blank_lines_before = MAX(before,0)
    ELSE
       blank_lines_before = 1
    END IF

    IF (PRESENT(declev)) THEN
       decoration_level = MAX(declev,0)
    ELSE
       decoration_level = 0
    END IF

    IF (decoration_level == 0) THEN
       rowlen = 78
    ELSE
       rowlen = 70
    END IF

    msglen = LEN_TRIM(message)

    ! Calculate number of rows

    nrow = msglen/(rowlen + 1) + 1

    ! Calculate appropriate row length

    rowlen = MIN(msglen,rowlen)

    ! Generate the blank lines before the message

    DO i=1,blank_lines_before
       WRITE (UNIT=output_unit,FMT="(A)") ""
    END DO

    ! Scan for the longest row

    ipos1 = 1
    ipos2 = rowlen
    maxrowlen = 0

    DO
       IF (ipos2 < msglen) THEN
          i = INDEX(message(ipos1:ipos2)," ",BACK=.TRUE.)
          IF (i == 0) THEN
             ibreak = ipos2
          ELSE
             ibreak = ipos1 + i - 2
          END IF
       ELSE
          ibreak = ipos2
       END IF

       maxrowlen = MAX(maxrowlen,ibreak - ipos1 + 1)

       ipos1 = ibreak + 2
       ipos2 = MIN(msglen,ipos1 + rowlen - 1)

       ! When the last row is processed, exit loop

       IF (ipos1 > msglen) EXIT

    END DO

    ! Generate the first set of star rows

    IF (decoration_level > 1) THEN
       DO i=1,decoration_level-1
          WRITE (UNIT=output_unit,FMT="(T2,A)") REPEAT("*",maxrowlen+8)
       END DO
    END IF

    ! Break long messages

    ipos1 = 1
    ipos2 = rowlen

    DO
       IF (ipos2 < msglen) THEN
          i = INDEX(message(ipos1:ipos2)," ",BACK=.TRUE.)
          IF (i == 0) THEN
             ibreak = ipos2
          ELSE
             ibreak = ipos1 + i - 2
          END IF
       ELSE
          ibreak = ipos2
       END IF

       IF (decoration_level == 0) THEN
          WRITE (UNIT=output_unit,FMT="(T2,A)") message(ipos1:ibreak)
       ELSE IF (decoration_level > 0) THEN
          WRITE (UNIT=output_unit,FMT="(T2,A)")&
            "*** "//message(ipos1:ibreak)//REPEAT(" ",ipos1+maxrowlen-ibreak)//"***"
       END IF

       ipos1 = ibreak + 2
       ipos2 = MIN(msglen,ipos1 + rowlen - 1)

       ! When the last row is processed, exit loop

       IF (ipos1 > msglen) EXIT
    END DO

    ! Generate the second set star rows

    IF (decoration_level > 1) THEN
       DO i=1,decoration_level-1
          WRITE (UNIT=output_unit,FMT="(T2,A)") REPEAT("*",maxrowlen+8)
       END DO
    END IF

    ! Generate the blank lines after the message

    DO i=1,blank_lines_after
       WRITE (UNIT=output_unit,FMT="(A)") ""
    END DO

  END SUBROUTINE print_message

! *****************************************************************************
!> \brief Initialise the output unit number for error messages.
!> \par History
!>      none
!> \author JGH
! *****************************************************************************
  SUBROUTINE set_error_unit(lunit)
    INTEGER, INTENT(IN)                      :: lunit

    CHARACTER(LEN=*), PARAMETER :: routineN = 'set_error_unit', &
      routineP = moduleN//':'//routineN

    error_unit = lunit

  END SUBROUTINE set_error_unit

! *****************************************************************************
!> \brief The memory allocation for a data object failed. Print an error
!>        message and stop the program execution.
!> \note
!>      routineN   : Name of the calling routine
!>      moduleN    : Name of the calling module including the calling routine
!>      line_number: Code line number in the module
!>      object     : Name of the data object for which the allocation failed
!>      memory     : Size of the data object in bytes. If zero no size is
!>                   printed.
!> \par History
!>      - CP2K by JGH 21.08.2000
!>      - Revised (16.02.2011,MK)
!> \author Matthias Krack (12.10.1999,MK)
! *****************************************************************************
  SUBROUTINE stop_allocate(routineN,moduleN,line_number,object,memory,para_env)

    CHARACTER(LEN=*), INTENT(IN)             :: routineN, moduleN
    INTEGER, INTENT(IN)                      :: line_number
    CHARACTER(LEN=*), INTENT(IN)             :: object
    INTEGER, INTENT(IN)                      :: memory
    TYPE(cp_para_env_type), OPTIONAL, &
      POINTER                                :: para_env

    CHARACTER(LEN=default_path_length)       :: message

    IF (memory == 0) THEN
      message = "The memory allocation for the data object <"//TRIM(object)//&
                "> failed"
    ELSE
      WRITE (message,"(A,I0,A)")&
        "The memory allocation for the data object <"//TRIM(object)//&
        "> failed. The requested memory size is ",memory/1024," KB"
    END IF

    IF (PRESENT(para_env)) THEN
      CALL stop_program(TRIM(routineN),TRIM(moduleN),line_number,TRIM(message),&
                        para_env)
    ELSE
      CALL stop_program(TRIM(routineN),TRIM(moduleN),line_number,TRIM(message))
    END IF

  END SUBROUTINE stop_allocate

! *****************************************************************************
!> \brief The memory deallocation for a data object failed. Print an error
!>        message and stop the program execution.
!> \note
!>      routineN   : Name of the calling routine
!>      moduleN    : Name of the calling module including the calling routine
!>      line_number: Code line number in the module
!>      object     : Name of the data object for which the deallocation failed
!> \par History
!>      CP2K by JGH 21.08.2000
!>      - Revised (16.02.2011,MK)
!> \author Matthias Krack (20.10.1999,MK)
! *****************************************************************************
  SUBROUTINE stop_deallocate(routineN,moduleN,line_number,object,para_env)

    CHARACTER(LEN=*), INTENT(IN)             :: routineN, moduleN
    INTEGER, INTENT(IN)                      :: line_number
    CHARACTER(LEN=*), INTENT(IN)             :: object
    TYPE(cp_para_env_type), OPTIONAL, &
      POINTER                                :: para_env

    CHARACTER(LEN=default_path_length)       :: message

    message = "The memory deallocation for the data object <"//TRIM(object)//&
              "> failed"

    IF (PRESENT(para_env)) THEN
      CALL stop_program(TRIM(routineN),TRIM(moduleN),line_number,TRIM(message),&
                        para_env)
    ELSE
      CALL stop_program(TRIM(routineN),TRIM(moduleN),line_number,TRIM(message))
    END IF

  END SUBROUTINE stop_deallocate

! *****************************************************************************
!> \brief Stop the program run and write an error message.
!> \note
!>      routine: Name of the calling routine
!> \par History
!>      Translated to Fortran 90 (07.10.99, MK)
!> \author Matthias Krack (28.08.1996,MK)
! *****************************************************************************
  SUBROUTINE stop_program(routineN,moduleN,line_number,error_message,&
                          para_env)

    CHARACTER(LEN=*), INTENT(IN)             :: routineN, moduleN
    INTEGER, INTENT(IN)                      :: line_number
    CHARACTER(LEN=*), INTENT(IN)             :: error_message
    TYPE(cp_para_env_type), OPTIONAL, &
      POINTER                                :: para_env

    CHARACTER(LEN=3*default_path_length)     :: message
    LOGICAL                                  :: ionode

    IF (PRESENT(para_env)) THEN
      ionode = para_env%ionode
    ELSE
      ionode = .TRUE.
    END IF

    ! Print the error message

    IF (ionode) THEN
      message = "ERROR in "//TRIM(routineN)//&
                " (MODULE "//TRIM(moduleN)//")"
      CALL print_message(message,error_unit,2,2,0)
      CALL print_message(error_message,error_unit,1,1,0)
      WRITE (UNIT=message,FMT="(A,I0,A)")&
        "Program stopped at line number ",line_number,&
        " of MODULE "//TRIM(moduleN)
      CALL print_message(message,error_unit,1,1,0)
      CALL print_stack(error_unit)
      CALL m_flush_internal(default_output_unit)
      CALL m_flush_internal(error_unit)
      CALL mp_abort()
    END IF

  END SUBROUTINE stop_program

! *****************************************************************************
!> \brief Print an error message and stop the program execution in case of a
!>        read error.
!> \note
!>      routineN   : Name of the calling routine
!>      moduleN    : Name of the calling module including the calling routine
!>      object     : Name of the data object for which I/O operation failed
!>      unit_number: Logical unit number of the file read from
!> \par History
!>      - Creation (15.02.2011,MK)
!> \author Matthias Krack (MK)
! *****************************************************************************
  SUBROUTINE stop_read(routineN,moduleN,line_number,object,unit_number,&
                       para_env)

    CHARACTER(LEN=*), INTENT(IN)             :: routineN, moduleN
    INTEGER, INTENT(IN)                      :: line_number
    CHARACTER(LEN=*), INTENT(IN)             :: object
    INTEGER, INTENT(IN)                      :: unit_number
    TYPE(cp_para_env_type), OPTIONAL, &
      POINTER                                :: para_env

    CHARACTER(LEN=2*default_path_length)     :: message
    CHARACTER(LEN=default_path_length)       :: file_name
    LOGICAL                                  :: file_exists

    INQUIRE (UNIT=unit_number,EXIST=file_exists)
    IF (file_exists) THEN
       INQUIRE (UNIT=unit_number,NAME=file_name)
       WRITE (UNIT=message,FMT="(A)")&
         "An error occurred reading data object <"//TRIM(ADJUSTL(object))//&
         "> from file <"//TRIM(ADJUSTL(file_name))//">"
    ELSE
       WRITE (UNIT=message,FMT="(A,I0,A)")&
         "Could not read data object <"//TRIM(ADJUSTL(object))//&
         "> from logical unit ",unit_number,". The I/O unit does not exist."
    END IF

    IF (PRESENT(para_env)) THEN
      CALL stop_program(TRIM(routineN),TRIM(moduleN),line_number,TRIM(message),&
                        para_env)
    ELSE
      CALL stop_program(TRIM(routineN),TRIM(moduleN),line_number,TRIM(message))
    END IF

  END SUBROUTINE stop_read

! *****************************************************************************
!> \brief Print an error message and stop the program execution in case of a
!>        read error.
!> \note
!>      routineN   : Name of the calling routine
!>      moduleN    : Name of the calling module including the calling routine
!>      object     : Name of the data object for which I/O operation failed
!>      unit_number: Logical unit number of the file written to
!> \par History
!>      - Creation (15.02.2011,MK)
!> \author Matthias Krack (MK)
! *****************************************************************************
  SUBROUTINE stop_write(routineN,moduleN,line_number,object,unit_number,&
                        para_env)

    CHARACTER(LEN=*), INTENT(IN)             :: routineN, moduleN
    INTEGER, INTENT(IN)                      :: line_number
    CHARACTER(LEN=*), INTENT(IN)             :: object
    INTEGER, INTENT(IN)                      :: unit_number
    TYPE(cp_para_env_type), OPTIONAL, &
      POINTER                                :: para_env

    CHARACTER(LEN=2*default_path_length)     :: message
    CHARACTER(LEN=default_path_length)       :: file_name
    LOGICAL                                  :: file_exists

    INQUIRE (UNIT=unit_number,EXIST=file_exists)
    IF (file_exists) THEN
       INQUIRE (UNIT=unit_number,NAME=file_name)
       WRITE (UNIT=message,FMT="(A)")&
         "An error occurred writing data object <"//TRIM(ADJUSTL(object))//&
         "> to file <"//TRIM(ADJUSTL(file_name))//">"
    ELSE
       WRITE (UNIT=message,FMT="(A,I0,A)")&
         "Could not write data object <"//TRIM(ADJUSTL(object))//&
         "> to logical unit ",unit_number,". The I/O unit does not exist."
    END IF

    IF (PRESENT(para_env)) THEN
      CALL stop_program(TRIM(routineN),TRIM(moduleN),line_number,TRIM(message),&
                        para_env)
    ELSE
      CALL stop_program(TRIM(routineN),TRIM(moduleN),line_number,TRIM(message))
    END IF

  END SUBROUTINE stop_write

END MODULE termination
