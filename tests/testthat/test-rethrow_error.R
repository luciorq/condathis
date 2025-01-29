testthat::test_that("Do not execute code in curl braces", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  px_res <- create_env(
    packages = c("r-base=4.1.3", "r-devtools"),
    env_name = "condathis-test-env"
  )

  testthat::expect_error(
    object = {
      run(
        "R", "-q", "-s", "-e", "stop(\"{ 5 + x }\")",
        env_name = "condathis-test-env",
        verbose = "silent",
        error = "cancel"
      )
    },
    class = "condathis_run_status_error"
  )

  testthat::expect_error(
    object = {
      run(
        "R", "-q", "-s", "-e", "stop(\"{{{ 5 + x }}}\")",
        env_name = "condathis-test-env",
        verbose = "silent",
        error = "cancel"
      )
    },
    class = "condathis_run_status_error"
  )

  px_res <- rethrow_error_run(
    expr = {
      run(
        "R", "-q", "-s", "-e", "stop(\"{{{ 5 + x }}}\")",
        env_name = "condathis-test-env",
        verbose = "silent",
        error = "continue"
      )
    }
  )

  testthat::expect_true(px_res$status != 0L)
})
