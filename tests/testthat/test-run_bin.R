test_that("Accept binary outside of environment", {
  run_bin_res <- run_bin(
    "R", "--version",
    env_name = "fake-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_true(is.numeric(run_bin_res$status))
})
