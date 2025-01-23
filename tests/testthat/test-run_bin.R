test_that("Accept binary outside of environment", {
  # `error = "continue"` Should not error even when R is not on PATH
  run_bin_res <- run_bin(
    "R", "--version",
    env_name = "fake-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_true(is.numeric(run_bin_res$status))


  run_bin_fake_res <- run_bin(
    "Rfakeexec", "--version",
    env_name = "fake-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_true(is.numeric(run_bin_fake_res$status))


  withr::with_path(
    new = list(
      `PATH` = ""
    ),
    code = {
      run_bin_no_path_res <- run_bin(
        "R", "--version",
        env_name = "fake-env",
        verbose = "silent",
        error = "continue"
      )
    },
    action = "replace"
  )

  testthat::expect_true(is.numeric(run_bin_no_path_res$status))

  testthat::expect_error(
    object = {
      run_bin_fake_res <- run_bin(
        "Rfakeexec", "--version",
        env_name = "fake-env",
        verbose = "silent",
        error = "cancel"
      )
    }
  )
})

test_that("Check if error is being rethrown when binary is not in path", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(env_name = "fake-env", verbose = "silent")

  run_res <- run(
    "Rfakeexec", "--version",
    env_name = "fake-env",
    verbose = "silent",
    error = "continue"
  )

  testthat::expect_true(run_res$status != 0L)

  run_bin_res <- run_bin(
    "Rfakeexec", "--version",
    env_name = "fake-env",
    verbose = "silent",
    error = "continue"
  )

  testthat::expect_true(run_bin_res$status != 0L)
})
