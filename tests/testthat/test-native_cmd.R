test_that("Native run conda command", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  px_res <- native_cmd("--help", verbose = FALSE)
  expect_equal(
    object = px_res$status,
    expected = 0L
  )

  px_res <- native_cmd("env", "list", verbose = FALSE)
  expect_equal(
    object = px_res$status,
    expected = 0L
  )

  px_res <- native_cmd("--version", verbose = FALSE)
  expect_equal(
    object = px_res$status,
    expected = 0L
  )
})

test_that("Native run accepts linux_pdeathsig", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  px_res <- native_cmd(
    "--version",
    verbose = FALSE,
    linux_pdeathsig = TRUE
  )
  expect_equal(
    object = px_res$status,
    expected = 0L
  )
})
