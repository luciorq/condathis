testthat::test_that("check_micromamba_version accepts newer versions with minimum=TRUE", {
  testthat::local_mocked_bindings(
    get_micromamba_version = function(...) "2.6.0"
  )
  testthat::expect_true(
    check_micromamba_version(target_version = "2.5.0", minimum = TRUE)
  )
  testthat::expect_false(
    check_micromamba_version(target_version = "2.5.0", minimum = FALSE)
  )
})

testthat::test_that("check_micromamba_version rejects older versions", {
  testthat::local_mocked_bindings(
    get_micromamba_version = function(...) "2.4.0"
  )
  testthat::expect_false(
    check_micromamba_version(target_version = "2.5.0", minimum = TRUE)
  )
  testthat::expect_false(
    check_micromamba_version(target_version = "2.5.0", minimum = FALSE)
  )
})

testthat::test_that("check_micromamba_version accepts exact match", {
  testthat::local_mocked_bindings(
    get_micromamba_version = function(...) "2.5.0"
  )
  testthat::expect_true(
    check_micromamba_version(target_version = "2.5.0", minimum = TRUE)
  )
  testthat::expect_true(
    check_micromamba_version(target_version = "2.5.0", minimum = FALSE)
  )
})

testthat::test_that("check_micromamba_version defaults to minimum=TRUE", {
  testthat::local_mocked_bindings(
    get_micromamba_version = function(...) "3.0.0"
  )
  # Default (minimum=TRUE) should accept v3.0.0 against target v2.5.0
  testthat::expect_true(
    check_micromamba_version(target_version = "2.5.0")
  )
})

testthat::test_that("is_umamba_version_available accepts newer versions", {
  # TODO: @luciorq - Update this to the newer version of micromamba upon
  # + update and ensure the test reflects that
  testthat::local_mocked_bindings(
    get_micromamba_version = function(...) "2.8.1"
  )
  # This should return TRUE since check_micromamba_version uses >= by default
  testthat::expect_true(is_umamba_version_available("/mock/path"))
})
