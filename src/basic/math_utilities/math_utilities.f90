MODULE math_utilities

  ! Some generally useful tools, and basic mathematical functions

! ===== Preamble =====
! ====================

  use tests_main
  use assertions_basic
  USE mpi
  USE precisions                                             , ONLY: dp
  USE mpi_basic                                              , ONLY: par, cerr, ierr, recv_status, sync
  USE control_resources_and_error_messaging                  , ONLY: warning, crash, happy, init_routine, finalise_routine, colour_string
  USE parameters
  USE reallocate_mod                                         , ONLY: reallocate

  IMPLICIT NONE

CONTAINS

! ===== Subroutines ======
! ========================

! == Floatation criterion, surface elevation, and thickness above floatation

  PURE FUNCTION is_floating( Hi, Hb, SL) RESULT( isso)
    ! The floatation criterion

    IMPLICIT NONE

    ! Input variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    REAL(dp)                                           , INTENT(IN)    :: Hi     ! [m] Ice thickness
    REAL(dp)                                           , INTENT(IN)    :: Hb     ! [m] Bedrock elevation
    REAL(dp)                                           , INTENT(IN)    :: SL     ! [m] Water surface elevation

    ! Output variables:
    LOGICAL                                                            :: isso   ! Whether or not the ice will float

    isso = .FALSE.
    IF (Hi < (SL - Hb) * seawater_density/ice_density) isso = .TRUE.

  END FUNCTION is_floating

  PURE FUNCTION ice_surface_elevation( Hi, Hb, SL) RESULT( Hs)
    ! The ice surface elevation equation

    IMPLICIT NONE

    ! Input variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    REAL(dp)                                           , INTENT(IN)    :: Hi     ! [m] Ice thickness
    REAL(dp)                                           , INTENT(IN)    :: Hb     ! [m] Bedrock elevation
    REAL(dp)                                           , INTENT(IN)    :: SL     ! [m] Water surface elevation

    ! Output variables:
    REAL(dp)                                                           :: Hs     ! [m] Ice surface elevation

    Hs = Hi + MAX( SL - ice_density / seawater_density * Hi, Hb)

  END FUNCTION ice_surface_elevation

  PURE FUNCTION thickness_above_floatation( Hi, Hb, SL) RESULT( TAF)
    ! The thickness-above-floatation equation

    IMPLICIT NONE

    ! Input variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    REAL(dp)                                           , INTENT(IN)    :: Hi     ! [m] Ice thickness
    REAL(dp)                                           , INTENT(IN)    :: Hb     ! [m] Bedrock elevation
    REAL(dp)                                           , INTENT(IN)    :: SL     ! [m] Water surface elevation

    ! Output variables:
    REAL(dp)                                                           :: TAF    ! [m] Ice thickness above floatation

    TAF = Hi - MAX( 0._dp, (SL - Hb) * (seawater_density / ice_density))

  END FUNCTION thickness_above_floatation

  FUNCTION Hi_from_Hb_Hs_and_SL( Hb, Hs, SL) RESULT( Hi)
    ! Calculate Hi from Hb, Hs, and SL

    IMPLICIT NONE

    ! Input variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    REAL(dp)                                           , INTENT(IN)    :: Hb     ! [m] Bedrock elevation
    REAL(dp)                                           , INTENT(IN)    :: Hs     ! [m] Surface elevation
    REAL(dp)                                           , INTENT(IN)    :: SL     ! [m] Water surface elevation

    ! Output variables:
    REAL(dp)                                                           :: Hi     ! [m] Ice thickness

    ! Local variables:
    REAL(dp)                                                           :: Hi_float ! [m] Maximum floating ice thickness
    REAL(dp)                                                           :: Hs_float ! [m] Surface elevation of maximum floating ice thickness

    Hi_float = MAX( 0._dp, (SL - Hb) * (seawater_density / ice_density))
    Hs_float = Hb + Hi_float

    IF (Hs > Hs_float) THEN
      Hi = Hs - Hb
    ELSE
      Hi = MIN( Hi_float, (Hs - SL) / (1._dp - (ice_density / seawater_density)) )
    END IF

  END FUNCTION Hi_from_Hb_Hs_and_SL

! == The error function

  PURE FUNCTION error_function( X) RESULT( ERR)
    ! Purpose: Compute error function erf(x)
    ! Input:   x   --- Argument of erf(x)
    ! Output:  ERR --- erf(x)

    IMPLICIT NONE

    ! Input variables:
    REAL(dp), INTENT(IN)  :: X

    ! Output variables:
    REAL(dp)              :: ERR

    ! Local variables:
    REAL(dp)              :: EPS
    REAL(dp)              :: X2
    REAL(dp)              :: ER
    REAL(dp)              :: R
    REAL(dp)              :: C0
    INTEGER               :: k

    EPS = 1.0E-15_dp
    X2  = X * X
    IF(ABS(X) < 3.5_dp) THEN
     ER = 1.0_dp
     R  = 1.0_dp
     DO k = 1, 50
       R  = R * X2 / (REAL(k, dp) + 0.5_dp)
       ER = ER+R
       IF(ABS(R) < ABS(ER) * EPS) THEN
        C0  = 2.0_dp / SQRT(pi) * X * EXP(-X2)
        ERR = C0 * ER
        EXIT
       END IF
     END DO
    ELSE
     ER = 1.0_dp
     R  = 1.0_dp
     DO k = 1, 12
       R  = -R * (REAL(k, dp) - 0.5_dp) / X2
       ER = ER + R
       C0  = EXP(-X2) / (ABS(X) * SQRT(pi))
       ERR = 1.0_dp - C0 * ER
       IF(X < 0.0_dp) ERR = -ERR
     END DO
    ENDIF

    RETURN
  END FUNCTION error_function

! == The oblique stereographic projection

  PURE SUBROUTINE oblique_sg_projection( lambda, phi, lambda_M_deg, phi_M_deg, beta_deg, x, y)
    ! This subroutine projects with an oblique stereographic projection the longitude-latitude
    ! coordinates to a rectangular coordinate system, with coordinates (x,y).
    !
    ! For more information about M, beta_deg, the center of projection and the used
    ! projection method see: Reerink et al. (2010), Mapping technique of climate fields
    ! between GCM's and ice models, GMD

    ! For North and South Pole: lambda_M_deg = 0._dp, to generate the correct coordinate
    ! system, see equation (2.3) or equation (A.53) in Reerink et al. (2010).

    IMPLICIT NONE

    ! Input variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    REAL(dp)                                           , INTENT(IN)    :: lambda         ! [degrees east ] Longitude
    REAL(dp)                                           , INTENT(IN)    :: phi            ! [degrees north] Latitude

    ! Polar stereographic projection parameters
    REAL(dp)                                           , INTENT(IN)    :: lambda_M_deg   ! [degrees east]  Longitude of the pole of the oblique stereographic projection
    REAL(dp)                                           , INTENT(IN)    :: phi_M_deg      ! [degrees north] Latitude  of the pole of the oblique stereographic projection
    REAL(dp)                                           , INTENT(IN)    :: beta_deg       ! [degrees]       Standard parallel     of the oblique stereographic projection

    ! Output variables:
    REAL(dp)                                           , INTENT(OUT)   :: x              ! [m] x-coordinate
    REAL(dp)                                           , INTENT(OUT)   :: y              ! [m] y-coordinate

    ! Local variables:
    REAL(dp)                                                           :: alpha_deg      ! [degrees]
    REAL(dp)                                                           :: phi_P          ! [radians]
    REAL(dp)                                                           :: lambda_P       ! [radians]
    REAL(dp)                                                           :: t_P_prime
    REAL(dp)                                                           :: lambda_M, phi_M, alpha

    ! Convert beta to alpha
    alpha_deg = 90._dp - beta_deg

    ! Convert longitude-latitude coordinates to radians:
    phi_P    = (pi / 180._dp) * phi
    lambda_P = (pi / 180._dp) * lambda

    ! Convert projection parameters to radians:
    lambda_M = (pi / 180._dp) * lambda_M_deg
    phi_M    = (pi / 180._dp) * phi_M_deg
    alpha    = (pi / 180._dp) * alpha_deg

    ! See equation (2.6) or equation (A.56) in Reerink et al. (2010):
    t_P_prime = (1._dp + COS(alpha)) / (1._dp + COS(phi_P) * COS(phi_M) * COS(lambda_P - lambda_M) + SIN(phi_P) * SIN(phi_M))

    ! See equations (2.4-2.5) or equations (A.54-A.55) in Reerink et al. (2010):
    x =  earth_radius * (COS(phi_P) * SIN(lambda_P - lambda_M)) * t_P_prime
    y =  earth_radius * (SIN(phi_P) * COS(phi_M) - (COS(phi_P) * SIN(phi_M)) * COS(lambda_P - lambda_M)) * t_P_prime

  END SUBROUTINE oblique_sg_projection

  PURE SUBROUTINE inverse_oblique_sg_projection( x, y, lambda_M_deg, phi_M_deg, beta_deg, lambda_P, phi_P)
    ! This subroutine projects with an inverse oblique stereographic projection the
    ! (x,y) coordinates to a longitude-latitude coordinate system, with coordinates (lambda, phi) in degrees.
    !
    ! For more information about M, alpha_deg, the center of projection and the used
    ! projection method see: Reerink et al. (2010), Mapping technique of climate fields
    ! between GCM's and ice models, GMD

    IMPLICIT NONE

    ! Input variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    REAL(dp)                                           , INTENT(IN)    :: x              ! [m] x-coordinate
    REAL(dp)                                           , INTENT(IN)    :: y              ! [m] y-coordinate

    ! Polar stereographic projection parameters
    REAL(dp)                                           , INTENT(IN)    :: lambda_M_deg   ! [degrees east]  Longitude of the pole of the oblique stereographic projection
    REAL(dp)                                           , INTENT(IN)    :: phi_M_deg      ! [degrees north] Latitude  of the pole of the oblique stereographic projection
    REAL(dp)                                           , INTENT(IN)    :: beta_deg       ! [degrees]       Standard parallel     of the oblique stereographic projection

    ! Output variables:
    REAL(dp)                                           , INTENT(OUT)   :: lambda_P       ! [degrees east ] Longitude
    REAL(dp)                                           , INTENT(OUT)   :: phi_P          ! [degrees north] Latitude

    ! Local variables:
    REAL(dp)                                                           :: alpha_deg      ! [degrees]
    REAL(dp)                                                           :: x_3D_P_prime   ! [m]
    REAL(dp)                                                           :: y_3D_P_prime   ! [m]
    REAL(dp)                                                           :: z_3D_P_prime   ! [m]
    REAL(dp)                                                           :: a
    REAL(dp)                                                           :: t_P
    REAL(dp)                                                           :: x_3D_P         ! [m]
    REAL(dp)                                                           :: y_3D_P         ! [m]
    REAL(dp)                                                           :: z_3D_P         ! [m]
    REAL(dp)                                                           :: lambda_M, phi_M, alpha

    ! Convert beta to alpha
    alpha_deg = 90._dp - beta_deg

    ! Convert projection parameters to radians:
    lambda_M = (pi / 180._dp) * lambda_M_deg
    phi_M    = (pi / 180._dp) * phi_M_deg
    alpha    = (pi / 180._dp) * alpha_deg

    ! See equations (2.14-2.16) or equations (B.21-B.23) in Reerink et al. (2010):
    x_3D_P_prime = earth_radius * COS(alpha) * COS(lambda_M) * COS(phi_M) - SIN(lambda_M) * x - COS(lambda_M) * SIN(phi_M) * y
    y_3D_P_prime = earth_radius * COS(alpha) * SIN(lambda_M) * COS(phi_M) + COS(lambda_M) * x - SIN(lambda_M) * SIN(phi_M) * y
    z_3D_P_prime = earth_radius * COS(alpha) *                 SIN(phi_M)                     +                 COS(phi_M) * y

    ! See equation (2.13) or equation (B.20) in Reerink et al. (2010):
    a = COS(lambda_M) * COS(phi_M) * x_3D_P_prime  +  SIN(lambda_M) * COS(phi_M) * y_3D_P_prime  +  SIN(phi_M) * z_3D_P_prime

    ! See equation (2.12) or equation (B.19) in Reerink et al. (2010):
    t_P = (2._dp * earth_radius**2 + 2._dp * earth_radius * a) / (earth_radius**2 + 2._dp * earth_radius * a + x_3D_P_prime**2 + y_3D_P_prime**2 + z_3D_P_prime**2)

    ! See equations (2.9-2.11) or equations (B.16-B.18) in Reerink et al. (2010):
    x_3D_P =  earth_radius * COS(lambda_M) * COS(phi_M) * (t_P - 1._dp) + x_3D_P_prime * t_P
    y_3D_P =  earth_radius * SIN(lambda_M) * COS(phi_M) * (t_P - 1._dp) + y_3D_P_prime * t_P
    z_3D_P =  earth_radius *                 SIN(phi_M) * (t_P - 1._dp) + z_3D_P_prime * t_P

    ! See equation (2.7) or equation (B.24) in Reerink et al. (2010):
    IF(x_3D_P <  0._dp                      ) THEN
      lambda_P = 180._dp + (180._dp / pi) * ATAN(y_3D_P / x_3D_P)
    ELSE IF(x_3D_P >  0._dp .AND. y_3D_P >= 0._dp) THEN
      lambda_P =           (180._dp / pi) * ATAN(y_3D_P / x_3D_P)
    ELSE IF(x_3D_P >  0._dp .AND. y_3D_P <  0._dp) THEN
      lambda_P = 360._dp + (180._dp / pi) * ATAN(y_3D_P / x_3D_P)
    ELSE IF(x_3D_P == 0._dp .AND. y_3D_P >  0._dp) THEN
      lambda_P =  90._dp
    ELSE IF(x_3D_P == 0._dp .AND. y_3D_P <  0._dp) THEN
      lambda_P = 270._dp
    ELSE IF(x_3D_P == 0._dp .AND. y_3D_P == 0._dp) THEN
      lambda_P =   0._dp
    END IF

    ! See equation (2.8) or equation (B.25) in Reerink et al. (2010):
    IF(x_3D_P /= 0._dp .OR. y_3D_P /= 0._dp) THEN
      phi_P = (180._dp / pi) * ATAN(z_3D_P / sqrt(x_3D_P**2 + y_3D_P**2))
    ELSE IF(z_3D_P >  0._dp) THEN
      phi_P =   90._dp
    ELSE IF(z_3D_P <  0._dp) THEN
      phi_P =  -90._dp
    END IF

  END SUBROUTINE inverse_oblique_sg_projection

! == Line integrals used in conservative remapping

  PURE FUNCTION line_integral_xdy(   p, q, tol_dist) RESULT( I_pq)
    ! Calculate the line integral x dy from p to q

    IMPLICIT NONE

    ! Input variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    REAL(dp), DIMENSION(2)                             , INTENT(IN)    :: p, q
    REAL(dp)                                           , INTENT(IN)    :: tol_dist

    ! Output variables:
    REAL(dp)                                                           :: I_pq

    ! Local variables:
    REAL(dp)                                                           :: xp, yp, xq, yq, dx, dy

    xp = p( 1)
    yp = p( 2)
    xq = q( 1)
    yq = q( 2)

    IF (ABS( yp-yq) < tol_dist) THEN
      I_pq = 0._dp
      RETURN
    END IF

    dx = q( 1) - p( 1)
    dy = q( 2) - p( 2)

    I_pq = xp*dy - yp*dx + (dx / (2._dp*dy)) * (yq**2 - yp**2)

  END FUNCTION line_integral_xdy

  PURE FUNCTION line_integral_mxydx( p, q, tol_dist) RESULT( I_pq)
    ! Calculate the line integral -xy dx from p to q

    IMPLICIT NONE

    ! Input variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    REAL(dp), DIMENSION(2)                             , INTENT(IN)    :: p, q
    REAL(dp)                                           , INTENT(IN)    :: tol_dist

    ! Output variables:
    REAL(dp)                                                           :: I_pq

    ! Local variables:
    REAL(dp)                                                           :: xp, yp, xq, yq, dx, dy

    xp = p( 1)
    yp = p( 2)
    xq = q( 1)
    yq = q( 2)

    IF (ABS( xp-xq) < tol_dist) THEN
      I_pq = 0._dp
      RETURN
    END IF

    dx = q( 1) - p( 1)
    dy = q( 2) - p( 2)

    I_pq = (1._dp/2._dp * (xp*dy/dx - yp) * (xq**2-xp**2)) - (1._dp/3._dp * dy/dx * (xq**3-xp**3))

  END FUNCTION line_integral_mxydx

  PURE FUNCTION line_integral_xydy(  p, q, tol_dist) RESULT( I_pq)
    ! Calculate the line integral xy dy from p to q

    IMPLICIT NONE

    ! Input variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    REAL(dp), DIMENSION(2)                             , INTENT(IN)    :: p, q
    REAL(dp)                                           , INTENT(IN)    :: tol_dist

    ! Output variables:
    REAL(dp)                                                           :: I_pq

    ! Local variables:
    REAL(dp)                                                           :: xp, yp, xq, yq, dx, dy

    xp = p( 1)
    yp = p( 2)
    xq = q( 1)
    yq = q( 2)

    IF (ABS( yp-yq) < tol_dist) THEN
      I_pq = 0._dp
      RETURN
    END IF

    dx = q( 1 ) - p( 1)
    dy = q( 2 ) - p( 2)

    I_pq = (1._dp/2._dp * (xp - yp*dx/dy) * (yq**2-yp**2)) + (1._dp/3._dp * dx/dy * (yq**3-yp**3))

  END FUNCTION line_integral_xydy

! == Finding inverses of some small matrices

  PURE FUNCTION calc_determinant_2_by_2( A) RESULT( detA)
    ! Determinant of a 2-by-2 matrix

    IMPLICIT NONE

    ! Input variables:
    REAL(dp), DIMENSION(2,2    )                       , INTENT(IN)    :: A

    ! Output variables:
    REAL(dp)                                                           :: detA

    ! Calculate the determinant of A
    detA = A( 1,1) * A( 2,2) - A( 1,2) * A( 2,1)

  END FUNCTION calc_determinant_2_by_2

  PURE FUNCTION calc_determinant_3_by_3( A) RESULT( detA)
    ! Determinant of a 2-by-2 matrix

    IMPLICIT NONE

    ! Input variables:
    REAL(dp), DIMENSION(3,3    )                       , INTENT(IN)    :: A

    ! Output variables:
    REAL(dp)                                                           :: detA

    ! Local variables:
    REAL(dp), DIMENSION(3,3    )                                       :: Ainv

    ! Calculate the minors of A
    Ainv( 1,1) = A( 2,2) * A( 3,3) - A( 2,3) * A( 3,2)
    Ainv( 1,2) = A( 2,1) * A( 3,3) - A( 2,3) * A( 3,1)
    Ainv( 1,3) = A( 2,1) * A( 3,2) - A( 2,2) * A( 3,1)
    Ainv( 2,1) = A( 1,2) * A( 3,3) - A( 1,3) * A( 3,2)
    Ainv( 2,2) = A( 1,1) * A( 3,3) - A( 1,3) * A( 3,1)
    Ainv( 2,3) = A( 1,1) * A( 3,2) - A( 1,2) * A( 3,1)
    Ainv( 3,1) = A( 1,2) * A( 2,3) - A( 1,3) * A( 2,2)
    Ainv( 3,2) = A( 1,1) * A( 2,3) - A( 1,3) * A( 2,1)
    Ainv( 3,3) = A( 1,1) * A( 2,2) - A( 1,2) * A( 2,1)

    ! Calculate the determinant of A
    detA = A( 1,1) * Ainv( 1,1) - A( 1,2) * Ainv( 1,2) + A( 1,3) * Ainv( 1,3)

  END FUNCTION calc_determinant_3_by_3

  PURE FUNCTION calc_determinant_5_by_5( A) RESULT( detA)
    ! Determinant of a 5-by-5 matrix
    !
    ! Source: https://caps.gsfc.nasa.gov/simpson/software/m55inv_f90.txt, accessed 2023-02-07

    USE iso_fortran_env, ONLY: real64

    IMPLICIT NONE

    ! Input variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    REAL(dp), DIMENSION(5,5    )                       , INTENT(IN)    :: A

    ! Output variables:
    REAL(dp)                                                           :: detA    ! Determinant of A

    ! Local variables:

    ! Local variables:
    REAL(real64) :: A11, A12, A13, A14, A15, A21, A22, A23, A24, &
         A25, A31, A32, A33, A34, A35, A41, A42, A43, A44, A45,   &
         A51, A52, A53, A54, A55

    A11=A(1,1); A12=A(1,2); A13=A(1,3); A14=A(1,4); A15=A(1,5)
    A21=A(2,1); A22=A(2,2); A23=A(2,3); A24=A(2,4); A25=A(2,5)
    A31=A(3,1); A32=A(3,2); A33=A(3,3); A34=A(3,4); A35=A(3,5)
    A41=A(4,1); A42=A(4,2); A43=A(4,3); A44=A(4,4); A45=A(4,5)
    A51=A(5,1); A52=A(5,2); A53=A(5,3); A54=A(5,4); A55=A(5,5)

    detA = REAL(                                                          &
       A15*A24*A33*A42*A51-A14*A25*A33*A42*A51-A15*A23*A34*A42*A51+       &
       A13*A25*A34*A42*A51+A14*A23*A35*A42*A51-A13*A24*A35*A42*A51-       &
       A15*A24*A32*A43*A51+A14*A25*A32*A43*A51+A15*A22*A34*A43*A51-       &
       A12*A25*A34*A43*A51-A14*A22*A35*A43*A51+A12*A24*A35*A43*A51+       &
       A15*A23*A32*A44*A51-A13*A25*A32*A44*A51-A15*A22*A33*A44*A51+       &
       A12*A25*A33*A44*A51+A13*A22*A35*A44*A51-A12*A23*A35*A44*A51-       &
       A14*A23*A32*A45*A51+A13*A24*A32*A45*A51+A14*A22*A33*A45*A51-       &
       A12*A24*A33*A45*A51-A13*A22*A34*A45*A51+A12*A23*A34*A45*A51-       &
       A15*A24*A33*A41*A52+A14*A25*A33*A41*A52+A15*A23*A34*A41*A52-       &
       A13*A25*A34*A41*A52-A14*A23*A35*A41*A52+A13*A24*A35*A41*A52+       &
       A15*A24*A31*A43*A52-A14*A25*A31*A43*A52-A15*A21*A34*A43*A52+       &
       A11*A25*A34*A43*A52+A14*A21*A35*A43*A52-A11*A24*A35*A43*A52-       &
       A15*A23*A31*A44*A52+A13*A25*A31*A44*A52+A15*A21*A33*A44*A52-       &
       A11*A25*A33*A44*A52-A13*A21*A35*A44*A52+A11*A23*A35*A44*A52+       &
       A14*A23*A31*A45*A52-A13*A24*A31*A45*A52-A14*A21*A33*A45*A52+       &
       A11*A24*A33*A45*A52+A13*A21*A34*A45*A52-A11*A23*A34*A45*A52+       &
       A15*A24*A32*A41*A53-A14*A25*A32*A41*A53-A15*A22*A34*A41*A53+       &
       A12*A25*A34*A41*A53+A14*A22*A35*A41*A53-A12*A24*A35*A41*A53-       &
       A15*A24*A31*A42*A53+A14*A25*A31*A42*A53+A15*A21*A34*A42*A53-       &
       A11*A25*A34*A42*A53-A14*A21*A35*A42*A53+A11*A24*A35*A42*A53+       &
       A15*A22*A31*A44*A53-A12*A25*A31*A44*A53-A15*A21*A32*A44*A53+       &
       A11*A25*A32*A44*A53+A12*A21*A35*A44*A53-A11*A22*A35*A44*A53-       &
       A14*A22*A31*A45*A53+A12*A24*A31*A45*A53+A14*A21*A32*A45*A53-       &
       A11*A24*A32*A45*A53-A12*A21*A34*A45*A53+A11*A22*A34*A45*A53-       &
       A15*A23*A32*A41*A54+A13*A25*A32*A41*A54+A15*A22*A33*A41*A54-       &
       A12*A25*A33*A41*A54-A13*A22*A35*A41*A54+A12*A23*A35*A41*A54+       &
       A15*A23*A31*A42*A54-A13*A25*A31*A42*A54-A15*A21*A33*A42*A54+       &
       A11*A25*A33*A42*A54+A13*A21*A35*A42*A54-A11*A23*A35*A42*A54-       &
       A15*A22*A31*A43*A54+A12*A25*A31*A43*A54+A15*A21*A32*A43*A54-       &
       A11*A25*A32*A43*A54-A12*A21*A35*A43*A54+A11*A22*A35*A43*A54+       &
       A13*A22*A31*A45*A54-A12*A23*A31*A45*A54-A13*A21*A32*A45*A54+       &
       A11*A23*A32*A45*A54+A12*A21*A33*A45*A54-A11*A22*A33*A45*A54+       &
       A14*A23*A32*A41*A55-A13*A24*A32*A41*A55-A14*A22*A33*A41*A55+       &
       A12*A24*A33*A41*A55+A13*A22*A34*A41*A55-A12*A23*A34*A41*A55-       &
       A14*A23*A31*A42*A55+A13*A24*A31*A42*A55+A14*A21*A33*A42*A55-       &
       A11*A24*A33*A42*A55-A13*A21*A34*A42*A55+A11*A23*A34*A42*A55+       &
       A14*A22*A31*A43*A55-A12*A24*A31*A43*A55-A14*A21*A32*A43*A55+       &
       A11*A24*A32*A43*A55+A12*A21*A34*A43*A55-A11*A22*A34*A43*A55-       &
       A13*A22*A31*A44*A55+A12*A23*A31*A44*A55+A13*A21*A32*A44*A55-       &
       A11*A23*A32*A44*A55-A12*A21*A33*A44*A55+A11*A22*A33*A44*A55, dp)

  END FUNCTIOn calc_determinant_5_by_5

  PURE FUNCTION calc_matrix_inverse_2_by_2( A) RESULT( Ainv)
    ! Direct inversion of a 2-by-2 matrix

    IMPLICIT NONE

    ! Input variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    REAL(dp), DIMENSION(2,2    )                       , INTENT(IN)    :: A       ! The matrix A to be inverted

    ! Output variables:
    REAL(dp), DIMENSION(2,2    )                                       :: Ainv    ! Inverse of A

    ! Local variables:
    REAL(dp)                                                           :: detA

    ! Calculate the determinant of A
    detA = A( 1,1) * A( 2,2) - A( 1,2) * A( 2,1)

    ! Safety
    IF (ABS( detA) < TINY( detA)) THEN
      error stop 'calc_matrix_inverse_2_by_2 - matrix is singular to working precision!'
    END IF

    ! Calculate the inverse of A
    Ainv( 1,1) =  A( 2,2) / detA
    Ainv( 1,2) = -A( 1,2) / detA
    Ainv( 2,1) = -A( 2,1) / detA
    Ainv( 2,2) =  A( 1,1) / detA

  END FUNCTION calc_matrix_inverse_2_by_2

  PURE FUNCTION calc_matrix_inverse_3_by_3( A) RESULT( Ainv)
    ! Direct inversion of a 3-by-3 matrix
    !
    ! See: https://metric.ma.ic.ac.uk/metric_public/matrices/inverses/inverses2.html

    IMPLICIT NONE

    ! Input variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    REAL(dp), DIMENSION(3,3    )                       , INTENT(IN)    :: A       ! The matrix A to be inverted

    ! Output variables:
    REAL(dp), DIMENSION(3,3    )                                       :: Ainv    ! Inverse of A

    ! Local variables:
    REAL(dp)                                                           :: detA

    ! Calculate the minors of A
    Ainv( 1,1) = A( 2,2) * A( 3,3) - A( 2,3) * A( 3,2)
    Ainv( 1,2) = A( 2,1) * A( 3,3) - A( 2,3) * A( 3,1)
    Ainv( 1,3) = A( 2,1) * A( 3,2) - A( 2,2) * A( 3,1)
    Ainv( 2,1) = A( 1,2) * A( 3,3) - A( 1,3) * A( 3,2)
    Ainv( 2,2) = A( 1,1) * A( 3,3) - A( 1,3) * A( 3,1)
    Ainv( 2,3) = A( 1,1) * A( 3,2) - A( 1,2) * A( 3,1)
    Ainv( 3,1) = A( 1,2) * A( 2,3) - A( 1,3) * A( 2,2)
    Ainv( 3,2) = A( 1,1) * A( 2,3) - A( 1,3) * A( 2,1)
    Ainv( 3,3) = A( 1,1) * A( 2,2) - A( 1,2) * A( 2,1)

    ! Calculate the determinant of A
    detA = A( 1,1) * Ainv( 1,1) - A( 1,2) * Ainv( 1,2) + A( 1,3) * Ainv( 1,3)

    ! Safety
    IF (ABS( detA) < TINY( detA)) THEN
      error stop 'calc_matrix_inverse_3_by_3 - matrix is singular to working precision!'
    END IF

    ! Change matrix of minors to get the matrix of cofactors
    Ainv( 1,2) = -Ainv( 1,2)
    Ainv( 2,1) = -Ainv( 2,1)
    Ainv( 2,3) = -Ainv( 2,3)
    Ainv( 3,2) = -Ainv( 3,2)

    ! Transpose matrix of cofactors
    Ainv( 1,2) = Ainv( 1,2) + Ainv( 2,1)
    Ainv( 2,1) = Ainv( 1,2) - Ainv( 2,1)
    Ainv( 1,2) = Ainv( 1,2) - Ainv( 2,1)

    Ainv( 1,3) = Ainv( 1,3) + Ainv( 3,1)
    Ainv( 3,1) = Ainv( 1,3) - Ainv( 3,1)
    Ainv( 1,3) = Ainv( 1,3) - Ainv( 3,1)

    Ainv( 2,3) = Ainv( 2,3) + Ainv( 3,2)
    Ainv( 3,2) = Ainv( 2,3) - Ainv( 3,2)
    Ainv( 2,3) = Ainv( 2,3) - Ainv( 3,2)

    ! Divide by det(A)
    Ainv = Ainv / detA

  END FUNCTION calc_matrix_inverse_3_by_3

  PURE FUNCTION calc_matrix_inverse_5_by_5( A) RESULT( Ainv)
    ! Direct inversion of a 5-by-5 matrix
    !
    ! Source: https://caps.gsfc.nasa.gov/simpson/software/m55inv_f90.txt, accessed 2023-02-07

    USE iso_fortran_env, ONLY: real64

    IMPLICIT NONE

    ! Input variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    REAL(dp), DIMENSION(5,5    )                       , INTENT(IN)    :: A       ! The matrix A to be inverted

    ! Output variables:
    REAL(dp), DIMENSION(5,5    )                                       :: Ainv    ! Inverse of A

    ! Local variables:
    REAL(dp)                                                           :: detA    ! Determinant of A

    ! Local variables:
    REAL(real64) :: A11, A12, A13, A14, A15, A21, A22, A23, A24, &
         A25, A31, A32, A33, A34, A35, A41, A42, A43, A44, A45,   &
         A51, A52, A53, A54, A55
    REAL(real64), DIMENSION(5,5) :: COFACTOR

    A11=A(1,1); A12=A(1,2); A13=A(1,3); A14=A(1,4); A15=A(1,5)
    A21=A(2,1); A22=A(2,2); A23=A(2,3); A24=A(2,4); A25=A(2,5)
    A31=A(3,1); A32=A(3,2); A33=A(3,3); A34=A(3,4); A35=A(3,5)
    A41=A(4,1); A42=A(4,2); A43=A(4,3); A44=A(4,4); A45=A(4,5)
    A51=A(5,1); A52=A(5,2); A53=A(5,3); A54=A(5,4); A55=A(5,5)

    detA = REAL(                                                          &
       A15*A24*A33*A42*A51-A14*A25*A33*A42*A51-A15*A23*A34*A42*A51+       &
       A13*A25*A34*A42*A51+A14*A23*A35*A42*A51-A13*A24*A35*A42*A51-       &
       A15*A24*A32*A43*A51+A14*A25*A32*A43*A51+A15*A22*A34*A43*A51-       &
       A12*A25*A34*A43*A51-A14*A22*A35*A43*A51+A12*A24*A35*A43*A51+       &
       A15*A23*A32*A44*A51-A13*A25*A32*A44*A51-A15*A22*A33*A44*A51+       &
       A12*A25*A33*A44*A51+A13*A22*A35*A44*A51-A12*A23*A35*A44*A51-       &
       A14*A23*A32*A45*A51+A13*A24*A32*A45*A51+A14*A22*A33*A45*A51-       &
       A12*A24*A33*A45*A51-A13*A22*A34*A45*A51+A12*A23*A34*A45*A51-       &
       A15*A24*A33*A41*A52+A14*A25*A33*A41*A52+A15*A23*A34*A41*A52-       &
       A13*A25*A34*A41*A52-A14*A23*A35*A41*A52+A13*A24*A35*A41*A52+       &
       A15*A24*A31*A43*A52-A14*A25*A31*A43*A52-A15*A21*A34*A43*A52+       &
       A11*A25*A34*A43*A52+A14*A21*A35*A43*A52-A11*A24*A35*A43*A52-       &
       A15*A23*A31*A44*A52+A13*A25*A31*A44*A52+A15*A21*A33*A44*A52-       &
       A11*A25*A33*A44*A52-A13*A21*A35*A44*A52+A11*A23*A35*A44*A52+       &
       A14*A23*A31*A45*A52-A13*A24*A31*A45*A52-A14*A21*A33*A45*A52+       &
       A11*A24*A33*A45*A52+A13*A21*A34*A45*A52-A11*A23*A34*A45*A52+       &
       A15*A24*A32*A41*A53-A14*A25*A32*A41*A53-A15*A22*A34*A41*A53+       &
       A12*A25*A34*A41*A53+A14*A22*A35*A41*A53-A12*A24*A35*A41*A53-       &
       A15*A24*A31*A42*A53+A14*A25*A31*A42*A53+A15*A21*A34*A42*A53-       &
       A11*A25*A34*A42*A53-A14*A21*A35*A42*A53+A11*A24*A35*A42*A53+       &
       A15*A22*A31*A44*A53-A12*A25*A31*A44*A53-A15*A21*A32*A44*A53+       &
       A11*A25*A32*A44*A53+A12*A21*A35*A44*A53-A11*A22*A35*A44*A53-       &
       A14*A22*A31*A45*A53+A12*A24*A31*A45*A53+A14*A21*A32*A45*A53-       &
       A11*A24*A32*A45*A53-A12*A21*A34*A45*A53+A11*A22*A34*A45*A53-       &
       A15*A23*A32*A41*A54+A13*A25*A32*A41*A54+A15*A22*A33*A41*A54-       &
       A12*A25*A33*A41*A54-A13*A22*A35*A41*A54+A12*A23*A35*A41*A54+       &
       A15*A23*A31*A42*A54-A13*A25*A31*A42*A54-A15*A21*A33*A42*A54+       &
       A11*A25*A33*A42*A54+A13*A21*A35*A42*A54-A11*A23*A35*A42*A54-       &
       A15*A22*A31*A43*A54+A12*A25*A31*A43*A54+A15*A21*A32*A43*A54-       &
       A11*A25*A32*A43*A54-A12*A21*A35*A43*A54+A11*A22*A35*A43*A54+       &
       A13*A22*A31*A45*A54-A12*A23*A31*A45*A54-A13*A21*A32*A45*A54+       &
       A11*A23*A32*A45*A54+A12*A21*A33*A45*A54-A11*A22*A33*A45*A54+       &
       A14*A23*A32*A41*A55-A13*A24*A32*A41*A55-A14*A22*A33*A41*A55+       &
       A12*A24*A33*A41*A55+A13*A22*A34*A41*A55-A12*A23*A34*A41*A55-       &
       A14*A23*A31*A42*A55+A13*A24*A31*A42*A55+A14*A21*A33*A42*A55-       &
       A11*A24*A33*A42*A55-A13*A21*A34*A42*A55+A11*A23*A34*A42*A55+       &
       A14*A22*A31*A43*A55-A12*A24*A31*A43*A55-A14*A21*A32*A43*A55+       &
       A11*A24*A32*A43*A55+A12*A21*A34*A43*A55-A11*A22*A34*A43*A55-       &
       A13*A22*A31*A44*A55+A12*A23*A31*A44*A55+A13*A21*A32*A44*A55-       &
       A11*A23*A32*A44*A55-A12*A21*A33*A44*A55+A11*A22*A33*A44*A55, dp)

    ! Safety
    IF (ABS( detA) < TINY( detA)) THEN
      error stop 'calc_matrix_inverse_3_by_3 - matrix is singular to working precision!'
    END IF

    COFACTOR(1,1) = A25*A34*A43*A52-A24*A35*A43*A52-A25*A33*A44*A52+      &
       A23*A35*A44*A52+A24*A33*A45*A52-A23*A34*A45*A52-A25*A34*A42*A53+   &
       A24*A35*A42*A53+A25*A32*A44*A53-A22*A35*A44*A53-A24*A32*A45*A53+   &
       A22*A34*A45*A53+A25*A33*A42*A54-A23*A35*A42*A54-A25*A32*A43*A54+   &
       A22*A35*A43*A54+A23*A32*A45*A54-A22*A33*A45*A54-A24*A33*A42*A55+   &
       A23*A34*A42*A55+A24*A32*A43*A55-A22*A34*A43*A55-A23*A32*A44*A55+   &
       A22*A33*A44*A55

    COFACTOR(2,1) = -A15*A34*A43*A52+A14*A35*A43*A52+A15*A33*A44*A52-     &
       A13*A35*A44*A52-A14*A33*A45*A52+A13*A34*A45*A52+A15*A34*A42*A53-   &
       A14*A35*A42*A53-A15*A32*A44*A53+A12*A35*A44*A53+A14*A32*A45*A53-   &
       A12*A34*A45*A53-A15*A33*A42*A54+A13*A35*A42*A54+A15*A32*A43*A54-   &
       A12*A35*A43*A54-A13*A32*A45*A54+A12*A33*A45*A54+A14*A33*A42*A55-   &
       A13*A34*A42*A55-A14*A32*A43*A55+A12*A34*A43*A55+A13*A32*A44*A55-   &
       A12*A33*A44*A55

    COFACTOR(3,1) = A15*A24*A43*A52-A14*A25*A43*A52-A15*A23*A44*A52+      &
       A13*A25*A44*A52+A14*A23*A45*A52-A13*A24*A45*A52-A15*A24*A42*A53+   &
       A14*A25*A42*A53+A15*A22*A44*A53-A12*A25*A44*A53-A14*A22*A45*A53+   &
       A12*A24*A45*A53+A15*A23*A42*A54-A13*A25*A42*A54-A15*A22*A43*A54+   &
       A12*A25*A43*A54+A13*A22*A45*A54-A12*A23*A45*A54-A14*A23*A42*A55+   &
       A13*A24*A42*A55+A14*A22*A43*A55-A12*A24*A43*A55-A13*A22*A44*A55+   &
       A12*A23*A44*A55

    COFACTOR(4,1) = -A15*A24*A33*A52+A14*A25*A33*A52+A15*A23*A34*A52-     &
       A13*A25*A34*A52-A14*A23*A35*A52+A13*A24*A35*A52+A15*A24*A32*A53-   &
       A14*A25*A32*A53-A15*A22*A34*A53+A12*A25*A34*A53+A14*A22*A35*A53-   &
       A12*A24*A35*A53-A15*A23*A32*A54+A13*A25*A32*A54+A15*A22*A33*A54-   &
       A12*A25*A33*A54-A13*A22*A35*A54+A12*A23*A35*A54+A14*A23*A32*A55-   &
       A13*A24*A32*A55-A14*A22*A33*A55+A12*A24*A33*A55+A13*A22*A34*A55-   &
       A12*A23*A34*A55

    COFACTOR(5,1) = A15*A24*A33*A42-A14*A25*A33*A42-A15*A23*A34*A42+      &
       A13*A25*A34*A42+A14*A23*A35*A42-A13*A24*A35*A42-A15*A24*A32*A43+   &
       A14*A25*A32*A43+A15*A22*A34*A43-A12*A25*A34*A43-A14*A22*A35*A43+   &
       A12*A24*A35*A43+A15*A23*A32*A44-A13*A25*A32*A44-A15*A22*A33*A44+   &
       A12*A25*A33*A44+A13*A22*A35*A44-A12*A23*A35*A44-A14*A23*A32*A45+   &
       A13*A24*A32*A45+A14*A22*A33*A45-A12*A24*A33*A45-A13*A22*A34*A45+   &
       A12*A23*A34*A45

    COFACTOR(1,2) = -A25*A34*A43*A51+A24*A35*A43*A51+A25*A33*A44*A51-     &
       A23*A35*A44*A51-A24*A33*A45*A51+A23*A34*A45*A51+A25*A34*A41*A53-   &
       A24*A35*A41*A53-A25*A31*A44*A53+A21*A35*A44*A53+A24*A31*A45*A53-   &
       A21*A34*A45*A53-A25*A33*A41*A54+A23*A35*A41*A54+A25*A31*A43*A54-   &
       A21*A35*A43*A54-A23*A31*A45*A54+A21*A33*A45*A54+A24*A33*A41*A55-   &
       A23*A34*A41*A55-A24*A31*A43*A55+A21*A34*A43*A55+A23*A31*A44*A55-   &
       A21*A33*A44*A55

    COFACTOR(2,2) = A15*A34*A43*A51-A14*A35*A43*A51-A15*A33*A44*A51+      &
       A13*A35*A44*A51+A14*A33*A45*A51-A13*A34*A45*A51-A15*A34*A41*A53+   &
       A14*A35*A41*A53+A15*A31*A44*A53-A11*A35*A44*A53-A14*A31*A45*A53+   &
       A11*A34*A45*A53+A15*A33*A41*A54-A13*A35*A41*A54-A15*A31*A43*A54+   &
       A11*A35*A43*A54+A13*A31*A45*A54-A11*A33*A45*A54-A14*A33*A41*A55+   &
       A13*A34*A41*A55+A14*A31*A43*A55-A11*A34*A43*A55-A13*A31*A44*A55+   &
       A11*A33*A44*A55

    COFACTOR(3,2) = -A15*A24*A43*A51+A14*A25*A43*A51+A15*A23*A44*A51-     &
       A13*A25*A44*A51-A14*A23*A45*A51+A13*A24*A45*A51+A15*A24*A41*A53-   &
       A14*A25*A41*A53-A15*A21*A44*A53+A11*A25*A44*A53+A14*A21*A45*A53-   &
       A11*A24*A45*A53-A15*A23*A41*A54+A13*A25*A41*A54+A15*A21*A43*A54-   &
       A11*A25*A43*A54-A13*A21*A45*A54+A11*A23*A45*A54+A14*A23*A41*A55-   &
       A13*A24*A41*A55-A14*A21*A43*A55+A11*A24*A43*A55+A13*A21*A44*A55-   &
       A11*A23*A44*A55

    COFACTOR(4,2) = A15*A24*A33*A51-A14*A25*A33*A51-A15*A23*A34*A51+      &
       A13*A25*A34*A51+A14*A23*A35*A51-A13*A24*A35*A51-A15*A24*A31*A53+   &
       A14*A25*A31*A53+A15*A21*A34*A53-A11*A25*A34*A53-A14*A21*A35*A53+   &
       A11*A24*A35*A53+A15*A23*A31*A54-A13*A25*A31*A54-A15*A21*A33*A54+   &
       A11*A25*A33*A54+A13*A21*A35*A54-A11*A23*A35*A54-A14*A23*A31*A55+   &
       A13*A24*A31*A55+A14*A21*A33*A55-A11*A24*A33*A55-A13*A21*A34*A55+   &
       A11*A23*A34*A55

    COFACTOR(5,2) = -A15*A24*A33*A41+A14*A25*A33*A41+A15*A23*A34*A41-     &
       A13*A25*A34*A41-A14*A23*A35*A41+A13*A24*A35*A41+A15*A24*A31*A43-   &
       A14*A25*A31*A43-A15*A21*A34*A43+A11*A25*A34*A43+A14*A21*A35*A43-   &
       A11*A24*A35*A43-A15*A23*A31*A44+A13*A25*A31*A44+A15*A21*A33*A44-   &
       A11*A25*A33*A44-A13*A21*A35*A44+A11*A23*A35*A44+A14*A23*A31*A45-   &
       A13*A24*A31*A45-A14*A21*A33*A45+A11*A24*A33*A45+A13*A21*A34*A45-   &
       A11*A23*A34*A45

    COFACTOR(1,3) = A25*A34*A42*A51-A24*A35*A42*A51-A25*A32*A44*A51+      &
       A22*A35*A44*A51+A24*A32*A45*A51-A22*A34*A45*A51-A25*A34*A41*A52+   &
       A24*A35*A41*A52+A25*A31*A44*A52-A21*A35*A44*A52-A24*A31*A45*A52+   &
       A21*A34*A45*A52+A25*A32*A41*A54-A22*A35*A41*A54-A25*A31*A42*A54+   &
       A21*A35*A42*A54+A22*A31*A45*A54-A21*A32*A45*A54-A24*A32*A41*A55+   &
       A22*A34*A41*A55+A24*A31*A42*A55-A21*A34*A42*A55-A22*A31*A44*A55+   &
       A21*A32*A44*A55

    COFACTOR(2,3) = -A15*A34*A42*A51+A14*A35*A42*A51+A15*A32*A44*A51-     &
       A12*A35*A44*A51-A14*A32*A45*A51+A12*A34*A45*A51+A15*A34*A41*A52-   &
       A14*A35*A41*A52-A15*A31*A44*A52+A11*A35*A44*A52+A14*A31*A45*A52-   &
       A11*A34*A45*A52-A15*A32*A41*A54+A12*A35*A41*A54+A15*A31*A42*A54-   &
       A11*A35*A42*A54-A12*A31*A45*A54+A11*A32*A45*A54+A14*A32*A41*A55-   &
       A12*A34*A41*A55-A14*A31*A42*A55+A11*A34*A42*A55+A12*A31*A44*A55-   &
       A11*A32*A44*A55

    COFACTOR(3,3) = A15*A24*A42*A51-A14*A25*A42*A51-A15*A22*A44*A51+      &
       A12*A25*A44*A51+A14*A22*A45*A51-A12*A24*A45*A51-A15*A24*A41*A52+   &
       A14*A25*A41*A52+A15*A21*A44*A52-A11*A25*A44*A52-A14*A21*A45*A52+   &
       A11*A24*A45*A52+A15*A22*A41*A54-A12*A25*A41*A54-A15*A21*A42*A54+   &
       A11*A25*A42*A54+A12*A21*A45*A54-A11*A22*A45*A54-A14*A22*A41*A55+   &
       A12*A24*A41*A55+A14*A21*A42*A55-A11*A24*A42*A55-A12*A21*A44*A55+   &
       A11*A22*A44*A55

    COFACTOR(4,3) = -A15*A24*A32*A51+A14*A25*A32*A51+A15*A22*A34*A51-     &
       A12*A25*A34*A51-A14*A22*A35*A51+A12*A24*A35*A51+A15*A24*A31*A52-   &
       A14*A25*A31*A52-A15*A21*A34*A52+A11*A25*A34*A52+A14*A21*A35*A52-   &
       A11*A24*A35*A52-A15*A22*A31*A54+A12*A25*A31*A54+A15*A21*A32*A54-   &
       A11*A25*A32*A54-A12*A21*A35*A54+A11*A22*A35*A54+A14*A22*A31*A55-   &
       A12*A24*A31*A55-A14*A21*A32*A55+A11*A24*A32*A55+A12*A21*A34*A55-   &
       A11*A22*A34*A55

    COFACTOR(5,3) = A15*A24*A32*A41-A14*A25*A32*A41-A15*A22*A34*A41+      &
       A12*A25*A34*A41+A14*A22*A35*A41-A12*A24*A35*A41-A15*A24*A31*A42+   &
       A14*A25*A31*A42+A15*A21*A34*A42-A11*A25*A34*A42-A14*A21*A35*A42+   &
       A11*A24*A35*A42+A15*A22*A31*A44-A12*A25*A31*A44-A15*A21*A32*A44+   &
       A11*A25*A32*A44+A12*A21*A35*A44-A11*A22*A35*A44-A14*A22*A31*A45+   &
       A12*A24*A31*A45+A14*A21*A32*A45-A11*A24*A32*A45-A12*A21*A34*A45+   &
       A11*A22*A34*A45

    COFACTOR(1,4) = -A25*A33*A42*A51+A23*A35*A42*A51+A25*A32*A43*A51-     &
       A22*A35*A43*A51-A23*A32*A45*A51+A22*A33*A45*A51+A25*A33*A41*A52-   &
       A23*A35*A41*A52-A25*A31*A43*A52+A21*A35*A43*A52+A23*A31*A45*A52-   &
       A21*A33*A45*A52-A25*A32*A41*A53+A22*A35*A41*A53+A25*A31*A42*A53-   &
       A21*A35*A42*A53-A22*A31*A45*A53+A21*A32*A45*A53+A23*A32*A41*A55-   &
       A22*A33*A41*A55-A23*A31*A42*A55+A21*A33*A42*A55+A22*A31*A43*A55-   &
       A21*A32*A43*A55

    COFACTOR(2,4) = A15*A33*A42*A51-A13*A35*A42*A51-A15*A32*A43*A51+      &
       A12*A35*A43*A51+A13*A32*A45*A51-A12*A33*A45*A51-A15*A33*A41*A52+   &
       A13*A35*A41*A52+A15*A31*A43*A52-A11*A35*A43*A52-A13*A31*A45*A52+   &
       A11*A33*A45*A52+A15*A32*A41*A53-A12*A35*A41*A53-A15*A31*A42*A53+   &
       A11*A35*A42*A53+A12*A31*A45*A53-A11*A32*A45*A53-A13*A32*A41*A55+   &
       A12*A33*A41*A55+A13*A31*A42*A55-A11*A33*A42*A55-A12*A31*A43*A55+   &
       A11*A32*A43*A55

    COFACTOR(3,4) = -A15*A23*A42*A51+A13*A25*A42*A51+A15*A22*A43*A51-     &
       A12*A25*A43*A51-A13*A22*A45*A51+A12*A23*A45*A51+A15*A23*A41*A52-   &
       A13*A25*A41*A52-A15*A21*A43*A52+A11*A25*A43*A52+A13*A21*A45*A52-   &
       A11*A23*A45*A52-A15*A22*A41*A53+A12*A25*A41*A53+A15*A21*A42*A53-   &
       A11*A25*A42*A53-A12*A21*A45*A53+A11*A22*A45*A53+A13*A22*A41*A55-   &
       A12*A23*A41*A55-A13*A21*A42*A55+A11*A23*A42*A55+A12*A21*A43*A55-   &
       A11*A22*A43*A55

    COFACTOR(4,4) = A15*A23*A32*A51-A13*A25*A32*A51-A15*A22*A33*A51+      &
       A12*A25*A33*A51+A13*A22*A35*A51-A12*A23*A35*A51-A15*A23*A31*A52+   &
       A13*A25*A31*A52+A15*A21*A33*A52-A11*A25*A33*A52-A13*A21*A35*A52+   &
       A11*A23*A35*A52+A15*A22*A31*A53-A12*A25*A31*A53-A15*A21*A32*A53+   &
       A11*A25*A32*A53+A12*A21*A35*A53-A11*A22*A35*A53-A13*A22*A31*A55+   &
       A12*A23*A31*A55+A13*A21*A32*A55-A11*A23*A32*A55-A12*A21*A33*A55+   &
       A11*A22*A33*A55

    COFACTOR(5,4) = -A15*A23*A32*A41+A13*A25*A32*A41+A15*A22*A33*A41-     &
       A12*A25*A33*A41-A13*A22*A35*A41+A12*A23*A35*A41+A15*A23*A31*A42-   &
       A13*A25*A31*A42-A15*A21*A33*A42+A11*A25*A33*A42+A13*A21*A35*A42-   &
       A11*A23*A35*A42-A15*A22*A31*A43+A12*A25*A31*A43+A15*A21*A32*A43-   &
       A11*A25*A32*A43-A12*A21*A35*A43+A11*A22*A35*A43+A13*A22*A31*A45-   &
       A12*A23*A31*A45-A13*A21*A32*A45+A11*A23*A32*A45+A12*A21*A33*A45-   &
       A11*A22*A33*A45

    COFACTOR(1,5) = A24*A33*A42*A51-A23*A34*A42*A51-A24*A32*A43*A51+      &
       A22*A34*A43*A51+A23*A32*A44*A51-A22*A33*A44*A51-A24*A33*A41*A52+   &
       A23*A34*A41*A52+A24*A31*A43*A52-A21*A34*A43*A52-A23*A31*A44*A52+   &
       A21*A33*A44*A52+A24*A32*A41*A53-A22*A34*A41*A53-A24*A31*A42*A53+   &
       A21*A34*A42*A53+A22*A31*A44*A53-A21*A32*A44*A53-A23*A32*A41*A54+   &
       A22*A33*A41*A54+A23*A31*A42*A54-A21*A33*A42*A54-A22*A31*A43*A54+   &
       A21*A32*A43*A54

    COFACTOR(2,5) = -A14*A33*A42*A51+A13*A34*A42*A51+A14*A32*A43*A51-     &
       A12*A34*A43*A51-A13*A32*A44*A51+A12*A33*A44*A51+A14*A33*A41*A52-   &
       A13*A34*A41*A52-A14*A31*A43*A52+A11*A34*A43*A52+A13*A31*A44*A52-   &
       A11*A33*A44*A52-A14*A32*A41*A53+A12*A34*A41*A53+A14*A31*A42*A53-   &
       A11*A34*A42*A53-A12*A31*A44*A53+A11*A32*A44*A53+A13*A32*A41*A54-   &
       A12*A33*A41*A54-A13*A31*A42*A54+A11*A33*A42*A54+A12*A31*A43*A54-   &
       A11*A32*A43*A54

    COFACTOR(3,5) = A14*A23*A42*A51-A13*A24*A42*A51-A14*A22*A43*A51+      &
       A12*A24*A43*A51+A13*A22*A44*A51-A12*A23*A44*A51-A14*A23*A41*A52+   &
       A13*A24*A41*A52+A14*A21*A43*A52-A11*A24*A43*A52-A13*A21*A44*A52+   &
       A11*A23*A44*A52+A14*A22*A41*A53-A12*A24*A41*A53-A14*A21*A42*A53+   &
       A11*A24*A42*A53+A12*A21*A44*A53-A11*A22*A44*A53-A13*A22*A41*A54+   &
       A12*A23*A41*A54+A13*A21*A42*A54-A11*A23*A42*A54-A12*A21*A43*A54+   &
       A11*A22*A43*A54

    COFACTOR(4,5) = -A14*A23*A32*A51+A13*A24*A32*A51+A14*A22*A33*A51-     &
       A12*A24*A33*A51-A13*A22*A34*A51+A12*A23*A34*A51+A14*A23*A31*A52-   &
       A13*A24*A31*A52-A14*A21*A33*A52+A11*A24*A33*A52+A13*A21*A34*A52-   &
       A11*A23*A34*A52-A14*A22*A31*A53+A12*A24*A31*A53+A14*A21*A32*A53-   &
       A11*A24*A32*A53-A12*A21*A34*A53+A11*A22*A34*A53+A13*A22*A31*A54-   &
       A12*A23*A31*A54-A13*A21*A32*A54+A11*A23*A32*A54+A12*A21*A33*A54-   &
       A11*A22*A33*A54

    COFACTOR(5,5) = A14*A23*A32*A41-A13*A24*A32*A41-A14*A22*A33*A41+      &
       A12*A24*A33*A41+A13*A22*A34*A41-A12*A23*A34*A41-A14*A23*A31*A42+   &
       A13*A24*A31*A42+A14*A21*A33*A42-A11*A24*A33*A42-A13*A21*A34*A42+   &
       A11*A23*A34*A42+A14*A22*A31*A43-A12*A24*A31*A43-A14*A21*A32*A43+   &
       A11*A24*A32*A43+A12*A21*A34*A43-A11*A22*A34*A43-A13*A22*A31*A44+   &
       A12*A23*A31*A44+A13*A21*A32*A44-A11*A23*A32*A44-A12*A21*A33*A44+   &
       A11*A22*A33*A44

    AINV = REAL( TRANSPOSE( COFACTOR),dp) / detA

  END FUNCTIOn calc_matrix_inverse_5_by_5

  PURE FUNCTION solve_Axb_2_by_2( A,b) RESULT( x)
    ! Direct solution of the 2-by-2 matrix equation Ax=b

    IMPLICIT NONE

    ! Input variables:
    REAL(dp), DIMENSION(2,2    )                       , INTENT(IN)    :: A       ! The matrix A
    REAL(dp), DIMENSION(2      )                       , INTENT(IN)    :: b       ! The right-hand side b

    ! Output variables:
    REAL(dp), DIMENSION(2      )                                       :: x       ! THe solution x

    ! Local variables:
    REAL(dp), DIMENSION(2,2    )                                       :: Ainv

    ! Calculate the inverse of A
    Ainv = calc_matrix_inverse_2_by_2( A)

    ! Calculate x
    x( 1) = Ainv( 1,1) * b( 1) + Ainv( 1,2) * b( 2)
    x( 2) = Ainv( 2,1) * b( 1) + Ainv( 2,2) * b( 2)

  END FUNCTION solve_Axb_2_by_2

! == Sorting

  SUBROUTINE quick_n_dirty_sort( f, ii)
    ! Inefficient but simple sorting algorithm
    ! Sort f ascending and return list of new indices

    IMPLICIT NONE

    ! In/output variables:
    REAL(dp), DIMENSION(:    ),          INTENT(INOUT) :: f
    INTEGER,  DIMENSION(:    ),          INTENT(INOUT) :: ii

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                      :: routine_name = 'quick_n_dirty_sort'
    INTEGER                                            :: n,i,j

    ! Add routine to path
    CALL init_routine( routine_name)

    ! Number of elements
    n = SIZE( f,1)

    ! Initialise current indices
    DO i = 1, n
      ii( i) = i
    END DO

    ! Sort
    DO i = 1, n-1
      DO j = i+1, n
        IF (f( i) > f( j)) THEN

          ! Now: f( i) = a, f( j) = b
          f(  j) = f(  j) + f(  i)
          ii( j) = ii( j) + ii( i)
          ! Now: f( i) = a, f( j) = a+b
          f(  i) = f(  j) - f(  i)
          ii( i) = ii( j) - ii( i)
          ! Now: f( i) = b, f( j) = a+b
          f(  j) = f(  j) - f(  i)
          ii( j) = ii( j) - ii( i)
          ! Now: f( i) = b, f( j) = a

        END IF
      END DO
    END DO

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE quick_n_dirty_sort

! == Some basic geometry

  PURE FUNCTION cross2( a,b) RESULT( z)
    ! Vector product z between 2-dimensional vectors a and b

    IMPLICIT NONE

    ! Input variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    REAL(dp), DIMENSION(2)                             , INTENT(IN)    :: a, b

    ! Output variables:
    REAL(dp)                                                           :: z

    z = (a( 1) * b( 2)) - (a( 2) * b( 1))

  END FUNCTION cross2

  PURE SUBROUTINE segment_intersection( p, q, r, s, llis, do_cross, tol_dist)
    ! Find out if the line segments [pq] and [rs] intersect. If so, return
    ! the coordinates of the point of intersection

    IMPLICIT NONE

    ! Input variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    REAL(dp), DIMENSION(2)                             , INTENT(IN)    :: p, q, r, s
    REAL(dp)                                           , INTENT(IN)    :: tol_dist

    ! Output variables
    REAL(dp), DIMENSION(2)                             , INTENT(OUT)   :: llis
    LOGICAL                                            , INTENT(OUT)   :: do_cross

    ! Local variables:
    REAL(dp), DIMENSION(2,2)                                           :: A
    REAL(dp), DIMENSION(2)                                             :: x, b

    ! If pq and rs are colinear, define them as not intersecting
    IF ( ABS( cross2( [q(1)-p(1), q(2)-p(2)], [s(1)-r(1), s(2)-r(2)] )) < tol_dist) THEN
      llis = [0._dp, 0._dp]
      do_cross = .FALSE.
      RETURN
    END IF

    A( 1,:) = [ (p( 1) - q( 1)), (r( 1) - s( 1))]
    A( 2,:) = [ (p( 2) - q( 2)), (r( 2) - s( 2))]
    b = [ (r( 1) - q( 1)), (r( 2) - q( 2))]

    ! Solve for x
    x = solve_Axb_2_by_2( A,b)

    llis = [q( 1) + x( 1) * (p( 1) - q( 1)), q( 2) + x( 1) * (p( 2) - q( 2))]

    IF (x( 1) > 0._dp .AND. x( 1) < 1._dp .AND. x( 2) > 0._dp .AND. x( 2) < 1._dp) THEN
      do_cross = .TRUE.
    ELSE
      do_cross = .FALSE.
    END IF

  END SUBROUTINE segment_intersection

  PURE FUNCTION is_in_polygons( poly_mult, p) RESULT( isso)
    ! Check if p is inside any of the polygons in poly_mult

    IMPLICIT NONE

    ! Input variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    REAL(dp), DIMENSION(:,:    )                       , INTENT(IN)    :: poly_mult
    REAL(dp), DIMENSION(2)                             , INTENT(IN)    :: p

    ! Output variables:
    LOGICAL                                                            :: isso

    ! Local variables:
    INTEGER                                                            :: n1,n2,nn
    REAL(dp), DIMENSION(:,:  ), ALLOCATABLE                            :: poly
    LOGICAL                                                            :: isso_single

    isso = .FALSE.

    n1 = 1
    n2 = 0

    DO WHILE (n2 < SIZE( poly_mult,1))

      ! Copy a single polygon from poly_mult
      nn = NINT( poly_mult( n1,1))
      n2 = n1 + nn
      ALLOCATE( poly( nn,2))
      poly = poly_mult( n1+1:n2,:)
      n1 = n2+1

      ! Check if p is inside this single polygon
      isso_single = is_in_polygon( poly, p)

      ! Clean up after yourself
      DEALLOCATE( poly)

      IF (isso_single) THEN
        isso = .TRUE.
        EXIT
      END IF

    END DO ! DO WHILE (n2 < SIZE( poly_mult,1))

  END FUNCTION is_in_polygons

  PURE FUNCTION is_in_polygon( Vpoly, p) RESULT( isso)
    ! Use the ray-casting algorithm to check if the point p = [px,py]
    ! lies inside the polygon spanned by poly = [x1,y1; x2,y2; ...; xn,yn]

    IMPLICIT NONE

    ! Input variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    REAL(dp), DIMENSION(:,:    )                       , INTENT(IN)    :: Vpoly
    REAL(dp), DIMENSION(2)                             , INTENT(IN)    :: p

    ! Output variables:
    LOGICAL                                                            :: isso

    ! Local variables:
    REAL(dp), DIMENSION(2)                                             :: q,r,s,llis
    REAL(dp)                                                           :: xmin,xmax,ymin,ymax
    INTEGER                                                            :: n_intersects
    INTEGER                                                            :: vi,vj,n_vertices
    LOGICAL                                                            :: do_cross
    REAL(dp), PARAMETER                                                :: tol_dist = 1E-5_dp

    isso = .FALSE.

    xmin = MINVAL( Vpoly(:,1))
    xmax = MAXVAL( Vpoly(:,1))
    ymin = MINVAL( Vpoly(:,2))
    ymax = MAXVAL( Vpoly(:,2))

    ! Quick test
    IF (p(1) < xmin .OR. p(1) > xmax .OR. &
        p(2) < ymin .OR. p(2) > ymax) THEN
      isso = .FALSE.
      RETURN
    END IF

    ! Define the endpoint of the east-pointing ray
    q = [xmax + (xmax - xmin) / 10._dp, p(2)]

    ! Determine how often the ray intersects the polygon

    n_vertices   = SIZE( Vpoly,1)
    n_intersects = 0

    DO vi = 1, n_vertices

      ! Find vertices spanning a polygon line section
      IF (vi < n_vertices) THEN
        vj = vi + 1
      ELSE
        vj = 1
      END IF

      ! Define the line section
      r = Vpoly( vi,:)
      s = Vpoly( vj,:)

      ! Determine if the ray intersects the line section
      IF ((r(2) < p(2) .AND. s(2) < p(2)) .OR. (r(2) > p(2) .AND. s(2) > p(2))) THEN
        do_cross = .FALSE.
      ELSE
        CALL segment_intersection( p, q, r, s, llis, do_cross, tol_dist)
      END IF

      IF (do_cross) n_intersects = n_intersects + 1

    END DO ! DO vi = 1, n_vertices

    ! If the number of intersections is odd, p lies inside the polygon
    IF (MOD( n_intersects,2) == 1) THEN
      isso = .TRUE.
    ELSE
      isso = .FALSE.
    END IF

  END FUNCTION is_in_polygon

  PURE FUNCTION lies_on_line_segment( pa, pb, pc, tol_dist) RESULT(isso)
    ! Test if the point pc lies within tol_dist of the line pa-pb

    IMPLICIT NONE

    ! In/output variables:
    REAL(dp), DIMENSION(2),   INTENT(IN)          :: pa, pb, pc
    REAL(dp),                 INTENT(IN)          :: tol_dist
    LOGICAL                                       :: isso

    ! Local variables:
    REAL(dp), DIMENSION(2)                        :: d, e, d_norm, e_par, e_ort

    d = pb - pa
    e = pc - pa

    d_norm = d / NORM2( d)

    e_par = (e( 1) * d_norm( 1) + e( 2) * d_norm( 2)) * d_norm
    e_ort = e - e_par

    isso = .TRUE.
    IF (NORM2( e_ort) > tol_dist) THEN
      isso = .FALSE.
      RETURN
    END IF

    IF ((e( 1) * d( 1) + e( 2)* d ( 2)) > 0._dp) THEN
      IF (NORM2( e_par) > (NORM2( d))) THEN
        isso = .FALSE.
        RETURN
      END IF
    ELSE
      IF (NORM2( e_par) > 0._dp) THEN
        isso = .FALSE.
        RETURN
      END IF
    END IF

  END FUNCTION lies_on_line_segment

  PURE SUBROUTINE line_from_points( p, q, la, lb, lc)
    ! Find a,b,c such that the line ax + by = c passes through p and q

    IMPLICIT NONE

    REAL(dp), DIMENSION(2),     INTENT(IN)        :: p, q
    REAL(dp),                   INTENT(OUT)       :: la, lb, lc

    la = q( 2) - p( 2)
    lb = p( 1) - q( 1)
    lc = la * (p( 1))+ lb * (p( 2))

  END SUBROUTINE line_from_points

  PURE SUBROUTINE perpendicular_bisector_from_line( p, q, la1, lb1, la2, lb2, lc2)
    ! Find a,b,c such that the line ax + by = c describes the perpendicular
    ! bisector to the line [pq]

    IMPLICIT NONE

    REAL(dp), DIMENSION(2),     INTENT(IN)        :: p, q
    REAL(dp),                   INTENT(IN)        :: la1, lb1
    REAL(dp),                   INTENT(OUT)       :: la2, lb2, lc2
    REAL(dp)                                      :: temp
    REAL(dp), DIMENSION(2)                        :: m

    m = (p+q)/2
    lc2 = -lb1*m(1) + la1*m(2)

    temp = la1
    la2 = -lb1
    lb2 = temp

  END SUBROUTINE perpendicular_bisector_from_line

  PURE SUBROUTINE line_line_intersection( la1, lb1, lc1, la2, lb2, lc2, llis)
    ! Find the intersection llis of the lines la1*x+lb1*y=lc1 and la2*x+lb2*y=lc2

    IMPLICIT NONE

    REAL(dp),                   INTENT(IN)        :: la1, lb1, lc1, la2, lb2, lc2
    REAL(dp), DIMENSION(2),     INTENT(OUT)       :: llis
    REAL(dp)                                      :: d

    d = la1*lb2 - la2*lb1
    IF (d == 0) THEN
      ! The lines are parallel.
      llis = [1E30, 1E30]
    ELSE
      llis = [(lb2*lc1 - lb1*lc2), (la1*lc2 - la2*lc1)]/d
    END IF

  END SUBROUTINE line_line_intersection

  PURE FUNCTION circumcenter( p, q, r) RESULT( cc)
    ! Find the circumcenter cc of the triangle pqr

    IMPLICIT NONE

    ! Some basic vector operations
    ! Find the circumcenter cc of the triangle pqr
    ! If pqr are colinear, returns [1e30,1e30]

    REAL(dp), DIMENSION(2),     INTENT(IN)        :: p, q, r
    REAL(dp), DIMENSION(2)                        :: cc
    REAL(dp)                                      :: la1,lb1,lc1,le1,lf1,lg1
    REAL(dp)                                      :: la2,lb2,lc2,le2,lf2,lg2

    cc = [0._dp, 0._dp]

    ! Line PQ is represented as ax + by = c, Line QR is represented as ex + fy = g
    CALL line_from_points( p, q, la1, lb1, lc1)
    CALL line_from_points( q, r, le1, lf1, lg1)

    ! Converting lines PQ and QR to perpendicular
    ! bisectors. After this, L = ax + by = c
    ! M = ex + fy = g
    CALL perpendicular_bisector_from_line( p, q, la1, lb1, la2, lb2, lc2)
    CALL perpendicular_bisector_from_line( q, r, le1, lf1, le2, lf2, lg2)

    ! The point of intersection of L and M gives
    ! the circumcenter
    CALL line_line_intersection( la2, lb2, lc2, le2, lf2, lg2, cc)

  END FUNCTION circumcenter

  PURE FUNCTION geometric_center( p, q, r) RESULT( gc)
    ! Calculate the geometric centre of triangle [pqr]

    IMPLICIT NONE

    ! In/output variables:
    REAL(dp), DIMENSION(2), INTENT(IN)            :: p, q, r
    REAL(dp), DIMENSION(2)                        :: gc

    gc = (p + q + r) / 3._dp

  END FUNCTION geometric_center

  PURE FUNCTION triangle_area( p, q, r) RESULT( A)
    ! Find the area of the triangle [p,q,r]

    IMPLICIT NONE

    REAL(dp), DIMENSION(2), INTENT(IN)  :: p, q, r
    REAL(dp)                            :: A

    A = ABS( cross2( [q(1)-p(1), q(2)-p(2)], [r(1)-p(1), r(2)-p(2)] )) / 2._dp

  END FUNCTION triangle_area

  PURE FUNCTION is_in_triangle( pa, pb, pc, p) RESULT(isso)
    ! Check if the point p lies inside the triangle abc, or within distance tol of its edges

    IMPLICIT NONE

    REAL(dp), DIMENSION(2),   INTENT(IN)          :: pa, pb, pc, p
    LOGICAL                                       :: isso
    REAL(dp)                                      :: as_x, as_y, s1, s2, s3
    REAL(dp), PARAMETER                           :: tol = 1E-9_dp

    as_x = p( 1) - pa( 1)
    as_y = p( 2) - pa( 2)

    s1 = ((pb( 1) - pa( 1)) * as_y - (pb( 2) - pa( 2)) * as_x)
    s2 = ((pc( 1) - pa( 1)) * as_y - (pc( 2) - pa( 2)) * as_x)
    s3 = ((pc( 1) - pb( 1)) * (p( 2) - pb( 2)) - (pc( 2) - pb( 2)) * (p( 1) - pb( 1)))

    isso = .FALSE.

    IF (s1 > -tol .AND. s2 < tol .AND. s3 > -tol) THEN
      isso = .TRUE.
      RETURN
    END IF

  END FUNCTION is_in_triangle

  PURE FUNCTION longest_triangle_leg( p, q, r) RESULT( d)
    ! Find the longest leg of the triangle [p,q,r]

    IMPLICIT NONE

    REAL(dp), DIMENSION(2), INTENT(IN)  :: p, q, r
    REAL(dp)                            :: d
    REAL(dp)                            :: d_pq, d_qr, d_rp

    d_pq = NORM2( p-q)
    d_qr = NORM2( q-r)
    d_rp = NORM2( r-p)
    d = MAX( MAX( d_pq, d_qr), d_rp)

  END FUNCTION longest_triangle_leg

  PURE FUNCTION smallest_triangle_angle( p, q, r) RESULT( alpha)
    ! Find the smallest internal angle of the triangle [p,q,r]

    IMPLICIT NONE

    REAL(dp), DIMENSION(2), INTENT(IN)  :: p, q, r
    REAL(dp)                            :: alpha
    REAL(dp), DIMENSION(2)              :: pq, qr, rp
    REAL(dp)                            :: ap, aq, ar

    ! Triangle legs
    pq = p-q
    qr = q-r
    rp = r-p

    ! Internal angles
    ap = ACOS(-(rp( 1) * pq( 1) + rp( 2) * pq( 2)) / (NORM2( rp) * NORM2( pq)))
    aq = ACOS(-(pq( 1) * qr( 1) + pq( 2) * qr( 2)) / (NORM2( pq) * NORM2( qr)))
    ar = ACOS(-(rp( 1) * qr( 1) + rp( 2) * qr( 2)) / (NORM2( rp) * NORM2( qr)))

    ! Smallest internal angle
    alpha = MIN( MIN( ap, aq), ar)

  END FUNCTION smallest_triangle_angle

  !> Calculate the largest internal angle of the triangle [p,q,r]
  pure function largest_triangle_angle( p, q, r) result( alpha)

    ! In/output variables:
    real(dp), dimension(2), intent(in) :: p, q, r
    real(dp)                           :: alpha

    ! Local variables:
    real(dp), dimension(2)             :: pq, qr, rp
    real(dp)                           :: ap, aq, ar

    ! Triangle legs
    pq = p-q
    qr = q-r
    rp = r-p

    ! Internal angles
    ap = acos(-(rp( 1) * pq( 1) + rp( 2) * pq( 2)) / (norm2( rp) * norm2( pq)))
    aq = acos(-(pq( 1) * qr( 1) + pq( 2) * qr( 2)) / (norm2( pq) * norm2( qr)))
    ar = acos(-(rp( 1) * qr( 1) + rp( 2) * qr( 2)) / (norm2( rp) * norm2( qr)))

    ! Largest internal angle
    alpha = max( max( ap, aq), ar)

  end function largest_triangle_angle

  !> Calculate the equiangular skewness of a triangle
  pure function equiangular_skewness( p, q, r) result( skewness)
    ! See: https://en.wikipedia.org/wiki/Types_of_mesh#Equiangular_skew

    ! In/output variables:
    real(dp), dimension(2), intent(in) :: p, q, r
    real(dp)                           :: skewness

    ! Local variables:
    real(dp) :: theta_e, theta_max, theta_min

    theta_e = 60._dp * pi / 180._dp

    theta_max = largest_triangle_angle ( p, q, r)
    theta_min = smallest_triangle_angle( p, q, r)

    skewness = max( (theta_max - theta_e  ) / (pi / 2._dp - theta_e), &
                    (theta_e   - theta_min) /               theta_e)

    end function equiangular_skewness

  SUBROUTINE crop_line_to_domain( p, q, xmin, xmax, ymin, ymax, tol_dist, pp, qq, is_valid_line)
    ! Crop the line [pq] so that it lies within the specified domain;
    ! if [pq] doesn't pass through the domain at all, return is_valid_line = .FALSE.

    IMPLICIT NONE

    ! In/output variables
    REAL(dp), DIMENSION(2),              INTENT(IN)    :: p, q
    REAL(dp),                            INTENT(IN)    :: xmin, xmax, ymin, ymax, tol_dist
    REAL(dp), DIMENSION(2),              INTENT(OUT)   :: pp, qq
    LOGICAL,                             INTENT(OUT)   :: is_valid_line

    ! Local variables:
    REAL(dp), DIMENSION(2)                             :: sw, se, nw, ne
    LOGICAL                                            :: p_inside
    LOGICAL                                            :: p_on_border
    LOGICAL                                            :: p_outside
    LOGICAL                                            :: q_inside
    LOGICAL                                            :: q_on_border
    LOGICAL                                            :: q_outside
    LOGICAL                                            :: do_cross_w
    LOGICAL                                            :: do_cross_e
    LOGICAL                                            :: do_cross_s
    LOGICAL                                            :: do_cross_n
    INTEGER                                            :: n_cross
    REAL(dp), DIMENSION(2)                             :: llis_w, llis_e, llis_s, llis_n, llis1, llis2

    sw = [xmin,ymin]
    se = [xmax,ymin]
    nw = [xmin,ymax]
    ne = [xmax,ymax]

    ! Determine where p and q are relative to the domain

    p_inside    = .FALSE.
    p_on_border = .FALSE.
    p_outside   = .FALSE.

    IF     (p( 1) > xmin .AND. p( 1) < xmax .AND. p( 2) > ymin .AND. p( 2) < ymax) THEN
      p_inside    = .TRUE.
    ELSEIF (p (1) < xmin .OR.  p( 1) > xmax .OR.  p( 2) < ymin .OR.  p( 2) > ymax) THEN
      p_outside   = .TRUE.
    ELSE
      p_on_border = .TRUE.
    END IF

    q_inside    = .FALSE.
    q_on_border = .FALSE.
    q_outside   = .FALSE.

    IF     (q( 1) > xmin .AND. q( 1) < xmax .AND. q( 2) > ymin .AND. q( 2) < ymax) THEN
      q_inside    = .TRUE.
    ELSEIF (q (1) < xmin .OR.  q( 1) > xmax .OR.  q( 2) < ymin .OR.  q( 2) > ymax) THEN
      q_outside   = .TRUE.
    ELSE
      q_on_border = .TRUE.
    END IF

    ! If both of them lie inside the domain, the solution is trivial
    IF (p_inside .AND. q_inside) THEN
      pp = p
      qq = q
      is_valid_line = .TRUE.
      RETURN
    END IF

    ! If both of them lie on the border, the solution is trivial
    IF (p_on_border .AND. q_on_border) THEN
      pp = p
      qq = q
      is_valid_line = .TRUE.
      RETURN
    END IF

    ! If one of them lies inside the domain and the other on the border, the solution is trivial
    IF ((p_inside .AND. q_on_border) .OR. (p_on_border .AND. q_inside)) THEN
      pp = p
      qq = q
      is_valid_line = .TRUE.
      RETURN
    END IF

    ! If one of them lies inside and the other outside, there must be a single border crossing
    IF (p_inside .AND. q_outside) THEN
      ! p lies inside the domain, q lies outside

      ! Possible pq passes through a corner of the domain?
      IF     (lies_on_line_segment( p, q, nw, tol_dist)) THEN
        ! pq passes through the northwest corner
        pp = p
        qq = nw
        is_valid_line = .TRUE.
        RETURN
      ELSEIF (lies_on_line_segment( p, q, ne, tol_dist)) THEN
        ! pq passes through the northeast corner
        pp = p
        qq = ne
        is_valid_line = .TRUE.
        RETURN
      ELSEIF (lies_on_line_segment( p, q, sw, tol_dist)) THEN
        ! pq passes through the southwest corner
        pp = p
        qq = sw
        is_valid_line = .TRUE.
        RETURN
      ELSEIF (lies_on_line_segment( p, q, se, tol_dist)) THEN
        ! pq passes through the southeast corner
        pp = p
        qq = se
        is_valid_line = .TRUE.
        RETURN
      END IF

      ! pq must pass through one of the four borders; determine which one
      CALL segment_intersection( p, q, sw, nw, llis_w, do_cross_w, tol_dist)
      CALL segment_intersection( p, q, se, ne, llis_e, do_cross_e, tol_dist)
      CALL segment_intersection( p, q, sw, se, llis_s, do_cross_s, tol_dist)
      CALL segment_intersection( p, q, nw, ne, llis_n, do_cross_n, tol_dist)

      IF     (do_cross_w) THEN
        ! pq crosses the western border
        pp = p
        qq = llis_w
        is_valid_line = .TRUE.
        RETURN
      ELSEIF (do_cross_e) THEN
        ! pq crosses the eastern border
        pp = p
        qq = llis_e
        is_valid_line = .TRUE.
        RETURN
      ELSEIF (do_cross_s) THEN
        ! pq crosses the southern border
        pp = p
        qq = llis_s
        is_valid_line = .TRUE.
        RETURN
      ELSEIF (do_cross_n) THEN
        ! pq crosses the northern border
        pp = p
        qq = llis_n
        is_valid_line = .TRUE.
        RETURN
      END IF

      ! This point should not be reachable!
      CALL crash('crop_line_to_domain - p lies inside, q lies outside, couldnt find exit point of pq!')

    ELSEIF (p_outside .AND. q_inside) THEN
      ! p lies outside the domain, q lies inside

      ! Possible pq passes through a corner of the domain?
      IF     (lies_on_line_segment( p, q, nw, tol_dist)) THEN
        ! pq passes through the northwest corner
        pp = nw
        qq = q
        is_valid_line = .TRUE.
        RETURN
      ELSEIF (lies_on_line_segment( p, q, ne, tol_dist)) THEN
        ! pq passes through the northeast corner
        pp = ne
        qq = q
        is_valid_line = .TRUE.
        RETURN
      ELSEIF (lies_on_line_segment( p, q, sw, tol_dist)) THEN
        ! pq passes through the southwest corner
        pp = sw
        qq = q
        is_valid_line = .TRUE.
        RETURN
      ELSEIF (lies_on_line_segment( p, q, se, tol_dist)) THEN
        ! pq passes through the southeast corner
        pp = se
        qq = q
        is_valid_line = .TRUE.
        RETURN
      END IF

      ! pq must pass through one of the four borders; determine which one
      CALL segment_intersection( p, q, sw, nw, llis_w, do_cross_w, tol_dist)
      CALL segment_intersection( p, q, se, ne, llis_e, do_cross_e, tol_dist)
      CALL segment_intersection( p, q, sw, se, llis_s, do_cross_s, tol_dist)
      CALL segment_intersection( p, q, nw, ne, llis_n, do_cross_n, tol_dist)

      IF     (do_cross_w) THEN
        ! pq crosses the western border
        pp = llis_w
        qq = q
        is_valid_line = .TRUE.
        RETURN
      ELSEIF (do_cross_e) THEN
        ! pq crosses the eastern border
        pp = llis_e
        qq = q
        is_valid_line = .TRUE.
        RETURN
      ELSEIF (do_cross_s) THEN
        ! pq crosses the southern border
        pp = llis_s
        qq = q
        is_valid_line = .TRUE.
        RETURN
      ELSEIF (do_cross_n) THEN
        ! pq crosses the northern border
        pp = llis_n
        qq = q
        is_valid_line = .TRUE.
        RETURN
      END IF

      ! This point should not be reachable!
      CALL crash('crop_line_to_domain - p lies outside, q lies inside, couldnt find exit point of pq!')

    END IF ! IF (p_inside .AND. q_outside) THEN

    ! If both of them lie outside the domain, there might still be a section passing through it
    IF (p_outside .AND. q_outside) THEN

      ! pq must pass through either none, or two of the four borders; determine which
      CALL segment_intersection( p, q, sw, nw, llis_w, do_cross_w, tol_dist)
      CALL segment_intersection( p, q, se, ne, llis_e, do_cross_e, tol_dist)
      CALL segment_intersection( p, q, sw, se, llis_s, do_cross_s, tol_dist)
      CALL segment_intersection( p, q, nw, ne, llis_n, do_cross_n, tol_dist)

      n_cross = 0

      IF (do_cross_w) THEN
        n_cross = n_cross + 1
        IF (n_cross == 1) THEN
          llis1 = llis_w
        ELSE
          llis2 = llis_w
        END IF
      END IF

      IF (do_cross_e) THEN
        n_cross = n_cross + 1
        IF (n_cross == 1) THEN
          llis1 = llis_e
        ELSE
          llis2 = llis_e
        END IF
      END IF

      IF (do_cross_s) THEN
        n_cross = n_cross + 1
        IF (n_cross == 1) THEN
          llis1 = llis_s
        ELSE
          llis2 = llis_s
        END IF
      END IF

      IF (do_cross_n) THEN
        n_cross = n_cross + 1
        IF (n_cross == 1) THEN
          llis1 = llis_n
        ELSE
          llis2 = llis_n
        END IF
      END IF

      IF     (n_cross == 0) THEN
        ! pq does not pass through the domain at all
        pp = 0._dp
        qq = 0._dp
        is_valid_line = .FALSE.
        RETURN
      ELSEIF (n_cross == 2) THEN
        ! pq passes through the domain; crop it

        IF (NORM2( llis1 - p) < NORM2( llis2 - p)) THEN
          ! the cropped line runs from llis1 to llis2
          pp = llis1
          qq = llis2
          is_valid_line = .TRUE.
          RETURN
        ELSE
          ! the cropped lines runs from llis2 to llis1
          pp = llis2
          qq = llis1
          is_valid_line = .TRUE.
          RETURN
        END IF

      ELSE
        ! This should not be possible
        CALL crash('pq crosses the domain border {int_01} times!', int_01 = n_cross)
      END IF

    END IF ! IF (p_outside .AND. q_outside) THEN

    ! If one of them lies on the border and another outside, it is possible
    ! that the line still passes through the domain, but we neglect that possibility for now...
    IF ((p_on_border .AND. q_outside) .OR. (p_outside .AND. q_on_border)) THEN
      pp = 0._dp
      qq = 0._dp
      is_valid_line = .FALSE.
      RETURN
    END IF

    ! This point should not be reachable!
    CALL crash('crop_line_to_domain - reached the unreachable end!')

  END SUBROUTINE crop_line_to_domain

  PURE FUNCTION encroaches_upon( pa, pb, pc, tol_dist) RESULT( isso)
    ! Check if c encroaches upon segment ab

    IMPLICIT NONE

    ! In/output variables:
    REAL(dp), DIMENSION(2), INTENT(IN)            :: pa, pb, pc
    REAL(dp),               INTENT(IN)            :: tol_dist
    LOGICAL                                       :: isso

    isso = NORM2( pc - (pa + pb) / 2._dp) < NORM2( pa - pb) / 2._dp + tol_dist

  END FUNCTION encroaches_upon

  PURE FUNCTION linint_points( x1, x2, f1, f2, f0) RESULT( x0)
    ! Given a function f( x) and points x1, x2 such that f( x1) = f1, f( x2) = f2,
    ! interpolate f linearly to find the point x0 such that f( x0) = f0

    IMPLICIT NONE

    REAL(dp),               INTENT(IN)  :: x1, x2, f1, f2, f0
    REAL(dp)                            :: x0
    REAL(dp)                            :: lambda

    ! Safety - if f1 == f2, then f = f0 = f1 everywhere
    IF (ABS( 1._dp - f1/f2) < 1E-9_dp) THEN
      x0 = (x1 + x2) / 2._dp
      RETURN
    END IF

    lambda = (f2 - f1) / (x2 - x1)
    x0 = x1 + (f0 - f1) / lambda

  END FUNCTION linint_points

! == Basic array operations

  SUBROUTINE permute_2D_int(  d, map)
    ! Permute a 2-D array

    IMPLICIT NONE

    ! In/output variables:
    INTEGER,  DIMENSION(:,:  ), ALLOCATABLE, INTENT(INOUT) :: d
    INTEGER,  DIMENSION(2),                  INTENT(IN)    :: map

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                          :: routine_name = 'permute_2D_int'
    INTEGER                                                :: i,j,n1,n2
    INTEGER,  DIMENSION(:,:  ), ALLOCATABLE                :: d_temp

    ! Add routine to path
    CALL init_routine( routine_name)

    IF (map( 1) == 1 .AND. map( 2) == 2) THEN
      ! Trivial
      RETURN
    ELSEIF (map( 1) == 2 .AND. map( 2) == 1) THEN
      ! 2-D transpose, as expected
    ELSE
      CALL crash('invalid permutation!')
    END IF

    n1 = SIZE( d,1)
    n2 = SIZE( d,2)

    ! Allocate temporary memory
    ALLOCATE( d_temp( n1, n2))

    ! Copy data to temporary memory
    d_temp = d

    ! Deallocate memory
    DEALLOCATE( d)

    ! Reallocate transposed memory
    ALLOCATE( d( n2, n1))

    ! Copy and transpose data from temporary memory
    DO i = 1, n1
    DO j = 1, n2
      d( j,i) = d_temp( i,j)
    END DO
    END DO

    ! Deallocate temporary memory
    DEALLOCATE( d_temp)

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE permute_2D_int

  SUBROUTINE permute_2D_dp(  d, map)
    ! Permute a 2-D array

    IMPLICIT NONE

    ! In/output variables:
    REAL(dp), DIMENSION(:,:  ), ALLOCATABLE, INTENT(INOUT) :: d
    INTEGER,  DIMENSION(2),                  INTENT(IN)    :: map

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                          :: routine_name = 'permute_2D_dp'
    INTEGER                                                :: i,j,n1,n2
    REAL(dp), DIMENSION(:,:  ), ALLOCATABLE                :: d_temp

    ! Add routine to path
    CALL init_routine( routine_name)

    IF (map( 1) == 1 .AND. map( 2) == 2) THEN
      ! Trivial
      RETURN
    ELSEIF (map( 1) == 2 .AND. map( 2) == 1) THEN
      ! 2-D transpose, as expected
    ELSE
      CALL crash('invalid permutation!')
    END IF

    n1 = SIZE( d,1)
    n2 = SIZE( d,2)

    ! Allocate temporary memory
    ALLOCATE( d_temp( n1, n2))

    ! Copy data to temporary memory
    d_temp = d

    ! Deallocate memory
    DEALLOCATE( d)

    ! Reallocate transposed memory
    ALLOCATE( d( n2, n1))

    ! Copy and transpose data from temporary memory
    DO i = 1, n1
    DO j = 1, n2
      d( j,i) = d_temp( i,j)
    END DO
    END DO

    ! Deallocate temporary memory
    DEALLOCATE( d_temp)

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE permute_2D_dp

  SUBROUTINE permute_3D_int(  d, map)
    ! Permute a 3-D array

    IMPLICIT NONE

    ! In/output variables:
    INTEGER,  DIMENSION(:,:,:), ALLOCATABLE, INTENT(INOUT) :: d
    INTEGER,  DIMENSION(3),                  INTENT(IN)    :: map

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                      :: routine_name = 'permute_3D_int'
    INTEGER                                            :: i,j,k,n1,n2,n3
    INTEGER,  DIMENSION(:,:,:), ALLOCATABLE            :: d_temp

    ! Add routine to path
    CALL init_routine( routine_name)

    n1 = SIZE( d,1)
    n2 = SIZE( d,2)
    n3 = SIZE( d,3)

    ! Allocate temporary memory
    ALLOCATE( d_temp( n1, n2, n3))

    ! Copy data to temporary memory
    d_temp = d

    ! Deallocate memory
    DEALLOCATE( d)

    ! Different permutation options
    IF (map( 1) == 1 .AND. map( 2) == 2 .AND. map( 3) == 3) THEN
      ! [i,j,k] -> [i,j,k] (trivial...)

      ! Reallocate permuted memory
      ALLOCATE( d( n1, n2, n3))

      ! Copy and permuted data from temporary memory
      DO i = 1, n1
      DO j = 1, n2
      DO k = 1, n3
        d( i,j,k) = d_temp( i,j,k)
      END DO
      END DO
      END DO

    ELSEIF (map( 1) == 1 .AND. map( 2) == 3 .AND. map( 3) == 2) THEN
      ! [i,j,k] -> [i,k,j]

      ! Reallocate permuted memory
      ALLOCATE( d( n1, n3, n2))

      ! Copy and permuted data from temporary memory
      DO i = 1, n1
      DO j = 1, n2
      DO k = 1, n3
        d( i,k,j) = d_temp( i,j,k)
      END DO
      END DO
      END DO

    ELSEIF (map( 1) == 2 .AND. map( 2) == 1 .AND. map( 3) == 3) THEN
      ! [i,j,k] -> [j,i,k]

      ! Reallocate permuted memory
      ALLOCATE( d( n2, n1, n3))

      ! Copy and permuted data from temporary memory
      DO i = 1, n1
      DO j = 1, n2
      DO k = 1, n3
        d( j,i,k) = d_temp( i,j,k)
      END DO
      END DO
      END DO

    ELSEIF (map( 1) == 2 .AND. map( 2) == 3 .AND. map( 3) == 1) THEN
      ! [i,j,k] -> [j,k,i]

      ! Reallocate permuted memory
      ALLOCATE( d( n2, n3, n1))

      ! Copy and permuted data from temporary memory
      DO i = 1, n1
      DO j = 1, n2
      DO k = 1, n3
        d( j,k,i) = d_temp( i,j,k)
      END DO
      END DO
      END DO

    ELSEIF (map( 1) == 3 .AND. map( 2) == 1 .AND. map( 3) == 2) THEN
      ! [i,j,k] -> [k,i,j]

      ! Reallocate permuted memory
      ALLOCATE( d( n3, n1, n2))

      ! Copy and permuted data from temporary memory
      DO i = 1, n1
      DO j = 1, n2
      DO k = 1, n3
        d( k,i,j) = d_temp( i,j,k)
      END DO
      END DO
      END DO

    ELSEIF (map( 1) == 3 .AND. map( 2) == 2 .AND. map( 3) == 1) THEN
      ! [i,j,k] -> [k,j,i]

      ! Reallocate permuted memory
      ALLOCATE( d( n3, n2, n1))

      ! Copy and permuted data from temporary memory
      DO i = 1, n1
      DO j = 1, n2
      DO k = 1, n3
        d( k,j,i) = d_temp( i,j,k)
      END DO
      END DO
      END DO

    ELSE
      CALL crash('invalid permutation!')
    END IF

    ! Deallocate temporary memory
    DEALLOCATE( d_temp)

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE permute_3D_int

  SUBROUTINE permute_3D_dp(  d, map)
    ! Permute a 3-D array

    IMPLICIT NONE

    ! In/output variables:
    REAL(dp), DIMENSION(:,:,:), ALLOCATABLE, INTENT(INOUT) :: d
    INTEGER,  DIMENSION(3),                  INTENT(IN)    :: map

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                      :: routine_name = 'permute_3D_dp'
    INTEGER                                            :: i,j,k,n1,n2,n3
    REAL(dp), DIMENSION(:,:,:), ALLOCATABLE            :: d_temp

    ! Add routine to path
    CALL init_routine( routine_name)

    n1 = SIZE( d,1)
    n2 = SIZE( d,2)
    n3 = SIZE( d,3)

    ! Allocate temporary memory
    ALLOCATE( d_temp( n1, n2, n3))

    ! Copy data to temporary memory
    d_temp = d

    ! Deallocate memory
    DEALLOCATE( d)

    ! Different permutation options
    IF (map( 1) == 1 .AND. map( 2) == 2 .AND. map( 3) == 3) THEN
      ! [i,j,k] -> [i,j,k] (trivial...)

      ! Reallocate permuted memory
      ALLOCATE( d( n1, n2, n3))

      ! Copy and permuted data from temporary memory
      DO i = 1, n1
      DO j = 1, n2
      DO k = 1, n3
        d( i,j,k) = d_temp( i,j,k)
      END DO
      END DO
      END DO

    ELSEIF (map( 1) == 1 .AND. map( 2) == 3 .AND. map( 3) == 2) THEN
      ! [i,j,k] -> [i,k,j]

      ! Reallocate permuted memory
      ALLOCATE( d( n1, n3, n2))

      ! Copy and permuted data from temporary memory
      DO i = 1, n1
      DO j = 1, n2
      DO k = 1, n3
        d( i,k,j) = d_temp( i,j,k)
      END DO
      END DO
      END DO

    ELSEIF (map( 1) == 2 .AND. map( 2) == 1 .AND. map( 3) == 3) THEN
      ! [i,j,k] -> [j,i,k]

      ! Reallocate permuted memory
      ALLOCATE( d( n2, n1, n3))

      ! Copy and permuted data from temporary memory
      DO i = 1, n1
      DO j = 1, n2
      DO k = 1, n3
        d( j,i,k) = d_temp( i,j,k)
      END DO
      END DO
      END DO

    ELSEIF (map( 1) == 2 .AND. map( 2) == 3 .AND. map( 3) == 1) THEN
      ! [i,j,k] -> [j,k,i]

      ! Reallocate permuted memory
      ALLOCATE( d( n2, n3, n1))

      ! Copy and permuted data from temporary memory
      DO i = 1, n1
      DO j = 1, n2
      DO k = 1, n3
        d( j,k,i) = d_temp( i,j,k)
      END DO
      END DO
      END DO

    ELSEIF (map( 1) == 3 .AND. map( 2) == 1 .AND. map( 3) == 2) THEN
      ! [i,j,k] -> [k,i,j]

      ! Reallocate permuted memory
      ALLOCATE( d( n3, n1, n2))

      ! Copy and permuted data from temporary memory
      DO i = 1, n1
      DO j = 1, n2
      DO k = 1, n3
        d( k,i,j) = d_temp( i,j,k)
      END DO
      END DO
      END DO

    ELSEIF (map( 1) == 3 .AND. map( 2) == 2 .AND. map( 3) == 1) THEN
      ! [i,j,k] -> [k,j,i]

      ! Reallocate permuted memory
      ALLOCATE( d( n3, n2, n1))

      ! Copy and permuted data from temporary memory
      DO i = 1, n1
      DO j = 1, n2
      DO k = 1, n3
        d( k,j,i) = d_temp( i,j,k)
      END DO
      END DO
      END DO

    ELSE
      CALL crash('invalid permutation!')
    END IF

    ! Deallocate temporary memory
    DEALLOCATE( d_temp)

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE permute_3D_dp

  SUBROUTINE flip_1D_int( d)
    ! Flip a 1-D array

    IMPLICIT NONE

    ! In/output variables:
    INTEGER,  DIMENSION(:    ),          INTENT(INOUT) :: d

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                      :: routine_name = 'flip_1D_int'
    INTEGER                                            :: i,nx,iopp

    ! Add routine to path
    CALL init_routine( routine_name)

    nx = SIZE( d,1)

    ! Flip the data
    DO i = 1, nx
      iopp = nx + 1 - i
      IF (iopp <= i) EXIT         ! [a  ] [b  ]
      d( i   ) = d( i) + d( iopp) ! [a+b] [b  ]
      d( iopp) = d( i) - d( iopp) ! [a+b] [a  ]
      d( i   ) = d( i) - d( iopp) ! [b  ] [a  ]
    END DO

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE flip_1D_int

  SUBROUTINE flip_1D_dp( d)
    ! Flip a 1-D array

    IMPLICIT NONE

    ! In/output variables:
    REAL(dp), DIMENSION(:    ),          INTENT(INOUT) :: d

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                      :: routine_name = 'flip_1D_dp'
    INTEGER                                            :: i,nx,iopp

    ! Add routine to path
    CALL init_routine( routine_name)

    nx = SIZE( d,1)

    ! Flip the data
    DO i = 1, nx
      iopp = nx + 1 - i
      IF (iopp <= i) EXIT         ! [a  ] [b  ]
      d( i   ) = d( i) + d( iopp) ! [a+b] [b  ]
      d( iopp) = d( i) - d( iopp) ! [a+b] [a  ]
      d( i   ) = d( i) - d( iopp) ! [b  ] [a  ]
    END DO

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE flip_1D_dp

  SUBROUTINE flip_2D_x1_int( d)
    ! Flip a 2-D array along the first dimension

    IMPLICIT NONE

    ! In/output variables:
    INTEGER,  DIMENSION(:,:  ),          INTENT(INOUT) :: d

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                      :: routine_name = 'flip_2D_x1_int'
    INTEGER                                            :: i,n1,n2,iopp

    ! Add routine to path
    CALL init_routine( routine_name)

    n1 = SIZE( d,1)
    n2 = SIZE( d,2)

    ! Flip the data
    DO i = 1, n1
      iopp = n1 + 1 - i
      IF (iopp <= i) EXIT               ! [a  ] [b  ]
      d( i   ,:) = d( i,:) + d( iopp,:) ! [a+b] [b  ]
      d( iopp,:) = d( i,:) - d( iopp,:) ! [a+b] [a  ]
      d( i   ,:) = d( i,:) - d( iopp,:) ! [b  ] [a  ]
    END DO

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE flip_2D_x1_int

  SUBROUTINE flip_2D_x1_dp( d)
    ! Flip a 2-D array along the first dimension

    IMPLICIT NONE

    ! In/output variables:
    REAL(dp), DIMENSION(:,:  ),          INTENT(INOUT) :: d

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                      :: routine_name = 'flip_2D_x1_dp'
    INTEGER                                            :: i,n1,n2,iopp

    ! Add routine to path
    CALL init_routine( routine_name)

    n1 = SIZE( d,1)
    n2 = SIZE( d,2)

    ! Flip the data
    DO i = 1, n1
      iopp = n1 + 1 - i
      IF (iopp <= i) EXIT               ! [a  ] [b  ]
      d( i   ,:) = d( i,:) + d( iopp,:) ! [a+b] [b  ]
      d( iopp,:) = d( i,:) - d( iopp,:) ! [a+b] [a  ]
      d( i   ,:) = d( i,:) - d( iopp,:) ! [b  ] [a  ]
    END DO

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE flip_2D_x1_dp

  SUBROUTINE flip_2D_x2_int( d)
    ! Flip a 2-D array along the second dimension

    IMPLICIT NONE

    ! In/output variables:
    INTEGER,  DIMENSION(:,:  ),          INTENT(INOUT) :: d

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                      :: routine_name = 'flip_2D_x2_int'
    INTEGER                                            :: j,n1,n2,jopp

    ! Add routine to path
    CALL init_routine( routine_name)

    n1 = SIZE( d,1)
    n2 = SIZE( d,2)

    ! Flip the data
    DO j = 1, n2
      jopp = n2 + 1 - j
      IF (jopp <= j) EXIT               ! [a  ] [b  ]
      d( :,j   ) = d( :,j) + d( :,jopp) ! [a+b] [b  ]
      d( :,jopp) = d( :,j) - d( :,jopp) ! [a+b] [a  ]
      d( :,j   ) = d( :,j) - d( :,jopp) ! [b  ] [a  ]
    END DO

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE flip_2D_x2_int

  SUBROUTINE flip_2D_x2_dp( d)
    ! Flip a 2-D array along the second dimension

    IMPLICIT NONE

    ! In/output variables:
    REAL(dp), DIMENSION(:,:  ),          INTENT(INOUT) :: d

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                      :: routine_name = 'flip_2D_x2_dp'
    INTEGER                                            :: j,n1,n2,jopp

    ! Add routine to path
    CALL init_routine( routine_name)

    n1 = SIZE( d,1)
    n2 = SIZE( d,2)

    ! Flip the data
    DO j = 1, n2
      jopp = n2 + 1 - j
      IF (jopp <= j) EXIT               ! [a  ] [b  ]
      d( :,j   ) = d( :,j) + d( :,jopp) ! [a+b] [b  ]
      d( :,jopp) = d( :,j) - d( :,jopp) ! [a+b] [a  ]
      d( :,j   ) = d( :,j) - d( :,jopp) ! [b  ] [a  ]
    END DO

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE flip_2D_x2_dp

  SUBROUTINE flip_3D_x1_int( d)
    ! Flip a 3-D array along the first dimension

    IMPLICIT NONE

    ! In/output variables:
    INTEGER,  DIMENSION(:,:,:),          INTENT(INOUT) :: d

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                      :: routine_name = 'flip_3D_x1_int'
    INTEGER                                            :: i,n1,n2,n3,iopp

    ! Add routine to path
    CALL init_routine( routine_name)

    n1 = SIZE( d,1)
    n2 = SIZE( d,2)
    n3 = SIZE( d,3)

    ! Flip the data
    DO i = 1, n1
      iopp = n1 + 1 - i
      IF (iopp <= i) EXIT                     ! [a  ] [b  ]
      d( i   ,:,:) = d( i,:,:) + d( iopp,:,:) ! [a+b] [b  ]
      d( iopp,:,:) = d( i,:,:) - d( iopp,:,:) ! [a+b] [a  ]
      d( i   ,:,:) = d( i,:,:) - d( iopp,:,:) ! [b  ] [a  ]
    END DO

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE flip_3D_x1_int

  SUBROUTINE flip_3D_x1_dp( d)
    ! Flip a 3-D array along the first dimension

    IMPLICIT NONE

    ! In/output variables:
    REAL(dp), DIMENSION(:,:,:),          INTENT(INOUT) :: d

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                      :: routine_name = 'flip_3D_x1_dp'
    INTEGER                                            :: i,n1,n2,n3,iopp

    ! Add routine to path
    CALL init_routine( routine_name)

    n1 = SIZE( d,1)
    n2 = SIZE( d,2)
    n3 = SIZE( d,3)

    ! Flip the data
    DO i = 1, n1
      iopp = n1 + 1 - i
      IF (iopp <= i) EXIT                     ! [a  ] [b  ]
      d( i   ,:,:) = d( i,:,:) + d( iopp,:,:) ! [a+b] [b  ]
      d( iopp,:,:) = d( i,:,:) - d( iopp,:,:) ! [a+b] [a  ]
      d( i   ,:,:) = d( i,:,:) - d( iopp,:,:) ! [b  ] [a  ]
    END DO

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE flip_3D_x1_dp

  SUBROUTINE flip_3D_x2_int( d)
    ! Flip a 3-D array along the second dimension

    IMPLICIT NONE

    ! In/output variables:
    INTEGER,  DIMENSION(:,:,:),          INTENT(INOUT) :: d

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                      :: routine_name = 'flip_3D_x2_int'
    INTEGER                                            :: j,n1,n2,n3,jopp

    ! Add routine to path
    CALL init_routine( routine_name)

    n1 = SIZE( d,1)
    n2 = SIZE( d,2)
    n3 = SIZE( d,3)

    ! Flip the data
    DO j = 1, n2
      jopp = n2 + 1 - j
      IF (jopp <= j) EXIT                     ! [a  ] [b  ]
      d( :,j   ,:) = d( :,j,:) + d( :,jopp,:) ! [a+b] [b  ]
      d( :,jopp,:) = d( :,j,:) - d( :,jopp,:) ! [a+b] [a  ]
      d( :,j   ,:) = d( :,j,:) - d( :,jopp,:) ! [b  ] [a  ]
    END DO

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE flip_3D_x2_int

  SUBROUTINE flip_3D_x2_dp( d)
    ! Flip a 3-D array along the second dimension

    IMPLICIT NONE

    ! In/output variables:
    REAL(dp), DIMENSION(:,:,:),          INTENT(INOUT) :: d

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                      :: routine_name = 'flip_3D_x2_dp'
    INTEGER                                            :: j,n1,n2,n3,jopp

    ! Add routine to path
    CALL init_routine( routine_name)

    n1 = SIZE( d,1)
    n2 = SIZE( d,2)
    n3 = SIZE( d,3)

    ! Flip the data
    DO j = 1, n2
      jopp = n2 + 1 - j
      IF (jopp <= j) EXIT                     ! [a  ] [b  ]
      d( :,j   ,:) = d( :,j,:) + d( :,jopp,:) ! [a+b] [b  ]
      d( :,jopp,:) = d( :,j,:) - d( :,jopp,:) ! [a+b] [a  ]
      d( :,j   ,:) = d( :,j,:) - d( :,jopp,:) ! [b  ] [a  ]
    END DO

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE flip_3D_x2_dp

  SUBROUTINE flip_3D_x3_int( d)
    ! Flip a 3-D array along the third dimension

    IMPLICIT NONE

    ! In/output variables:
    INTEGER,  DIMENSION(:,:,:),          INTENT(INOUT) :: d

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                      :: routine_name = 'flip_3D_x3_int'
    INTEGER                                            :: k,n1,n2,n3,kopp

    ! Add routine to path
    CALL init_routine( routine_name)

    n1 = SIZE( d,1)
    n2 = SIZE( d,2)
    n3 = SIZE( d,3)

    ! Flip the data
    DO k = 1, n3
      kopp = n3 + 1 - k
      IF (kopp <= k) EXIT                     ! [a  ] [b  ]
      d( :,:,k   ) = d( :,:,k) + d( :,:,kopp) ! [a+b] [b  ]
      d( :,:,kopp) = d( :,:,k) - d( :,:,kopp) ! [a+b] [a  ]
      d( :,:,k   ) = d( :,:,k) - d( :,:,kopp) ! [b  ] [a  ]
    END DO

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE flip_3D_x3_int

  SUBROUTINE flip_3D_x3_dp( d)
    ! Flip a 3-D array along the third dimension

    IMPLICIT NONE

    ! In/output variables:
    REAL(dp), DIMENSION(:,:,:),          INTENT(INOUT) :: d

    ! Local variables:
    CHARACTER(LEN=256), PARAMETER                      :: routine_name = 'flip_3D_x3_dp'
    INTEGER                                            :: k,n1,n2,n3,kopp

    ! Add routine to path
    CALL init_routine( routine_name)

    n1 = SIZE( d,1)
    n2 = SIZE( d,2)
    n3 = SIZE( d,3)

    ! Flip the data
    DO k = 1, n3
      kopp = n3 + 1 - k
      IF (kopp <= k) EXIT                     ! [a  ] [b  ]
      d( :,:,k   ) = d( :,:,k) + d( :,:,kopp) ! [a+b] [b  ]
      d( :,:,kopp) = d( :,:,k) - d( :,:,kopp) ! [a+b] [a  ]
      d( :,:,k   ) = d( :,:,k) - d( :,:,kopp) ! [b  ] [a  ]
    END DO

    ! Finalise routine path
    CALL finalise_routine( routine_name)

  END SUBROUTINE flip_3D_x3_dp

! == Debugging

  SUBROUTINE check_for_NaN_dp_0D(  d, d_name)
    ! Check if NaN values occur in the 0-D dp data field d

    IMPLICIT NONE

    ! Inpit variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    REAL(dp)                                           , INTENT(IN)    :: d
    CHARACTER(LEN=*),                          OPTIONAL, INTENT(IN)    :: d_name

    ! Local variables:
    CHARACTER(LEN=256)                                                 :: d_name_loc

    ! Variable name and routine name
    IF (PRESENT( d_name)) THEN
      d_name_loc = TRIM(d_name)
    ELSE
      d_name_loc = '?'
    END IF

    ! Inspect data field
    IF     ( ISNAN( d)) THEN
      CALL crash( 'detected NaN in variable "' // TRIM( d_name_loc) // '"')
    ELSEIF (d /= d) THEN
      CALL crash( 'detected NaN in variable "' // TRIM( d_name_loc) // '"')
    ELSEIF (d > HUGE( d)) THEN
      CALL crash( 'detected Inf in variable "' // TRIM( d_name_loc) // '"')
    ELSEIF (d  < -HUGE( d)) THEN
      CALL crash( 'detected -Inf in variable "' // TRIM( d_name_loc) // '"')
    END IF

  END SUBROUTINE check_for_NaN_dp_0D

  SUBROUTINE check_for_NaN_dp_1D(  d, d_name)
    ! Check if NaN values occur in the 1-D dp data field d

    IMPLICIT NONE

    ! Inpit variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    REAL(dp), DIMENSION(:      )                       , INTENT(IN)    :: d
    CHARACTER(LEN=*),                          OPTIONAL, INTENT(IN)    :: d_name

    ! Local variables:
    CHARACTER(LEN=256)                                                 :: d_name_loc
    INTEGER                                                            :: i

    ! Variable name and routine name
    IF (PRESENT( d_name)) THEN
      d_name_loc = TRIM(d_name)
    ELSE
      d_name_loc = '?'
    END IF

    ! Inspect data field
    DO i = 1, SIZE( d,1)

      IF     ( ISNAN( d( i))) THEN
        CALL crash( 'detected NaN in variable "' // TRIM( d_name_loc) // '" at [{int_01}]', int_01 = i)
      ELSEIF (d( i) /= d( i)) THEN
        CALL crash( 'detected NaN in variable "' // TRIM( d_name_loc) // '" at [{int_01}]', int_01 = i)
      ELSEIF (d( i) > HUGE( d( i))) THEN
        CALL crash( 'detected Inf in variable "' // TRIM( d_name_loc) // '" at [{int_01}]', int_01 = i)
      ELSEIF (d( i)  < -HUGE( d( i))) THEN
        CALL crash( 'detected -Inf in variable "' // TRIM( d_name_loc) // '" at [{int_01}]', int_01 = i)
      END IF

    END DO

  END SUBROUTINE check_for_NaN_dp_1D

  SUBROUTINE check_for_NaN_dp_2D(  d, d_name)
    ! Check if NaN values occur in the 2-D dp data field d

    IMPLICIT NONE

    ! Inpit variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    REAL(dp), DIMENSION(:,:    )                       , INTENT(IN)    :: d
    CHARACTER(LEN=*),                          OPTIONAL, INTENT(IN)    :: d_name

    ! Local variables:
    CHARACTER(LEN=256)                                                 :: d_name_loc
    INTEGER                                                            :: i,j

    ! Variable name and routine name
    IF (PRESENT( d_name)) THEN
      d_name_loc = TRIM(d_name)
    ELSE
      d_name_loc = '?'
    END IF

    ! Inspect data field
    DO i = 1, SIZE( d,1)
    DO j = 1, SIZE( d,2)

      IF     ( ISNAN( d( i,j))) THEN
        CALL crash( 'detected NaN in variable "' // TRIM( d_name_loc) // '" at [{int_01},{int_02}]', int_01 = i, int_02 = j)
      ELSEIF (d( i,j) /= d( i,j)) THEN
        CALL crash( 'detected NaN in variable "' // TRIM( d_name_loc) // '" at [{int_01},{int_02}]', int_01 = i, int_02 = j)
      ELSEIF (d( i,j) > HUGE( d( i,j))) THEN
        CALL crash( 'detected Inf in variable "' // TRIM( d_name_loc) // '" at [{int_01},{int_02}]', int_01 = i, int_02 = j)
      ELSEIF (d( i,j)  < -HUGE( d( i,j))) THEN
        CALL crash( 'detected -Inf in variable "' // TRIM( d_name_loc) // '" at [{int_01},{int_02}]', int_01 = i, int_02 = j)
      END IF

    END DO
    END DO

  END SUBROUTINE check_for_NaN_dp_2D

  SUBROUTINE check_for_NaN_dp_3D(  d, d_name)
    ! Check if NaN values occur in the 3-D dp data field d

    IMPLICIT NONE

    ! Inpit variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    REAL(dp), DIMENSION(:,:,:  )                       , INTENT(IN)    :: d
    CHARACTER(LEN=*),                          OPTIONAL, INTENT(IN)    :: d_name

    ! Local variables:
    CHARACTER(LEN=256)                                                 :: d_name_loc
    INTEGER                                                            :: i,j,k

    ! Variable name and routine name
    IF (PRESENT( d_name)) THEN
      d_name_loc = TRIM(d_name)
    ELSE
      d_name_loc = '?'
    END IF

    ! Inspect data field
    DO i = 1, SIZE( d,1)
    DO j = 1, SIZE( d,2)
    DO k = 1, SIZE( d,3)

      IF     ( ISNAN( d( i,j,k))) THEN
        CALL crash( 'detected NaN in variable "' // TRIM( d_name_loc) // '" at [{int_01},{int_02},{int_03}]', int_01 = i, int_02 = j, int_03 = k)
      ELSEIF (d( i,j,k) /= d( i,j,k)) THEN
        CALL crash( 'detected NaN in variable "' // TRIM( d_name_loc) // '" at [{int_01},{int_02},{int_03}]', int_01 = i, int_02 = j, int_03 = k)
      ELSEIF (d( i,j,k) > HUGE( d( i,j,k))) THEN
        CALL crash( 'detected Inf in variable "' // TRIM( d_name_loc) // '" at [{int_01},{int_02},{int_03}]', int_01 = i, int_02 = j, int_03 = k)
      ELSEIF (d( i,j,k)  < -HUGE( d( i,j,k))) THEN
        CALL crash( 'detected -Inf in variable "' // TRIM( d_name_loc) // '" at [{int_01},{int_02},{int_03}]', int_01 = i, int_02 = j, int_03 = k)
      END IF

    END DO
    END DO
    END DO

  END SUBROUTINE check_for_NaN_dp_3D

  SUBROUTINE check_for_NaN_dp_4D(  d, d_name)
    ! Check if NaN values occur in the 4-D dp data field d

    IMPLICIT NONE

    ! Inpit variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    REAL(dp), DIMENSION(:,:,:,:)                       , INTENT(IN)    :: d
    CHARACTER(LEN=*),                          OPTIONAL, INTENT(IN)    :: d_name

    ! Local variables:
    CHARACTER(LEN=256)                                                 :: d_name_loc
    INTEGER                                                            :: i,j,k,r

    ! Variable name and routine name
    IF (PRESENT( d_name)) THEN
      d_name_loc = TRIM(d_name)
    ELSE
      d_name_loc = '?'
    END IF

    ! Inspect data field
    DO i = 1, SIZE( d,1)
    DO j = 1, SIZE( d,2)
    DO k = 1, SIZE( d,3)
    DO r = 1, SIZE( d,4)

      IF     ( ISNAN( d( i,j,k,r))) THEN
        CALL crash( 'detected NaN in variable "' // TRIM( d_name_loc) // '" at [{int_01},{int_02},{int_03},{int_04}]', int_01 = i, int_02 = j, int_03 = k, int_04 = r)
      ELSEIF (d( i,j,k,r) /= d( i,j,k,r)) THEN
        CALL crash( 'detected NaN in variable "' // TRIM( d_name_loc) // '" at [{int_01},{int_02},{int_03},{int_04}]', int_01 = i, int_02 = j, int_03 = k, int_04 = r)
      ELSEIF (d( i,j,k,r) > HUGE( d( i,j,k,r))) THEN
        CALL crash( 'detected Inf in variable "' // TRIM( d_name_loc) // '" at [{int_01},{int_02},{int_03},{int_04}]', int_01 = i, int_02 = j, int_03 = k, int_04 = r)
      ELSEIF (d( i,j,k,r)  < -HUGE( d( i,j,k,r))) THEN
        CALL crash( 'detected -Inf in variable "' // TRIM( d_name_loc) // '" at [{int_01},{int_02},{int_03},{int_04}]', int_01 = i, int_02 = j, int_03 = k, int_04 = r)
      END IF

    END DO
    END DO
    END DO
    END DO

  END SUBROUTINE check_for_NaN_dp_4D

  SUBROUTINE check_for_NaN_int_0D(  d, d_name)
    ! Check if NaN values occur in the 0-D dp data field d

    IMPLICIT NONE

    ! Inpit variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    REAL(dp)                                           , INTENT(IN)    :: d
    CHARACTER(LEN=*),                          OPTIONAL, INTENT(IN)    :: d_name

    ! Local variables:
    CHARACTER(LEN=256)                                                 :: d_name_loc

    ! Variable name and routine name
    IF (PRESENT( d_name)) THEN
      d_name_loc = TRIM(d_name)
    ELSE
      d_name_loc = '?'
    END IF

    ! Inspect data field
    IF     (d /= d) THEN
      CALL crash( 'detected NaN in variable "' // TRIM( d_name_loc) // '"')
    ELSEIF (d > HUGE( d)) THEN
      CALL crash( 'detected Inf in variable "' // TRIM( d_name_loc) // '"')
    ELSEIF (d  < -HUGE( d)) THEN
      CALL crash( 'detected -Inf in variable "' // TRIM( d_name_loc) // '"')
    END IF

  END SUBROUTINE check_for_NaN_int_0D

  SUBROUTINE check_for_NaN_int_1D(  d, d_name)
    ! Check if NaN values occur in the 1-D dp data field d

    IMPLICIT NONE

    ! Inpit variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    INTEGER , DIMENSION(:      )                       , INTENT(IN)    :: d
    CHARACTER(LEN=*),                          OPTIONAL, INTENT(IN)    :: d_name

    ! Local variables:
    CHARACTER(LEN=256)                                                 :: d_name_loc
    INTEGER                                                            :: i

    ! Variable name and routine name
    IF (PRESENT( d_name)) THEN
      d_name_loc = TRIM(d_name)
    ELSE
      d_name_loc = '?'
    END IF

    ! Inspect data field
    DO i = 1, SIZE( d,1)

      IF     (d( i) /= d( i)) THEN
        CALL crash( 'detected NaN in variable "' // TRIM( d_name_loc) // '" at [{int_01}]', int_01 = i)
      ELSEIF (d( i) > HUGE( d( i))) THEN
        CALL crash( 'detected Inf in variable "' // TRIM( d_name_loc) // '" at [{int_01}]', int_01 = i)
      ELSEIF (d( i)  < -HUGE( d( i))) THEN
        CALL crash( 'detected -Inf in variable "' // TRIM( d_name_loc) // '" at [{int_01}]', int_01 = i)
      END IF

    END DO

  END SUBROUTINE check_for_NaN_int_1D

  SUBROUTINE check_for_NaN_int_2D(  d, d_name)
    ! Check if NaN values occur in the 2-D dp data field d

    IMPLICIT NONE

    ! Inpit variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    INTEGER , DIMENSION(:,:    )                       , INTENT(IN)    :: d
    CHARACTER(LEN=*),                          OPTIONAL, INTENT(IN)    :: d_name

    ! Local variables:
    CHARACTER(LEN=256)                                                 :: d_name_loc
    INTEGER                                                            :: i,j

    ! Variable name and routine name
    IF (PRESENT( d_name)) THEN
      d_name_loc = TRIM(d_name)
    ELSE
      d_name_loc = '?'
    END IF

    ! Inspect data field
    DO i = 1, SIZE( d,1)
    DO j = 1, SIZE( d,2)

      IF     (d( i,j) /= d( i,j)) THEN
        CALL crash( 'detected NaN in variable "' // TRIM( d_name_loc) // '" at [{int_01},{int_02}]', int_01 = i, int_02 = j)
      ELSEIF (d( i,j) > HUGE( d( i,j))) THEN
        CALL crash( 'detected Inf in variable "' // TRIM( d_name_loc) // '" at [{int_01},{int_02}]', int_01 = i, int_02 = j)
      ELSEIF (d( i,j)  < -HUGE( d( i,j))) THEN
        CALL crash( 'detected -Inf in variable "' // TRIM( d_name_loc) // '" at [{int_01},{int_02}]', int_01 = i, int_02 = j)
      END IF

    END DO
    END DO

  END SUBROUTINE check_for_NaN_int_2D

  SUBROUTINE check_for_NaN_int_3D(  d, d_name)
    ! Check if NaN values occur in the 3-D dp data field d

    IMPLICIT NONE

    ! Inpit variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    INTEGER , DIMENSION(:,:,:  )                       , INTENT(IN)    :: d
    CHARACTER(LEN=*),                          OPTIONAL, INTENT(IN)    :: d_name

    ! Local variables:
    CHARACTER(LEN=256)                                                 :: d_name_loc
    INTEGER                                                            :: i,j,k

    ! Variable name and routine name
    IF (PRESENT( d_name)) THEN
      d_name_loc = TRIM(d_name)
    ELSE
      d_name_loc = '?'
    END IF

    ! Inspect data field
    DO i = 1, SIZE( d,1)
    DO j = 1, SIZE( d,2)
    DO k = 1, SIZE( d,3)

      IF     (d( i,j,k) /= d( i,j,k)) THEN
        CALL crash( 'detected NaN in variable "' // TRIM( d_name_loc) // '" at [{int_01},{int_02},{int_03}]', int_01 = i, int_02 = j, int_03 = k)
      ELSEIF (d( i,j,k) > HUGE( d( i,j,k))) THEN
        CALL crash( 'detected Inf in variable "' // TRIM( d_name_loc) // '" at [{int_01},{int_02},{int_03}]', int_01 = i, int_02 = j, int_03 = k)
      ELSEIF (d( i,j,k)  < -HUGE( d( i,j,k))) THEN
        CALL crash( 'detected -Inf in variable "' // TRIM( d_name_loc) // '" at [{int_01},{int_02},{int_03}]', int_01 = i, int_02 = j, int_03 = k)
      END IF

    END DO
    END DO
    END DO

  END SUBROUTINE check_for_NaN_int_3D

  SUBROUTINE check_for_NaN_int_4D(  d, d_name)
    ! Check if NaN values occur in the 4-D dp data field d

    IMPLICIT NONE

    ! Inpit variables:
!   REAL(dp), DIMENSION(:,:,:,:), ALLOCATABLE, OPTIONAL, INTENT(INOUT) :: i
    INTEGER , DIMENSION(:,:,:,:)                       , INTENT(IN)    :: d
    CHARACTER(LEN=*),                          OPTIONAL, INTENT(IN)    :: d_name

    ! Local variables:
    CHARACTER(LEN=256)                                                 :: d_name_loc
    INTEGER                                                            :: i,j,k,r

    ! Variable name and routine name
    IF (PRESENT( d_name)) THEN
      d_name_loc = TRIM(d_name)
    ELSE
      d_name_loc = '?'
    END IF

    ! Inspect data field
    DO i = 1, SIZE( d,1)
    DO j = 1, SIZE( d,2)
    DO k = 1, SIZE( d,3)
    DO r = 1, SIZE( d,4)

      IF     (d( i,j,k,r) /= d( i,j,k,r)) THEN
        CALL crash( 'detected NaN in variable "' // TRIM( d_name_loc) // '" at [{int_01},{int_02},{int_03},{int_04}]', int_01 = i, int_02 = j, int_03 = k, int_04 = r)
      ELSEIF (d( i,j,k,r) > HUGE( d( i,j,k,r))) THEN
        CALL crash( 'detected Inf in variable "' // TRIM( d_name_loc) // '" at [{int_01},{int_02},{int_03},{int_04}]', int_01 = i, int_02 = j, int_03 = k, int_04 = r)
      ELSEIF (d( i,j,k,r)  < -HUGE( d( i,j,k,r))) THEN
        CALL crash( 'detected -Inf in variable "' // TRIM( d_name_loc) // '" at [{int_01},{int_02},{int_03},{int_04}]', int_01 = i, int_02 = j, int_03 = k, int_04 = r)
      END IF

    END DO
    END DO
    END DO
    END DO

  END SUBROUTINE check_for_NaN_int_4D

  ! Remapping of a 1-D variable (2nd-order conservative)
  subroutine remap_cons_2nd_order_1D( z_src, mask_src, d_src, z_dst, mask_dst, d_dst)
    ! 2nd-order conservative remapping of a 1-D variable
    !
    ! Used to remap ocean data from the provided vertical grid to the UFEMISM ocean vertical grid
    !
    ! Both z_src and z_dst can be irregular.
    !
    ! Both the src and dst data have a mask, with 0 indicating grid points where no data is defined.
    !
    ! This subroutine is serial, as it will be applied to single grid cells when remapping 3-D data fields,
    !   with the parallelisation being done by distributing the 2-D grid cells over the processes.

    ! In/output variables:
    real(dp), dimension(:    ),          intent(in)    :: z_src
    integer,  dimension(:    ),          intent(in)    :: mask_src
    real(dp), dimension(:    ),          intent(in)    :: d_src
    real(dp), dimension(:    ),          intent(in)    :: z_dst
    integer,  dimension(:    ),          intent(in)    :: mask_dst
    real(dp), dimension(:    ),          intent(out)   :: d_dst

    ! Local variables:
    logical                                            :: all_are_masked
    integer                                            :: nz_src, nz_dst
    integer                                            :: k
    real(dp), dimension(:    ), allocatable            :: ddz_src
    integer                                            :: k_src, k_dst
    real(dp)                                           :: zl_src, zu_src, zl_dst, zu_dst, z_lo, z_hi, z, d
    real(dp)                                           :: dz_overlap, dz_overlap_tot, d_int, d_int_tot
    real(dp)                                           :: dist_to_dst, dist_to_dst_min, max_dist
    integer                                            :: k_src_nearest_to_dst

    ! Initialise
    d_dst = 0._dp

    ! sizes
    nz_src = size( z_src,1)
    nz_dst = size( z_dst,1)

    ! Maximum distance on combined grids
    max_dist = maxval([ abs( z_src( nz_src) - z_src( 1)), &
                        abs( z_dst( nz_dst) - z_dst( 1)), &
                        abs( z_src( nz_src) - z_dst( 1)), &
                        abs( z_dst( nz_dst) - z_src( 1))])

    ! Exception for when the entire src field is masked
    all_are_masked = .true.
    do k = 1, nz_src
      if (mask_src( k) == 1) all_are_masked = .false.
    end do
    if (all_are_masked) return

    ! Exception for when the entire dst field is masked
    all_are_masked = .true.
    do k = 1, nz_dst
      if (mask_dst( k) == 1) all_are_masked = .false.
    end do
    if (all_are_masked) return

    ! Calculate derivative d_src/dz (one-sided differencing at the boundary, central differencing everywhere else)
    allocate( ddz_src( nz_src))
    do k = 2, nz_src-1
      ddz_src( k    ) = (d_src( k+1   ) - d_src( k-1     )) / (z_src( k+1   ) - z_src( k-1     ))
    end do
    ddz_src(  1     ) = (d_src( 2     ) - d_src( 1       )) / (z_src( 2     ) - z_src( 1       ))
    ddz_src(  nz_src) = (d_src( nz_src) - d_src( nz_src-1)) / (z_src( nz_src) - z_src( nz_src-1))

    ! Perform conservative remapping by finding regions of overlap
    ! between source and destination grid cells

    do k_dst = 1, nz_dst

      ! Skip masked grid cells
      if (mask_dst( k_dst) == 0) then
        d_dst( k_dst) = 0._dp
        cycle
      end if

      ! Find z range covered by this dst grid cell
      if (k_dst > 1) then
        zl_dst = 0.5_dp * (z_dst( k_dst - 1) + z_dst( k_dst))
      else
        zl_dst = z_dst( 1) - 0.5_dp * (z_dst( 2) - z_dst( 1))
      end if
      if (k_dst < nz_dst) then
        zu_dst = 0.5_dp * (z_dst( k_dst + 1) + z_dst( k_dst))
      else
        zu_dst = z_dst( nz_dst) + 0.5_dp * (z_dst( nz_dst) - z_dst( nz_dst-1))
      end if

      ! Find all overlapping src grid cells
      d_int_tot      = 0._dp
      dz_overlap_tot = 0._dp
      do k_src = 1, nz_src

        ! Skip masked grid cells
        if (mask_src( k_src) == 0) cycle

        ! Find z range covered by this src grid cell
        if (k_src > 1) then
          zl_src = 0.5_dp * (z_src( k_src - 1) + z_src( k_src))
        else
          zl_src = z_src( 1) - 0.5_dp * (z_src( 2) - z_src( 1))
        end if
        if (k_src < nz_src) then
          zu_src = 0.5_dp * (z_src( k_src + 1) + z_src( k_src))
        else
          zu_src = z_src( nz_src) + 0.5_dp * (z_src( nz_src) - z_src( nz_src-1))
        end if

        ! Find region of overlap
        z_lo = max( zl_src, zl_dst)
        z_hi = min( zu_src, zu_dst)
        dz_overlap = max( 0._dp, z_hi - z_lo)

        ! Calculate integral over region of overlap and add to sum
        if (dz_overlap > 0._dp) then
          z = 0.5_dp * (z_lo + z_hi)
          d = d_src( k_src) + ddz_src( k_src) * (z - z_src( k_src))
          d_int = d * dz_overlap

          d_int_tot      = d_int_tot      + d_int
          dz_overlap_tot = dz_overlap_tot + dz_overlap
        end if

      end do ! do k_src = 1, nz_src

      if (dz_overlap_tot > 0._dp) then
        ! Calculate dst value
        d_dst( k_dst) = d_int_tot / dz_overlap_tot
      else
        ! Exception for when no overlapping src grid cells were found; use nearest-neighbour extrapolation

        k_src_nearest_to_dst = 0._dp
        dist_to_dst_min      = max_dist
        do k_src = 1, nz_src
          if (mask_src( k_src) == 1) then
            dist_to_dst = abs( z_src( k_src) - z_dst( k_dst))
            if (dist_to_dst < dist_to_dst_min) then
              dist_to_dst_min      = dist_to_dst
              k_src_nearest_to_dst = k_src
            end if
          end if
        end do

        ! Safety
        if (k_src_nearest_to_dst == 0) then
          WRITE(0,*) '  remap_cons_2nd_order_1D - ERROR: couldnt find nearest neighbour on source grid!'
          call MPI_ABORT( MPI_COMM_WORLD, cerr, ierr)
        end if

        d_dst( k_dst) = d_src( k_src_nearest_to_dst)

      end if ! if (dz_overlap_tot > 0._dp) then

    end do ! do k_dst = 1, nz_dst

    ! Clean up after yourself
    deallocate( ddz_src)

  end subroutine remap_cons_2nd_order_1D

  subroutine interpolate_inside_triangle_dp_2D( pa, pb, pc, fa, fb, fc, p, f, tol_dist)

    ! In/output variables
    real(dp), dimension(2), intent(in   ) :: pa, pb, pc
    real(dp),               intent(in   ) :: fa, fb, fc
    real(dp), dimension(2), intent(in   ) :: p
    real(dp),               intent(  out) :: f
    real(dp),               intent(in   ) :: tol_dist

    ! Local variables
    real(dp) :: Atri_abp, Atri_bcp, Atri_cap, Atri_tot, wa, wb, wc

#if (DO_ASSERTIONS)
    call assert( is_in_triangle( pa, pb, pc, p) .or. &
      lies_on_line_segment( pa, pb, p, tol_dist) .or. &
      lies_on_line_segment( pb, pc, p, tol_dist) .or. &
      lies_on_line_segment( pc, pa, p, tol_dist) .or. &
      norm2( pa - p) <= tol_dist .or. &
      norm2( pb - p) <= tol_dist .or. &
      norm2( pc - p) <= tol_dist, 'p does not lie in triangle')
#endif

    ! If p coincides with a, b, or c, copy f from there
    if (norm2( pa - p) <= tol_dist) then
      f = fa
    elseif (norm2( pb - p) <= tol_dist) then
      f = fb
    elseif (norm2( pc - p) <= tol_dist) then
      f = fc

    ! If p lies on one of the three edges, interpolate between its two vertices
    elseif (lies_on_line_segment( pa, pb, p, tol_dist)) then
      wa = norm2( pb - p) / norm2( pb - pa)
      wb = 1._dp - wa
      f = wa * fa + wb * fb
    elseif (lies_on_line_segment( pb, pc, p, tol_dist)) then
      wb = norm2( pc - p) / norm2( pc - pb)
      wc = 1._dp - wb
      f = wb * fb + wc * fc
    elseif (lies_on_line_segment( pc, pa, p, tol_dist)) then
      wc = norm2( pa - p) / norm2( pa - pc)
      wa = 1._dp - wc
      f = wc * fc + wa * fa

    ! Otherwise, p lies inside the triangle; do a trilinear interpolation
    else
      Atri_abp = triangle_area( pa, pb, p)
      Atri_bcp = triangle_area( pb, pc, p)
      Atri_cap = triangle_area( pc, pa, p)
      Atri_tot = Atri_abp + Atri_bcp + Atri_cap
      wa = Atri_bcp / Atri_tot
      wb = Atri_cap / Atri_tot
      wc = Atri_abp / Atri_tot
      f = wa * fa + wb * fb + wc * fc
    end if

  end subroutine interpolate_inside_triangle_dp_2D

  subroutine interpolate_inside_triangle_dp_3D( pa, pb, pc, fa, fb, fc, p, f, tol_dist)
    ! In/output variables
    real(dp), dimension(2), intent(in   ) :: pa, pb, pc
    real(dp), dimension(:), intent(in   ) :: fa, fb, fc
    real(dp), dimension(2), intent(in   ) :: p
    real(dp), dimension(:), intent(  out) :: f
    real(dp),               intent(in   ) :: tol_dist
    ! Local variables
    real(dp) :: Atri_abp, Atri_bcp, Atri_cap, Atri_tot, wa, wb, wc

#if (DO_ASSERTIONS)
    call assert( is_in_triangle( pa, pb, pc, p) .or. &
      lies_on_line_segment( pa, pb, p, tol_dist) .or. &
      lies_on_line_segment( pb, pc, p, tol_dist) .or. &
      lies_on_line_segment( pc, pa, p, tol_dist) .or. &
      norm2( pa - p) <= tol_dist .or. &
      norm2( pb - p) <= tol_dist .or. &
      norm2( pc - p) <= tol_dist, 'p does not lie in triangle')
    call assert( size( fa) == size( fb) .and. size( fb) == size( fc) .and. size( fc) == size( f), &
      'incorrect input dimensions')
#endif

    ! If p coincides with a, b, or c, copy f from there
    if (norm2( pa - p) <= tol_dist) then
      f = fa
    elseif (norm2( pb - p) <= tol_dist) then
      f = fb
    elseif (norm2( pc - p) <= tol_dist) then
      f = fc

    ! If p lies on one of the three edges, interpolate between its two vertices
    elseif (lies_on_line_segment( pa, pb, p, tol_dist)) then
      wa = norm2( pb - p) / norm2( pb - pa)
      wb = 1._dp - wa
      f = wa * fa + wb * fb
    elseif (lies_on_line_segment( pb, pc, p, tol_dist)) then
      wb = norm2( pc - p) / norm2( pc - pb)
      wc = 1._dp - wb
      f = wb * fb + wc * fc
    elseif (lies_on_line_segment( pc, pa, p, tol_dist)) then
      wc = norm2( pa - p) / norm2( pa - pc)
      wa = 1._dp - wc
      f = wc * fc + wa * fa

    ! Otherwise, p lies inside the triangle; do a trilinear interpolation
    else
      Atri_abp = triangle_area( pa, pb, p)
      Atri_bcp = triangle_area( pb, pc, p)
      Atri_cap = triangle_area( pc, pa, p)
      Atri_tot = Atri_abp + Atri_bcp + Atri_cap
      wa = Atri_bcp / Atri_tot
      wb = Atri_cap / Atri_tot
      wc = Atri_abp / Atri_tot
      f = wa * fa + wb * fb + wc * fc
    end if

  end subroutine interpolate_inside_triangle_dp_3D

END MODULE math_utilities
