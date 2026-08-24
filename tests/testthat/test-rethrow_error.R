testthat::test_that("Do not execute code in curly braces", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  # `test_r_base_pkgs()` (helper-cli-tools.R) pins the broken conda-forge
  # MinGW runtime on Windows — see the helper for the full root-cause
  # analysis. Note this test only passed with the broken runtime by
  # accident (a crashing R also "errors"), but it needs a *working* R to
  # actually exercise the curly-brace escaping in real R error messages
  # it's about.
  px_res <- create_env(
    packages = test_r_base_pkgs(),
    env_name = "condathis-rethrow-test-env",
    verbose = "silent"
  )

  testthat::expect_error(
    object = {
      run(
        "R",
        "-q",
        "-s",
        "-e",
        "stop(\"{ 5 + x }\")",
        env_name = "condathis-rethrow-test-env",
        verbose = "silent",
        error = "cancel"
      )
    },
    class = "condathis_run_status_error"
  )

  testthat::expect_error(
    object = {
      run(
        "R",
        "-q",
        "-s",
        "-e",
        "stop(\"{{{ 5 + x }}}\")",
        env_name = "condathis-rethrow-test-env",
        verbose = "silent",
        error = "cancel"
      )
    },
    class = "condathis_run_status_error"
  )

  px_res <- rethrow_error_run(
    expr = {
      run(
        "R",
        "-q",
        "-s",
        "-e",
        "stop(\"{{{ 5 + x }}}\")",
        env_name = "condathis-rethrow-test-env",
        verbose = "silent",
        error = "continue"
      )
    }
  )

  testthat::expect_true(px_res$status != 0L)
})

# Test checking if stdin is a file
# TODO: @luciorq Improve tests
testthat::test_that("stdin is a file", {
  error <- "cancel"
  error_var <- TRUE
  stdin <- NULL

  px_res <- rethrow_error_run(
    expr = {
      ls_res <- ls()
    },
    env = parent.frame()
  )
  testthat::expect_null(stdin)
  # testthat::expect_equal(px_res$status, 0L)

  rm(px_res)
  stdin <- "missing_file_stdin.txt"

  testthat::expect_error(
    object = {
      rethrow_error_run(
        expr = {
          ls_res <- ls()
        }
      )
    },
    class = "condathis_run_stdin_error"
  )
  # rm(px_res)

  stdin <- "|"
  px_res <- rethrow_error_run(
    expr = {
      ls_res <- ls()
    }
  )
  testthat::expect_true("stdin" %in% ls_res)
  # testthat::expect_equal(px_res$status, 0L)

  # error <- "continue"
  # error_var <- FALSE
  # status_code <- 99
  # px_res <- rethrow_error_run(
  #  expr = {
  #    message("Error message")
  #  },
  #  env = parent.frame()
  # )
})
