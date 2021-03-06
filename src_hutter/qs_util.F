!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2011  CP2K developers group                          !
!-----------------------------------------------------------------------------!

! *****************************************************************************
!> \brief All kind of helpfull little routines
!> \par History
!>      none
!> \author CJM & JGH
! *****************************************************************************
MODULE qs_util

  USE f77_blas
  USE kinds,                           ONLY: dp,&
                                             dp_size
  USE mathconstants,                   ONLY: &
       dfac, fac, fourpi, oorootpi, rootpi, sqrt105, sqrt15, sqrt2, sqrt21, &
       sqrt3, sqrt35, sqrt5, sqrt7, sqrthalf
  USE orbital_pointers,                ONLY: indco,&
                                             nco,&
                                             ncoset,&
                                             nso,&
                                             nsoset
  USE orbital_transformation_matrices, ONLY: orbtramat
  USE termination,                     ONLY: stop_memory,&
                                             stop_program
#include "cp_common_uses.h"

  IMPLICIT NONE

  PRIVATE

  CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'qs_util'

  !MK sqrt* constants moved to mathconstants

  REAL(KIND=dp), PARAMETER ::  s_root1o4pi=0.5_dp*oorootpi
  REAL(KIND=dp), PARAMETER :: root4pi=2.0_dp*rootpi
  REAL(KIND=dp), PARAMETER ::  s_root3o4pi=sqrt3*s_root1o4pi
  REAL(KIND=dp), PARAMETER :: root4pio3=root4pi/sqrt3
  REAL(KIND=dp), PARAMETER :: root4pio5=root4pi/sqrt5
  REAL(KIND=dp), PARAMETER ::  s_root15o4pi=sqrt15*s_root1o4pi
  REAL(KIND=dp), PARAMETER :: root4pio15=root4pi/sqrt15
  REAL(KIND=dp), PARAMETER ::  s_root105o4pi=sqrt105*s_root1o4pi
  REAL(KIND=dp), PARAMETER :: root4pio105=root4pi/sqrt105
  REAL(KIND=dp), PARAMETER ::  s_root1o16pi=0.25_dp*oorootpi
  REAL(KIND=dp), PARAMETER :: root16pi=4.0_dp*rootpi
  REAL(KIND=dp), PARAMETER ::  s_root5o16pi=sqrt5*s_root1o16pi
  REAL(KIND=dp), PARAMETER :: root16pio5=root16pi/sqrt5
  REAL(KIND=dp), PARAMETER ::  s_2root5o16pi=2.0_dp*s_root5o16pi
  REAL(KIND=dp), PARAMETER :: root16pio5o2=root16pio5*0.5_dp
  REAL(KIND=dp), PARAMETER ::  s_3root5o16pi=3.0_dp*s_root5o16pi
  REAL(KIND=dp), PARAMETER :: root16pio5o3=root16pio5/3.0_dp
  REAL(KIND=dp), PARAMETER ::  s_18root5o16pi=18.0_dp*s_root5o16pi
  REAL(KIND=dp), PARAMETER :: root16pio5o18=root16pio5/18.0_dp
  REAL(KIND=dp), PARAMETER ::  s_2root7o16pi=2.0_dp*sqrt7*s_root1o16pi
  REAL(KIND=dp), PARAMETER :: root16pio7o2=root16pi/sqrt7*0.5_dp
  REAL(KIND=dp), PARAMETER ::  s_3root7o16pi=3.0_dp*sqrt7*s_root1o16pi
  REAL(KIND=dp), PARAMETER :: root16pio7o3=root16pi/sqrt7/3.0_dp
  REAL(KIND=dp), PARAMETER ::  s_root15o16pi=sqrt15*s_root1o16pi
  REAL(KIND=dp), PARAMETER :: root16pio15=root16pi/sqrt15
  REAL(KIND=dp), PARAMETER ::  s_3root35o16pi=sqrt5*s_3root7o16pi
  REAL(KIND=dp), PARAMETER :: root16pio35o3=root16pio7o3/sqrt5
  REAL(KIND=dp), PARAMETER ::  s_root105o16pi=0.5_dp*s_root105o4pi
  REAL(KIND=dp), PARAMETER ::  root16pio105=root4pio105*2.0_dp
  REAL(KIND=dp), PARAMETER ::  s_root1o32pi=0.25_dp*sqrthalf*oorootpi
  REAL(KIND=dp), PARAMETER ::  root32pi=root16pi*sqrt2
  REAL(KIND=dp), PARAMETER ::  s_3root5o32pi=3.0_dp*sqrt5*s_root1o32pi
  REAL(KIND=dp), PARAMETER ::  root32pio5o3=root32pi/sqrt5/3.0_dp
  REAL(KIND=dp), PARAMETER ::  s_9root5o32pi=9.0_dp*sqrt5*s_root1o32pi
  REAL(KIND=dp), PARAMETER ::  root32pio5o9=root32pi/sqrt5/9.0_dp
  REAL(KIND=dp), PARAMETER ::  s_12root5o32pi=12.0_dp*sqrt5*s_root1o32pi
  REAL(KIND=dp), PARAMETER ::  root32pio5o12=root32pi/sqrt5/12.0_dp
  REAL(KIND=dp), PARAMETER ::  s_root21o32pi=sqrt21*s_root1o32pi
  REAL(KIND=dp), PARAMETER ::  root32pio21=root32pi/sqrt21
  REAL(KIND=dp), PARAMETER ::  s_4root21o32pi=4.0_dp*s_root21o32pi
  REAL(KIND=dp), PARAMETER ::  root32pio21o4=root32pio21/4.0_dp
  REAL(KIND=dp), PARAMETER ::  s_root35o32pi=sqrt35*s_root1o32pi
  REAL(KIND=dp), PARAMETER ::  root32pio35=root32pi/sqrt35
  REAL(KIND=dp), PARAMETER ::  s_3root35o32pi=3.0_dp*s_root35o32pi
  REAL(KIND=dp), PARAMETER ::  s_9root35o32pi=9.0_dp*s_root35o32pi
  REAL(KIND=dp), PARAMETER ::  s_18root35o32pi=18.0_dp*s_root35o32pi
  REAL(KIND=dp), PARAMETER ::  s_root1o64pi=0.125_dp*oorootpi
  REAL(KIND=dp), PARAMETER ::  s_3root5o64pi=3.0_dp*sqrt5*s_root1o64pi
  REAL(KIND=dp), PARAMETER ::  s_18root5o64pi=18.0_dp*sqrt5*s_root1o64pi
  REAL(KIND=dp), PARAMETER ::  s_root1o256pi=0.0625_dp*oorootpi
  REAL(KIND=dp), PARAMETER ::  s_3root1o256pi=3.0_dp*s_root1o256pi
  REAL(KIND=dp), PARAMETER ::  s_9root1o256pi=9.0_dp*s_root1o256pi
  REAL(KIND=dp), PARAMETER ::  s_18root1o256pi=18.0_dp*s_root1o256pi
  REAL(KIND=dp), PARAMETER ::  s_24root1o256pi=24.0_dp*s_root1o256pi
  REAL(KIND=dp), PARAMETER ::  s_72root1o256pi=72.0_dp*s_root1o256pi
  REAL(KIND=dp), PARAMETER ::  s_3root35o256pi=3.0_dp*sqrt35*s_root1o256pi
  REAL(KIND=dp), PARAMETER ::  s_18root35o256pi=18.0_dp*sqrt35*s_root1o256pi

  ! *** Public subroutines ***

  PUBLIC :: cart2sph_mat,&
       exp_radius,& 
       gauss_exponent,&
       gaussint_sph,&
       trace_r_AxB, &
       trace_r_AxB_new, &
       transform_c2s,&
       transform_c2s_new,&
       transform_s2c

CONTAINS

! *****************************************************************************
!> \brief  The exponent of a primitive Gaussian function for a given radius
!>         and threshold is calculated. 
!> \author MK 
!> \date   07.03.1999
!> \par Variables
!>      - exponent : Exponent of the primitive Gaussian function.
!>      - l        : Angular momentum quantum number l.
!>      - prefactor: Prefactor of the Gaussian function (e.g. a contraction
!>                   coefficient).
!>      - radius   : Calculated radius of the Gaussian function.
!>      - threshold: Threshold for radius. 
!> \version 1.0
! *****************************************************************************
  FUNCTION gauss_exponent(l,radius,threshold,prefactor) RESULT(exponent)
    INTEGER, INTENT(IN)                      :: l
    REAL(KIND=dp), INTENT(IN)                :: radius, threshold, prefactor
    REAL(KIND=dp)                            :: exponent

    exponent = 0.0_dp

    IF (radius < 1.0E-6_dp) RETURN
    IF (threshold < 1.0E-12_dp) RETURN

    exponent = LOG(ABS(prefactor)*radius**l/threshold)/radius**2

  END FUNCTION gauss_exponent

! *****************************************************************************
!> \brief  The radius of a primitive Gaussian function for a given threshold
!>         is calculated. 
!>               g(r) = prefactor*r**l*exp(-alpha*r**2) - threshold = 0
!> \par History
!>            - Modified to bisection to avoid division by zero (01.2002, Joost)
!>            - that means the old version contains bugs .......(04.2002, Joost)
!>              so keep this one ...
!> \author  MK
!> \date    26.02.1999
!> \par Variables
!>        - alpha    : Exponent of the primitive Gaussian function.
!>        - l        : Angular momentum quantum number l.
!>        - prefactor: Prefactor of the Gaussian function (e.g. a contraction
!>                     coefficient).
!>        - radius   : Calculated radius of the Gaussian function.
!>        - threshold: Threshold for radius.
!>        - epsiter: Convergence criterion.
!>        - g      : The function g(r).
!>        - maxiter: Maximum number of iterations.
!> \version 1.0
! *****************************************************************************
  FUNCTION exp_radius(l,alpha,threshold,prefactor,epsin) RESULT(radius)
    INTEGER, INTENT(IN)                      :: l
    REAL(KIND=dp), INTENT(IN)                :: alpha, threshold, prefactor
    REAL(KIND=dp), INTENT(IN), OPTIONAL      :: epsin
    REAL(KIND=dp)                            :: radius

    CHARACTER(len=*), PARAMETER :: routineN = 'exp_radius', &
      routineP = moduleN//':'//routineN
    INTEGER, PARAMETER                       :: maxiter = 5000

    INTEGER                                  :: iter
    REAL(KIND=dp)                            :: a, ar2, d, epsiter, g, r, &
                                                rhigh, rlow, rmid, t

    IF (PRESENT(epsin)) THEN
       epsiter=epsin
    ELSE
       epsiter=EPSILON(epsiter)*(1.0E-12_dp / 2.22044604925031E-16_dp)
    ENDIF

    ! Initialize function value

    radius = 0.0_dp

    ! Load and check parameter values

    IF (l < 0) THEN
       CALL stop_program(routineN,moduleN,__LINE__,&
                         "The angular momentum quantum number is negative")
    END IF

    IF (alpha == 0.0_dp) THEN
       CALL stop_program(routineN,moduleN,__LINE__,&
                        "The Gaussian function exponent is zero")
    ELSE
       a = ABS(alpha)
    END IF

    IF (threshold == 0.0_dp) THEN
       CALL stop_program(routineN,moduleN,__LINE__,&
                         "The requested threshold is zero")
    ELSE
       t = ABS(threshold)
    END IF

    IF (prefactor == 0.0_dp) THEN
       RETURN
    ELSE
       d = ABS(prefactor)
    END IF

    ! Calculate the Maximum g(r)
    r = SQRT(0.5_dp*REAL(l,dp)/a)
    ar2 = a*r*r

    IF (l == 0) THEN
       g = d
    ELSE
       g = d*r**l*EXP(-ar2)
    END IF

    IF (t > g) THEN
       RETURN
    END IF

    rlow  = r
    rhigh = 2.0_dp*rlow+1.0_dp
    iter=0
    DO 
       iter=iter+1
       IF (iter.gt.maxiter) THEN
          CALL stop_program(routineN,moduleN,__LINE__,&
                            "Maximum number of iterations exceeded")
       END IF
       g = d*rhigh**l*EXP(-a*rhigh**2)
       IF (g < t) EXIT
       rlow = rhigh
       rhigh =  2.0_dp*rlow+1.0_dp 
    ENDDO

    DO iter=1,maxiter
       rmid= (rlow+rhigh)*0.5_dp
       ar2 = a*rmid*rmid
       g   = d*rmid**l*EXP(-ar2)
       IF  (g.lt.t) THEN
          rhigh=rmid
       ELSE
          rlow=rmid
       ENDIF
       IF (ABS(rhigh-rlow).lt.epsiter) THEN
          radius=rhigh
          RETURN
       ENDIF
    ENDDO
    CALL stop_program(routineN,moduleN,__LINE__,&
                      "Maximum number of iterations exceeded")

  END FUNCTION exp_radius

! *****************************************************************************
  FUNCTION gaussint_sph(alpha,l)

    !  calculates the radial integral over a spherical Gaussian
    !  of the form
    !     r**(2+l) * exp(-alpha * r**2)
    !

    REAL(dp), INTENT(IN)                     :: alpha
    INTEGER, INTENT(IN)                      :: l
    REAL(dp)                                 :: gaussint_sph

    IF ((l/2)*2==l) THEN
       !even l:
       gaussint_sph=ROOTPI * 0.5_dp**(l/2+2) * dfac(l+1    )&
            /SQRT(alpha)**(l+3)
    ELSE
       !odd l:
       gaussint_sph=0.5_dp * fac((l+1    )/2) /SQRT(alpha)**(l+3)
    ENDIF

  END FUNCTION gaussint_sph

! *****************************************************************************
  FUNCTION trace_r_AxB(A,lda,B,ldb,m,n)

    INTEGER, INTENT(in)                      :: lda
    REAL(dp), INTENT(in)                     :: A(lda,*)
    INTEGER, INTENT(in)                      :: ldb
    REAL(dp), INTENT(in)                     :: B(ldb,*)
    INTEGER, INTENT(in)                      :: m, n
    REAL(dp)                                 :: trace_r_AxB

    INTEGER                                  :: i1, i2, imod, mminus3
    REAL(dp)                                 :: t1, t2, t3, t4

    t1=0._dp
    t2=0._dp
    t3=0._dp
    t4=0._dp
    imod=MODULO(m,4)
    SELECT CASE (imod)
    CASE (0)
       DO i2=1,n
          DO i1=1,m,4
             t1=t1+A(i1,i2)*B(i1,i2)
             t2=t2+A(i1+1,i2)*B(i1+1,i2)
             t3=t3+A(i1+2,i2)*B(i1+2,i2)
             t4=t4+A(i1+3,i2)*B(i1+3,i2)
          ENDDO
       ENDDO
    CASE (1)
       mminus3=m-3
       DO i2=1,n
          DO i1=1,mminus3,4
             t1=t1+A(i1,i2)*B(i1,i2)
             t2=t2+A(i1+1,i2)*B(i1+1,i2)
             t3=t3+A(i1+2,i2)*B(i1+2,i2)
             t4=t4+A(i1+3,i2)*B(i1+3,i2)
          ENDDO
          t1=t1+A(m,i2)*B(m,i2)
       ENDDO
    CASE (2)
       mminus3=m-3
       DO i2=1,n
          DO i1=1,mminus3,4
             t1=t1+A(i1,i2)*B(i1,i2)
             t2=t2+A(i1+1,i2)*B(i1+1,i2)
             t3=t3+A(i1+2,i2)*B(i1+2,i2)
             t4=t4+A(i1+3,i2)*B(i1+3,i2)
          ENDDO
          t1=t1+A(m-1,i2)*B(m-1,i2)
          t2=t2+A(m,i2)*B(m,i2)
       ENDDO
    CASE (3)
       mminus3=m-3
       DO i2=1,n
          DO i1=1,mminus3,4
             t1=t1+A(i1,i2)*B(i1,i2)
             t2=t2+A(i1+1,i2)*B(i1+1,i2)
             t3=t3+A(i1+2,i2)*B(i1+2,i2)
             t4=t4+A(i1+3,i2)*B(i1+3,i2)
          ENDDO
          t1=t1+A(m-2,i2)*B(m-2,i2)
          t2=t2+A(m-1,i2)*B(m-1,i2)
          t3=t3+A(m,i2)*B(m,i2)
       ENDDO
    END SELECT
    trace_r_AxB=t1+t2+t3+t4

  END FUNCTION trace_r_AxB

! *****************************************************************************
  FUNCTION trace_r_AxB_new(A,lda,ia,ja,B,ldb,ib,jb,m,n)

    INTEGER, INTENT(in)                      :: lda
    REAL(dp), INTENT(in)                     :: A(lda,*)
    INTEGER, INTENT(in)                      :: ia, ja, ldb
    REAL(dp), INTENT(in)                     :: B(ldb,*)
    INTEGER, INTENT(in)                      :: ib, jb, m, n
    REAL(dp)                                 :: trace_r_AxB_new

    INTEGER                                  :: i1, i2, imod, mminus3
    REAL(dp)                                 :: t1, t2, t3, t4

    t1=0._dp
    t2=0._dp
    t3=0._dp
    t4=0._dp
    imod=MODULO(m,4)
    SELECT CASE (imod)
    CASE (0)
       DO i2=1,n
          DO i1=1,m,4
             t1=t1+A(i1+ia,i2+ja)*B(i1+ib,i2+jb)
             t2=t2+A(i1+ia+1,i2+ja)*B(i1+ib+1,i2+jb)
             t3=t3+A(i1+ia+2,i2+ja)*B(i1+ib+2,i2+jb)
             t4=t4+A(i1+ia+3,i2+ja)*B(i1+ib+3,i2+jb)
          ENDDO
       ENDDO
    CASE (1)
       mminus3=m-3
       DO i2=1,n
          DO i1=1,mminus3,4
             t1=t1+A(i1+ia,i2+ja)*B(i1+ib,i2+jb)
             t2=t2+A(i1+ia+1,i2+ja)*B(i1+ib+1,i2+jb)
             t3=t3+A(i1+ia+2,i2+ja)*B(i1+ib+2,i2+jb)
             t4=t4+A(i1+ia+3,i2+ja)*B(i1+ib+3,i2+jb)
          ENDDO
          t1=t1+A(m+ia,i2+ja)*B(m+ib,i2+jb)
       ENDDO
    CASE (2)
       mminus3=m-3
       DO i2=1,n
          DO i1=1,mminus3,4
             t1=t1+A(i1+ia,i2+ja)*B(i1+ib,i2+jb)
             t2=t2+A(i1+ia+1,i2+ja)*B(i1+ib+1,i2+jb)
             t3=t3+A(i1+ia+2,i2+ja)*B(i1+ib+2,i2+jb)
             t4=t4+A(i1+ia+3,i2+ja)*B(i1+ib+3,i2+jb)
          ENDDO
          t1=t1+A(m-1+ia,i2+ja)*B(m-1+ib,i2+jb)
          t2=t2+A(m+ia,i2+ja)*B(m+ib,i2+jb)
       ENDDO
    CASE (3)
       mminus3=m-3
       DO i2=1,n
          DO i1=1,mminus3,4
             t1=t1+A(i1+ia,i2+ja)*B(i1+ib,i2+jb)
             t2=t2+A(i1+ia+1,i2+ja)*B(i1+ib+1,i2+jb)
             t3=t3+A(i1+ia+2,i2+ja)*B(i1+ib+2,i2+jb)
             t4=t4+A(i1+ia+3,i2+ja)*B(i1+ib+3,i2+jb)
          ENDDO
          t1=t1+A(m-2+ia,i2+ja)*B(m-2+ib,i2+jb)
          t2=t2+A(m-1+ia,i2+ja)*B(m-1+ib,i2+jb)
          t3=t3+A(m+ia,i2+ja)*B(m+ib,i2+jb)
       ENDDO
    END SELECT
    trace_r_AxB_new=t1+t2+t3+t4

  END FUNCTION trace_r_AxB_new

! *****************************************************************************
  SUBROUTINE transform_c2s(CPC_co,CPC_so,maxl,lm1,lm2)

    REAL(dp), DIMENSION(:, :), INTENT(IN)    :: CPC_co
    REAL(dp), DIMENSION(:, :), INTENT(OUT)   :: CPC_so
    INTEGER                                  :: maxl, lm1, lm2

    CHARACTER(len=*), PARAMETER :: routineN = 'transform_c2s', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: ic1, ic2, is1, is2, istat, l, &
                                                lx, ly, lz
    REAL(dp), ALLOCATABLE, DIMENSION(:, :)   :: work

    ALLOCATE (work(ncoset(maxl),nsoset(maxl)),STAT=istat)
    IF (istat /= 0) THEN
       CALL stop_memory(routineN,moduleN,__LINE__,&
                        "work",dp_size*ncoset(maxl)*nsoset(maxl))
    END IF
    CPC_so = 0.0_dp
    work   = 0.0_dp

    !    DO l = 0,maxl
    !      ncgf = nco(l)
    !      nsgf = nso(l)
    !      ico = ncoset(l-1) + 1
    !      iso = nsoset(l-1) + 1
    !
    !      CALL dgemm("N","T",ncoset(maxl),nsgf,ncgf,&
    !                 1.0_dp,CPC_co(1,ico),ncoset(maxl),&
    !                 orbtramat(l)%c2s(1,1),nsgf,&
    !                 0.0_dp,work(1,iso),ncoset(maxl))
    !    ENDDO
    !
    !    DO l = 0,maxl
    !      ncgf = nco(l)
    !      nsgf = nso(l)
    !      ico = ncoset(l-1) + 1
    !      iso = nsoset(l-1) + 1
    !
    !      CALL dgemm("N","N",nsgf,nsoset(maxl),ncgf,&
    !                 1.0_dp,orbtramat(l)%c2s(1,1),nsgf,&
    !                 work(ico,1),ncoset(maxl),&
    !                 0.0_dp,CPC_so(iso,1),nsoset(maxl))
    !    ENDDO

    !  do l = 0,maxl
    !     do is1 = 1,nso(l)
    !      write(*,'(A,2I3,10f10.5)') 'or ', l, is1, orbtramat(l)%c2s(is1,1:nco(l))
    !     enddo
    !  enddo
    !
    !  stop

    CPC_so = 0.0_dp
    work = 0.0_dp
    DO ic1 = 1,ncoset(lm1)
       DO l = 0,lm2
          DO is2 = 1,nso(l)
             DO ic2 = 1,nco(l)
                lx = indco(1,ic2+ncoset(l-1))
                ly = indco(2,ic2+ncoset(l-1))
                lz = indco(3,ic2+ncoset(l-1))
                work(ic1,is2+nsoset(l-1)) = &
                     work(ic1,is2+nsoset(l-1)) + &
                     CPC_co(ic1,ic2+ncoset(l-1))*&
                     orbtramat(l)%c2s(is2,ic2)*& 
                     SQRT(fourpi/dfac(2*l+1)*&
                     dfac(2*lx-1)*dfac(2*ly-1)*dfac(2*lz-1)) 
                !         write(*,*) 'dfac 1', dfac(2*lx-1)*dfac(2*ly-1)*dfac(2*lz-1)
             ENDDO
          ENDDO
       ENDDO
    ENDDO

    DO is2 = 1,nsoset(lm2)
       DO l = 0,lm1
          DO is1 = 1,nso(l)
             DO ic1 = 1,nco(l)
                lx = indco(1,ic1+ncoset(l-1))
                ly = indco(2,ic1+ncoset(l-1))
                lz = indco(3,ic1+ncoset(l-1))
                CPC_so(is1+nsoset(l-1),is2) = &
                     CPC_so(is1+nsoset(l-1),is2) + &
                     work(ic1+ncoset(l-1),is2)* &
                     orbtramat(l)%c2s(is1,ic1)* &
                     SQRT(fourpi/dfac(2*l+1)*&
                     dfac(2*lx-1)*dfac(2*ly-1)*dfac(2*lz-1))
                !          write(*,*) 'dfac 2', dfac(2*lx-1)*dfac(2*ly-1)*dfac(2*lz-1)
             ENDDO
          ENDDO
       ENDDO
    ENDDO

    DEALLOCATE (work,STAT=istat)
    IF (istat /= 0) THEN
       CALL stop_memory(routineN,moduleN,__LINE__,"work")
    END IF

  END SUBROUTINE transform_c2s

! *****************************************************************************
  SUBROUTINE transform_c2s_new(CPC_co,CPC_so,maxl)

    REAL(dp), DIMENSION(:, :), INTENT(IN)    :: CPC_co
    REAL(dp), DIMENSION(:, :), INTENT(OUT)   :: CPC_so
    INTEGER                                  :: maxl

    CHARACTER(len=*), PARAMETER :: routineN = 'transform_c2s_new', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: iso, istat, ldc, lds
    REAL(dp), ALLOCATABLE, &
      DIMENSION(:, :, :)                     :: work

    ALLOCATE (work(ncoset(maxl),ncoset(maxl),1),STAT=istat)
    IF (istat /= 0) THEN
       CALL stop_memory(routineN,moduleN,__LINE__,&
                        "work",dp_size*ncoset(maxl)*nsoset(maxl))
    END IF
    ldc = ncoset(maxl)
    lds = nsoset(maxl)
    CPC_so = 0.0_dp
    work   = 0.0_dp

    work(1:ldc,1:ldc,1) = CPC_co(1:ldc,1:ldc)

    CALL cart2sph_mat(work,ldc,ldc,1,maxl,maxl)

    DO iso = 1,nsoset(maxl)
       CPC_so(1:nsoset(maxl),iso) = work(1:nsoset(maxl),iso,1)
    END DO

    DEALLOCATE (work,STAT=istat)
    IF (istat /= 0) THEN
       CALL stop_memory(routineN,moduleN,__LINE__,"work")
    END IF

  END SUBROUTINE transform_c2s_new

! *****************************************************************************
  SUBROUTINE transform_s2c(matso,matco,maxl,lm1,lm2)

    REAL(dp), DIMENSION(:, :), INTENT(IN)    :: matso
    REAL(dp), DIMENSION(:, :), INTENT(OUT)   :: matco
    INTEGER, INTENT(IN)                      :: maxl, lm1, lm2

    CHARACTER(len=*), PARAMETER :: routineN = 'transform_s2c', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: ic1, ic2, ico, is1, is2, iso, &
                                                istat, l, lx, ly, lz, nc1, &
                                                nc2, ns1, ns2
    REAL(dp), ALLOCATABLE, DIMENSION(:, :)   :: matsc

    ALLOCATE (matsc(nsoset(maxl),ncoset(maxl)),STAT=istat)
    IF (istat /= 0) THEN
       CALL stop_memory(routineN,moduleN,__LINE__,&
            "work",nsoset(maxl)*ncoset(maxl))
    END IF
    matco = 0.0_dp
    matsc  = 0.0_dp

    ns1 = nsoset(lm1)
    ns2 = nsoset(lm2)
    nc1 = ncoset(lm1)
    nc2 = ncoset(lm2)

    !   A = matso (ns1 x ns2)
    !   C = Tt x A x T = matco (nc1 x nc2)   
    !   B = A x T      = matsc (ns1 x nc2)

    !   Calculate B
    DO is1 = 1,ns1
       DO l = 0,lm2
          DO ico = 1,nco(l)
             ic2 = ncoset(l-1) + ico
             lx = indco(1,ico+ncoset(l-1))
             ly = indco(2,ico+ncoset(l-1))
             lz = indco(3,ico+ncoset(l-1))
             DO iso = 1,nso(l)
                is2 = nsoset(l-1) + iso
                matsc(is1,ic2) = matsc(is1,ic2) + &
                     matso(is1,is2) * orbtramat(l)%s2c(iso,ico) *&
                     SQRT((fourpi)/dfac(2*l+1)*&
                     dfac(2*lx-1)*dfac(2*ly-1)*dfac(2*lz-1))
             ENDDO ! iso
          ENDDO ! ico
       ENDDO ! l
    ENDDO ! is1

    !   Calculate C
    DO  ic2 = 1,nc2
       DO l = 0,lm1
          DO ico = 1,nco(l)
             ic1 = ncoset(l-1) + ico
             lx = indco(1,ico+ncoset(l-1))
             ly = indco(2,ico+ncoset(l-1))
             lz = indco(3,ico+ncoset(l-1))
             DO iso = 1,nso(l)
                is1=nsoset(l-1) + iso
                matco(ic1,ic2) = matco(ic1,ic2) + &
                     matsc(is1,ic2) * orbtramat(l)%s2c(iso,ico) *&
                     SQRT((fourpi)/dfac(2*l+1)*&
                     dfac(2*lx-1)*dfac(2*ly-1)*dfac(2*lz-1))
             ENDDO ! iso
          ENDDO ! ico
       ENDDO ! l
    ENDDO ! ic2

    DEALLOCATE (matsc,STAT=istat)
    IF (istat /= 0) THEN
       CALL stop_memory(routineN,moduleN,__LINE__,"matsc")
    END IF

  END SUBROUTINE transform_s2c
  !------------------------------------------------------------------------------!
! *****************************************************************************
  SUBROUTINE sph2cart_mat(mat,ld_mat,sd_mat,n,lmax1,lmax2)
    INTEGER                                  :: ld_mat, sd_mat, n
    REAL(dp)                                 :: mat(ld_mat,sd_mat,n)
    INTEGER                                  :: lmax1, lmax2

    CHARACTER(len=*), PARAMETER :: routineN = 'sph2cart_mat', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: idx_l1, idx_l2
    REAL(dp) :: mat_aux(ncoset(lmax1),nsoset(lmax2),n)

    IF (lmax1>3.or.lmax2>3) THEN
       CALL stop_program(routineN,moduleN,__LINE__,&
                         "l>3 not implemented")
    END IF
    DO idx_l2=1,nsoset(lmax2)

       mat_aux(1,idx_l2,:)&
            =s_root1o4pi*mat(1,idx_l2,:)

       IF (lmax1==0) CYCLE

       mat_aux(2,idx_l2,:)&
            =-s_root3o4pi*mat(4,idx_l2,:)

       mat_aux(3,idx_l2,:)&
            =-s_root3o4pi*mat(2,idx_l2,:)

       mat_aux(4,idx_l2,:)&
            =s_root3o4pi*mat(3,idx_l2,:)

       IF (lmax1==1) CYCLE

       mat_aux(5,idx_l2,:)&
            =-s_root5o16pi*mat(7,idx_l2,:)&
            +s_root15o16pi*mat(9,idx_l2,:)

       mat_aux(6,idx_l2,:)&
            =s_root15o4pi*mat(5,idx_l2,:)

       mat_aux(7,idx_l2,:)&
            =-s_root5o16pi*mat(7,idx_l2,:)&
            -s_root15o16pi*mat(9,idx_l2,:)

       mat_aux(8,idx_l2,:)&
            =-s_root15o4pi*mat(8,idx_l2,:)

       mat_aux(9,idx_l2,:)&
            =-s_root15o4pi*mat(6,idx_l2,:)

       mat_aux(10,idx_l2,:)&
            =s_2root5o16pi*mat(7,idx_l2,:)

       IF (lmax1==2) CYCLE

       mat_aux(11,idx_l2,:)&
            =-s_root21o32pi*mat(14,idx_l2,:)&
            +s_root35o32pi*mat(16,idx_l2,:)

       mat_aux(12,idx_l2,:)&
            =-s_3root35o32pi*mat(10,idx_l2,:)&
            +s_root21o32pi*mat(12,idx_l2,:)

       mat_aux(13,idx_l2,:)&
            =s_root21o32pi*mat(14,idx_l2,:)&
            +s_3root35o32pi*mat(16,idx_l2,:)

       mat_aux(14,idx_l2,:)&
            =s_root35o32pi*mat(10,idx_l2,:)&
            +s_root21o32pi*mat(12,idx_l2,:)

       mat_aux(15,idx_l2,:)&
            =-s_3root7o16pi*mat(13,idx_l2,:)&
            +s_root105o16pi*mat(15,idx_l2,:)

       mat_aux(16,idx_l2,:)&
            =s_root105o4pi*mat(11,idx_l2,:)

       mat_aux(17,idx_l2,:)&
            =-s_3root7o16pi*mat(13,idx_l2,:)&
            -s_root105o16pi*mat(15,idx_l2,:)

       mat_aux(18,idx_l2,:)&
            =-s_4root21o32pi*mat(14,idx_l2,:)

       mat_aux(19,idx_l2,:)&
            =-s_4root21o32pi*mat(12,idx_l2,:)

       mat_aux(20,idx_l2,:)&
            =s_2root7o16pi*mat(13,idx_l2,:)

    ENDDO

    DO idx_l1=1,ncoset(lmax1)

       mat(idx_l1,1,:)&
            =s_root1o4pi*mat_aux(idx_l1,1,:)

       IF (lmax2==0) CYCLE

       mat(idx_l1,2,:)&
            =-s_root3o4pi*mat_aux(idx_l1,4,:)

       mat(idx_l1,3,:)&
            =-s_root3o4pi*mat_aux(idx_l1,2,:)

       mat(idx_l1,4,:)&
            =s_root3o4pi*mat_aux(idx_l1,3,:)

       IF (lmax2==1) CYCLE

       mat(idx_l1,5,:)&
            =-s_root5o16pi*mat_aux(idx_l1,7,:)&
            +s_root15o16pi*mat_aux(idx_l1,9,:)

       mat(idx_l1,6,:)&
            =s_root15o4pi*mat_aux(idx_l1,5,:)

       mat(idx_l1,7,:)&
            =-s_root5o16pi*mat_aux(idx_l1,7,:)&
            -s_root15o16pi*mat_aux(idx_l1,9,:)

       mat(idx_l1,8,:)&
            =-s_root15o4pi*mat_aux(idx_l1,8,:)

       mat(idx_l1,9,:)&
            =-s_root15o4pi*mat_aux(idx_l1,6,:)

       mat(idx_l1,10,:)&
            =s_2root5o16pi*mat_aux(idx_l1,7,:)

       IF (lmax2==2) CYCLE

       mat(idx_l1,11,:)&
            =-s_root21o32pi*mat_aux(idx_l1,14,:)&
            +s_root35o32pi*mat_aux(idx_l1,16,:)

       mat(idx_l1,12,:)&
            =-s_3root35o32pi*mat_aux(idx_l1,10,:)&
            +s_root21o32pi*mat_aux(idx_l1,12,:)

       mat(idx_l1,13,:)&
            =s_root21o32pi*mat_aux(idx_l1,14,:)&
            +s_3root35o32pi*mat_aux(idx_l1,16,:)

       mat(idx_l1,14,:)&
            =s_root35o32pi*mat_aux(idx_l1,10,:)&
            +s_root21o32pi*mat_aux(idx_l1,12,:)

       mat(idx_l1,15,:)&
            =-s_3root7o16pi*mat_aux(idx_l1,13,:)&
            +s_root105o16pi*mat_aux(idx_l1,15,:)

       mat(idx_l1,16,:)&
            =s_root105o4pi*mat_aux(idx_l1,11,:)

       mat(idx_l1,17,:)&
            =-s_3root7o16pi*mat_aux(idx_l1,13,:)&
            -s_root105o16pi*mat_aux(idx_l1,15,:)

       mat(idx_l1,18,:)&
            =-s_4root21o32pi*mat_aux(idx_l1,14,:)

       mat(idx_l1,19,:)&
            =-s_4root21o32pi*mat_aux(idx_l1,12,:)

       mat(idx_l1,20,:)&
            =s_2root7o16pi*mat_aux(idx_l1,13,:)

    ENDDO

  END SUBROUTINE sph2cart_mat

! *****************************************************************************
  SUBROUTINE cart2sph_mat(mat,ld_mat,sd_mat,n,lmax1,lmax2)

    !in:
    INTEGER                                  :: ld_mat, sd_mat, n
    REAL(dp)                                 :: mat(ld_mat,sd_mat,n)
    INTEGER                                  :: lmax1, lmax2

    CHARACTER(len=*), PARAMETER :: routineN = 'cart2sph_mat', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: idx_l2, idx_lm1
    REAL(dp) :: mat_aux(nsoset(lmax1),ncoset(lmax2),n)

    IF ((lmax1 > 3).OR.(lmax2 > 3)) THEN
       CALL stop_program(routineN,moduleN,__LINE__,&
                         "l > 3 not implemented")
    END IF

    DO idx_l2=1,ncoset(lmax2)

       mat_aux(1,idx_l2,:)&
            =root4pi*mat(1,idx_l2,:)

       IF (lmax1==0) CYCLE

       mat_aux(2,idx_l2,:)&
            =-root4pio3*mat(3,idx_l2,:)

       mat_aux(3,idx_l2,:)&
            =root4pio3*mat(4,idx_l2,:)

       mat_aux(4,idx_l2,:)&
            =-root4pio3*mat(2,idx_l2,:)

       IF (lmax1==1) CYCLE

       mat_aux(5,idx_l2,:)&
            =root4pio15*mat(6,idx_l2,:)

       mat_aux(6,idx_l2,:)&
            =-root4pio15*mat(9,idx_l2,:)

       mat_aux(7,idx_l2,:)&
            =-0.5_dp*root4pio5*mat(5,idx_l2,:)&
            -0.5_dp*root4pio5*mat(7,idx_l2,:)&
            +root4pio5*mat(10,idx_l2,:)

       mat_aux(8,idx_l2,:)&
            =-root4pio15*mat(8,idx_l2,:)

       mat_aux(9,idx_l2,:)&
            =0.5_dp*root4pio15*mat(5,idx_l2,:)&
            -0.5_dp*root4pio15*mat(7,idx_l2,:)

       IF (lmax1==2) CYCLE

       mat_aux(10,idx_l2,:)&
            =-s_3root35o32pi*mat(12,idx_l2,:)&
            +s_root35o32pi*mat(14,idx_l2,:)

       mat_aux(11,idx_l2,:)&
            =s_root105o4pi*mat(16,idx_l2,:)

       mat_aux(12,idx_l2,:)&
            =s_root21o32pi*mat(12,idx_l2,:)&
            +s_root21o32pi*mat(14,idx_l2,:)&
            -s_4root21o32pi*mat(19,idx_l2,:)

       mat_aux(13,idx_l2,:)&
            =-s_3root7o16pi*mat(15,idx_l2,:)&
            -s_3root7o16pi*mat(17,idx_l2,:)&
            +s_2root7o16pi*mat(20,idx_l2,:)

       mat_aux(14,idx_l2,:)&
            =s_root21o32pi*mat(11,idx_l2,:)&
            +s_root21o32pi*mat(13,idx_l2,:)&
            -s_4root21o32pi*mat(18,idx_l2,:)

       mat_aux(15,idx_l2,:)&
            =s_root105o16pi*mat(15,idx_l2,:)&
            -s_root105o16pi*mat(17,idx_l2,:)

       mat_aux(16,idx_l2,:)&
            =-s_root35o32pi*mat(11,idx_l2,:)&
            +s_3root35o32pi*mat(13,idx_l2,:)

    ENDDO

    DO idx_lm1=1,nsoset(lmax1)

       mat(idx_lm1,1,:)&
            =root4pi*mat_aux(idx_lm1,1,:)

       IF (lmax2==0) CYCLE

       mat(idx_lm1,2,:)&
            =-root4pio3*mat_aux(idx_lm1,3,:)

       mat(idx_lm1,3,:)&
            =root4pio3*mat_aux(idx_lm1,4,:)

       mat(idx_lm1,4,:)&
            =-root4pio3*mat_aux(idx_lm1,2,:)

       IF (lmax2==1) CYCLE

       mat(idx_lm1,5,:)&
            =root4pio15*mat_aux(idx_lm1,6,:)

       mat(idx_lm1,6,:)&
            =-root4pio15*mat_aux(idx_lm1,9,:)

       mat(idx_lm1,7,:)&
            =-0.5_dp*root4pio5*mat_aux(idx_lm1,5,:)&
            -0.5_dp*root4pio5*mat_aux(idx_lm1,7,:)&
            +root4pio5*mat_aux(idx_lm1,10,:)

       mat(idx_lm1,8,:)&
            =-root4pio15*mat_aux(idx_lm1,8,:)

       mat(idx_lm1,9,:)&
            =0.5_dp*root4pio15*mat_aux(idx_lm1,5,:)&
            -0.5_dp*root4pio15*mat_aux(idx_lm1,7,:)

       IF (lmax2==2) CYCLE

       mat(idx_lm1,10,:)&
            =-s_3root35o32pi*mat_aux(idx_lm1,12,:)&
            +s_root35o32pi*mat_aux(idx_lm1,14,:)

       mat(idx_lm1,11,:)&
            =s_root105o4pi*mat_aux(idx_lm1,16,:)

       mat(idx_lm1,12,:)&
            =s_root21o32pi*mat_aux(idx_lm1,12,:)&
            +s_root21o32pi*mat_aux(idx_lm1,14,:)&
            -s_4root21o32pi*mat_aux(idx_lm1,19,:)

       mat(idx_lm1,13,:)&
            =-s_3root7o16pi*mat_aux(idx_lm1,15,:)&
            -s_3root7o16pi*mat_aux(idx_lm1,17,:)&
            +s_2root7o16pi*mat_aux(idx_lm1,20,:)

       mat(idx_lm1,14,:)&
            =s_root21o32pi*mat_aux(idx_lm1,11,:)&
            +s_root21o32pi*mat_aux(idx_lm1,13,:)&
            -s_4root21o32pi*mat_aux(idx_lm1,18,:)

       mat(idx_lm1,15,:)&
            =s_root105o16pi*mat_aux(idx_lm1,15,:)&
            -s_root105o16pi*mat_aux(idx_lm1,17,:)

       mat(idx_lm1,16,:)&
            =-s_root35o32pi*mat_aux(idx_lm1,11,:)&
            +s_3root35o32pi*mat_aux(idx_lm1,13,:)

    ENDDO

  END SUBROUTINE cart2sph_mat

END MODULE qs_util
