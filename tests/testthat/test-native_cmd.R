test_that("Native run conda command", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  px_res <- native_cmd("--help", verbose = FALSE)
  expect_equal(
    object = px_res$status,
    expected = 0
  )

  px_res <- native_cmd("env", "list", verbose = FALSE)
  expect_equal(
    object = px_res$status,
    expected = 0
  )

  px_res <- native_cmd("--version", verbose = FALSE)
  expect_equal(
    object = px_res$status,
    expected = 0
  )
})
