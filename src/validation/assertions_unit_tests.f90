module assertions_unit_tests

  ! The main assertions/unit tests module.
  !
  ! The "test_XX" generic interfaces choose the appropriate subroutines automatically.
  !
  ! The user must provide the "test_mode" inoput variable, which should equal either
  ! ASSERTION or UNIT_TEST (which can be imported from thsi module). ASSERTION will
  ! crash the model if the test fails; UNIT_TEST will not crash the model, but will
  ! write the test result (both pass and fail) to output.
  !
  ! test_tol is also defined for several derived types, including CSR-type matrices,\
  ! x/y-grids, lon/lat-grids, and meshes

  use assertions_unit_tests_basic, only: ASSERTION, UNIT_TEST, process_test_result
  use assertions_unit_tests_logical
  use assertions_unit_tests_int
  use assertions_unit_tests_dp
  use assertions_unit_tests_CSR
  use assertions_unit_tests_grid
  use assertions_unit_tests_grid_lonlat
  use assertions_unit_tests_mesh

  implicit none

  private

  public :: ASSERTION, UNIT_TEST
  public :: test_eqv, test_neqv, test_eq, test_neq, test_gt, test_lt, test_ge, test_le, test_ge_le, test_tol
  public :: test_eq_permute, test_tol_mesh, test_mesh_is_self_consistent

  ! Generic interfaces to specific test routines
  ! ============================================

  !> Test if a .eqv. b
  interface test_eqv
  procedure test_eqv_logical_0D
  procedure test_eqv_logical_1D_scalar, test_eqv_logical_1D_array
  procedure test_eqv_logical_2D_scalar, test_eqv_logical_2D_array
  procedure test_eqv_logical_3D_scalar, test_eqv_logical_3D_array
  procedure test_eqv_logical_4D_scalar, test_eqv_logical_4D_array
end interface test_eqv

!> Test if a .neqv. b
interface test_neqv
  procedure test_neqv_logical_0D
  procedure test_neqv_logical_1D_scalar, test_neqv_logical_1D_array
  procedure test_neqv_logical_2D_scalar, test_neqv_logical_2D_array
  procedure test_neqv_logical_3D_scalar, test_neqv_logical_3D_array
  procedure test_neqv_logical_4D_scalar, test_neqv_logical_4D_array
end interface test_neqv

  !> Test if a == b
  interface test_eq
    ! Integer
    procedure test_eq_int_0D
    procedure test_eq_int_1D_scalar, test_eq_int_1D_array
    procedure test_eq_int_2D_scalar, test_eq_int_2D_array
    procedure test_eq_int_3D_scalar, test_eq_int_3D_array
    procedure test_eq_int_4D_scalar, test_eq_int_4D_array
    ! Double precision
    procedure test_eq_dp_0D
    procedure test_eq_dp_1D_scalar, test_eq_dp_1D_array
    procedure test_eq_dp_2D_scalar, test_eq_dp_2D_array
    procedure test_eq_dp_3D_scalar, test_eq_dp_3D_array
    procedure test_eq_dp_4D_scalar, test_eq_dp_4D_array
  end interface test_eq

  !> Test if a /= b
  interface test_neq
  ! Integer
    procedure test_neq_int_0D
    procedure test_neq_int_1D_scalar, test_neq_int_1D_array
    procedure test_neq_int_2D_scalar, test_neq_int_2D_array
    procedure test_neq_int_3D_scalar, test_neq_int_3D_array
    procedure test_neq_int_4D_scalar, test_neq_int_4D_array
    ! Double precision
    procedure test_neq_dp_0D
    procedure test_neq_dp_1D_scalar, test_neq_dp_1D_array
    procedure test_neq_dp_2D_scalar, test_neq_dp_2D_array
    procedure test_neq_dp_3D_scalar, test_neq_dp_3D_array
    procedure test_neq_dp_4D_scalar, test_neq_dp_4D_array
  end interface test_neq

  !> Test if a > b
  interface test_gt
  ! Integer
    procedure test_gt_int_0D
    procedure test_gt_int_1D_scalar, test_gt_int_1D_array
    procedure test_gt_int_2D_scalar, test_gt_int_2D_array
    procedure test_gt_int_3D_scalar, test_gt_int_3D_array
    procedure test_gt_int_4D_scalar, test_gt_int_4D_array
    ! Double precision
    procedure test_gt_dp_0D
    procedure test_gt_dp_1D_scalar, test_gt_dp_1D_array
    procedure test_gt_dp_2D_scalar, test_gt_dp_2D_array
    procedure test_gt_dp_3D_scalar, test_gt_dp_3D_array
    procedure test_gt_dp_4D_scalar, test_gt_dp_4D_array
  end interface test_gt

  !> Test if a < b
  interface test_lt
  ! Integer
    procedure test_lt_int_0D
    procedure test_lt_int_1D_scalar, test_lt_int_1D_array
    procedure test_lt_int_2D_scalar, test_lt_int_2D_array
    procedure test_lt_int_3D_scalar, test_lt_int_3D_array
    procedure test_lt_int_4D_scalar, test_lt_int_4D_array
    ! Double precision
    procedure test_lt_dp_0D
    procedure test_lt_dp_1D_scalar, test_lt_dp_1D_array
    procedure test_lt_dp_2D_scalar, test_lt_dp_2D_array
    procedure test_lt_dp_3D_scalar, test_lt_dp_3D_array
    procedure test_lt_dp_4D_scalar, test_lt_dp_4D_array
  end interface test_lt

  !> Test if a >= b
  interface test_ge
  ! Integer
    procedure test_ge_int_0D
    procedure test_ge_int_1D_scalar, test_ge_int_1D_array
    procedure test_ge_int_2D_scalar, test_ge_int_2D_array
    procedure test_ge_int_3D_scalar, test_ge_int_3D_array
    procedure test_ge_int_4D_scalar, test_ge_int_4D_array
    ! Double precision
    procedure test_ge_dp_0D
    procedure test_ge_dp_1D_scalar, test_ge_dp_1D_array
    procedure test_ge_dp_2D_scalar, test_ge_dp_2D_array
    procedure test_ge_dp_3D_scalar, test_ge_dp_3D_array
    procedure test_ge_dp_4D_scalar, test_ge_dp_4D_array
  end interface test_ge

  !> Test if a <= b
  interface test_le
  ! Integer
    procedure test_le_int_0D
    procedure test_le_int_1D_scalar, test_le_int_1D_array
    procedure test_le_int_2D_scalar, test_le_int_2D_array
    procedure test_le_int_3D_scalar, test_le_int_3D_array
    procedure test_le_int_4D_scalar, test_le_int_4D_array
    ! Double precision
    procedure test_le_dp_0D
    procedure test_le_dp_1D_scalar, test_le_dp_1D_array
    procedure test_le_dp_2D_scalar, test_le_dp_2D_array
    procedure test_le_dp_3D_scalar, test_le_dp_3D_array
    procedure test_le_dp_4D_scalar, test_le_dp_4D_array
  end interface test_le

  !> Test if a >= b1 && a <= b2
  interface test_ge_le
  ! Integer
    procedure test_ge_le_int_0D
    procedure test_ge_le_int_1D_scalar, test_ge_le_int_1D_array
    procedure test_ge_le_int_2D_scalar, test_ge_le_int_2D_array
    procedure test_ge_le_int_3D_scalar, test_ge_le_int_3D_array
    procedure test_ge_le_int_4D_scalar, test_ge_le_int_4D_array
    ! Double precision
    procedure test_ge_le_dp_0D
    procedure test_ge_le_dp_1D_scalar, test_ge_le_dp_1D_array
    procedure test_ge_le_dp_2D_scalar, test_ge_le_dp_2D_array
    procedure test_ge_le_dp_3D_scalar, test_ge_le_dp_3D_array
    procedure test_ge_le_dp_4D_scalar, test_ge_le_dp_4D_array
  end interface test_ge_le

  !> Test if a >= (b - tol) && a <= (b + tol)
  interface test_tol
  ! Integer
    procedure test_tol_int_0D
    procedure test_tol_int_1D_scalar, test_tol_int_1D_array
    procedure test_tol_int_2D_scalar, test_tol_int_2D_array
    procedure test_tol_int_3D_scalar, test_tol_int_3D_array
    procedure test_tol_int_4D_scalar, test_tol_int_4D_array
    ! Double precision
    procedure test_tol_dp_0D
    procedure test_tol_dp_1D_scalar, test_tol_dp_1D_array
    procedure test_tol_dp_2D_scalar, test_tol_dp_2D_array
    procedure test_tol_dp_3D_scalar, test_tol_dp_3D_array
    procedure test_tol_dp_4D_scalar, test_tol_dp_4D_array
    ! Derived types
    procedure test_tol_CSR
    procedure test_tol_grid
    procedure test_tol_grid_lonlat
    procedure test_tol_mesh
  end interface test_tol

  !> Test if a(:) == b(:) for any cyclical permutation of a(:)
  !> (used e.g. for comparing triangle-vertex lists between meshes)
  interface test_eq_permute
    procedure test_eq_permute_int_1D
  end interface test_eq_permute

contains

end module assertions_unit_tests