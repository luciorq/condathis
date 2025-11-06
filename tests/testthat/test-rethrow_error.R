testthat::test_that("Do not execute code in curly braces", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  px_res <- create_env(
    packages = c("r-base=4.1.3", "r-devtools"),
    env_name = "condathis-rethrow-test-env"
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
  testthat::expect_true(is.null(stdin))
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
