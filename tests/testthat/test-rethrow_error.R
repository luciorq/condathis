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
    test_r_base_pkgs(),
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
  # The fallback check has the classes of rule R1 too.
  cnd <- testthat::expect_error(
    rethrow_error_run(expr = {
      ls_res <- ls()
    }),
    class = "condathis_run_invalid_stdin"
  )
  testthat::expect_identical(
    class(cnd)[1:5],
    c(
      "condathis_run_invalid_stdin",
      "condathis_run_stdin_error",
      "condathis_invalid_stdin",
      "condathis_invalid_arg",
      "condathis_error"
    )
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
  # A spawn failure: the only status-less condition still reported as a
  # status-127 result (any other one is re-raised unchanged).
  res <- rethrow_error_run(
    expr = {
      rlang::abort(
        message = "cannot start processx process 'some-cmd'",
        class = "c_error"
      )
    },
    env = caller_env
  )
  testthat::expect_type(res, "list")
  testthat::expect_false(identical(res, "user workspace object"))
  testthat::expect_equal(res$status, 127L)
})

testthat::test_that("rethrow_error_run() reports 'command not found' only for spawn failures", {
  # Regression test: any caught condition without a status (a time limit
  # firing while polling, an error inside the I/O pump) was reported as
  # status 127 "command not found".
  cmd <- "anything"
  error_var <- TRUE
  other <- rlang::catch_cnd(rethrow_error_run(
    rlang::abort(
      "interrupted while polling",
      class = c("c_error", "rlib_error_3_0")
    )
  ))
  testthat::expect_s3_class(other, "c_error")
  testthat::expect_false(inherits(other, "condathis_run_status_error"))
  testthat::expect_match(conditionMessage(other), "interrupted while polling")

  spawn <- rlang::catch_cnd(rethrow_error_run(
    processx::run("definitely-not-a-command-condathis-xyz")
  ))
  testthat::expect_s3_class(spawn, "condathis_run_status_error")
})

testthat::test_that("rethrow_error_cmd() reports micromamba's error message", {
  # Regression test: the error was built from stderr alone, so a command
  # that printed nothing raised an error with no text.
  fail_with <- function(stderr) {
    rlang::catch_cnd(
      rethrow_error_cmd(
        rlang::abort(
          "failed",
          class = "system_command_status_error",
          status = 1L,
          stderr = stderr
        )
      ),
      classes = "condathis_cmd_status_error"
    )
  }

  cnd <- fail_with("")
  testthat::expect_s3_class(cnd, "condathis_cmd_status_error")
  testthat::expect_match(
    conditionMessage(cnd),
    "failed with status code 1",
    fixed = TRUE
  )

  # Level prefixes are dropped, and the `critical` copy of the error too.
  cnd <- fail_with(paste(
    "error    libmamba Could not solve for environment specs",
    "    \u2514\u2500 no-such-pkg =* * does not exist {braces}",
    "critical libmamba Could not solve for environment specs",
    sep = "\n"
  ))
  msg <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(msg, "does not exist {braces}", fixed = TRUE)
  testthat::expect_identical(
    lengths(regmatches(msg, gregexpr("Could not solve", msg, fixed = TRUE))),
    1L
  )
  testthat::expect_no_match(msg, "libmamba", fixed = TRUE)
})

# --- Classes and fields of status and timeout errors -----------------------

# The frame of an exported function, as `rethrow_error_run()` reads it.
rethrow_test_env <- function(stdout = "|", stderr = "|", timeout = 5) {
  return(rlang::env(
    cmd = "some-cmd",
    error_var = TRUE,
    stdin = NULL,
    stdout = stdout,
    stderr = stderr,
    timeout = timeout
  ))
}

testthat::test_that("rethrow_error_run() status errors carry classes and fields", {
  # Regression test: the status was only in the message text ("Status
  # code: 1"), and no class was shared by run(), run_bin() and
  # run_pipeline().
  fail_with <- function(fn, env = rethrow_test_env()) {
    return(rlang::catch_cnd(
      rethrow_error_run(
        expr = rlang::abort(
          "failed",
          class = "system_command_status_error",
          status = 2L,
          stdout = "partial output",
          stderr = "boom {braces}"
        ),
        env = env,
        fn = fn
      ),
      classes = "error"
    ))
  }

  cnd <- fail_with("run")
  testthat::expect_identical(
    class(cnd)[1:3],
    c("condathis_run_status_error", "condathis_status_error", "condathis_error")
  )
  testthat::expect_identical(cnd$status, 2L)
  testthat::expect_identical(cnd$stdout, "partial output")
  testthat::expect_identical(cnd$stderr, "boom {braces}")
  testthat::expect_false(cnd$timeout)
  msg <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(msg, "failed with exit status 2.", fixed = TRUE)
  testthat::expect_match(msg, "boom {braces}", fixed = TRUE)

  cnd <- fail_with("run_bin")
  testthat::expect_identical(
    class(cnd)[1:4],
    c(
      "condathis_run_bin_status_error",
      "condathis_run_status_error",
      "condathis_status_error",
      "condathis_error"
    )
  )

  # A stream that was not captured is NA, as in a result.
  cnd <- fail_with("run", env = rethrow_test_env(stdout = NULL, stderr = "x"))
  testthat::expect_identical(cnd$stdout, NA_character_)
  testthat::expect_identical(cnd$stderr, NA_character_)

  # The error names the call of the frame it evaluates in: the exported
  # function, not this helper.
  outer_fn <- function() {
    cmd <- "x"
    error_var <- TRUE
    timeout <- Inf
    rethrow_error_run(
      expr = rlang::abort(
        "failed",
        class = "system_command_status_error",
        status = 1L
      ),
      fn = "run"
    )
  }
  cnd <- testthat::expect_error(outer_fn(), class = "condathis_status_error")
  testthat::expect_identical(rlang::call_name(conditionCall(cnd)), "outer_fn")
})

testthat::test_that("rethrow_error_run() timeout errors carry classes and fields", {
  cnd <- rlang::catch_cnd(
    rethrow_error_run(
      expr = rlang::abort(
        "timed out",
        class = "system_command_timeout_error",
        status = 2L,
        stderr = ""
      ),
      env = rethrow_test_env(timeout = 1),
      fn = "run_bin"
    ),
    classes = "error"
  )
  testthat::expect_identical(
    class(cnd)[1:4],
    c(
      "condathis_run_bin_timeout_error",
      "condathis_run_timeout_error",
      "condathis_timeout_error",
      "condathis_error"
    )
  )
  # The same status as a result under `error = "continue"`, whatever the
  # operating system reported for the killed process.
  testthat::expect_identical(cnd$status, -9L)
  testthat::expect_true(cnd$timeout)
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "timed out after 1 second.",
    fixed = TRUE
  )
})

testthat::test_that("rethrow_error_run() gives status 127 to a command that cannot start", {
  env <- rethrow_test_env()
  env$cmd <- "definitely-not-a-command-condathis-xyz"
  cnd <- rlang::catch_cnd(
    rethrow_error_run(
      processx::run("definitely-not-a-command-condathis-xyz"),
      env = env
    ),
    classes = "error"
  )
  testthat::expect_s3_class(cnd, "condathis_status_error")
  testthat::expect_identical(cnd$status, 127L)
  testthat::expect_match(
    conditionMessage(cnd),
    "definitely-not-a-command-condathis-xyz: command not found",
    fixed = TRUE
  )
  # The streams of the result that `error = "continue"` gives: the error had
  # `NA` (not captured).
  testthat::expect_identical(cnd$stdout, "")
  testthat::expect_identical(
    cnd$stderr,
    "System command definitely-not-a-command-condathis-xyz not found"
  )
  env$error_var <- FALSE
  res <- rethrow_error_run(
    processx::run("definitely-not-a-command-condathis-xyz"),
    env = env
  )
  testthat::expect_identical(res$stderr, cnd$stderr)
  # A stream that is not captured stays `NA`.
  env <- rethrow_test_env(stderr = NULL)
  env$cmd <- "definitely-not-a-command-condathis-xyz"
  cnd <- rlang::catch_cnd(
    rethrow_error_run(
      processx::run("definitely-not-a-command-condathis-xyz"),
      env = env
    ),
    classes = "error"
  )
  testthat::expect_identical(cnd$stderr, NA_character_)
  testthat::expect_identical(cnd$stdout, "")
})

testthat::test_that("rethrow_error_cmd() errors carry the new class, the old class and fields", {
  cnd <- rlang::catch_cnd(
    rethrow_error_cmd(
      rlang::abort(
        "failed",
        class = "system_command_status_error",
        status = 3L,
        stderr = "error    libmamba nothing provides x"
      )
    ),
    classes = "error"
  )
  testthat::expect_identical(
    class(cnd)[1:3],
    c(
      "condathis_micromamba_status_error",
      "condathis_cmd_status_error",
      "condathis_error"
    )
  )
  testthat::expect_identical(cnd$status, 3L)
  testthat::expect_identical(cnd$stderr, "error    libmamba nothing provides x")

  # micromamba could not start: no status in the caught condition.
  cnd <- rlang::catch_cnd(
    rethrow_error_cmd(
      rlang::abort("cannot start processx process", class = "c_error")
    ),
    classes = "error"
  )
  testthat::expect_s3_class(cnd, "condathis_micromamba_status_error")
  testthat::expect_identical(cnd$status, 127L)
  testthat::expect_identical(cnd$stderr, NA_character_)
})

testthat::test_that("process errors of execute_command() can be formatted and printed", {
  # Regression test: these errors had the class `system_command_error`,
  # whose `processx` format() and print() methods expect a processx error
  # object. format() failed with "invalid 'trim' argument", so a condathis
  # error with such a parent could not print its parent.
  rscript <- normalizePath(
    file.path(
      R.home("bin"),
      if (isTRUE(is_windows())) "Rscript.exe" else "Rscript"
    ),
    mustWork = TRUE
  )
  # The timeout kills the process, which leaves its temporary directory
  # behind (see local_child_tempdir()). On Windows, a killed `Rscript -e`
  # also leaves its code behind in a file in `TMPDIR`, so the code is in a
  # file here.
  local_child_tempdir()
  sleep_script <- withr::local_tempfile(fileext = ".R")
  writeLines("Sys.sleep(30)", sleep_script)
  cases <- list(
    status = list(args = c("--vanilla", "-e", "quit(status = 3)")),
    status_input = list(
      args = c("--vanilla", "-e", "quit(status = 3)"),
      stdin = "|",
      input = "x"
    ),
    timeout = list(
      args = c("--vanilla", sleep_script),
      timeout = 0.5
    )
  )
  for (case_name in names(cases)) {
    case <- cases[[case_name]]
    cnd <- tryCatch(
      execute_command(
        rscript,
        args = case$args,
        stdin = case$stdin,
        input = case$input,
        timeout = case$timeout %||% Inf,
        error_on_status = TRUE
      ),
      error = function(e) e
    )
    testthat::expect_true(
      inherits(cnd, "system_command_status_error") ||
        inherits(cnd, "system_command_timeout_error"),
      info = case_name
    )
    testthat::expect_false(
      inherits(cnd, "system_command_error"),
      info = case_name
    )
    testthat::expect_no_error(format(cnd))
    testthat::expect_no_error(utils::capture.output(print(cnd)))
    wrapped <- rlang::catch_cnd(
      rlang::abort("Outer error.", parent = cnd),
      classes = "error"
    )
    testthat::expect_no_error(utils::capture.output(print(wrapped)))
  }
})
