# =============================================================================
# Unit tests: No network, no skip. Expected values from libmambapy calibration.
# =============================================================================

testthat::test_that("ms_version_compare: true comparisons", {

  testthat::expect_true(ms_compare_version("1.12.1", "1.12"))

  testthat::expect_true(ms_compare_version("2025b", ">=2025a,<2026"))

  testthat::expect_true(ms_compare_version("2025b", "=2022a,<2025|2025b"))

})


testthat::test_that("ms_version_compare: false comparisons", {

  testthat::expect_false(ms_compare_version("1.26.4", ">=1.8,<2,!=1.26.4"))

  testthat::expect_false(ms_compare_version("2025b", ">=2025a,<2026,!=2025b"))

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

  test_versions <- list(
    c("1.26.4", "!=1.26.*"), # FALSE
    c("1.26.4", "==1.8.1" ), # FALSE
    c("1.26.4", ">=1.8,<1.9|==1.26.4"), # TRUE
    c("1.26.4", ">=1.8,<2,!=1.26.4"), # FALSE
    c("2025b", ">=2025a,<2026"), # TRUE
    c("2025b", ">=2025a,<2026,!=2025b"), # FALSE
    c("2025b", "=2022a,<2025|2025b"), # TRUE
    c("2025b", ">=2022a,<x"), # FALSE
    c("1.2.9", "=1.2.*"), # TRUE
    c("1.2.9", "==1.2.*"), # TRUE
    c("1.2.9", "=1.2"), # TRUE
    c("1.2.9", "==1.2"), # FALSE
    c("1.2.9", "=1.2,*"), # TRUE
    c("1.2.9", "==1.2.0,*"), # FALSE
    c("1.2.9", "==1.2.0|*"), # FALSE
    c("1.2.9", "1.2.0"), # FALSE
    c("1.2.9", "1.2.9"), # TRUE
    c("1.12", "1.12"), # TRUE
    c("1.12.1", "1.12") # FALSE
  )

  for (test_vector in test_versions) {
    is_satisfied_rstats <- ms_compare_version(test_vector[1], test_vector[2])
    is_satisfied_py <- ms_compare_version_py(test_vector[1], test_vector[2])
    testthat::expect_equal(
      is_satisfied_rstats,
      is_satisfied_py,
      info = paste0("Version: '", test_vector[1], "' - Spec: '", test_vector[2], "'")
    )
  }
})
