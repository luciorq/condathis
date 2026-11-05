# The exported API of `run_pipeline()` and `run_step()`: argument checks,
# condition classes, error fields and the result. Most tests run a pipeline
# through a stub backend (see helper-stub-backend.R), with R's own `Rscript`
# by absolute path as the command, so they need no network and no
# micromamba, and run the same way on every platform.

# A stub backend named "stub-pipe" that is the only backend in priority
# order, so no test here probes micromamba.
local_pipeline_stub <- function(
  ...,
  envs = "stub-env",
  envir = parent.frame()
) {
  stub <- local_stub_backend("stub-pipe", ..., envs = envs, envir = envir)
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() "stub-pipe",
    .env = envir
  )
  return(invisible(stub))
}

# A pipeline step that runs R code with `Rscript`.
r_step <- function(code, ...) {
  return(run_step(
    file.path(R.home("bin"), "Rscript"),
    "--vanilla",
    "-e",
    code,
    ...
  ))
}

# A last step that reads its stdin to the end and copies it to stdout, so
# the step before it always exits on its own.
r_copy_step <- function(...) {
  return(r_step("writeLines(readLines(file('stdin'), warn = FALSE))", ...))
}

# The same path, written the same way on every platform.
same_dir <- function(x) {
  x <- normalizePath(x, winslash = "/", mustWork = TRUE)
  if (isTRUE(is_windows())) {
    x <- tolower(x)
  }
  return(x)
}

# Fails the test when the pipeline gets past its argument checks.
local_no_backend_calls <- function(envir = parent.frame()) {
  testthat::local_mocked_bindings(
    precreate_envs = function(...) {
      stop("precreate_envs() must not run before every argument is checked.")
    },
    resolve_backend = function(...) {
      stop("resolve_backend() must not run before every argument is checked.")
    },
    .env = envir
  )
  return(invisible(NULL))
}

two_steps <- function() {
  return(list(run_step("cmd-a"), run_step("cmd-b")))
}

testthat::test_that("run_pipeline() argument errors have the new and the old class", {
  local_no_backend_calls()
  # Exact class vectors: the new name, the old one, the shared classes.
  cnd <- testthat::expect_error(
    run_pipeline(run_step("cmd-a"), "cmd-b"),
    class = "condathis_run_pipeline_invalid_step"
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_run_pipeline_invalid_step",
      "condathis_pipeline_invalid_step",
      "condathis_invalid_arg",
      "condathis_error",
      "rlang_error",
      "error",
      "condition"
    )
  )

  cnd <- testthat::expect_error(
    run_pipeline(run_step("cmd-a")),
    class = "condathis_run_pipeline_too_few_commands"
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_run_pipeline_too_few_commands",
      "condathis_pipeline_too_few_commands",
      "condathis_invalid_arg",
      "condathis_error",
      "rlang_error",
      "error",
      "condition"
    )
  )

  cnd <- testthat::expect_error(
    run_pipeline(!!!two_steps(), binary = NA),
    class = "condathis_run_pipeline_invalid_binary"
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_run_pipeline_invalid_binary",
      "condathis_pipeline_invalid_binary_arg",
      "condathis_invalid_binary",
      "condathis_invalid_arg",
      "condathis_error",
      "rlang_error",
      "error",
      "condition"
    )
  )

  cnd <- testthat::expect_error(
    run_pipeline(
      run_step("cmd-a", env_name = "shared-env", method = "micromamba"),
      run_step("cmd-b", env_name = "shared-env", method = "other-backend")
    ),
    class = "condathis_run_pipeline_conflicting_method"
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_run_pipeline_conflicting_method",
      "condathis_pipeline_conflicting_method",
      "condathis_invalid_arg",
      "condathis_error",
      "rlang_error",
      "error",
      "condition"
    )
  )

  # These use helpers of other files, so their classes are checked one by
  # one, in the order of rule R1.
  expect_classes <- function(cnd, classes) {
    for (cls in classes) {
      testthat::expect_s3_class(cnd, cls)
    }
    positions <- match(classes, class(cnd))
    testthat::expect_false(is.unsorted(positions))
  }
  cnd <- testthat::expect_error(
    run_pipeline(!!!two_steps(), env_name = "../outside")
  )
  expect_classes(
    cnd,
    c(
      "condathis_run_pipeline_invalid_env_name",
      "condathis_pipeline_invalid_env_name",
      "condathis_invalid_env_name",
      "condathis_invalid_arg",
      "condathis_error"
    )
  )
  cnd <- testthat::expect_error(
    run_pipeline(!!!two_steps(), input = "x")
  )
  expect_classes(
    cnd,
    c(
      "condathis_run_pipeline_invalid_input",
      "condathis_pipeline_invalid_input",
      "condathis_invalid_input",
      "condathis_invalid_arg",
      "condathis_error"
    )
  )
  cnd <- testthat::expect_error(
    run_pipeline(!!!two_steps(), stdin = "|", input = 1)
  )
  expect_classes(
    cnd,
    c(
      "condathis_run_pipeline_invalid_input",
      "condathis_pipeline_invalid_input",
      "condathis_invalid_input",
      "condathis_invalid_arg",
      "condathis_error"
    )
  )
})

testthat::test_that("run_pipeline() errors name the run_pipeline() call", {
  local_no_backend_calls()
  expect_run_pipeline_call <- function(cnd) {
    testthat::expect_identical(
      rlang::call_name(conditionCall(cnd)),
      "run_pipeline"
    )
  }
  expect_run_pipeline_call(testthat::expect_error(
    run_pipeline(run_step("cmd-a"), "cmd-b")
  ))
  expect_run_pipeline_call(testthat::expect_error(
    run_pipeline(run_step("cmd-a"))
  ))
  expect_run_pipeline_call(testthat::expect_error(
    run_pipeline(!!!two_steps(), env_name = 1)
  ))
  expect_run_pipeline_call(testthat::expect_error(
    run_pipeline(!!!two_steps(), input = "x")
  ))
  expect_run_pipeline_call(testthat::expect_error(
    run_pipeline(!!!two_steps(), binary = "yes")
  ))
  expect_run_pipeline_call(testthat::expect_error(
    run_pipeline(!!!two_steps(), error = "stop")
  ))
  expect_run_pipeline_call(testthat::expect_error(
    run_pipeline(!!!two_steps(), verbose = "loud")
  ))
  expect_run_pipeline_call(testthat::expect_error(
    run_pipeline(!!!two_steps(), timeout = "10")
  ))
  expect_run_pipeline_call(testthat::expect_error(
    run_pipeline(
      run_step("cmd-a", env_name = "shared-env", method = "micromamba"),
      run_step("cmd-b", env_name = "shared-env", method = "other-backend")
    )
  ))
  # A malformed step built by hand.
  bad_step <- run_step("cmd-a")
  bad_step$args <- NA
  expect_run_pipeline_call(testthat::expect_error(
    run_pipeline(bad_step, run_step("cmd-b")),
    class = "condathis_run_pipeline_invalid_step"
  ))
})

testthat::test_that("run_pipeline() classes invalid error and verbose values", {
  local_no_backend_calls()
  # Shared parsers: only the shared classes.
  cnd <- testthat::expect_error(
    run_pipeline(!!!two_steps(), error = "stop"),
    class = "condathis_invalid_error"
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_invalid_error",
      "condathis_invalid_arg",
      "condathis_error",
      "rlang_error",
      "error",
      "condition"
    )
  )
  testthat::expect_error(
    run_pipeline(!!!two_steps(), error = c("continue", "cancel", "x")),
    class = "condathis_invalid_error"
  )
  cnd <- testthat::expect_error(
    run_pipeline(!!!two_steps(), verbose = "loud"),
    class = "condathis_invalid_verbose"
  )
  testthat::expect_s3_class(cnd, "condathis_invalid_arg")
  testthat::expect_s3_class(cnd, "condathis_error")
  # Only internal callers may pass an already-parsed list.
  testthat::expect_error(
    run_pipeline(!!!two_steps(), verbose = list(internal_verbose = "silent")),
    class = "condathis_invalid_verbose"
  )
})

testthat::test_that("run_pipeline() checks its process arguments before any backend call", {
  local_no_backend_calls()
  expect_arg_error <- function(arg, ...) {
    cnd <- testthat::expect_error(
      run_pipeline(!!!two_steps(), ...),
      class = paste0("condathis_run_pipeline_invalid_", arg)
    )
    testthat::expect_s3_class(cnd, paste0("condathis_invalid_", arg))
    testthat::expect_s3_class(cnd, "condathis_invalid_arg")
    testthat::expect_s3_class(cnd, "condathis_error")
    return(invisible(cnd))
  }
  for (timeout in list("10", NA, NA_real_, -1, c(1, 2), NULL)) {
    expect_arg_error("timeout", timeout = timeout)
  }
  expect_arg_error("supervise", supervise = NA)
  expect_arg_error("supervise", supervise = c(TRUE, FALSE))
  expect_arg_error("cleanup_tree", cleanup_tree = "yes")
  expect_arg_error("linux_pdeathsig", linux_pdeathsig = 1)
  expect_arg_error("activate", activate = "yes")
  expect_arg_error("stdout", stdout = 1)
  expect_arg_error("stderr", stderr = c("a.log", "b.log"))
  missing_file <- file.path(withr::local_tempdir(), "nonexistent")
  expect_arg_error("stdin", stdin = missing_file)
  expect_arg_error("stdin", stdin = 1)
})

testthat::test_that("run_pipeline() checks the method of every step before any backend call", {
  local_no_backend_calls()
  cnd <- testthat::expect_error(
    run_pipeline(
      run_step("cmd-a", method = "not-a-registered-backend"),
      run_step("cmd-b")
    ),
    class = "condathis_invalid_method_arg"
  )
  testthat::expect_s3_class(cnd, "condathis_error")
  testthat::expect_identical(
    rlang::call_name(conditionCall(cnd)),
    "run_pipeline"
  )
})

testthat::test_that("run_step() checks cmd as run() and run_bin() do", {
  expect_cmd_error <- function(expr) {
    cnd <- testthat::expect_error(
      expr,
      class = "condathis_run_step_invalid_cmd"
    )
    testthat::expect_identical(
      class(cnd),
      c(
        "condathis_run_step_invalid_cmd",
        "condathis_invalid_cmd",
        "condathis_invalid_arg",
        "condathis_error",
        "rlang_error",
        "error",
        "condition"
      )
    )
    testthat::expect_identical(rlang::call_name(conditionCall(cnd)), "run_step")
    return(invisible(cnd))
  }
  # A missing cmd was an unclassed rlang error.
  cnd <- expect_cmd_error(run_step())
  testthat::expect_match(conditionMessage(cnd), "absent", fixed = TRUE)
  for (cmd in list(1, NA, NA_character_, "", NULL)) {
    expect_cmd_error(run_step(cmd))
  }
  cnd <- expect_cmd_error(run_step(c("echo", "x")))
  testthat::expect_match(conditionMessage(cnd), "...", fixed = TRUE)
})

testthat::test_that("run_step() argument errors have the shared classes", {
  cnd <- testthat::expect_error(
    run_step("cmd", method = 1),
    class = "condathis_run_step_invalid_method"
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_run_step_invalid_method",
      "condathis_invalid_method",
      "condathis_invalid_arg",
      "condathis_error",
      "rlang_error",
      "error",
      "condition"
    )
  )
  cnd <- testthat::expect_error(
    run_step("cmd", stderr = 1),
    class = "condathis_run_step_invalid_stderr"
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_run_step_invalid_stderr",
      "condathis_invalid_stderr",
      "condathis_invalid_arg",
      "condathis_error",
      "rlang_error",
      "error",
      "condition"
    )
  )
  cnd <- testthat::expect_error(
    run_step("cmd", list("a")),
    class = "condathis_run_step_invalid_args"
  )
  testthat::expect_s3_class(cnd, "condathis_invalid_arg")
  testthat::expect_s3_class(cnd, "condathis_error")
})

testthat::test_that("every invalid env_name of run_step() and run_pipeline() has condathis_invalid_env_name", {
  local_no_backend_calls()
  malformed <- structure(list(path = "relative"), class = "condathis_env_path")
  for (env_name in list(1, NA, c("a", "b"), "../outside", malformed)) {
    cnd <- testthat::expect_error(
      run_step("cmd", env_name = env_name),
      class = "condathis_invalid_env_name"
    )
    testthat::expect_s3_class(cnd, "condathis_run_step_invalid_env_name")
    testthat::expect_s3_class(cnd, "condathis_invalid_arg")
    testthat::expect_s3_class(cnd, "condathis_error")

    cnd <- testthat::expect_error(
      run_pipeline(!!!two_steps(), env_name = env_name),
      class = "condathis_invalid_env_name"
    )
    testthat::expect_s3_class(cnd, "condathis_run_pipeline_invalid_env_name")
    testthat::expect_s3_class(cnd, "condathis_pipeline_invalid_env_name")
    testthat::expect_s3_class(cnd, "condathis_error")
  }
  # The malformed object keeps its own class too.
  testthat::expect_error(
    run_step("cmd", env_name = malformed),
    class = "condathis_env_path_invalid"
  )
  testthat::expect_error(
    run_pipeline(!!!two_steps(), env_name = malformed),
    class = "condathis_env_path_invalid"
  )
  # A step edited by hand is checked again, with the step class.
  bad_step <- run_step("cmd-a")
  bad_step$env_name <- 1
  cnd <- testthat::expect_error(
    run_pipeline(bad_step, run_step("cmd-b")),
    class = "condathis_invalid_env_name"
  )
  testthat::expect_s3_class(cnd, "condathis_run_pipeline_invalid_step")
  testthat::expect_s3_class(cnd, "condathis_pipeline_invalid_step")
})

testthat::test_that("run_pipeline() messages follow one style", {
  local_no_backend_calls()
  cnd <- testthat::expect_error(run_pipeline(!!!two_steps(), input = "x"))
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "`input` must be `NULL` unless `stdin`")
  cnd <- testthat::expect_error(run_pipeline(!!!two_steps(), binary = 1))
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "`binary` must be `TRUE` or `FALSE`")
  testthat::expect_no_match(message, "needs to be", fixed = TRUE)
})

testthat::test_that("pipeline_status() follows the rule of error = 'cancel'", {
  testthat::expect_identical(pipeline_status(c(0L, 0L)), 0L)
  # An upstream SIGPIPE is not a failure.
  testthat::expect_identical(pipeline_status(c(broken_pipe_status, 0L)), 0L)
  # The last command's own SIGPIPE status is.
  testthat::expect_identical(
    pipeline_status(c(0L, broken_pipe_status)),
    broken_pipe_status
  )
  # The first failure wins.
  testthat::expect_identical(pipeline_status(c(1L, 0L)), 1L)
  testthat::expect_identical(pipeline_status(c(0L, 2L, 3L)), 2L)
  testthat::expect_identical(pipeline_status(c(127L, 1L)), 127L)
  # A timeout gives -9, as for run().
  testthat::expect_identical(pipeline_status(c(1L, 0L), timeout = TRUE), -9L)
  testthat::expect_identical(pipeline_status(c(NA_integer_, 0L)), 0L)
  testthat::expect_identical(
    is_failed_stage(c(broken_pipe_status, 1L, NA_integer_, 0L)),
    c(FALSE, TRUE, FALSE, FALSE)
  )
})

testthat::test_that("a pipeline result has a scalar status and the whole cmd", {
  proc <- function(cmd, status) {
    return(new_condathis_result(
      status = status,
      stdout = NA_character_,
      stderr = "",
      cmd = cmd,
      env_name = "e"
    ))
  }
  res <- new_condathis_pipeline(
    statuses = c(1L, 0L),
    processes = list(proc("'false'", 1L), proc("'cat'", 0L))
  )
  # Regression test: `res$status` partially matched `res$statuses`, with a
  # warning under `warnPartialMatchDollar`, and gave the whole vector.
  testthat::expect_no_warning(status <- res$status)
  testthat::expect_identical(status, 1L)
  testthat::expect_identical(res$cmd, "'false' | 'cat'")
  testthat::expect_identical(as.list(res)$status, 1L)
  testthat::expect_identical(as.list(res)$cmd, "'false' | 'cat'")
  testthat::expect_match(format(res), "status: exit: 1", fixed = TRUE)
  ok <- new_condathis_pipeline(
    statuses = c(broken_pipe_status, 0L),
    processes = list(proc("'seq'", broken_pipe_status), proc("'head'", 0L))
  )
  testthat::expect_identical(ok$status, 0L)
  testthat::expect_match(format(ok), "status: OK", fixed = TRUE)
  timed_out <- new_condathis_pipeline(
    statuses = c(-9L, -9L),
    processes = list(proc("'a'", -9L), proc("'b'", -9L)),
    timeout = TRUE
  )
  testthat::expect_identical(timed_out$status, -9L)
})

testthat::test_that("run_pipeline() runs through a stub backend and reports status and cmd", {
  testthat::skip_on_cran()
  local_pipeline_stub()
  res <- run_pipeline(
    r_step("cat('through-stub')"),
    r_copy_step(),
    env_name = "stub-env",
    verbose = "silent"
  )
  testthat::expect_s3_class(res, "condathis_pipeline")
  testthat::expect_identical(res$statuses, c(0L, 0L))
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(parse_output(res), "through-stub")
  testthat::expect_identical(
    res$cmd,
    paste(
      vapply(res$processes, `[[`, character(1L), "cmd"),
      collapse = " | "
    )
  )

  res <- run_pipeline(
    r_step("quit(status = 3L)"),
    r_copy_step(),
    env_name = "stub-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_identical(res$statuses, c(3L, 0L))
  testthat::expect_identical(res$status, 3L)
})

testthat::test_that("a failed pipeline aborts with the status fields and the result", {
  testthat::skip_on_cran()
  local_pipeline_stub()
  cnd <- testthat::expect_error(
    run_pipeline(
      r_step("message('to-stderr'); cat('partial'); quit(status = 3L)"),
      r_copy_step(),
      env_name = "stub-env",
      verbose = "silent"
    ),
    class = "condathis_run_pipeline_status_error"
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_run_pipeline_status_error",
      "condathis_pipeline_status_error",
      "condathis_status_error",
      "condathis_error",
      "rlang_error",
      "error",
      "condition"
    )
  )
  testthat::expect_identical(cnd$status, 3L)
  testthat::expect_identical(cnd$statuses, c(3L, 0L))
  testthat::expect_false(cnd$timeout)
  testthat::expect_s3_class(cnd$result, "condathis_pipeline")
  testthat::expect_identical(cnd$result$status, 3L)
  testthat::expect_match(cnd$stdout, "partial", fixed = TRUE)
  testthat::expect_match(cnd$stderr, "to-stderr", fixed = TRUE)
  testthat::expect_identical(
    rlang::call_name(conditionCall(cnd)),
    "run_pipeline"
  )
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "exited with a non-zero status.",
    fixed = TRUE
  )
  # One handler for the whole run family.
  status <- tryCatch(
    run_pipeline(
      r_step("quit(status = 3L)"),
      r_copy_step(),
      env_name = "stub-env",
      verbose = "silent"
    ),
    condathis_status_error = function(e) e$status
  )
  testthat::expect_identical(status, 3L)
})

testthat::test_that("a pipeline timeout aborts with the timeout fields, or gives status -9", {
  testthat::skip_on_cran()
  local_pipeline_stub()
  cnd <- testthat::expect_error(
    run_pipeline(
      r_step("Sys.sleep(20)"),
      r_copy_step(),
      env_name = "stub-env",
      verbose = "silent",
      timeout = 1
    ),
    class = "condathis_run_pipeline_timeout_error"
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_run_pipeline_timeout_error",
      "condathis_pipeline_timeout_error",
      "condathis_timeout_error",
      "condathis_error",
      "rlang_error",
      "error",
      "condition"
    )
  )
  testthat::expect_identical(cnd$status, -9L)
  testthat::expect_true(cnd$timeout)
  testthat::expect_true(cnd$result$timeout)
  testthat::expect_identical(
    rlang::call_name(conditionCall(cnd)),
    "run_pipeline"
  )
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "timed out after 1 seconds.",
    fixed = TRUE
  )

  res <- run_pipeline(
    r_step("Sys.sleep(20)"),
    r_copy_step(),
    env_name = "stub-env",
    verbose = "silent",
    error = "continue",
    timeout = 1
  )
  testthat::expect_true(res$timeout)
  testthat::expect_identical(res$status, -9L)
})

testthat::test_that("a timeout above the largest process wait is lowered", {
  testthat::skip_on_cran()
  local_pipeline_stub()
  # A deadline this far away gave a wait in milliseconds that is not an
  # integer.
  res <- run_pipeline(
    r_step("cat('far-deadline')"),
    r_copy_step(),
    env_name = "stub-env",
    verbose = "silent",
    timeout = 1e10
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(parse_output(res), "far-deadline")
})

testthat::test_that("a missing step environment aborts with condathis_env_not_found", {
  local_pipeline_stub()
  cnd <- testthat::expect_error(
    run_pipeline(
      run_step("cmd-a"),
      run_step("cmd-b"),
      env_name = "stub-missing-env",
      verbose = "silent"
    ),
    class = "condathis_run_pipeline_env_not_found"
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_run_pipeline_env_not_found",
      "condathis_pipeline_env_not_found",
      "condathis_env_not_found",
      "condathis_error",
      "rlang_error",
      "error",
      "condition"
    )
  )
  testthat::expect_identical(
    rlang::call_name(conditionCall(cnd)),
    "run_pipeline"
  )
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "Environment stub-missing-env does not exist.",
    fixed = TRUE
  )

  res <- run_pipeline(
    run_step("cmd-a"),
    run_step("cmd-b"),
    env_name = "stub-missing-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_identical(res$statuses, c(127L, 127L))
  testthat::expect_identical(res$status, 127L)
})

testthat::test_that("run_pipeline() creates condathis-env with the backend that method names", {
  testthat::skip_on_cran()
  # Regression test: the default environment was always created through
  # `method = "auto"`, so under the first backend in priority order, and
  # then only warned that it belonged to another backend.
  stub_a <- local_stub_backend("stub-a")
  stub_b <- local_stub_backend("stub-b")
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() c("stub-b", "stub-a")
  )
  testthat::expect_no_warning(
    res <- run_pipeline(
      r_step("cat('created')"),
      r_copy_step(),
      method = "stub-a",
      verbose = "silent"
    ),
    class = "condathis_backend_mismatch_warning"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_true(fs::dir_exists(fs::path(
    stub_a$root,
    "envs",
    "condathis-env"
  )))
  testthat::expect_false(fs::dir_exists(fs::path(
    stub_b$root,
    "envs",
    "condathis-env"
  )))
  testthat::expect_length(stub_calls(stub_b, "backend_create_env"), 0L)
})

testthat::test_that("run_pipeline() runs each command in the directory the backend gives", {
  testthat::skip_on_cran()
  backend_dir <- withr::local_tempdir()
  local_pipeline_stub(
    backend_resolve_run = function(backend, cmd, args = character(0L), ...) {
      return(list(command = cmd, args = args, env = NULL, dir = backend_dir))
    }
  )
  res <- run_pipeline(
    r_step("cat(getwd())"),
    r_step("writeLines(c(readLines(file('stdin'), warn = FALSE), getwd()))"),
    env_name = "stub-env",
    verbose = "silent"
  )
  dirs <- parse_output(res)
  testthat::expect_length(dirs, 2L)
  testthat::expect_identical(same_dir(dirs[[1L]]), same_dir(backend_dir))
  testthat::expect_identical(same_dir(dirs[[2L]]), same_dir(backend_dir))

  # `activate = FALSE` does not ask the backend: R's working directory.
  res <- run_pipeline(
    r_step("cat(getwd())"),
    r_copy_step(),
    env_name = "stub-env",
    verbose = "silent",
    activate = FALSE
  )
  testthat::expect_identical(same_dir(parse_output(res)), same_dir(getwd()))
})

testthat::test_that("an invalid dir from the backend is a contract error", {
  testthat::skip_on_cran()
  local_pipeline_stub(
    backend_resolve_run = function(backend, cmd, args = character(0L), ...) {
      return(list(command = cmd, args = args, env = NULL, dir = 1))
    }
  )
  cnd <- testthat::expect_error(
    run_pipeline(
      r_step("cat('x')"),
      r_copy_step(),
      env_name = "stub-env",
      verbose = "silent"
    ),
    class = "condathis_backend_resolve_run_invalid"
  )
  testthat::expect_identical(
    rlang::call_name(conditionCall(cnd)),
    "run_pipeline"
  )
  # The error names the backend, as in run() and run_bin(), and is not
  # wrapped as a resolution failure.
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "Backend stub-pipe returned an invalid value",
    fixed = TRUE
  )
  testthat::expect_false(inherits(cnd, "condathis_run_pipeline_resolve_failed"))
  res <- run_pipeline(
    r_step("cat('x')"),
    r_copy_step(),
    env_name = "stub-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_identical(res$statuses, c(127L, 127L))
})

testthat::test_that("a command that cannot be resolved aborts with the resolve class, or gives one text", {
  testthat::skip_on_cran()
  local_pipeline_stub(
    backend_resolve_run = function(...) {
      cli::cli_abort(
        message = "Activation {.strong broke}.",
        class = "stub_activation_error"
      )
    }
  )
  withr::local_options(cli.num_colors = 256L)
  # Under error = "cancel": a resolution error, not a status error. The
  # backend's error is the parent, so its own class is still found.
  cnd <- testthat::expect_error(
    run_pipeline(
      r_step("cat('x')"),
      r_copy_step(),
      env_name = "stub-env",
      verbose = "silent"
    ),
    class = "condathis_run_pipeline_resolve_failed"
  )
  testthat::expect_identical(
    setdiff(class(cnd), c("rlang_error", "error", "condition")),
    c(
      "condathis_run_pipeline_resolve_failed",
      "condathis_backend_error",
      "condathis_error"
    )
  )
  testthat::expect_false(inherits(cnd, "condathis_status_error"))
  testthat::expect_s3_class(cnd$parent, "stub_activation_error")
  testthat::expect_true(rlang::cnd_inherits(cnd, "stub_activation_error"))
  testthat::expect_identical(
    rlang::call_name(conditionCall(cnd)),
    "run_pipeline"
  )
  header <- cli::ansi_strip(rlang::cnd_header(cnd))
  testthat::expect_match(header, "Backend stub-pipe", fixed = TRUE)
  testthat::expect_match(header, "resolve command 1", fixed = TRUE)
  testthat::expect_match(header, "environment stub-env", fixed = TRUE)

  # Under error = "continue": status 127, and the text of
  # resolve_failure_stderr(), without ANSI codes and with a final newline.
  res <- run_pipeline(
    r_step("cat('x')"),
    r_copy_step(),
    env_name = "stub-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_identical(res$statuses, c(127L, 127L))
  testthat::expect_identical(
    res$processes[[1L]]$stderr,
    "Failed to resolve command for environment 'stub-env': Activation broke.\n"
  )
})

testthat::test_that("a plain error from a backend's backend_resolve_run() gets the condathis classes", {
  testthat::skip_on_cran()
  # A third-party backend that calls stop(), for the second command only.
  # Before, `error = "cancel"` re-raised the bare `simpleError`, with the
  # call of the backend's own function.
  local_pipeline_stub(
    backend_resolve_run = function(backend, cmd, args = character(0L), ...) {
      if (isTRUE(any(grepl("FAILME", args, fixed = TRUE)))) {
        stop("plain backend failure")
      }
      return(list(command = cmd, args = args, env = NULL, dir = NULL))
    }
  )
  cnd <- testthat::expect_error(
    run_pipeline(
      r_step("cat('x')"),
      r_step("cat('FAILME')"),
      env_name = "stub-env",
      verbose = "silent"
    ),
    class = "condathis_run_pipeline_resolve_failed"
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_run_pipeline_resolve_failed",
      "condathis_backend_error",
      "condathis_error",
      "rlang_error",
      "error",
      "condition"
    )
  )
  testthat::expect_s3_class(cnd$parent, "simpleError")
  testthat::expect_identical(
    conditionMessage(cnd$parent),
    "plain backend failure"
  )
  testthat::expect_identical(
    rlang::call_name(conditionCall(cnd)),
    "run_pipeline"
  )
  testthat::expect_match(
    cli::ansi_strip(rlang::cnd_header(cnd)),
    "resolve command 2",
    fixed = TRUE
  )

  # Under error = "continue", only the second command fails.
  res <- run_pipeline(
    r_step("cat('x')"),
    r_step("cat('FAILME')"),
    env_name = "stub-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_identical(res$statuses[[2L]], 127L)
  testthat::expect_identical(
    res$processes[[2L]]$stderr,
    "Failed to resolve command for environment 'stub-env': plain backend failure\n"
  )
})

testthat::test_that("a failed micromamba activation of an env_path() step names run_pipeline()", {
  testthat::skip_on_cran()
  # The real micromamba resolution of an environment given by path, where
  # only the `micromamba run` process of the activation is replaced by a
  # real process that fails, so the test needs no micromamba binary and
  # runs the same way on every platform. Before, the micromamba status
  # error escaped with an internal call and no step or environment in its
  # message.
  env_dir <- fs::path(withr::local_tempdir(), "broken-env")
  fs::dir_create(fs::path(env_dir, "conda-meta"))
  testthat::local_mocked_bindings(
    ensure_windows_micromamba_bat = function(...) invisible(NULL),
    native_cmd = function(...) {
      return(processx::run(
        command = file.path(R.home("bin"), "Rscript"),
        args = c("--vanilla", "-e", "quit(status = 3L)"),
        error_on_status = TRUE
      ))
    }
  )
  cnd <- testthat::expect_error(
    run_pipeline(
      r_step("cat('x')"),
      r_copy_step(),
      env_name = env_path(env_dir),
      verbose = "silent"
    ),
    class = "condathis_run_pipeline_resolve_failed"
  )
  testthat::expect_identical(
    setdiff(class(cnd), c("rlang_error", "error", "condition")),
    c(
      "condathis_run_pipeline_resolve_failed",
      "condathis_backend_error",
      "condathis_micromamba_status_error",
      "condathis_cmd_status_error",
      "condathis_error"
    )
  )
  testthat::expect_identical(cnd$parent$status, 3L)
  testthat::expect_identical(
    rlang::call_name(conditionCall(cnd)),
    "run_pipeline"
  )
  header <- cli::ansi_strip(rlang::cnd_header(cnd))
  testthat::expect_match(header, "Backend micromamba", fixed = TRUE)
  testthat::expect_match(header, "resolve command 1", fixed = TRUE)
  testthat::expect_match(header, "broken-env", fixed = TRUE)

  res <- run_pipeline(
    r_step("cat('x')"),
    r_copy_step(),
    env_name = env_path(env_dir),
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_identical(res$statuses, c(127L, 127L))
  testthat::expect_match(
    res$processes[[1L]]$stderr,
    "^Failed to resolve command for environment '.*broken-env': .*status code 3"
  )
})

testthat::test_that("both activate modes give a stage the CONDA_ENVS_PATH of the clean overlay", {
  testthat::skip_on_cran()
  stub <- local_pipeline_stub()
  for (activate in c(TRUE, FALSE)) {
    res <- run_pipeline(
      r_step("cat(Sys.getenv('CONDA_ENVS_PATH'))"),
      r_copy_step(),
      env_name = "stub-env",
      verbose = "silent",
      activate = activate
    )
    # A child of another backend: the directory that holds its
    # environment (see child_conda_dirs()).
    testthat::expect_identical(
      same_dir(parse_output(res)),
      same_dir(fs::path(stub$root, "envs"))
    )
  }
})
