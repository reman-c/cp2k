!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2011  CP2K developers group                          !
!-----------------------------------------------------------------------------!

! *****************************************************************************
!> \brief Calculation of the QMMM Hamiltonian integral matrix <a|\sum_i q_i|b> for
!>      semi-empirical methods
!> \author Teodoro Laino 04.2007 [created]
! *****************************************************************************
MODULE qmmm_se_energy
  USE atomic_kind_types,               ONLY: atomic_kind_type,&
                                             get_atomic_kind
  USE cell_types,                      ONLY: cell_type,&
                                             pbc
  USE cp_control_types,                ONLY: dft_control_type
  USE cp_dbcsr_interface,              ONLY: cp_dbcsr_copy,&
                                             cp_dbcsr_get_block_p,&
                                             cp_dbcsr_init,&
                                             cp_dbcsr_set
  USE cp_dbcsr_operations,             ONLY: cp_dbcsr_allocate_matrix_set
  USE cp_dbcsr_output,                 ONLY: cp_dbcsr_write_sparse_matrix
  USE cp_dbcsr_types,                  ONLY: cp_dbcsr_p_type
  USE cp_output_handling,              ONLY: cp_p_file,&
                                             cp_print_key_finished_output,&
                                             cp_print_key_should_output,&
                                             cp_print_key_unit_nr
  USE cp_para_types,                   ONLY: cp_para_env_type
  USE f77_blas
  USE input_constants,                 ONLY: &
       do_method_am1, do_method_mndo, do_method_mndod, do_method_pchg, &
       do_method_pdg, do_method_pm3, do_method_pm6, do_method_pnnl, &
       do_method_rm1, do_multipole_none, do_qmmm_coulomb, do_qmmm_gauss, &
       do_qmmm_none, do_qmmm_swave, use_orb_basis_set
  USE kinds,                           ONLY: dp
  USE message_passing,                 ONLY: mp_sum
  USE particle_types,                  ONLY: particle_type
  USE qmmm_types,                      ONLY: qmmm_env_qm_type,&
                                             qmmm_pot_p_type,&
                                             qmmm_pot_type
  USE qmmm_util,                       ONLY: spherical_cutoff_factor
  USE qs_environment_types,            ONLY: get_qs_env,&
                                             qs_environment_type,&
                                             set_qs_env
  USE qs_ks_qmmm_types,                ONLY: qs_ks_qmmm_env_type
  USE qs_neighbor_lists,               ONLY: build_qs_neighbor_lists
  USE qs_overlap,                      ONLY: build_overlap_matrix
  USE semi_empirical_int_arrays,       ONLY: se_orbital_pointer
  USE semi_empirical_integrals,        ONLY: corecore,&
                                             rotnuc
  USE semi_empirical_types,            ONLY: get_se_param,&
                                             se_int_control_type,&
                                             se_taper_type,&
                                             semi_empirical_create,&
                                             semi_empirical_release,&
                                             semi_empirical_type,&
                                             setup_se_int_control_type
  USE semi_empirical_utils,            ONLY: get_se_type,&
                                             se_param_set_default
  USE termination,                     ONLY: stop_program
  USE timings,                         ONLY: timeset,&
                                             timestop
#include "cp_common_uses.h"

  IMPLICIT NONE

  PRIVATE

  CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'qmmm_se_energy'

  PUBLIC :: build_se_qmmm_matrix

CONTAINS

! *****************************************************************************
!> \brief Constructs the 1-el semi-empirical hamiltonian
!> \author Teodoro Laino 04.2007 [created]
! *****************************************************************************
  SUBROUTINE build_se_qmmm_matrix(qs_env,qmmm_env,mm_particles,mm_cell,para_env,error)

    TYPE(qs_environment_type), POINTER       :: qs_env
    TYPE(qmmm_env_qm_type), POINTER          :: qmmm_env
    TYPE(particle_type), DIMENSION(:), &
      POINTER                                :: mm_particles
    TYPE(cell_type), POINTER                 :: mm_cell
    TYPE(cp_para_env_type), POINTER          :: para_env
    TYPE(cp_error_type), INTENT(inout)       :: error

    CHARACTER(len=*), PARAMETER :: routineN = 'build_se_qmmm_matrix', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: handle, i, iatom, ikind, &
                                                itype, iw, natom, natorb_a, &
                                                nkind, stat
    INTEGER, DIMENSION(:), POINTER           :: list
    LOGICAL                                  :: anag, defined, failure, found
    REAL(KIND=dp)                            :: enuclear
    REAL(KIND=dp), DIMENSION(:, :), POINTER  :: h_block_a
    TYPE(atomic_kind_type), DIMENSION(:), &
      POINTER                                :: atomic_kind_set
    TYPE(atomic_kind_type), POINTER          :: atomic_kind
    TYPE(cp_dbcsr_p_type), DIMENSION(:), &
      POINTER                                :: matrix_s
    TYPE(cp_logger_type), POINTER            :: logger
    TYPE(dft_control_type), POINTER          :: dft_control
    TYPE(qs_ks_qmmm_env_type), POINTER       :: ks_qmmm_env_loc
    TYPE(se_int_control_type)                :: se_int_control
    TYPE(se_taper_type), POINTER             :: se_taper
    TYPE(semi_empirical_type), POINTER       :: se_kind_a, se_kind_mm

    failure = .FALSE.
    CALL timeset(routineN,handle)
    NULLIFY(logger)
    logger => cp_error_get_logger(error)

    NULLIFY (matrix_s, atomic_kind_set)
    NULLIFY (se_kind_a, se_kind_mm, se_taper)
    CALL build_qs_neighbor_lists(qs_env,para_env,force_env_section=qs_env%input,error=error)
    CALL get_qs_env(qs_env=qs_env, matrix_s=matrix_s, error=error)
    CALL build_overlap_matrix(qs_env,matrix_s=matrix_s,&
                              matrix_name="OVERLAP",&
                              basis_set_id_a=use_orb_basis_set,&
                              basis_set_id_b=use_orb_basis_set, &
                              sab_nl=qs_env%sab_orb,&
                              error=error)

    CALL set_qs_env(qs_env=qs_env,matrix_s=matrix_s,error=error)
    CALL get_qs_env(qs_env=qs_env,&
                    se_taper=se_taper,&
                    atomic_kind_set=atomic_kind_set,&
                    ks_qmmm_env=ks_qmmm_env_loc,&
                    dft_control=dft_control,error=error)

    SELECT CASE (dft_control%qs_control%method_id)
    CASE (do_method_am1,do_method_rm1,do_method_mndo,do_method_pdg,&
          do_method_pm3,do_method_pm6,do_method_mndod, do_method_pnnl)
       ! Go on with the calculation.. 
    CASE DEFAULT
       ! Otherwise stop..
       CALL stop_program(routineN,moduleN,__LINE__,&
            "Method not available",para_env)
    END SELECT
    anag = dft_control%qs_control%se_control%analytical_gradients
    ! Setup type for SE integral control 
    CALL setup_se_int_control_type(se_int_control, shortrange=.FALSE.,do_ewald_r3=.FALSE.,&
         do_ewald_gks=.FALSE., integral_screening=dft_control%qs_control%se_control%integral_screening,&
         max_multipole=do_multipole_none, pc_coulomb_int=.FALSE.)

    ! Allocate the core Hamiltonian matrix
    CALL cp_dbcsr_allocate_matrix_set(ks_qmmm_env_loc%matrix_h,1,error=error)
    ALLOCATE(ks_qmmm_env_loc%matrix_h(1)%matrix, STAT=stat)
    CPPrecondition(stat==0,cp_failure_level,routineP,error,failure)

    CALL cp_dbcsr_init(ks_qmmm_env_loc%matrix_h(1)%matrix,error)

    CALL cp_dbcsr_copy(ks_qmmm_env_loc%matrix_h(1)%matrix,matrix_s(1)%matrix,&
                    name="QMMM HAMILTONIAN MATRIX",error=error)
    CALL cp_dbcsr_set(ks_qmmm_env_loc%matrix_h(1)%matrix,0.0_dp,error)

    SELECT CASE(qmmm_env%qmmm_coupl_type)
    CASE(do_qmmm_coulomb,do_qmmm_gauss,do_qmmm_swave)
       ! Create a fake semi-empirical type to handle the classical atom
       CALL semi_empirical_create(se_kind_mm,error)
       CALL se_param_set_default(se_kind_mm,0,do_method_pchg,error)
       itype    = get_se_type(se_kind_mm%typ)
       nkind    = SIZE(atomic_kind_set)
       enuclear = 0.0_dp
       Kinds: DO ikind=1,nkind
          atomic_kind => atomic_kind_set(ikind)
          CALL get_atomic_kind(atomic_kind=atomic_kind,&
                               natom=natom,&
                               se_parameter=se_kind_a,&
                               atom_list=list)
          CALL get_se_param(se_kind_a,&
                            defined=defined,&
                            natorb=natorb_a)
          IF (.NOT.defined .OR. natorb_a < 1) CYCLE
          Atoms: DO i = 1, SIZE(list)
             iatom = list(i)
             ! Give back block
             NULLIFY(h_block_a)
             CALL cp_dbcsr_get_block_p(matrix=ks_qmmm_env_loc%matrix_h(1)%matrix,&
                  row=iatom,col=iatom,BLOCK=h_block_a,found=found)

             IF (ASSOCIATED(h_block_a)) THEN
                h_block_a = 0.0_dp
                ! Real QM/MM computation
                CALL build_se_qmmm_matrix_low(h_block_a,&
                                              se_kind_a,&
                                              se_kind_mm,&
                                              qmmm_env%Potentials,&
                                              mm_particles,&
                                              qmmm_env%mm_atom_chrg,&
                                              qmmm_env%mm_el_pot_radius,&
                                              qmmm_env%mm_atom_index,&
                                              qmmm_env%num_mm_atoms,&
                                              mm_cell,&
                                              qmmm_env%qm_atom_index(iatom),&
                                              enuclear,&
                                              itype,&
                                              se_taper,&
                                              se_int_control,&
                                              anag,&
                                              qmmm_env%spherical_cutoff,&
                                              error)
                ! Possibly added charges
                IF (qmmm_env%move_mm_charges.OR.qmmm_env%add_mm_charges) THEN
                   CALL build_se_qmmm_matrix_low(h_block_a,&
                                                 se_kind_a,&
                                                 se_kind_mm,&
                                                 qmmm_env%added_charges%potentials,&
                                                 qmmm_env%added_charges%added_particles,&
                                                 qmmm_env%added_charges%mm_atom_chrg,&
                                                 qmmm_env%added_charges%mm_el_pot_radius,&
                                                 qmmm_env%added_charges%mm_atom_index,&
                                                 qmmm_env%added_charges%num_mm_atoms,&
                                                 mm_cell,&
                                                 qmmm_env%qm_atom_index(iatom),&
                                                 enuclear,&
                                                 itype,&
                                                 se_taper,&
                                                 se_int_control,&
                                                 anag,&
                                                 qmmm_env%spherical_cutoff,&
                                                 error)       
                END IF
             END IF
          END DO Atoms
       END DO Kinds
       CALL mp_sum(enuclear,para_env%group)
       qs_env%energy%qmmm_nu = enuclear
       CALL semi_empirical_release(se_kind_mm,error)
    CASE(do_qmmm_none)
       ! Zero Matrix 
       CALL cp_dbcsr_set(ks_qmmm_env_loc%matrix_h(1)%matrix,0.0_dp,error=error)
    END SELECT
    IF (BTEST(cp_print_key_should_output(logger%iter_info,&
         qs_env%input,"QMMM%PRINT%QMMM_MATRIX",error=error),cp_p_file)) THEN
       iw = cp_print_key_unit_nr(logger,qs_env%input,"QMMM%PRINT%QMMM_MATRIX",&
            extension=".Log",error=error)
       CALL cp_dbcsr_write_sparse_matrix(ks_qmmm_env_loc%matrix_h(1)%matrix,4,6,qs_env,para_env,&
            scale=1.0_dp,output_unit=iw,error=error)
       CALL cp_print_key_finished_output(iw,logger,qs_env%input,&
            "QMMM%PRINT%QMMM_MATRIX", error=error)
    END IF

    CALL timestop(handle)

  END SUBROUTINE build_se_qmmm_matrix

! *****************************************************************************
!> \brief Low Level : Constructs the 1-el semi-empirical hamiltonian block
!> \author Teodoro Laino 04.2007 [created]
! *****************************************************************************
  SUBROUTINE build_se_qmmm_matrix_low(h_block_a, se_kind_a, se_kind_mm, potentials,&
       mm_particles, mm_charges, mm_el_pot_radius, mm_atom_index, num_mm_atoms,&
       mm_cell, IndQM, enuclear, itype, se_taper, se_int_control, anag, &
       qmmm_spherical_cutoff, error)

    REAL(KIND=dp), DIMENSION(:, :), POINTER  :: h_block_a
    TYPE(semi_empirical_type), POINTER       :: se_kind_a, se_kind_mm
    TYPE(qmmm_pot_p_type), DIMENSION(:), &
      POINTER                                :: potentials
    TYPE(particle_type), DIMENSION(:), &
      POINTER                                :: mm_particles
    REAL(KIND=dp), DIMENSION(:), POINTER     :: mm_charges, mm_el_pot_radius
    INTEGER, DIMENSION(:), POINTER           :: mm_atom_index
    INTEGER, INTENT(IN)                      :: num_mm_atoms
    TYPE(cell_type), POINTER                 :: mm_cell
    INTEGER, INTENT(IN)                      :: IndQM
    REAL(KIND=dp), INTENT(INOUT)             :: enuclear
    INTEGER, INTENT(IN)                      :: itype
    TYPE(se_taper_type), POINTER             :: se_taper
    TYPE(se_int_control_type), INTENT(IN)    :: se_int_control
    LOGICAL, INTENT(IN)                      :: anag
    REAL(KIND=dp), INTENT(IN)                :: qmmm_spherical_cutoff(2)
    TYPE(cp_error_type), INTENT(inout)       :: error

    CHARACTER(len=*), PARAMETER :: routineN = 'build_se_qmmm_matrix_low', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: handle, i1, i1L, i2, Imm, &
                                                Imp, IndMM, Ipot, j1, j1L
    REAL(KIND=dp)                            :: enuc, rt1, rt2, rt3, &
                                                sph_chrg_factor
    REAL(KIND=dp), DIMENSION(3)              :: r_pbc, rij
    REAL(KIND=dp), DIMENSION(45)             :: e1b
    TYPE(qmmm_pot_type), POINTER             :: Pot

    CALL timeset(routineN,handle)
    ! Loop Over MM atoms
    ! Loop over Pot stores atoms with the same charge
    MainLoopPot: DO Ipot = 1, SIZE(Potentials)
       Pot    => Potentials(Ipot)%Pot
       ! Loop over atoms belonging to this type
       LoopMM: DO Imp = 1, SIZE(Pot%mm_atom_index)
          Imm = Pot%mm_atom_index(Imp)
          IndMM = mm_atom_index(Imm) 
          r_pbc=pbc(mm_particles(IndMM)%r-mm_particles(IndQM)%r, mm_cell)
          rt1= r_pbc(1) 
          rt2= r_pbc(2) 
          rt3= r_pbc(3) 
          rij = (/rt1,rt2,rt3/)
          se_kind_mm%zeff = mm_charges(Imm)
          ! Computes the screening factor for the spherical cutoff (if defined)
          IF (qmmm_spherical_cutoff(1)>0.0_dp) THEN 
             CALL spherical_cutoff_factor(qmmm_spherical_cutoff, rij, sph_chrg_factor, error)
             se_kind_mm%zeff = se_kind_mm%zeff * sph_chrg_factor
          END IF
          IF (ABS(se_kind_mm%zeff)<=EPSILON(0.0_dp)) CYCLE
          CALL rotnuc (se_kind_a, se_kind_mm, rij, itype=itype, e1b=e1b, anag=anag,&
               se_int_control=se_int_control, se_taper=se_taper, error=error)
          CALL corecore(se_kind_a, se_kind_mm, rij, itype=itype, enuc=enuc, anag=anag,&
               se_int_control=se_int_control, se_taper=se_taper, error=error)
          enuclear = enuclear + enuc
          ! Contribution to the iatom block
          ! Computation of the QMMM core matrix
          i2 = 0
          DO i1L = 1, se_kind_a%natorb
             i1 = se_orbital_pointer(i1L)
             DO j1L = 1, i1L-1
                j1 = se_orbital_pointer(j1L)
                i2 = i2 + 1
                h_block_a(i1,j1) = h_block_a(i1,j1) + e1b(i2)
                h_block_a(j1,i1) = h_block_a(i1,j1)
             END DO
             j1 = se_orbital_pointer(j1L)
             i2 = i2 + 1
             h_block_a(i1,j1) = h_block_a(i1,j1) + e1b(i2)
          END DO
       END DO LoopMM
    END DO MainLoopPot
    CALL timestop(handle)
  END SUBROUTINE build_se_qmmm_matrix_low

END MODULE qmmm_se_energy
