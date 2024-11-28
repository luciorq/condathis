test_that("Accept binary outside of environment", {
  run_bin_res <- run_bin(
    "R", "--version",
    env_name = "fake-env",
    verbose = "silent"
  )
  testthat::expect_equal(run_bin_res$status, 0)
})
