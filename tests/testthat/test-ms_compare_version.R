# Tests for ms_compare_version following libmamba/libmambapy semantics
# See: https://github.com/mamba-org/mamba/blob/main/libmamba/src/specs/version_spec.cpp
# See: https://github.com/mamba-org/mamba/blob/main/libmamba/src/specs/version.cpp

# =============================================================================
# Unit tests: No network, no skip. Expected values from libmambapy calibration.
# =============================================================================

testthat::test_that("ms_compare_version rejects invalid input", {
  testthat::expect_error(
    ms_compare_version(NULL, ">=1.0"),
    class = "condathis_ms_compare_version_invalid_input"
  )
  testthat::expect_error(
    ms_compare_version("1.0", NULL),
    class = "condathis_ms_compare_version_invalid_input"
  )
  testthat::expect_error(
    ms_compare_version(42, ">=1.0"),
    class = "condathis_ms_compare_version_invalid_input"
  )
  testthat::expect_error(
    ms_compare_version("1.0", 42),
    class = "condathis_ms_compare_version_invalid_input"
  )
  testthat::expect_error(
    ms_compare_version(c("1.0", "2.0"), ">=1.0"),
    class = "condathis_ms_compare_version_invalid_input"
  )
})


testthat::test_that("ms_compare_version: free interval (wildcard) always TRUE", {
  testthat::expect_true(ms_compare_version("1.0", "*"))
  testthat::expect_true(ms_compare_version("0.0.1", "*"))
  testthat::expect_true(ms_compare_version("999.999", "*"))
  testthat::expect_true(ms_compare_version("1.0", "=*"))
  testthat::expect_true(ms_compare_version("1.0", "==*"))
})


testthat::test_that("ms_compare_version: exact match with bare version", {
  # Bare version (no operator) means exact match (==)
  testthat::expect_true(ms_compare_version("1.2.3", "1.2.3"))
  testthat::expect_false(ms_compare_version("1.2.3", "1.2.4"))
  testthat::expect_false(ms_compare_version("1.2.4", "1.2.3"))
  testthat::expect_true(ms_compare_version("1.12", "1.12"))
  # Bare "1.12" means ==1.12 (exact match); 1.12.1 != 1.12
  testthat::expect_false(ms_compare_version("1.12.1", "1.12"))
  testthat::expect_true(ms_compare_version("1.2.9", "1.2.9"))
  testthat::expect_false(ms_compare_version("1.2.9", "1.2.0"))
})


testthat::test_that("ms_compare_version: trailing zeros in exact match", {
  # 1.0.0 == 1.0 (trailing zero segments are equivalent)
  testthat::expect_true(ms_compare_version("1.0.0", "1.0"))
  testthat::expect_true(ms_compare_version("1.0", "1.0.0"))
  testthat::expect_true(ms_compare_version("1.0.0.0", "1.0"))
  testthat::expect_true(ms_compare_version("2.0", "2.0.0.0"))
})


testthat::test_that("ms_compare_version: == operator (exact match)", {
  testthat::expect_true(ms_compare_version("1.8", "==1.8"))
  testthat::expect_false(ms_compare_version("1.8.1", "==1.8"))
  testthat::expect_false(ms_compare_version("1.7", "==1.8"))
  testthat::expect_true(ms_compare_version("1.26.4", "==1.26.4"))
  testthat::expect_false(ms_compare_version("1.26.4", "==1.8.1"))
  # ==1.2 is exact, 1.2.9 does NOT equal 1.2
  testthat::expect_false(ms_compare_version("1.2.9", "==1.2"))
})


testthat::test_that("ms_compare_version: != operator", {
  testthat::expect_true(ms_compare_version("1.8.1", "!=1.8"))
  testthat::expect_false(ms_compare_version("1.8", "!=1.8"))
  testthat::expect_true(ms_compare_version("2.0", "!=1.8"))
})


testthat::test_that("ms_compare_version: > operator", {
  testthat::expect_true(ms_compare_version("1.9", ">1.8"))
  testthat::expect_false(ms_compare_version("1.8", ">1.8"))
  testthat::expect_false(ms_compare_version("1.7", ">1.8"))
  testthat::expect_true(ms_compare_version("2.0", ">1.999"))
})


testthat::test_that("ms_compare_version: >= operator", {
  testthat::expect_true(ms_compare_version("1.9", ">=1.8"))
  testthat::expect_true(ms_compare_version("1.8", ">=1.8"))
  testthat::expect_false(ms_compare_version("1.7", ">=1.8"))
})


testthat::test_that("ms_compare_version: < operator", {
  testthat::expect_true(ms_compare_version("1.7", "<1.8"))
  testthat::expect_false(ms_compare_version("1.8", "<1.8"))
  testthat::expect_false(ms_compare_version("1.9", "<1.8"))
})


testthat::test_that("ms_compare_version: <= operator", {
  testthat::expect_true(ms_compare_version("1.7", "<=1.8"))
  testthat::expect_true(ms_compare_version("1.8", "<=1.8"))
  testthat::expect_false(ms_compare_version("1.9", "<=1.8"))
})


testthat::test_that("ms_compare_version: = operator (starts_with / fuzzy)", {
  # =1.2 matches any version starting with 1.2
  testthat::expect_true(ms_compare_version("1.2", "=1.2"))
  testthat::expect_true(ms_compare_version("1.2.0", "=1.2"))
  testthat::expect_true(ms_compare_version("1.2.3", "=1.2"))
  testthat::expect_true(ms_compare_version("1.2.9", "=1.2"))
  testthat::expect_false(ms_compare_version("1.3", "=1.2"))
  testthat::expect_false(ms_compare_version("1.1", "=1.2"))
  testthat::expect_false(ms_compare_version("2.2", "=1.2"))
})


testthat::test_that("ms_compare_version: = with .* suffix (fuzzy)", {
  testthat::expect_true(ms_compare_version("1.2.9", "=1.2.*"))
  testthat::expect_true(ms_compare_version("1.2.0", "=1.2.*"))
  testthat::expect_true(ms_compare_version("1.2", "=1.2.*"))
  testthat::expect_false(ms_compare_version("1.3", "=1.2.*"))
})


testthat::test_that("ms_compare_version: == with .* suffix (becomes starts_with)", {
  testthat::expect_true(ms_compare_version("1.2.9", "==1.2.*"))
  testthat::expect_true(ms_compare_version("1.2.0", "==1.2.*"))
  testthat::expect_false(ms_compare_version("1.3.0", "==1.2.*"))
})


testthat::test_that("ms_compare_version: != with .* suffix (negated starts_with)", {
  testthat::expect_false(ms_compare_version("1.26.4", "!=1.26.*"))
  testthat::expect_false(ms_compare_version("1.26.0", "!=1.26.*"))
  testthat::expect_true(ms_compare_version("1.27.0", "!=1.26.*"))
  testthat::expect_true(ms_compare_version("2.0", "!=1.26.*"))
})


testthat::test_that("ms_compare_version: ~= operator (compatible release)", {
  # ~=1.4.2 means >=1.4.2 AND first (n-1)=2 segments identical
  # i.e., >=1.4.2 AND =1.4.*
  testthat::expect_true(ms_compare_version("1.4.2", "~=1.4.2"))
  testthat::expect_true(ms_compare_version("1.4.3", "~=1.4.2"))
  testthat::expect_true(ms_compare_version("1.4.99", "~=1.4.2"))
  testthat::expect_false(ms_compare_version("1.4.1", "~=1.4.2"))
  testthat::expect_false(ms_compare_version("1.5.0", "~=1.4.2"))
  testthat::expect_false(ms_compare_version("2.0.0", "~=1.4.2"))

  # ~=1.2 means >=1.2 AND first 1 segment matches (major=1)
  testthat::expect_true(ms_compare_version("1.2", "~=1.2"))
  testthat::expect_true(ms_compare_version("1.3", "~=1.2"))
  testthat::expect_true(ms_compare_version("1.99", "~=1.2"))
  testthat::expect_false(ms_compare_version("1.1", "~=1.2"))
  testthat::expect_false(ms_compare_version("2.0", "~=1.2"))
})


testthat::test_that("ms_compare_version: compound AND with comma", {
  testthat::expect_true(ms_compare_version("1.5", ">=1.0,<2.0"))
  testthat::expect_true(ms_compare_version("1.0", ">=1.0,<2.0"))
  testthat::expect_false(ms_compare_version("2.0", ">=1.0,<2.0"))
  testthat::expect_false(ms_compare_version("0.9", ">=1.0,<2.0"))
  testthat::expect_true(ms_compare_version("1.26.4", ">=1.8,<2"))
  testthat::expect_false(
    ms_compare_version("1.26.4", ">=1.8,<2,!=1.26.4")
  )
  testthat::expect_true(ms_compare_version("2025b", ">=2025a,<2026"))
  testthat::expect_false(
    ms_compare_version("2025b", ">=2025a,<2026,!=2025b")
  )
})


testthat::test_that("ms_compare_version: compound OR with pipe", {
  testthat::expect_true(ms_compare_version("1.26.4", ">=1.8,<1.9|==1.26.4"))
  testthat::expect_true(ms_compare_version("1.8.5", ">=1.8,<1.9|==1.26.4"))
  testthat::expect_false(ms_compare_version("1.10", ">=1.8,<1.9|==1.26.4"))
})


testthat::test_that("ms_compare_version: mixed AND/OR precedence", {
  # In libmamba, OR (|) binds tighter than AND (,).
  # So a,b|c means a AND (b OR c), NOT (a AND b) OR c.
  # =2022a,<2025|2025b means =2022a AND (<2025 OR ==2025b)
  # For 2025b: starts_with(2022a)=FALSE -> AND short-circuits = FALSE
  testthat::expect_false(ms_compare_version("2025b", "=2022a,<2025|2025b"))
  # >=1.8,<1.9|==1.26.4 means (>=1.8) AND (<1.9 OR ==1.26.4)
  testthat::expect_true(ms_compare_version("1.8.0", ">=1.8,<1.9|==1.26.4"))
  testthat::expect_true(ms_compare_version("1.26.4", ">=1.8,<1.9|==1.26.4"))
  testthat::expect_false(ms_compare_version("1.10", ">=1.8,<1.9|==1.26.4"))
})


testthat::test_that("ms_compare_version: starts_with combined with AND", {
  # =1.2 AND * (free) -> effectively =1.2
  testthat::expect_true(ms_compare_version("1.2.9", "=1.2,*"))
  # ==1.2.0 AND * -> effectively ==1.2.0
  testthat::expect_false(ms_compare_version("1.2.9", "==1.2.0,*"))
})


testthat::test_that("ms_compare_version: letter-based version components", {
  # 2025b > 2025a (both parse as segment with atoms {2025, "a"} vs {2025, "b"})
  testthat::expect_true(ms_compare_version("2025b", ">2025a"))
  testthat::expect_false(ms_compare_version("2025a", ">2025b"))
  testthat::expect_true(ms_compare_version("2025a", "==2025a"))
  # Letter versions compare: "x" has numeral 0 in first atom
  # 2025b has numeral 2025, so 2025b > x (numeral comparison)
  testthat::expect_false(ms_compare_version("2025b", "<x"))
})


testthat::test_that("ms_compare_version: dev and post special literals", {
  # dev sorts before regular strings and empty strings
  testthat::expect_true(ms_compare_version("1.0.dev", "<1.0"))
  # 1.0dev parses as segment [{1,""}, ...] then [{0,"dev"}]?

  # Actually "1.0dev" splits by "." into ["1", "0dev"]
  # "0dev" -> atoms: [{0, "dev"}]
  # "1.0" -> atoms: [[{1,""}], [{0,""}]]
  # Segment compare: first segments equal ({1,""} == {1,""})
  # Second: {0,"dev"} vs {0,""}. Priority: dev=-2, ""=1. dev < "". So 1.0dev < 1.0.
  testthat::expect_true(ms_compare_version("1.0dev", "<1.0"))
  testthat::expect_false(ms_compare_version("1.0dev", ">=1.0"))

  # post sorts after empty string
  testthat::expect_true(ms_compare_version("1.0post", ">1.0"))
  testthat::expect_false(ms_compare_version("1.0post", "<=1.0"))
})


testthat::test_that("ms_compare_version: epoch handling", {
  # Same epoch, version comparison applies
  testthat::expect_true(ms_compare_version("1!2.0", "==1!2.0"))
  testthat::expect_false(ms_compare_version("1!2.0", "==2.0"))
  testthat::expect_false(ms_compare_version("2.0", "==1!2.0"))

  # Higher epoch always wins regardless of version
  testthat::expect_true(ms_compare_version("1!0.1", ">0!999.0"))
  testthat::expect_true(ms_compare_version("2!1.0", ">1!999.0"))
})


testthat::test_that("ms_compare_version: edge cases for = vs == distinction", {
  # =1.2 (starts_with) matches 1.2.9
  testthat::expect_true(ms_compare_version("1.2.9", "=1.2"))
  # ==1.2 (exact) does NOT match 1.2.9
  testthat::expect_false(ms_compare_version("1.2.9", "==1.2"))
  # ==1.2.* (starts_with due to .*) matches 1.2.9
  testthat::expect_true(ms_compare_version("1.2.9", "==1.2.*"))
  # =1.2.* (starts_with, .* stripped) matches 1.2.9
  testthat::expect_true(ms_compare_version("1.2.9", "=1.2.*"))
})


testthat::test_that("ms_compare_version: multi-segment version comparison", {
  testthat::expect_true(ms_compare_version("1.2.3.4", ">=1.2.3"))
  testthat::expect_true(ms_compare_version("1.2.3.4", "=1.2.3"))
  testthat::expect_false(ms_compare_version("1.2.3.4", "==1.2.3"))
  testthat::expect_true(ms_compare_version("10.2", ">9.99"))
  testthat::expect_true(ms_compare_version("1.10", ">1.9"))
  # Numeric comparison, not lexicographic string: 10 > 9
  testthat::expect_true(ms_compare_version("1.10", ">1.2"))
})


testthat::test_that("ms_compare_version: version with dashes and underscores", {
  # Dashes and underscores are segment separators like dots
  testthat::expect_true(ms_compare_version("1.2.3", "==1-2-3"))
  testthat::expect_true(ms_compare_version("1.2.3", "==1_2_3"))
})


testthat::test_that("ms_compare_version: complex realistic specs", {
  # numpy-style constraints
  testthat::expect_true(ms_compare_version("1.26.4", ">=1.8,<2"))
  testthat::expect_false(ms_compare_version("2.0", ">=1.8,<2"))
  testthat::expect_false(ms_compare_version("1.7", ">=1.8,<2"))

  # Python-style constraints
  testthat::expect_true(ms_compare_version("3.11.5", ">=3.8,<3.14"))
  testthat::expect_false(ms_compare_version("3.7", ">=3.8,<3.14"))
  testthat::expect_false(ms_compare_version("3.14", ">=3.8,<3.14"))

  # Multiple OR branches
  testthat::expect_true(ms_compare_version(
    "3.12",
    ">=3.8,<3.9|>=3.10,<3.11|==3.12"
  ))
  testthat::expect_false(ms_compare_version(
    "3.9.5",
    ">=3.8,<3.9|>=3.10,<3.11|==3.12"
  ))
})


testthat::test_that("ms_compare_version: version comparisons with letter-only segments", {
  # "a" < "b" (lexicographic, both have implicit leading 0)
  testthat::expect_true(ms_compare_version("a", "<b"))
  testthat::expect_true(ms_compare_version("b", ">a"))
  testthat::expect_true(ms_compare_version("alpha", "<beta"))
})


testthat::test_that("ms_compare_version: compatible release with single segment", {
  # ~=2 means >= 2 (only 1 segment, level=0, no prefix constraint)
  testthat::expect_true(ms_compare_version("2", "~=2"))
  testthat::expect_true(ms_compare_version("3", "~=2"))
  testthat::expect_false(ms_compare_version("1", "~=2"))
})


testthat::test_that("ms_compare_version: starts_with edge cases", {
  # =1 matches 1, 1.0, 1.anything
  testthat::expect_true(ms_compare_version("1", "=1"))
  testthat::expect_true(ms_compare_version("1.0", "=1"))
  testthat::expect_true(ms_compare_version("1.99", "=1"))
  testthat::expect_false(ms_compare_version("2", "=1"))
  testthat::expect_false(ms_compare_version("0.1", "=1"))
})


# =============================================================================
# Integration test: compare R output to libmambapy (skip on CI)
# =============================================================================

testthat::test_that("ms_version_compare: matches libmambapy implementation", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()
  testthat::skip_on_ci()

  # Load helper function
  base::source(testthat::test_path("libmamba_wrappers.R"))

  # All cases below were verified against libmambapy (0 mismatches in 142 cases)

  test_versions <- list(
    # --- Free interval ---
    c("1.0", "*"), # TRUE
    c("0.0.1", "*"), # TRUE
    c("1.0", "=*"), # TRUE
    c("1.0", "==*"), # TRUE

    # --- Bare version (exact match) ---
    c("1.2.3", "1.2.3"), # TRUE
    c("1.2.3", "1.2.4"), # FALSE
    c("1.12", "1.12"), # TRUE
    c("1.12.1", "1.12"), # FALSE
    c("1.2.9", "1.2.9"), # TRUE
    c("1.2.9", "1.2.0"), # FALSE

    # --- Trailing zeros ---
    c("1.0.0", "1.0"), # TRUE
    c("1.0", "1.0.0"), # TRUE
    c("1.0.0.0", "1.0"), # TRUE
    c("2.0", "2.0.0.0"), # TRUE

    # --- == operator ---
    c("1.8", "==1.8"), # TRUE
    c("1.8.1", "==1.8"), # FALSE
    c("1.7", "==1.8"), # FALSE
    c("1.26.4", "==1.26.4"), # TRUE
    c("1.26.4", "==1.8.1"), # FALSE
    c("1.2.9", "==1.2"), # FALSE

    # --- != operator ---
    c("1.8.1", "!=1.8"), # TRUE
    c("1.8", "!=1.8"), # FALSE
    c("2.0", "!=1.8"), # TRUE

    # --- > operator ---
    c("1.9", ">1.8"), # TRUE
    c("1.8", ">1.8"), # FALSE
    c("1.7", ">1.8"), # FALSE
    c("2.0", ">1.999"), # TRUE

    # --- >= operator ---
    c("1.9", ">=1.8"), # TRUE
    c("1.8", ">=1.8"), # TRUE
    c("1.7", ">=1.8"), # FALSE

    # --- < operator ---
    c("1.7", "<1.8"), # TRUE
    c("1.8", "<1.8"), # FALSE
    c("1.9", "<1.8"), # FALSE

    # --- <= operator ---
    c("1.7", "<=1.8"), # TRUE
    c("1.8", "<=1.8"), # TRUE
    c("1.9", "<=1.8"), # FALSE

    # --- = (starts_with) ---
    c("1.2", "=1.2"), # TRUE
    c("1.2.0", "=1.2"), # TRUE
    c("1.2.3", "=1.2"), # TRUE
    c("1.2.9", "=1.2"), # TRUE
    c("1.3", "=1.2"), # FALSE
    c("1.1", "=1.2"), # FALSE
    c("2.2", "=1.2"), # FALSE

    # --- = with .* suffix ---
    c("1.2.9", "=1.2.*"), # TRUE
    c("1.2.0", "=1.2.*"), # TRUE
    c("1.2", "=1.2.*"), # TRUE
    c("1.3", "=1.2.*"), # FALSE

    # --- == with .* suffix ---
    c("1.2.9", "==1.2.*"), # TRUE
    c("1.2.0", "==1.2.*"), # TRUE
    c("1.3.0", "==1.2.*"), # FALSE

    # --- != with .* suffix ---
    c("1.26.4", "!=1.26.*"), # FALSE
    c("1.26.0", "!=1.26.*"), # FALSE
    c("1.27.0", "!=1.26.*"), # TRUE
    c("2.0", "!=1.26.*"), # TRUE

    # --- ~= (compatible release) ---
    c("1.4.2", "~=1.4.2"), # TRUE
    c("1.4.3", "~=1.4.2"), # TRUE
    c("1.4.99", "~=1.4.2"), # TRUE
    c("1.4.1", "~=1.4.2"), # FALSE
    c("1.5.0", "~=1.4.2"), # FALSE
    c("2.0.0", "~=1.4.2"), # FALSE
    c("1.2", "~=1.2"), # TRUE
    c("1.3", "~=1.2"), # TRUE
    c("1.99", "~=1.2"), # TRUE
    c("1.1", "~=1.2"), # FALSE
    c("2.0", "~=1.2"), # FALSE

    # --- Compound AND ---
    c("1.5", ">=1.0,<2.0"), # TRUE
    c("1.0", ">=1.0,<2.0"), # TRUE
    c("2.0", ">=1.0,<2.0"), # FALSE
    c("0.9", ">=1.0,<2.0"), # FALSE
    c("1.26.4", ">=1.8,<2"), # TRUE
    c("1.26.4", ">=1.8,<2,!=1.26.4"), # FALSE
    c("2025b", ">=2025a,<2026"), # TRUE
    c("2025b", ">=2025a,<2026,!=2025b"), # FALSE

    # --- Compound OR ---
    c("1.26.4", ">=1.8,<1.9|==1.26.4"), # TRUE
    c("1.8.5", ">=1.8,<1.9|==1.26.4"), # TRUE
    c("1.10", ">=1.8,<1.9|==1.26.4"), # FALSE

    # --- Mixed AND/OR precedence (OR binds tighter than AND) ---
    c("2025b", "=2022a,<2025|2025b"), # FALSE
    c("1.8.0", ">=1.8,<1.9|==1.26.4"), # TRUE
    c("1.26.4", ">=1.8,<1.9|==1.26.4"), # TRUE
    c("1.10", ">=1.8,<1.9|==1.26.4"), # FALSE

    # --- starts_with with AND ---
    c("1.2.9", "=1.2,*"), # TRUE
    c("1.2.9", "==1.2.0,*"), # FALSE

    # --- Letter-based version components ---
    c("2025b", ">2025a"), # TRUE
    c("2025a", ">2025b"), # FALSE
    c("2025a", "==2025a"), # TRUE
    c("2025b", "<x"), # FALSE

    # --- dev and post special literals ---
    c("1.0dev", "<1.0"), # TRUE
    c("1.0dev", ">=1.0"), # FALSE
    c("1.0post", ">1.0"), # TRUE
    c("1.0post", "<=1.0"), # FALSE

    # --- Epoch handling ---
    c("1!2.0", "==1!2.0"), # TRUE
    c("1!2.0", "==2.0"), # FALSE
    c("2.0", "==1!2.0"), # FALSE
    c("1!0.1", ">0!999.0"), # TRUE
    c("2!1.0", ">1!999.0"), # TRUE

    # --- = vs == distinction ---
    c("1.2.9", "=1.2"), # TRUE
    c("1.2.9", "==1.2"), # FALSE
    c("1.2.9", "==1.2.*"), # TRUE
    c("1.2.9", "=1.2.*"), # TRUE

    # --- Multi-segment ---
    c("1.2.3.4", ">=1.2.3"), # TRUE
    c("1.2.3.4", "=1.2.3"), # TRUE
    c("1.2.3.4", "==1.2.3"), # FALSE
    c("10.2", ">9.99"), # TRUE
    c("1.10", ">1.9"), # TRUE
    c("1.10", ">1.2"), # TRUE

    # --- Dashes and underscores ---
    c("1.2.3", "==1-2-3"), # TRUE
    c("1.2.3", "==1_2_3"), # TRUE

    # --- Letter-only segments ---
    c("a", "<b"), # TRUE
    c("b", ">a"), # TRUE
    c("alpha", "<beta"), # TRUE

    # --- Compatible release with single segment ---
    c("2", "~=2"), # TRUE
    c("3", "~=2"), # TRUE
    c("1", "~=2"), # FALSE

    # --- starts_with edge cases ---
    c("1", "=1"), # TRUE
    c("1.0", "=1"), # TRUE
    c("1.99", "=1"), # TRUE
    c("2", "=1"), # FALSE
    c("0.1", "=1"), # FALSE

    # --- Complex realistic ---
    c("3.11.5", ">=3.8,<3.14"), # TRUE
    c("3.7", ">=3.8,<3.14"), # FALSE
    c("3.14", ">=3.8,<3.14"), # FALSE
    c("3.12", ">=3.8,<3.9|>=3.10,<3.11|==3.12"), # TRUE
    c("3.9.5", ">=3.8,<3.9|>=3.10,<3.11|==3.12"), # FALSE

    # --- OR with free interval ---
    c("1.2.9", "==1.2.0|*"), # TRUE (* is free interval)

    # --- Version vs letter-only spec ---
    c("2025b", ">=2022a,<x"), # FALSE

    # --- dev with dot separator ---
    c("1.0.dev", "<1.0") # TRUE
  )

  for (test_vector in test_versions) {
    is_satisfied_rstats <- ms_compare_version(test_vector[1], test_vector[2])
    is_satisfied_py <- ms_compare_version_py(test_vector[1], test_vector[2])
    testthat::expect_equal(
      is_satisfied_rstats,
      is_satisfied_py,
      info = paste0(
        "Version: '",
        test_vector[1],
        "' - Spec: '",
        test_vector[2],
        "'"
      )
    )
  }
})
