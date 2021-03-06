!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2011  CP2K developers group                          !
!-----------------------------------------------------------------------------!

! *****************************************************************************
!> \brief   DBCSR example 3
!>          This example shows how to multiply two dbcsr matrices
!> \author  V. Weber
!> \date    2010
!> \version 1.0
!>
!> <b>Modification history:</b>
!> - Created 2010
! *****************************************************************************
PROGRAM dbcsr_example_3
  USE array_types,                     ONLY: array_data,&
                                             array_i1d_obj,&
                                             array_new,&
                                             array_nullify,&
                                             array_release
  USE dbcsr_block_access
  USE dbcsr_data_methods
  USE dbcsr_dist_operations,           ONLY: dbcsr_get_stored_coordinates
  USE dbcsr_error_handling,            ONLY: dbcsr_error_type
  USE dbcsr_io,                        ONLY: dbcsr_print
  USE dbcsr_kinds,                     ONLY: real_8
  USE dbcsr_message_passing,           ONLY: mp_cart_create,&
                                             mp_cart_rank,&
                                             mp_environ,&
                                             mp_world_finalize,&
                                             mp_world_init
  USE dbcsr_methods
  USE dbcsr_operations
  USE dbcsr_ptr_util
  USE dbcsr_transformations
  USE dbcsr_types
  USE dbcsr_util
  USE dbcsr_work_operations

  !$ USE OMP_LIB

  IMPLICIT NONE

  TYPE(dbcsr_obj)                          :: matrix_a, matrix_b, matrix_c
  TYPE(dbcsr_error_type)                   :: error

  TYPE(array_i1d_obj)                      :: col_blk_sizes, row_blk_sizes
  INTEGER, DIMENSION(:), POINTER           :: rbs, cbs
  INTEGER                                  :: mp_comm, group, numnodes, mynode, &
       prow, pcol, nblkrows_total, nblkcols_total, node_holds_blk, max_nze, nze, &
       row, col
  INTEGER, DIMENSION(2)                    :: npdims, myploc
  INTEGER, DIMENSION(:,:), POINTER         :: pgrid
  TYPE(array_i1d_obj)                      :: col_dist, row_dist
  TYPE(dbcsr_distribution_obj)             :: dist
  TYPE(dbcsr_mp_obj)                       :: mp_env
  REAL(real_8), DIMENSION(:), ALLOCATABLE  :: values
  LOGICAL                                  :: tr

  !***************************************************************************************

  CALL mp_world_init(mp_comm)
  npdims(:) = 0
  CALL mp_cart_create (mp_comm, 2, npdims, myploc, group)
  CALL mp_environ (numnodes, mynode, group)
  ALLOCATE (pgrid(0:npdims(1)-1, 0:npdims(2)-1))
  DO prow = 0, npdims(1)-1
     DO pcol = 0, npdims(2)-1
        CALL mp_cart_rank (group, (/ prow, pcol /), pgrid(prow, pcol))
     ENDDO
  ENDDO
  CALL dbcsr_mp_new (mp_env, pgrid, group, mynode, numnodes,&
       myprow=myploc(1), mypcol=myploc(2))
  WRITE(*,*) 'mynode ',mynode,' numnodes',numnodes
  DEALLOCATE(pgrid)

  !***************************************************************************************

  !
  ! the matrix will contain nblkrows_total row blocks and nblkcols_total column blocks
  nblkrows_total = 4
  nblkcols_total = 4

  !
  ! set the block size for each row and column
  ALLOCATE (rbs(nblkrows_total), cbs(nblkcols_total))
  rbs(:) = 2
  cbs(:) = 2

  !
  ! set up the block size arrays
  CALL array_nullify (row_blk_sizes)
  CALL array_nullify (col_blk_sizes)
  CALL array_new (row_blk_sizes, rbs, gift=.TRUE.)
  CALL array_new (col_blk_sizes, cbs, gift=.TRUE.)

  !
  ! set the row and column distributions (here the distribution is set randomly)
  CALL random_dist (row_dist, nblkrows_total, npdims(1))
  CALL random_dist (col_dist, nblkcols_total, npdims(2))

  !
  ! set the dbcsr distribution object
  CALL dbcsr_distribution_new (dist, mp_env, row_dist, col_dist)

  !
  ! initialize the dbcsr matrices
  CALL dbcsr_init (matrix_a)
  CALL dbcsr_init (matrix_b)
  CALL dbcsr_init (matrix_c)

  !
  ! create the dbcsr matrices, i.e. a double precision non symmetric matrix
  ! with nblkrows_total x nblkcols_total blocks and
  ! sizes "sum(row_blk_sizes)" x "sum(col_blk_sizes)", distributed as 
  ! specified by the dist object
  CALL dbcsr_create (matrix=matrix_a,&
       name="this is my matrix a",&
       dist=dist, &
       matrix_type=dbcsr_type_no_symmetry,&
       row_blk_size=row_blk_sizes,&
       col_blk_size=col_blk_sizes,&
       data_type=dbcsr_type_real_8,&
       error=error)

  CALL dbcsr_create (matrix=matrix_b,&
       name="this is my matrix b",&
       dist=dist, &
       matrix_type=dbcsr_type_no_symmetry,&
       row_blk_size=row_blk_sizes,&
       col_blk_size=col_blk_sizes,&
       data_type=dbcsr_type_real_8,&
       error=error)

  CALL dbcsr_create (matrix=matrix_c,&
       name="this is my matrix c",&
       dist=dist, &
       matrix_type=dbcsr_type_no_symmetry,&
       row_blk_size=row_blk_sizes,&
       col_blk_size=col_blk_sizes,&
       data_type=dbcsr_type_real_8,&
       error=error)

  !
  ! set up the a matrix
  rbs => array_data (dbcsr_row_block_sizes (matrix_a))
  cbs => array_data (dbcsr_col_block_sizes (matrix_a))
  mynode = dbcsr_mp_mynode (dbcsr_distribution_mp (dbcsr_distribution (matrix_a)))
  max_nze = dbcsr_max_row_size (matrix_a) * dbcsr_max_col_size (matrix_a)
  ALLOCATE (values (max_nze))
  DO row = 1, dbcsr_nblkrows_total (matrix_a)
     DO col = MAX(row-1,1), MIN(row+1,dbcsr_nblkcols_total (matrix_a))
        tr = .FALSE.
        CALL dbcsr_get_stored_coordinates (matrix_a, row, col, tr, node_holds_blk)
        IF(node_holds_blk .EQ. mynode) THEN
           nze = rbs(row) * cbs(col)
           CALL RANDOM_NUMBER (values (1:nze))
           CALL dbcsr_put_block (matrix_a, row, col, values(1:nze))
        ENDIF
     ENDDO
  ENDDO
  DEALLOCATE (values)

  !
  ! set up the b matrix
  rbs => array_data (dbcsr_row_block_sizes (matrix_b))
  cbs => array_data (dbcsr_col_block_sizes (matrix_b))
  mynode = dbcsr_mp_mynode (dbcsr_distribution_mp (dbcsr_distribution (matrix_b)))
  max_nze = dbcsr_max_row_size (matrix_a) * dbcsr_max_col_size (matrix_b)
  ALLOCATE (values (max_nze))
  DO row = 1, dbcsr_nblkrows_total (matrix_b)
     DO col = MAX(row-1,1), MIN(row+1,dbcsr_nblkcols_total (matrix_b))
        tr = .FALSE.
        CALL dbcsr_get_stored_coordinates (matrix_b, row, col, tr, node_holds_blk)
        IF(node_holds_blk .EQ. mynode) THEN
           nze = rbs(row) * cbs(col)
           CALL RANDOM_NUMBER (values (1:nze))
           CALL dbcsr_put_block (matrix_b, row, col, values(1:nze))
        ENDIF
     ENDDO
  ENDDO
  DEALLOCATE (values)

  !
  ! finalize the dbcsr matrices
  CALL dbcsr_finalize (matrix_a, error=error)
  CALL dbcsr_finalize (matrix_b, error=error)
  CALL dbcsr_finalize (matrix_c, error=error)

  !
  ! multiply the matrices
  CALL dbcsr_multiply ('N', 'N', 1.0_real_8, matrix_a, matrix_b, 0.0_real_8, matrix_c, error=error)

  !
  ! print the matrices
  CALL dbcsr_print (matrix_a, error=error)
  CALL dbcsr_print (matrix_b, error=error)
  CALL dbcsr_print (matrix_c, error=error)

  !
  ! release the matrices
  CALL dbcsr_release (matrix_a)
  CALL dbcsr_release (matrix_b)
  CALL dbcsr_release (matrix_c)

  CALL dbcsr_distribution_release (dist)
  CALL dbcsr_mp_release (mp_env)
  CALL array_release (row_dist)
  CALL array_release (col_dist)
  CALL array_release (row_blk_sizes)
  CALL array_release (col_blk_sizes)

  !***************************************************************************************

  CALL mp_world_finalize ()

  !***************************************************************************************

CONTAINS

  SUBROUTINE random_dist (dist_array, dist_size, nbins)
    TYPE(array_i1d_obj), INTENT(out)         :: dist_array
    INTEGER, INTENT(in)                      :: dist_size, nbins

    INTEGER                                  :: i
    INTEGER, ALLOCATABLE, DIMENSION(:)       :: grid_dist

    ALLOCATE (grid_dist(dist_size))
    CALL array_nullify (dist_array)

    FORALL (i = 1 : dist_size)
       grid_dist(i) = MODULO (nbins-i, nbins)
    END FORALL

    CALL array_new (dist_array, grid_dist, lb=1)
    DEALLOCATE (grid_dist)

  END SUBROUTINE random_dist

END PROGRAM dbcsr_example_3
