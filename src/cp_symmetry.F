!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2011  CP2K developers group                          !
!-----------------------------------------------------------------------------!

! *****************************************************************************
!> \brief Work with symmetry
!> \par History
!> \author jgh
! *****************************************************************************
MODULE cp_symmetry
  USE atomic_kind_types,               ONLY: get_atomic_kind
  USE cell_types,                      ONLY: cell_type
  USE cp_output_handling,              ONLY: cp_print_key_finished_output,&
                                             cp_print_key_unit_nr
  USE f77_blas
  USE input_section_types,             ONLY: section_vals_get_subs_vals,&
                                             section_vals_type,&
                                             section_vals_val_get
  USE k290,                            ONLY: csym_type,&
                                             kp_sym_gen,&
                                             pgrd,&
                                             pgrp,&
                                             print_crys_symmetry,&
                                             release_csym_type
  USE kinds,                           ONLY: dp
  USE molsym,                          ONLY: molecular_symmetry,&
                                             molsym_type,&
                                             print_symmetry,&
                                             release_molsym
  USE particle_types,                  ONLY: particle_type
  USE physcon,                         ONLY: massunit
  USE string_utilities,                ONLY: uppercase
  USE timings,                         ONLY: timeset,&
                                             timestop
#include "cp_common_uses.h"

  IMPLICIT NONE

  PRIVATE

  ! Global parameters (in this module)

  CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'cp_symmetry'

  PUBLIC :: write_symmetry

! *****************************************************************************

CONTAINS

! *****************************************************************************
!> \brief Write symmetry information to output
!> \par History
!> \author jgh
! *****************************************************************************
  SUBROUTINE write_symmetry(particle_set,cell,input_section,error)
    TYPE(particle_type), DIMENSION(:), &
      POINTER                                :: particle_set
    TYPE(cell_type), POINTER                 :: cell
    TYPE(section_vals_type), POINTER         :: input_section
    TYPE(cp_error_type), INTENT(INOUT)       :: error

    CHARACTER(LEN=*), PARAMETER :: routineN = 'write_symmetry', &
      routineP = moduleN//':'//routineN

    CHARACTER(LEN=2), ALLOCATABLE, &
      DIMENSION(:)                           :: element
    CHARACTER(LEN=8)                         :: csym1, csym2, csymm, esymm
    INTEGER                                  :: handle, i, ierr, iw, natom, &
                                                plevel
    INTEGER, ALLOCATABLE, DIMENSION(:)       :: atype
    LOGICAL                                  :: check, failure = .FALSE., &
                                                molecular, pall, pcoor, &
                                                pinertia, prmat, psymmele
    REAL(KIND=dp)                            :: eps_geo
    REAL(KIND=dp), ALLOCATABLE, DIMENSION(:) :: weight, zeff
    REAL(KIND=dp), ALLOCATABLE, &
      DIMENSION(:, :)                        :: coord
    TYPE(cp_logger_type), POINTER            :: logger
    TYPE(csym_type), POINTER                 :: crys_sym
    TYPE(molsym_type), POINTER               :: mol_sym
    TYPE(section_vals_type), POINTER         :: section

    CALL timeset(routineN,handle)

    NULLIFY (logger)
    NULLIFY (section)

    logger => cp_error_get_logger(error)
    iw = cp_print_key_unit_nr(logger=logger,&
                              basis_section=input_section,&
                              print_key_path="PRINT%SYMMETRY",&
                              extension=".symLog",&
                              error=error)

    IF (iw > 0) THEN
      section => section_vals_get_subs_vals(section_vals=input_section,&
                        subsection_name="PRINT%SYMMETRY",error=error)
      CALL section_vals_val_get(section_vals=section,&
                        keyword_name="MOLECULE",l_val=molecular,error=error)
      CALL section_vals_val_get(section_vals=section,&
                        keyword_name="EPS_GEO",r_val=eps_geo,error=error)
      IF ( molecular ) THEN

        NULLIFY(mol_sym)

        natom = SIZE(particle_set)
        ALLOCATE(coord(3,natom),zeff(natom),weight(natom),atype(natom),element(natom),STAT=ierr)
        CPPostcondition(ierr==0,cp_failure_level,routineP,error,failure)

        DO i=1,natom
          CALL get_atomic_kind(atomic_kind=particle_set(i)%atomic_kind,&
                  kind_number=atype(i),element_symbol=element(i),mass=weight(i),zeff=zeff(i))
          coord(1:3,i) = particle_set(i)%r(1:3)
        END DO
        weight = weight/massunit

        CALL molecular_symmetry(mol_sym,eps_geo,coord,atype,weight,error)

        CALL section_vals_val_get(section_vals=section,&
                        keyword_name="STANDARD_ORIENTATION",l_val=pcoor,error=error)
        CALL section_vals_val_get(section_vals=section,&
                        keyword_name="INERTIA",l_val=pinertia,error=error)
        CALL section_vals_val_get(section_vals=section,&
                        keyword_name="SYMMETRY_ELEMENTS",l_val=psymmele,error=error)
        CALL section_vals_val_get(section_vals=section,&
                        keyword_name="ALL",l_val=pall,error=error)
        plevel = 0
        IF ( pcoor ) plevel = plevel + 1
        IF ( pinertia ) plevel = plevel + 10
        IF ( psymmele ) plevel = plevel + 100
        IF ( pall ) plevel = 1111111111

        CALL print_symmetry(mol_sym,coord,atype,element,zeff,weight,iw,plevel,error)

        CALL section_vals_val_get(section_vals=section,&
                        keyword_name="CHECK_SYMMETRY",c_val=esymm,error=error)
        CALL uppercase(esymm)
        IF ( TRIM(esymm) /= "NONE" ) THEN
          csymm = mol_sym%point_group_symbol
          CALL uppercase(csymm)
          check = TRIM(ADJUSTL(csymm)) == TRIM(ADJUSTL(esymm))
          CPPostcondition(check,cp_failure_level,routineP,error,failure)
        END IF

        DEALLOCATE(coord,zeff,weight,atype,element,STAT=ierr)
        CPPostcondition(ierr==0,cp_failure_level,routineP,error,failure)
        
        CALL release_molsym(mol_sym,error)

      ELSE
        ! Crystal symmetry

        NULLIFY(crys_sym)

        natom = SIZE(particle_set)
        ALLOCATE(coord(3,natom),zeff(natom),weight(natom),atype(natom),element(natom),STAT=ierr)
        CPPostcondition(ierr==0,cp_failure_level,routineP,error,failure)

        DO i=1,natom
          CALL get_atomic_kind(atomic_kind=particle_set(i)%atomic_kind,&
                  kind_number=atype(i),element_symbol=element(i),mass=weight(i),zeff=zeff(i))
          coord(1:3,i) = particle_set(i)%r(1:3)
        END DO
        weight = weight/massunit

        CALL kp_sym_gen(crys_sym,coord,atype,cell%hmat,delta=eps_geo,unit=iw,error=error)

        CALL section_vals_val_get(section_vals=section,&
                        keyword_name="ROTATION_MATRICES",l_val=prmat,error=error)
        CALL section_vals_val_get(section_vals=section,&
                        keyword_name="ALL",l_val=pall,error=error)
        plevel = 0
        IF ( prmat ) plevel = plevel + 1
        IF ( pall ) plevel = 1111111111
        crys_sym%plevel = plevel

        CALL print_crys_symmetry(crys_sym,error)

        CALL section_vals_val_get(section_vals=section,&
                        keyword_name="CHECK_SYMMETRY",c_val=esymm,error=error)
        CALL uppercase(esymm)
        IF ( TRIM(esymm) /= "NONE" ) THEN
          csym1 = pgrp(crys_sym%indpg)
          CALL uppercase(csym1)
          csym2 = pgrd(crys_sym%indpg)
          CALL uppercase(csym2)
          check = (TRIM(ADJUSTL(csym1)) == TRIM(ADJUSTL(esymm))).OR.(TRIM(ADJUSTL(csym2)) == TRIM(ADJUSTL(esymm)))
          CPPostcondition(check,cp_failure_level,routineP,error,failure)
        END IF

        CALL release_csym_type(crys_sym,error)

      END IF

    END IF
    CALL cp_print_key_finished_output(iw,logger,input_section,"PRINT%SYMMETRY", error=error)

    CALL timestop(handle)

  END SUBROUTINE write_symmetry

! *****************************************************************************

END MODULE cp_symmetry
