!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2011  Urban Borstnik and the CP2K developers group   !
!-----------------------------------------------------------------------------!

  SUBROUTINE do_mm_stack_c (param_stack, stack_size, nparams,&
       a_data, b_data, c_data, c_locks, m_max, n_max, k_max, error)
    TYPE(dbcsr_cuda_mem_type_i4), INTENT(IN) :: param_stack
    INTEGER, INTENT(IN)                      :: stack_size, nparams
    TYPE(dbcsr_cuda_mem_type_c4), INTENT(IN) :: a_data, b_data
    TYPE(dbcsr_cuda_mem_type_c4), &
      INTENT(INOUT)                          :: c_data
    TYPE(dbcsr_cuda_mem_type_i4), INTENT(IN) :: c_locks
    INTEGER, INTENT(IN)                      :: m_max, n_max, k_max
    TYPE(dbcsr_error_type), INTENT(INOUT)    :: error

    CHARACTER(len=*), PARAMETER :: routineN = 'do_mm_stack_c', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: error_handle, istat

!   ---------------------------------------------------------------------------

    CALL dbcsr_error_set (routineN, error_handle, error)
#if defined (__DBCSR_CUDA)
    istat = cuda_do_stack_cu(param_stack%ref, INT(stack_size, KIND=C_INT),&
         INT(nparams, KIND=C_INT),&
         INT(dbcsr_type_complex_4, KIND=C_INT),&
         a_data%ref, b_data%ref, c_data%ref, c_locks%ref,&
         INT(m_max,KIND=C_INT), INT(n_max,KIND=C_INT), INT(k_max,KIND=C_INT))
#else
    istat = -1
#endif
    IF (istat /= 0) THEN
       CALL dbcsr_assert (istat, "EQ", 0,&
            dbcsr_fatal_level, dbcsr_internal_error, routineN,&
            "Error executing CUDA kernel.",&
            __LINE__, error=error)
    ENDIF
    CALL dbcsr_error_stop (error_handle, error)
  END SUBROUTINE do_mm_stack_c




  SUBROUTINE cp_host_to_dev_c (host_mem, dev_mem, n, error)
    INTEGER, INTENT(IN)                         :: n
    TYPE(dbcsr_cuda_mem_type_c4),&
         INTENT(INOUT)                          :: dev_mem
    COMPLEX(kind=real_4), DIMENSION(1:n), INTENT(IN), TARGET :: host_mem
    TYPE(dbcsr_error_type), INTENT(INOUT)       :: error

    CHARACTER(len=*), PARAMETER :: routineN = 'cp_host_to_dev_c', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: error_handle, istat
    COMPLEX(kind=real_4), POINTER                         :: host_first_el
    TYPE(C_PTR)                              :: host_mem_c_ptr

!   ---------------------------------------------------------------------------

    CALL dbcsr_error_set (routineN, error_handle, error)
    IF (careful_mod) &
         CALL dbcsr_assert (n, "LE", dev_mem%len,&
         dbcsr_fatal_level, dbcsr_internal_error, routineN,&
         "Device memory too small for copy.",&
         __LINE__, error=error)
#if defined (__DBCSR_CUDA)
    IF (n .GT. 0) THEN
       host_first_el => host_mem(1)
       host_mem_c_ptr = C_LOC (host_first_el)
    ENDIF
    IF (n .GT. 0) THEN
       istat = cuda_memcpy_h2d_cu(host_mem_c_ptr, dev_mem%ref,&
            INT(n*(2*real_4_size), KIND=C_SIZE_T))
    ELSE
       istat = 0
    ENDIF
#else
    istat = -1
#endif
    IF (istat /= 0) THEN
       CALL dbcsr_assert (istat, "EQ", 0,&
            dbcsr_fatal_level, dbcsr_internal_error, routineN,&
            "Error copying data from host to device memory.",&
            __LINE__, error=error)
    ENDIF
    CALL dbcsr_error_stop (error_handle, error)
  END SUBROUTINE cp_host_to_dev_c


  SUBROUTINE cp_dev_to_host_c (dev_mem, host_mem, n, error)
    TYPE(dbcsr_cuda_mem_type_c4), INTENT(IN) :: dev_mem
    INTEGER, INTENT(IN)                      :: n
    COMPLEX(kind=real_4), DIMENSION(1:n), INTENT(OUT),&
      TARGET                                 :: host_mem
    TYPE(dbcsr_error_type), INTENT(INOUT)    :: error

    CHARACTER(len=*), PARAMETER :: routineN = 'cp_dev_to_host_c', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: error_handle, istat
    COMPLEX(kind=real_4), POINTER                         :: host_first_el
    TYPE(C_PTR)                              :: host_mem_c_ptr

!   ---------------------------------------------------------------------------

    CALL dbcsr_error_set (routineN, error_handle, error)
    IF (careful_mod) &
         CALL dbcsr_assert (n, "LE", dev_mem%len,&
         dbcsr_fatal_level, dbcsr_internal_error, routineN,&
         "Device memory too small for copy.",&
         __LINE__, error=error)
#if defined (__DBCSR_CUDA)
    IF (n .GT. 0) THEN
       host_first_el => host_mem(1)
       host_mem_c_ptr = C_LOC (host_first_el)
    ENDIF
    IF (n .GT. 0) THEN
       istat = cuda_memcpy_d2h_cu(dev_mem%ref, host_mem_c_ptr,&
            INT(n*(2*real_4_size), KIND=C_SIZE_T))
    ELSE
       istat = 0
    ENDIF
#else
    istat = -1
#endif
    IF (istat /= 0) THEN
       CALL dbcsr_assert (istat, "EQ", 0,&
            dbcsr_fatal_level, dbcsr_internal_error, routineN,&
            "Error copying data from device to host memory.",&
            __LINE__, error=error)
    ENDIF
    CALL dbcsr_error_stop (error_handle, error)
  END SUBROUTINE cp_dev_to_host_c
