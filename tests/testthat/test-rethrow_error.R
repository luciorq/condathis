testthat::test_that("Do not execute code in curly braces", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  # `test_r_base_pkgs()` (helper-cli-tools.R) pins the broken conda-forge
  # MinGW runtime on Windows - see the helper for the full root-cause
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

testthat::test_that("rethrow_error_run never picks up a px_res from the user's workspace", {
  # Regression test: the post-eval `exists("px_res")` check used the
  # default inherits = TRUE, whose lookup reaches the global environment -
  # a workspace object named `px_res` was returned *as the process result*
  # whenever the wrapped expression errored before assigning locally.
  assign("px_res", "user workspace object", envir = globalenv())
  withr::defer(rm("px_res", envir = globalenv()))

  # The variables rethrow_error_run() reads from its `env` argument are
  # passed as an explicit environment object.
  caller_env <- rlang::env(
    error = "continue",
    error_var = FALSE,
    stdin = NULL,
    cmd = "some-cmd"
  )
  res <- rethrow_error_run(
    expr = {
      rlang::abort(message = "boom", class = "c_error")
    },
    env = caller_env
  )
  testthat::expect_type(res, "list")
  testthat::expect_false(identical(res, "user workspace object"))
  testthat::expect_equal(res$status, 127L)
})
