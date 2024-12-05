test_that("env_exists missing env_name", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  expect_error(env_exists())
  expect_equal(env_exists(NULL), FALSE)
  expect_equal(env_exists(NA), FALSE)
})
