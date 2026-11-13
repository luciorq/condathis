testthat::test_that("Run with partial match argument", {
  testthat::expect_error(
    object = {
      run("R", method = "nat")
    },
    class = "rlang_error"
  )
})

testthat::test_that("Run with missing argument", {
  testthat::expect_error(
    object = {
      run("R", method = "Drawing")
    },
    class = "rlang_error"
  )
})

testthat::test_that("Run with unexpected error argument", {
  testthat::expect_error(
    object = {
      run("R", error = "Drawing")
    },
    class = "rlang_error"
  )
})

testthat::test_that("Run with partial match error argument", {
  testthat::expect_error(
    object = {
      run("R", error = "co")
    },
    class = "rlang_error"
  )
})

testthat::test_that("Run with NULL cmd", {
  cnd_res <- rlang::catch_cnd(
    expr = {
      run(cmd = NULL)
    }
  )
  testthat::expect_s3_class(cnd_res, "condathis_run_null_cmd")

  testthat::expect_error(
    object = {
      run(NULL)
    },
    class = "condathis_run_null_cmd"
  )
})


testthat::test_that("Run empty cmd", {
  cnd_res <- rlang::catch_cnd(
    expr = {
      run()
    }
  )
  testthat::expect_s3_class(cnd_res, "rlang_error")

  testthat::expect_error(
    object = {
      run(NULL)
    },
    class = "condathis_run_null_cmd"
  )
})

test_that("Run with missing custom env and error = continue returns a result", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  res <- run(
    "echo",
    "hi",
    env_name = "totally-custom-missing-env",
    error = "continue"
  )
  testthat::expect_s3_class(res, "condathis_result")
  testthat::expect_equal(res$status, 127L)
  testthat::expect_match(
    res$stderr,
    "Conda environment 'totally-custom-missing-env' does not exist"
  )
  testthat::expect_false(
    env_exists("totally-custom-missing-env", verbose = "silent")
  )
})

test_that("Run with missing custom env and error = cancel still fails fast", {
  testthat::expect_error(
    object = run(
      "echo",
      "hi",
      env_name = "totally-custom-missing-env",
      error = "cancel"
    ),
    class = "condathis_run_env_not_found"
  )
  testthat::expect_false(
    env_exists("totally-custom-missing-env", verbose = "silent")
  )
})

test_that("Run with a missing custom env never creates condathis-env as a side effect", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  condathis::with_sandbox_dir({
    testthat::expect_false(env_exists("condathis-env", verbose = "silent"))
    run(
      "echo",
      "hi",
      env_name = "another-totally-custom-missing-env",
      error = "continue"
    )
    testthat::expect_false(env_exists("condathis-env", verbose = "silent"))
  })
})

test_that("Run returns a condathis_result object", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    test_os_pkg("coreutils"),
    env_name = "run-cli-tools-env",
    verbose = "silent"
  )
  res <- run(
    "echo",
    "hello",
    env_name = "run-cli-tools-env",
    verbose = "silent"
  )
  testthat::expect_s3_class(res, "condathis_result")
  testthat::expect_equal(res$status, 0L)
  testthat::expect_match(res$stdout, "hello")
  testthat::expect_true(is.numeric(res$pid))
  testthat::expect_match(res$cmd, "echo")
  testthat::expect_equal(res$env_name, "run-cli-tools-env")

  formatted <- format(res)
  testthat::expect_type(formatted, "character")
  testthat::expect_match(formatted, "condathis_result")
})

test_that("Run supports stdin = '|' with input", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    test_os_pkg("coreutils"),
    env_name = "run-cli-tools-env",
    verbose = "silent"
  )
  res <- run(
    "sort",
    stdin = "|",
    input = "b\na\nc\na\nb\n",
    env_name = "run-cli-tools-env",
    verbose = "silent"
  )
  testthat::expect_s3_class(res, "condathis_result")
  sorted <- strsplit(trimws(res$stdout), "\n")[[1]]
  testthat::expect_equal(sorted, c("a", "a", "b", "b", "c"))
})

test_that("Run rejects input without stdin = '|'", {
  testthat::expect_error(
    object = run("echo", "hello", input = "x", verbose = "silent"),
    class = "condathis_run_invalid_input"
  )
})

test_that("Run with stdin = '|' respects error = cancel/continue", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    c(test_os_pkg("coreutils"), test_os_pkg("bash")),
    env_name = "run-bash-tools-env",
    verbose = "silent"
  )
  res <- run(
    "bash",
    "-c",
    "cat; exit 1",
    stdin = "|",
    input = "boom\n",
    env_name = "run-bash-tools-env",
    error = "continue",
    verbose = "silent"
  )
  testthat::expect_equal(res$status, 1L)
  testthat::expect_match(res$stdout, "boom")

  testthat::expect_error(
    object = run(
      "bash",
      "-c",
      "cat >&2; exit 1",
      stdin = "|",
      input = "boom\n",
      env_name = "run-bash-tools-env",
      error = "cancel",
      verbose = "silent"
    ),
    class = "condathis_run_status_error"
  )
})

test_that("Run accepts crash-safety parameters", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    test_os_pkg("coreutils"),
    env_name = "run-cli-tools-env",
    verbose = "silent"
  )
  # `linux_pdeathsig` is ignored without a warning on platforms other than
  # Linux.
  testthat::expect_no_warning(
    res <- run(
      "echo",
      "hi",
      supervise = TRUE,
      cleanup_tree = TRUE,
      linux_pdeathsig = TRUE,
      env_name = "run-cli-tools-env",
      verbose = "silent"
    )
  )
  testthat::expect_equal(res$status, 0L)
})

test_that("Run with binary = TRUE round-trips raw bytes from a file", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    test_os_pkg("coreutils"),
    env_name = "run-cli-tools-env",
    verbose = "silent"
  )

  # includes an embedded NUL and 0xFF, both invalid as standalone UTF-8
  raw_bytes <- as.raw(c(0x00, 0x01, 0xFF, 0x41, 0x0A, 0xFE, 0x00))
  tmp_file <- withr::local_tempfile()
  writeBin(raw_bytes, tmp_file)

  res <- run(
    "cat",
    tmp_file,
    env_name = "run-cli-tools-env",
    binary = TRUE,
    verbose = "silent"
  )
  testthat::expect_type(res$stdout, "raw")
  testthat::expect_identical(res$stdout, raw_bytes)
})

test_that("Run with binary = TRUE round-trips raw bytes through stdin", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    test_os_pkg("coreutils"),
    env_name = "run-cli-tools-env",
    verbose = "silent"
  )

  raw_bytes <- as.raw(c(0x00, 0x01, 0xFF, 0x41, 0x0A, 0xFE, 0x00))
  res <- run(
    "cat",
    stdin = "|",
    input = raw_bytes,
    env_name = "run-cli-tools-env",
    binary = TRUE,
    verbose = "silent"
  )
  testthat::expect_identical(res$stdout, raw_bytes)
})

test_that("Run with binary = FALSE (default) still captures text", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    test_os_pkg("coreutils"),
    env_name = "run-cli-tools-env",
    verbose = "silent"
  )
  res <- run(
    "echo",
    "hello",
    env_name = "run-cli-tools-env",
    verbose = "silent"
  )
  testthat::expect_type(res$stdout, "character")

  formatted <- format(res)
  testthat::expect_type(formatted, "character")
})

test_that("Run rejects non-logical binary argument", {
  testthat::expect_error(
    object = run("echo", "hello", binary = "yes", verbose = "silent"),
    class = "condathis_run_invalid_binary_arg"
  )
})

test_that("Run with stdin = '|' does not deadlock when stdout and stderr are both large", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  # Regression test: run_process_with_input() used to call wait() before
  # draining either stream, which deadlocks once combined output exceeds
  # the OS pipe buffer (64KB on Linux, smaller on macOS/Windows) - the
  # child blocks on write() to whichever stream isn't read yet, so it never
  # exits, so wait() never returns.
  #
  # Byte generation uses `head -c N /dev/zero | tr '\0' 'X'`, not
  # `printf '%*s' N ''` - `run()` always spawns `bash` via `micromamba run`
  # (through `native_cmd()`), and confirmed directly on Windows: literal
  # `%` characters are silently stripped somewhere in `micromamba run`'s
  # own Windows argument handling (even a bare `echo '100% done'` comes
  # back as `100 done`), corrupting `printf`'s format string and any
  # command containing one. `head`/`tr` invoked directly (bypassing
  # `micromamba run`, e.g. from `run_pipeline()`) are unaffected - this is
  # specific to arguments that cross that wrapper, not a `condathis` bug.
  create_env(
    c(test_os_pkg("coreutils"), test_os_pkg("bash")),
    env_name = "run-bash-tools-env",
    verbose = "silent"
  )
  res <- run(
    "bash",
    "-c",
    "cat; head -c 200000 /dev/zero | tr '\\0' 'B' 1>&2",
    stdin = "|",
    input = strrep("A", 200000),
    env_name = "run-bash-tools-env",
    verbose = "silent"
  )
  testthat::expect_equal(nchar(res$stdout), 200000L)
  testthat::expect_equal(nchar(res$stderr), 200000L)
})

test_that("Run with stdin = '|' does not truncate large input", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  # Regression test: write_input() once, then close immediately, silently
  # truncates `input` past the OS pipe buffer - confirmed empirically: only
  # 8192 of 200000 bytes delivered on macOS, no error. `wc -c` independently
  # counts exactly how many bytes the child received on stdin.
  create_env(
    test_os_pkg("coreutils"),
    env_name = "run-cli-tools-env",
    verbose = "silent"
  )
  res <- run(
    "wc",
    "-c",
    stdin = "|",
    input = strrep("A", 200000),
    env_name = "run-cli-tools-env",
    verbose = "silent"
  )
  testthat::expect_equal(trimws(res$stdout), "200000")
})

test_that("Run respects timeout under error = continue", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    test_os_pkg("coreutils"),
    env_name = "run-cli-tools-env",
    verbose = "silent"
  )
  res <- run(
    "sleep",
    "5",
    env_name = "run-cli-tools-env",
    error = "continue",
    timeout = 1,
    verbose = "silent"
  )
  testthat::expect_s3_class(res, "condathis_result")
  testthat::expect_equal(res$status, -9L)
  testthat::expect_true(res$timeout)
})

test_that("Run timeout is enforced when stdout/stderr are redirected to files", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  # Regression test: with both streams file-redirected the stream pump has
  # nothing to watch, returns immediately, and a bare `wait()` used to
  # block until the child exited on its own - silently disabling `timeout`
  # entirely (a 2-second timeout waited out the whole sleep).
  create_env(
    test_os_pkg("coreutils"),
    env_name = "run-cli-tools-env",
    verbose = "silent"
  )
  out_file <- withr::local_tempfile()
  err_file <- withr::local_tempfile()
  t_start <- Sys.time()
  res <- run(
    "sleep",
    "30",
    env_name = "run-cli-tools-env",
    stdin = "|",
    input = "",
    stdout = out_file,
    stderr = err_file,
    error = "continue",
    timeout = 2,
    verbose = "silent"
  )
  elapsed <- as.numeric(Sys.time() - t_start, units = "secs")
  testthat::expect_equal(res$status, -9L)
  testthat::expect_true(res$timeout)
  testthat::expect_lt(elapsed, 20)
})

test_that("Run respects timeout under error = cancel", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    test_os_pkg("coreutils"),
    env_name = "run-cli-tools-env",
    verbose = "silent"
  )
  cnd_res <- rlang::catch_cnd(
    expr = {
      run(
        "sleep",
        "5",
        env_name = "run-cli-tools-env",
        error = "cancel",
        timeout = 1,
        verbose = "silent"
      )
    }
  )
  testthat::expect_s3_class(cnd_res, "condathis_run_timeout_error")
})

test_that("Run with stdin = '|' also respects timeout", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    c(test_os_pkg("coreutils"), test_os_pkg("bash")),
    env_name = "run-bash-tools-env",
    verbose = "silent"
  )
  # The timeout leaves room for process startup before `echo` runs: on
  # Windows, starting `bash` alone can take more than a second, and a
  # one-second timeout then killed it before it printed anything.
  res <- run(
    "bash",
    "-c",
    "echo hello; sleep 60",
    stdin = "|",
    input = "unused\n",
    env_name = "run-bash-tools-env",
    error = "continue",
    timeout = 5,
    verbose = "silent"
  )
  testthat::expect_equal(res$status, -9L)
  testthat::expect_true(res$timeout)
  testthat::expect_match(res$stdout, "hello")
})

test_that("format.condathis_result previews raw stdout without erroring", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    test_os_pkg("coreutils"),
    env_name = "run-cli-tools-env",
    verbose = "silent"
  )
  raw_bytes <- as.raw(c(0x00, 0x01, 0xFF))
  tmp_file <- withr::local_tempfile()
  writeBin(raw_bytes, tmp_file)

  res <- run(
    "cat",
    tmp_file,
    env_name = "run-cli-tools-env",
    binary = TRUE,
    verbose = "silent"
  )
  formatted <- format(res)
  testthat::expect_type(formatted, "character")
  testthat::expect_match(formatted, "binary data, 3 bytes")
})

test_that("Run proceeds when the environment existence check itself fails", {
  # Regression test: the execution gate used backend_has_env(), whose
  # never-errors contract coerces a *failed* `micromamba env list`
  # (transient lock, corrupt metadata, JSON hiccup) to FALSE - so run()
  # aborted "environment does not exist" for environments that exist and
  # would run fine. An undeterminable existence check must fall through
  # to execution, not block it.
  testthat::local_mocked_bindings(
    backend_env_exists = function(...) {
      cli::cli_abort("Simulated transient listing failure.")
    },
    run_internal_backend = function(...) {
      list(status = 0L, stdout = "ran fine", stderr = "", timeout = FALSE)
    }
  )
  # Backend resolution reports the failed probe as a warning (rule R5) and
  # goes on.
  testthat::expect_warning(
    res <- run(
      "echo",
      "hi",
      env_name = "some-existing-env",
      error = "cancel",
      verbose = "silent"
    ),
    class = "condathis_backend_query_failed"
  )
  testthat::expect_equal(res$status, 0L)
  testthat::expect_equal(res$stdout, "ran fine")
})

test_that("Run reports the real exit status when the child exits before consuming input", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  # Regression test: a child exiting before consuming a large stdin
  # `input` raises a low-level broken-pipe error from the write, which
  # used to escape pump_process_io() and get misreported by
  # rethrow_error_run() as a status-127 "command not found" - masking the
  # child's real exit status.
  create_env(
    c(test_os_pkg("coreutils"), test_os_pkg("bash")),
    env_name = "run-bash-tools-env",
    verbose = "silent"
  )
  res <- run(
    "bash",
    "-c",
    "exit 3",
    stdin = "|",
    input = strrep("x", 200000L),
    env_name = "run-bash-tools-env",
    error = "continue",
    verbose = "silent"
  )
  testthat::expect_equal(res$status, 3L)

  testthat::expect_error(
    object = run(
      "bash",
      "-c",
      "exit 3",
      stdin = "|",
      input = strrep("x", 200000L),
      env_name = "run-bash-tools-env",
      error = "cancel",
      verbose = "silent"
    ),
    class = "condathis_run_status_error"
  )
})

test_that("the backend run path routes resolution failures through `error`", {
  # Regression test: on the direct-spawn path (every non-micromamba backend,
  # and micromamba on Windows), a failing backend_resolve_run() escaped
  # error = "continue" or was reported as a failure of the command itself.
  testthat::local_mocked_bindings(
    backend_resolve_run = function(...) {
      cli::cli_abort(
        "Simulated activation failure.",
        class = "condathis_activation_dump_error"
      )
    }
  )
  res <- run_internal_backend(
    micromamba_backend(),
    "true",
    env_name = "any-env",
    error = "continue",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 127L)
  # One text for every "Failed to resolve" result: no ANSI codes, and a
  # final newline.
  testthat::expect_identical(
    res$stderr,
    "Failed to resolve command for environment 'any-env': Simulated activation failure.\n"
  )
  testthat::expect_error(
    run_internal_backend(
      micromamba_backend(),
      "true",
      env_name = "any-env",
      error = "cancel",
      verbose = "silent"
    ),
    class = "condathis_activation_dump_error"
  )
})

test_that("run() wraps a backend's resolution error with its own class", {
  # Regression test: under error = "cancel", run() re-raised the backend's
  # error unchanged, with an internal call, and a backend that calls stop()
  # gave a bare simpleError without condathis_error. run_pipeline()
  # already wrapped it.
  stub <- local_run_family_stub(
    backend_resolve_run = function(...) {
      stop("plain resolution failure")
    }
  )
  cnd <- rlang::catch_cnd(
    run("echo", "hi", env_name = "stub-env", verbose = "silent"),
    classes = "error"
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_run_resolve_failed",
      "condathis_backend_error",
      "condathis_error",
      "rlang_error",
      "error",
      "condition"
    )
  )
  testthat::expect_s3_class(cnd$parent, "simpleError")
  testthat::expect_identical(rlang::call_name(conditionCall(cnd)), "run")
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "Backend stub-run failed to resolve command `echo` for environment stub-env.",
    fixed = TRUE
  )

  # The condathis classes of the backend's error stay on the new error.
  stub <- local_run_family_stub(
    "stub-run-classed",
    backend_resolve_run = function(...) {
      cli::cli_abort(
        "Simulated activation failure.",
        class = "condathis_activation_dump_error"
      )
    }
  )
  cnd <- rlang::catch_cnd(
    run("echo", env_name = "stub-env", verbose = "silent"),
    classes = "error"
  )
  testthat::expect_identical(
    class(cnd)[1:4],
    c(
      "condathis_run_resolve_failed",
      "condathis_backend_error",
      "condathis_activation_dump_error",
      "condathis_error"
    )
  )

  # Under error = "continue", the result is unchanged.
  res <- run(
    "echo",
    env_name = "stub-env",
    error = "continue",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 127L)
  testthat::expect_identical(
    res$stderr,
    "Failed to resolve command for environment 'stub-env': Simulated activation failure.\n"
  )
})

test_that("the writable-stdin path kills its child when R exits early", {
  # Regression test: an R-level abort during the I/O pump (an error, an
  # interrupt, setTimeLimit()) left the child running until garbage
  # collection.
  px <- processx:::get_tool("px")
  seen <- NULL
  testthat::local_mocked_bindings(
    pump_process_io = function(proc, ...) {
      seen <<- proc
      stop("simulated abort inside the pump")
    }
  )
  testthat::expect_error(
    run_process_with_input(px, c("sleep", "30"), input = "x"),
    "simulated abort"
  )
  testthat::expect_false(is.null(seen))
  testthat::expect_false(seen$is_alive())
})

# --- Argument checks (rules R1 and R2) --------------------------------------

testthat::test_that("run() rejects a cmd that is not a single, non-empty string", {
  # Regression test: run(1) and run(NA_character_) tried to start programs
  # named "1" and "NA", run("") failed with status 126, and
  # run(c("echo", "x")) silently ran `echo x`.
  local_no_backend_calls()
  for (bad_cmd in list(1, NA_character_, "", c("echo", "x"), NULL, TRUE)) {
    cnd <- testthat::expect_error(
      run(bad_cmd, verbose = "silent"),
      class = "condathis_run_invalid_cmd"
    )
    # The old class stays on every invalid cmd.
    testthat::expect_identical(
      class(cnd)[1:5],
      c(
        "condathis_run_invalid_cmd",
        "condathis_run_null_cmd",
        "condathis_invalid_cmd",
        "condathis_invalid_arg",
        "condathis_error"
      )
    )
    testthat::expect_identical(rlang::call_name(conditionCall(cnd)), "run")
  }
  cnd <- testthat::expect_error(run(), class = "condathis_run_invalid_cmd")
  testthat::expect_match(conditionMessage(cnd), "absent", fixed = TRUE)
  cnd <- testthat::expect_error(
    run(c("echo", "x")),
    class = "condathis_invalid_cmd"
  )
  testthat::expect_match(conditionMessage(cnd), "...", fixed = TRUE)
})

testthat::test_that("run() checks timeout and the process arguments before any backend call", {
  # Regression test: a non-numeric `timeout` failed late with an unclassed
  # processx error (after `condathis-env` was created), or meant no limit.
  local_no_backend_calls()
  bad_args <- list(
    timeout = list("10", NA, -1, c(1, 2)),
    supervise = list(NA, "yes"),
    cleanup_tree = list(NA),
    linux_pdeathsig = list(1L),
    stdout = list(1),
    stderr = list(c("|", "|")),
    stdin = list("/nonexistent/condathis-stdin-file")
  )
  for (arg in names(bad_args)) {
    for (value in bad_args[[arg]]) {
      call_args <- c(
        list("echo", verbose = "silent"),
        rlang::set_names(list(value), arg)
      )
      cnd <- testthat::expect_error(
        do.call(run, call_args),
        class = paste0("condathis_run_invalid_", arg),
        info = arg
      )
      testthat::expect_s3_class(cnd, paste0("condathis_invalid_", arg))
      testthat::expect_s3_class(cnd, "condathis_invalid_arg")
      testthat::expect_s3_class(cnd, "condathis_error")
    }
  }
  # The old stdin class stays.
  testthat::expect_error(
    run("echo", stdin = "/nonexistent/condathis-stdin-file"),
    class = "condathis_run_stdin_error"
  )
})

testthat::test_that("run() lowers a huge timeout to what processx accepts", {
  stub <- local_run_family_stub()
  seen_timeout <- NULL
  testthat::local_mocked_bindings(
    run_internal_backend = function(..., timeout) {
      seen_timeout <<- timeout
      return(list(status = 0L, stdout = "", stderr = "", timeout = FALSE))
    }
  )
  run("echo", env_name = "stub-env", timeout = 1e10, verbose = "silent")
  testthat::expect_identical(seen_timeout, 2147483)
  run("echo", env_name = "stub-env", timeout = Inf, verbose = "silent")
  testthat::expect_identical(seen_timeout, Inf)
})

testthat::test_that("run() raises classed errors for error, verbose, input, binary and env_name", {
  local_no_backend_calls()
  cnd <- testthat::expect_error(
    run("echo", error = "bogus"),
    class = "condathis_invalid_error"
  )
  # A shared parser: only the shared classes.
  testthat::expect_identical(
    class(cnd)[1:3],
    c("condathis_invalid_error", "condathis_invalid_arg", "condathis_error")
  )
  testthat::expect_identical(rlang::call_name(conditionCall(cnd)), "run")

  cnd <- testthat::expect_error(
    run("echo", verbose = "bogus"),
    class = "condathis_invalid_verbose"
  )
  testthat::expect_identical(rlang::call_name(conditionCall(cnd)), "run")

  for (bad_input in list(1, c("a", NA))) {
    cnd <- testthat::expect_error(
      run("echo", stdin = "|", input = bad_input),
      class = "condathis_run_invalid_input"
    )
    testthat::expect_identical(
      class(cnd)[1:4],
      c(
        "condathis_run_invalid_input",
        "condathis_invalid_input",
        "condathis_invalid_arg",
        "condathis_error"
      )
    )
  }
  cnd <- testthat::expect_error(
    run("echo", input = "x"),
    class = "condathis_invalid_input"
  )
  testthat::expect_match(conditionMessage(cnd), "must be", fixed = TRUE)

  cnd <- testthat::expect_error(
    run("echo", binary = "yes"),
    class = "condathis_run_invalid_binary"
  )
  testthat::expect_identical(
    class(cnd)[1:5],
    c(
      "condathis_run_invalid_binary",
      "condathis_run_invalid_binary_arg",
      "condathis_invalid_binary",
      "condathis_invalid_arg",
      "condathis_error"
    )
  )
  testthat::expect_match(conditionMessage(cnd), "must be", fixed = TRUE)

  cnd <- testthat::expect_error(
    run("echo", env_name = 1),
    class = "condathis_run_invalid_env_name"
  )
  testthat::expect_s3_class(cnd, "condathis_invalid_env_name")
  testthat::expect_s3_class(cnd, "condathis_error")
})

testthat::test_that("run() rejects named command arguments with a hint", {
  # Regression test: a misspelled option lands in `...`, and the rlang
  # error had no condathis class. The classes of that rlang error stay,
  # so old handlers still match.
  local_no_backend_calls()
  cnd <- testthat::expect_error(
    run("echo", "x", verbos = "silent"),
    class = "condathis_run_invalid_args"
  )
  testthat::expect_identical(
    setdiff(class(cnd), c("rlang_error", "error", "condition")),
    c(
      "condathis_run_invalid_args",
      "condathis_invalid_cmd_args",
      "condathis_invalid_arg",
      "condathis_error",
      "rlib_error_dots_named",
      "rlib_error_dots"
    )
  )
  testthat::expect_error(
    run("echo", "x", verbos = "silent"),
    class = "rlib_error_dots_named"
  )
  # The old classes are only on the error of a named value.
  na_cnd <- testthat::expect_error(
    run("echo", NA),
    class = "condathis_run_invalid_args"
  )
  testthat::expect_false(inherits(na_cnd, "rlib_error_dots_named"))
  testthat::expect_match(conditionMessage(cnd), "verbose", fixed = TRUE)
  testthat::expect_identical(rlang::call_name(conditionCall(cnd)), "run")
  testthat::expect_error(
    run("echo", list("x")),
    class = "condathis_invalid_cmd_args"
  )
})

# --- Missing environments (decision D3) -------------------------------------

testthat::test_that("run() reports a missing custom environment with the shared class", {
  stub <- local_run_family_stub()
  cnd <- testthat::expect_error(
    run("echo", env_name = "stub-missing-env", verbose = "silent"),
    class = "condathis_run_env_not_found"
  )
  testthat::expect_identical(
    class(cnd)[1:3],
    c(
      "condathis_run_env_not_found",
      "condathis_env_not_found",
      "condathis_error"
    )
  )
  testthat::expect_identical(rlang::call_name(conditionCall(cnd)), "run")
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "stub-missing-env",
    fixed = TRUE
  )

  res <- run(
    "echo",
    env_name = "stub-missing-env",
    error = "continue",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 127L)
  testthat::expect_identical(
    res$stderr,
    "Conda environment 'stub-missing-env' does not exist.\n"
  )
  # Nothing was created, and nothing was run.
  testthat::expect_false(fs::dir_exists(fs::path(
    stub$root,
    "envs",
    "stub-missing-env"
  )))
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
  testthat::expect_length(stub_calls(stub, "backend_resolve_run"), 0L)
})

testthat::test_that("run() creates condathis-env with the backend that method names", {
  testthat::skip_on_cran()
  # Regression test: create_base_env() always used method = "auto", so with
  # another backend first in priority order, run(method = "a") created
  # condathis-env under that other backend and then warned that the
  # environment was owned by it.
  stub_a <- local_stub_backend("stub-a")
  stub_b <- local_stub_backend("stub-b")
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() c("stub-b", "stub-a")
  )
  rscript <- run_family_rscript()
  testthat::expect_no_warning(
    res <- run(
      rscript,
      "--vanilla",
      "-e",
      "cat('created')",
      method = "stub-a",
      verbose = "silent"
    )
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(res$stdout, "created")
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

# --- Errors of a failed command ----------------------------------------------

testthat::test_that("run() status errors carry the exit status and the output", {
  testthat::skip_on_cran()
  # Regression test: the status was only in the message text.
  stub <- local_run_family_stub()
  rscript <- run_family_rscript()
  code <- "cat('some output'); message('some error'); quit(status = 3)"
  status <- tryCatch(
    run(
      rscript,
      "--vanilla",
      "-e",
      code,
      env_name = "stub-env",
      verbose = "silent"
    ),
    condathis_status_error = function(e) e$status
  )
  testthat::expect_identical(status, 3L)

  cnd <- testthat::expect_error(
    run(
      rscript,
      "--vanilla",
      "-e",
      code,
      env_name = "stub-env",
      verbose = "silent"
    ),
    class = "condathis_run_status_error"
  )
  testthat::expect_identical(
    class(cnd)[1:3],
    c("condathis_run_status_error", "condathis_status_error", "condathis_error")
  )
  testthat::expect_identical(rlang::call_name(conditionCall(cnd)), "run")
  testthat::expect_identical(cnd$stdout, "some output")
  testthat::expect_match(cnd$stderr, "some error", fixed = TRUE)
  testthat::expect_false(cnd$timeout)

  # A stream that was not captured is NA, as in the result.
  out_file <- withr::local_tempfile()
  cnd <- testthat::expect_error(
    run(
      rscript,
      "--vanilla",
      "-e",
      code,
      env_name = "stub-env",
      stdout = out_file,
      verbose = "silent"
    ),
    class = "condathis_status_error"
  )
  testthat::expect_identical(cnd$stdout, NA_character_)
})

testthat::test_that("run() timeout errors carry the shared class and fields", {
  testthat::skip_on_cran()
  stub <- local_run_family_stub()
  cnd <- testthat::expect_error(
    run(
      run_family_rscript(),
      "--vanilla",
      "-e",
      "Sys.sleep(30)",
      env_name = "stub-env",
      timeout = 1,
      verbose = "silent"
    ),
    class = "condathis_timeout_error"
  )
  testthat::expect_identical(
    class(cnd)[1:3],
    c(
      "condathis_run_timeout_error",
      "condathis_timeout_error",
      "condathis_error"
    )
  )
  testthat::expect_true(cnd$timeout)
  testthat::expect_identical(cnd$status, -9L)
})

# --- The backend_resolve_run() contract ---------------------------------------

testthat::test_that("run() checks the dir that backend_resolve_run() returns", {
  # Regression test: dir was not checked, so processx failed late with an
  # error that named no backend.
  stub <- local_run_family_stub(
    backend_resolve_run = function(backend, cmd, args = character(0L), ...) {
      return(list(command = cmd, args = args, env = NULL, dir = 1))
    }
  )
  cnd <- testthat::expect_error(
    run("echo", env_name = "stub-env", verbose = "silent"),
    class = "condathis_backend_resolve_run_invalid"
  )
  testthat::expect_identical(
    class(cnd)[1:4],
    c(
      "condathis_backend_resolve_run_invalid",
      "condathis_backend_invalid_return",
      "condathis_backend_contract_violation",
      "condathis_error"
    )
  )
  # The error names the user's call and the backend.
  testthat::expect_identical(rlang::call_name(conditionCall(cnd)), "run")
  testthat::expect_match(conditionMessage(cnd), "stub-run", fixed = TRUE)

  res <- run(
    "echo",
    env_name = "stub-env",
    error = "continue",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 127L)
  testthat::expect_match(
    res$stderr,
    "^Failed to resolve command for environment 'stub-env': .*\n$"
  )
})

testthat::test_that("run() runs in the dir that backend_resolve_run() returns", {
  testthat::skip_on_cran()
  work_dir <- withr::local_tempdir()
  stub <- local_run_family_stub(
    backend_resolve_run = function(backend, cmd, args = character(0L), ...) {
      return(list(command = cmd, args = args, env = NULL, dir = work_dir))
    }
  )
  res <- run(
    run_family_rscript(),
    "--vanilla",
    "-e",
    "cat(getwd())",
    env_name = "stub-env",
    verbose = "silent"
  )
  testthat::expect_identical(
    normalizePath(res$stdout, winslash = "/"),
    normalizePath(work_dir, winslash = "/")
  )
})

# --- Process tree cleanup (run-family-docs) ---------------------------------

testthat::test_that("cleanup_tree = TRUE stops a daemon on both stdin paths of run() and run_bin()", {
  # Regression test: with `stdin = "|"`, the process tree was killed only
  # when the process object was garbage collected, so a daemon the command
  # started outlived the call. Without a writable stdin, `processx::run()`
  # already killed it.
  testthat::skip_on_cran()
  stub <- local_run_family_stub()
  daemon <- local_run_family_daemon()
  for (fn_name in c("run", "run_bin")) {
    for (with_input in c(FALSE, TRUE)) {
      pid_file <- file.path(
        daemon$dir,
        paste0(fn_name, "-", with_input, "-tree.pid")
      )
      res <- do.call(
        fn_name,
        list(
          run_family_rscript(),
          daemon$args(pid_file),
          env_name = "stub-env",
          stdin = if (isTRUE(with_input)) "|" else NULL,
          input = if (isTRUE(with_input)) "x" else NULL,
          cleanup_tree = TRUE,
          verbose = "silent"
        )
      )
      label <- paste0(fn_name, "(), input: ", with_input)
      testthat::expect_identical(res$status, 0L, info = label)
      pid <- run_family_read_pid(pid_file)
      testthat::expect_false(is.na(pid), info = label)
      testthat::expect_false(run_family_pid_survives(pid), info = label)
    }
  }
})

testthat::test_that("cleanup_tree = FALSE keeps a daemon alive with stdin = '|'", {
  # The default keeps daemons alive, on the writable-stdin path too: only
  # a child that still runs when the call returns is killed.
  # The output goes to files: on Windows, a daemon that holds a captured
  # output pipe ends when processx has read that output (checked with
  # processx 3.9.0), whatever `cleanup_tree` is.
  testthat::skip_on_cran()
  stub <- local_run_family_stub()
  daemon <- local_run_family_daemon()
  pid_file <- file.path(daemon$dir, "kept.pid")
  res <- run(
    run_family_rscript(),
    daemon$args(pid_file),
    env_name = "stub-env",
    stdin = "|",
    input = "x",
    stdout = file.path(daemon$dir, "kept.out"),
    stderr = file.path(daemon$dir, "kept.err"),
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  pid <- run_family_read_pid(pid_file)
  testthat::expect_true(run_family_pid_running(pid))
})

testthat::test_that("linux_pdeathsig = TRUE reaches processx on Linux only, on every path that starts a command", {
  testthat::skip_on_cran()
  # processx warns about a `linux_pdeathsig` other than FALSE on platforms
  # other than Linux, where it ignores it. condathis passes FALSE there.
  stub <- local_run_family_stub()
  rscript <- run_family_rscript()
  real_process <- processx::process
  seen <- new.env(parent = emptyenv())
  seen$values <- list()
  # `processx::run()` also starts its process with `process$new()`. Only
  # the commands get `linux_pdeathsig`, not the orphaned-pipe watchers that
  # a pipeline starts on Windows.
  testthat::local_mocked_bindings(
    process = list(
      new = function(...) {
        px_args <- list(...)
        if (isTRUE("linux_pdeathsig" %in% names(px_args))) {
          seen$values <- c(seen$values, list(px_args[["linux_pdeathsig"]]))
        }
        return(real_process$new(...))
      }
    ),
    .package = "processx"
  )

  testthat::expect_no_warning(
    res <- run(
      rscript,
      "--vanilla",
      "-e",
      "cat('run')",
      env_name = "stub-env",
      linux_pdeathsig = TRUE,
      verbose = "silent"
    )
  )
  testthat::expect_identical(res$stdout, "run")
  testthat::expect_no_warning(
    res <- run(
      rscript,
      "--vanilla",
      "-e",
      "cat(readLines(file('stdin')))",
      env_name = "stub-env",
      stdin = "|",
      input = "input",
      linux_pdeathsig = TRUE,
      verbose = "silent"
    )
  )
  testthat::expect_identical(res$stdout, "input")
  testthat::expect_no_warning(
    res <- run_pipeline(
      run_step(rscript, "--vanilla", "-e", "cat('piped')"),
      run_step(rscript, "--vanilla", "-e", "cat(readLines(file('stdin')))"),
      env_name = "stub-env",
      linux_pdeathsig = TRUE,
      verbose = "silent"
    )
  )
  testthat::expect_identical(res$statuses, c(0L, 0L))
  testthat::expect_identical(res$processes[[2L]]$stdout, "piped")

  on_linux <- identical(Sys.info()[["sysname"]], "Linux")
  testthat::expect_identical(seen$values, rep(list(on_linux), 4L))
})

testthat::test_that("linux_pdeathsig = TRUE ends the command when R ends, on Linux only", {
  # On Linux, the command of an R session that ends, even by a crash, gets
  # SIGTERM. On other platforms condathis ignores the option, so the
  # command fares as with FALSE.
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("callr")
  # The R children that this test kills cannot delete their temporary
  # directories.
  local_child_tempdir()
  register_lock_stub(env = environment())
  withr::defer({
    root <- backend_root_dir("lockstub")
    if (isTRUE(fs::dir_exists(root))) {
      fs::dir_delete(root)
    }
  })
  create_env(
    env_name = "pdeathsig-env",
    method = "lockstub",
    verbose = "silent"
  )
  dir <- withr::local_tempdir()
  sleeper <- file.path(dir, "sleeper.R")
  writeLines(
    c(
      "pid_file <- commandArgs(TRUE)[[1L]]",
      # Written to a temporary name first, so a reader never sees half.
      "writeLines(as.character(Sys.getpid()), paste0(pid_file, '.tmp'))",
      "file.rename(paste0(pid_file, '.tmp'), pid_file)",
      "Sys.sleep(60)"
    ),
    sleeper
  )
  pids <- integer(0L)
  withr::defer({
    for (pid in pids) {
      if (isTRUE(run_family_pid_running(pid))) {
        tryCatch(ps::ps_kill(ps::ps_handle(pid)), error = function(e) NULL)
      }
    }
  })

  # Runs the sleeper with run() in a new R session (see
  # `local_lock_session()`), kills that session as a crash would, and
  # tells whether the sleeper still runs.
  survives_crash <- function(linux_pdeathsig) {
    pid_file <- file.path(dir, paste0(linux_pdeathsig, ".pid"))
    session <- local_lock_session()
    session$run(register_lock_stub)
    session$call(
      function(rscript, sleeper, pid_file, linux_pdeathsig) {
        condathis::run(
          rscript,
          "--vanilla",
          sleeper,
          pid_file,
          env_name = "pdeathsig-env",
          method = "lockstub",
          linux_pdeathsig = linux_pdeathsig,
          verbose = "silent"
        )
      },
      args = list(
        rscript = run_family_rscript(),
        sleeper = sleeper,
        pid_file = pid_file,
        linux_pdeathsig = linux_pdeathsig
      )
    )
    # A call that fails returns at once, without the PID file.
    lock_wait_until(
      function() {
        isFALSE(is.na(run_family_read_pid(pid_file))) ||
          identical(session$poll_process(0L), "ready")
      },
      what = "the sleeper to start"
    )
    pid <- run_family_read_pid(pid_file)
    if (isTRUE(is.na(pid))) {
      out <- session$read()
      testthat::fail(paste(
        "The sleeper did not start:",
        if (isFALSE(is.null(out$error))) conditionMessage(out$error)
      ))
      return(NA)
    }
    pids <<- c(pids, pid)
    session$kill()
    return(run_family_pid_survives(pid, wait = 5))
  }
  survived <- c(
    `FALSE` = survives_crash(FALSE),
    `TRUE` = survives_crash(TRUE)
  )

  if (isTRUE(identical(Sys.info()[["sysname"]], "Linux"))) {
    testthat::expect_identical(survived, c(`FALSE` = TRUE, `TRUE` = FALSE))
  } else {
    testthat::expect_identical(survived[["TRUE"]], survived[["FALSE"]])
  }
})

# --- base_env, command lookup and signal status (backend contract v2) -------

testthat::test_that("run() gives backend_resolve_run() the child's block before activation", {
  # The backend computes its activation against `base_env`, the block the
  # command gets without activation: the session's environment with the
  # clean conda overlay, the per-call TMPDIR and the backend's conda
  # directories. The child's block is exactly that plus the activation
  # variables.
  seen <- new.env(parent = emptyenv())
  stub <- local_run_family_stub(
    backend_resolve_run = function(
      backend,
      cmd,
      args = character(0L),
      ...,
      base_env = NULL
    ) {
      seen$base_env <- base_env
      return(list(
        command = cmd,
        args = args,
        env = c(CONDATHIS_TEST_ACTIVATED = "yes", CONDA_SHLVL = "1"),
        dir = NULL
      ))
    }
  )
  testthat::local_mocked_bindings(
    execute_command = function(command, args, env, ...) {
      seen$env <- env
      return(list(status = 0L, stdout = "", stderr = "", timeout = FALSE))
    }
  )
  withr::local_envvar(
    CONDATHIS_TEST_SESSION = "kept",
    CONDARC = "/caller/condarc.yml",
    CONDA_PREFIX = "/caller/prefix"
  )
  res <- run(
    run_family_rscript(),
    "--version",
    env_name = "stub-env",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)

  base_env <- seen$base_env
  testthat::expect_type(base_env, "character")
  testthat::expect_false(is.null(names(base_env)))
  testthat::expect_identical(
    unname(base_env[["CONDATHIS_TEST_SESSION"]]),
    "kept"
  )
  testthat::expect_identical(unname(base_env[["CONDARC"]]), "")
  testthat::expect_identical(unname(base_env[["CONDA_PREFIX"]]), "")
  testthat::expect_identical(unname(base_env[["CONDA_SHLVL"]]), "0")
  testthat::expect_match(base_env[["TMPDIR"]], "condathis-tmp", fixed = TRUE)
  testthat::expect_identical(
    unname(base_env[["CONDA_ENVS_PATH"]]),
    as.character(fs::path(stub$root, "envs"))
  )
  testthat::expect_identical(
    unname(base_env[["CONDA_PKGS_DIRS"]]),
    as.character(fs::path(stub$root, "conda-pkgs"))
  )
  testthat::expect_false("CONDATHIS_TEST_ACTIVATED" %in% names(base_env))

  # The child's block: `base_env`, then the activation variables.
  child_env <- seen$env
  overlay_names <- c("CONDATHIS_TEST_ACTIVATED", "CONDA_SHLVL")
  testthat::expect_setequal(
    names(child_env),
    union(names(base_env), overlay_names)
  )
  testthat::expect_identical(
    unname(child_env[overlay_names]),
    c("yes", "1")
  )
  kept <- setdiff(names(base_env), overlay_names)
  testthat::expect_identical(child_env[kept], base_env[kept])
})

testthat::test_that("run() starts a bare command as the micromamba backend does", {
  # Regression tests: on the direct path, a bare command from
  # backend_resolve_run() went to processx unchanged. On Linux and macOS,
  # where processx searches the child's PATH, it is still kept bare. On
  # Windows, the environment's binary directories are searched first, and
  # any other name goes to processx as for the micromamba backend: looking
  # it up on the child's PATH found `cmd`, the MSYS2 shell script that
  # Rtools puts ahead of `C:/Windows/System32`, so `run("cmd", ...)` failed
  # with status 127.
  session_path <- Sys.getenv("PATH")
  tool_dir <- withr::local_tempdir()
  run_family_write_tool(tool_dir, "condathis-run-activation-tool", "activated")
  # A same-named program on the session's PATH must not run.
  decoy_dir <- withr::local_tempdir()
  run_family_write_tool(decoy_dir, "condathis-run-activation-tool", "decoy")
  stub <- local_run_family_stub(
    backend_resolve_run = function(backend, cmd, args = character(0L), ...) {
      return(list(
        command = cmd,
        args = args,
        # The PATH of the session when the command runs.
        env = c(
          PATH = paste(tool_dir, Sys.getenv("PATH"), sep = .Platform$path.sep)
        ),
        dir = NULL
      ))
    }
  )
  if (isTRUE(is_windows())) {
    # A `.cmd` file in a binary directory of the environment, found with
    # PATHEXT.
    scripts_dir <- fs::path(stub$root, "envs", "stub-env", "Scripts")
    fs::dir_create(scripts_dir)
    run_family_write_tool(scripts_dir, "condathis-run-env-tool", "in env")
    res <- run(
      "condathis-run-env-tool",
      env_name = "stub-env",
      verbose = "silent"
    )
    testthat::expect_identical(res$status, 0L)
    testthat::expect_identical(parse_output(res), "in env")
    # A file without an extension ahead of `cmd.exe` on the PATH, as the
    # `cmd` script of Rtools.
    fake_rtools <- withr::local_tempdir()
    writeLines(
      c("#!/usr/bin/env bash", "echo rtools"),
      fs::path(fake_rtools, "cmd")
    )
    withr::local_envvar(PATH = paste(fake_rtools, session_path, sep = ";"))
    res <- run(
      "cmd",
      "/c",
      "echo hi",
      env_name = "stub-env",
      verbose = "silent"
    )
    testthat::expect_identical(res$status, 0L)
    testthat::expect_identical(parse_output(res), "hi")
  } else {
    withr::local_envvar(
      PATH = paste(decoy_dir, session_path, sep = .Platform$path.sep)
    )
    res <- run(
      "condathis-run-activation-tool",
      env_name = "stub-env",
      verbose = "silent"
    )
    testthat::expect_identical(res$status, 0L)
    testthat::expect_identical(parse_output(res), "activated")
    # `cmd` is the user's command line, not the resolved path.
    testthat::expect_identical(
      res$cmd,
      shQuote("condathis-run-activation-tool")
    )
  }

  # Found nowhere: the command stays bare and fails to start.
  res <- run(
    "condathis-run-missing-tool",
    env_name = "stub-env",
    error = "continue",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 127L)
  cnd <- testthat::expect_error(
    run(
      "condathis-run-missing-tool",
      env_name = "stub-env",
      verbose = "silent"
    ),
    class = "condathis_run_status_error"
  )
  testthat::expect_identical(cnd$status, 127L)
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "condathis-run-missing-tool: command not found",
    fixed = TRUE
  )
})

testthat::test_that("resolve_direct_run_command() follows the micromamba backend on each OS", {
  withr::local_dir(withr::local_tempdir())
  env_dir <- fs::path(getwd(), "env")
  fs::dir_create(c(
    fs::path(env_dir, "bin"),
    fs::path(env_dir, "Scripts"),
    fs::path(env_dir, "Library", "usr", "bin")
  ))
  writeLines("", fs::path(env_dir, "bin", "tool.cmd"))
  writeLines("", fs::path(env_dir, "Scripts", "other.bat"))
  # Files without an extension, as MSYS2 scripts in `Library/usr/bin`.
  writeLines("", fs::path(env_dir, "Library", "usr", "bin", "script"))
  writeLines("", fs::path(env_dir, "Library", "usr", "bin", "tool"))

  # Linux and macOS: the command is kept, so that processx starts it with
  # `execvp()` on the child's PATH, with its own name as `argv[0]`.
  for (command in c("tool", "other", "./tool", "/abs/tool")) {
    testthat::expect_identical(
      resolve_direct_run_command(
        command,
        env_dir = env_dir,
        on_windows = FALSE
      ),
      command
    )
  }

  # Windows: the environment's binary directories, in the order of
  # activation, with the PATHEXT extensions in order. A file without an
  # extension never counts for a name without one: processx would look
  # for `<name>.com` and `<name>.exe` next to it.
  testthat::expect_identical(
    resolve_direct_run_command(
      "tool",
      env_dir = env_dir,
      on_windows = TRUE,
      pathext = ".EXE;.CMD"
    ),
    normalizePath(fs::path(env_dir, "bin", "tool.cmd"), mustWork = FALSE)
  )
  testthat::expect_identical(
    resolve_direct_run_command(
      "other",
      env_dir = env_dir,
      on_windows = TRUE,
      pathext = ".EXE;.BAT"
    ),
    normalizePath(fs::path(env_dir, "Scripts", "other.bat"), mustWork = FALSE)
  )
  # Found nowhere in the environment, or with a directory part: unchanged,
  # so processx searches the working directory and the PATH of R, as it
  # does for the micromamba backend.
  for (command in c("script", "missing", "cmd")) {
    testthat::expect_identical(
      resolve_direct_run_command(
        command,
        env_dir = env_dir,
        on_windows = TRUE,
        pathext = ".EXE;.BAT"
      ),
      command
    )
  }
  testthat::expect_identical(
    resolve_direct_run_command(
      "sub\\tool",
      env_dir = env_dir,
      on_windows = TRUE
    ),
    "sub\\tool"
  )
})

testthat::test_that("run() reports a command killed by a signal as 128 + n off Windows", {
  testthat::skip_on_cran()
  # Regression test: `micromamba run` reports a command killed by signal n
  # as 128 + n (137 for SIGKILL), but a command of another backend, started
  # directly, gave -n. run_bin() starts the command directly for every
  # backend and keeps -n.
  stub <- local_run_family_stub()
  kill_self <- c(
    "--vanilla",
    "-e",
    "tools::pskill(Sys.getpid(), tools::SIGKILL)"
  )
  run_res <- run(
    run_family_rscript(),
    kill_self,
    env_name = "stub-env",
    error = "continue",
    verbose = "silent"
  )
  run_bin_res <- run_bin(
    run_family_rscript(),
    kill_self,
    env_name = "stub-env",
    error = "continue",
    verbose = "silent"
  )
  testthat::expect_false(run_res$timeout)
  if (isTRUE(is_windows())) {
    # No signals: the exit status is kept, and both paths agree.
    testthat::expect_identical(run_res$status, run_bin_res$status)
  } else {
    testthat::expect_identical(run_res$status, 137L)
    testthat::expect_identical(run_bin_res$status, -9L)
    cnd <- testthat::expect_error(
      run(
        run_family_rscript(),
        kill_self,
        env_name = "stub-env",
        verbose = "silent"
      ),
      class = "condathis_run_status_error"
    )
    testthat::expect_identical(cnd$status, 137L)
  }
})

testthat::test_that("signal_exit_status() maps only a negative status off Windows", {
  testthat::expect_identical(signal_exit_status(-9L, on_windows = FALSE), 137L)
  testthat::expect_identical(signal_exit_status(-15L, on_windows = FALSE), 143L)
  testthat::expect_identical(signal_exit_status(-9L, on_windows = TRUE), -9L)
  for (status in list(0L, 1L, 127L, NA_integer_, NULL)) {
    testthat::expect_identical(
      signal_exit_status(status, on_windows = FALSE),
      status
    )
  }
})

testthat::test_that("run() starts the command of a micromamba environment itself, on every OS", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  # Regression test (R-4): on Linux and macOS, run() started the command
  # through `micromamba run`, unlike run() on Windows, run_bin(),
  # run_pipeline() and every other backend: `timeout` covered the
  # activation, what `activate.d` scripts printed was in the output, a
  # failing `activate.d` script gave the status of the script, and the
  # command got micromamba's own `TMPDIR`, `MAMBA_ROOT_PREFIX` and
  # `mamba/proc` directory. condathis now records the activation, and
  # starts the command itself, with the activation's variables, also the
  # ones that an `activate.d` script unsets.
  env_name <- "run-direct-activation-env"
  create_polyglot_env(env_name)
  env_dir <- get_env_dir(env_name)
  activate_dir <- fs::path(env_dir, "etc", "conda", "activate.d")
  fs::dir_create(activate_dir)
  writeLines(
    c(
      "echo activate.d output",
      "export CONDATHIS_RUN_ACTIVATED=yes",
      "unset CONDATHIS_RUN_UNSET"
    ),
    fs::path(activate_dir, "condathis-run.sh")
  )
  writeLines(
    c(
      "@echo activate.d output",
      "@set CONDATHIS_RUN_ACTIVATED=yes",
      "@set CONDATHIS_RUN_UNSET="
    ),
    fs::path(activate_dir, "condathis-run.bat")
  )
  reset_micromamba_activation_cache(env_name)
  withr::local_envvar(
    CONDATHIS_RUN_UNSET = "session",
    CONDATHIS_RUN_KEPT = "session"
  )
  print_vars <- paste0(
    "cat(Sys.getenv(c('CONDATHIS_RUN_ACTIVATED', 'CONDATHIS_RUN_UNSET', ",
    "'CONDATHIS_RUN_KEPT', 'MAMBA_ROOT_PREFIX', 'XDG_CACHE_HOME'), ",
    "unset = '<unset>'), basename(Sys.getenv('TMPDIR')), sep = '\\n')"
  )
  res <- run(
    get_condathis_rscript_path(),
    "--vanilla",
    "-e",
    print_vars,
    env_name = env_name,
    verbose = "silent"
  )
  out <- parse_output(res)
  testthat::expect_identical(
    out[1:5],
    c("yes", "<unset>", "session", "", Sys.getenv("XDG_CACHE_HOME"))
  )
  testthat::expect_match(out[[6L]], "^condathis-tmp")
  # What the activate.d script printed is not the command's output.
  res <- run("polyglot", env_name = env_name, verbose = "silent")
  testthat::expect_identical(parse_output(res)[[1L]], polyglot_expected_line())
  testthat::expect_false(grepl("activate.d output", res$stdout, fixed = TRUE))
  # The "Running" line names the command, not micromamba.
  running <- utils::capture.output(
    run("polyglot", env_name = env_name, verbose = "cmd")
  )
  testthat::expect_match(running[[1L]], "^Running ")
  testthat::expect_false(any(grepl("--rc-file", running, fixed = TRUE)))

  # A failing activate.d script. cmd.exe calls the scripts on Windows, and
  # their exit status does not fail the activation there.
  fail_env <- "run-failing-activation-env"
  create_polyglot_env(fail_env)
  fail_dir <- fs::path(get_env_dir(fail_env), "etc", "conda", "activate.d")
  fs::dir_create(fail_dir)
  writeLines(
    c("echo failing activation >&2", "exit 3"),
    fs::path(fail_dir, "condathis-fail.sh")
  )
  writeLines(
    c("@echo failing activation 1>&2", "@exit /b 3"),
    fs::path(fail_dir, "condathis-fail.bat")
  )
  reset_micromamba_activation_cache(fail_env)
  if (isTRUE(is_windows())) {
    res <- run("polyglot", env_name = fail_env, verbose = "silent")
    testthat::expect_identical(res$status, 0L)
  } else {
    testthat::expect_error(
      run("polyglot", env_name = fail_env, verbose = "silent"),
      class = "condathis_run_resolve_failed"
    )
    res <- run(
      "polyglot",
      env_name = fail_env,
      error = "continue",
      verbose = "silent"
    )
    testthat::expect_identical(res$status, 127L)
    testthat::expect_match(res$stderr, "failing activation", fixed = TRUE)
  }
})

testthat::test_that("run() activates micromamba environments also without basename on PATH", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  # Regression test (R-4 g): micromamba's shell hook runs `basename`, so
  # with a PATH that has only `sh`, `micromamba run` activated nothing and
  # the command ran without activation. On Windows, cmd.exe activates.
  env_name <- "run-sh-only-env"
  create_polyglot_env(env_name)
  reset_micromamba_activation_cache(env_name)
  sh_only <- withr::local_tempdir()
  if (isFALSE(is_windows())) {
    # The binary that created the environment: one that is found only on
    # `PATH` is not found with the new `PATH`, and run() would download
    # another.
    withr::local_options(
      condathis.micromamba_path = as.character(get_best_micromamba_path())
    )
    fs::link_create(Sys.which("sh"), fs::path(sh_only, "sh"))
    withr::local_envvar(PATH = sh_only)
  }
  res <- run(
    get_condathis_rscript_path(),
    "--vanilla",
    "-e",
    "cat(Sys.getenv('CONDA_PREFIX'), Sys.getenv('PATH'), sep = '\\n')",
    env_name = env_name,
    verbose = "silent"
  )
  out <- parse_output(res)
  testthat::expect_identical(
    fs::path_norm(out[[1L]]),
    fs::path_norm(get_env_dir(env_name))
  )
  path_parts <- strsplit(out[[2L]], .Platform$path.sep, fixed = TRUE)[[1L]]
  if (isFALSE(is_windows())) {
    # The directory of `basename` that micromamba got is not the command's.
    testthat::expect_identical(path_parts[[length(path_parts)]], sh_only)
    testthat::expect_false(any(path_parts %in% c("/usr/bin", "/bin")))
  }
})

testthat::test_that("run() finds the environment's program first, also when the session's PATH has its directory further back", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  # Regression test: the activation's PATH was reduced to the directories
  # that the session's PATH lacks, so an environment directory that the
  # session's PATH has at its end stayed there, and a program of the same
  # name earlier on the PATH ran instead of the environment's.
  env_name <- "run-path-order-env"
  create_polyglot_env(env_name)
  reset_micromamba_activation_cache(env_name)
  env_dir <- as.character(get_env_dir(env_name))
  fake_dir <- withr::local_tempdir()
  if (isTRUE(is_windows())) {
    writeLines("@echo fake polyglot", fs::path(fake_dir, "polyglot.bat"))
  } else {
    fake <- fs::path(fake_dir, "polyglot")
    writeLines(c("#!/bin/sh", "echo fake polyglot"), fake)
    fs::file_chmod(fake, "u+x")
  }
  bin_dirs <- as.character(env_bin_search_dirs(env_dir))
  withr::local_envvar(
    PATH = paste(
      c(fake_dir, Sys.getenv("PATH"), bin_dirs),
      collapse = .Platform$path.sep
    )
  )
  res <- run("polyglot", env_name = env_name, verbose = "silent")
  testthat::expect_identical(parse_output(res)[[1L]], polyglot_expected_line())
  copy_stage <- run_step(
    get_condathis_rscript_path(),
    "--vanilla",
    "-e",
    "cat(readLines(file('stdin')), sep = '\\n')"
  )
  pipe <- run_pipeline(
    run_step("polyglot"),
    copy_stage,
    env_name = env_name,
    verbose = "silent"
  )
  testthat::expect_identical(
    parse_output(pipe$processes[[2L]])[[1L]],
    polyglot_expected_line()
  )
  # The environment's directories lead the command's PATH, and the
  # session's entries follow in their order.
  res <- run(
    get_condathis_rscript_path(),
    "--vanilla",
    "-e",
    "cat(Sys.getenv('PATH'))",
    env_name = env_name,
    verbose = "silent"
  )
  spelling <- function(x) {
    x <- gsub("\\\\", "/", as.character(x))
    if (isTRUE(is_windows())) {
      x <- tolower(x)
    }
    return(x)
  }
  parts <- spelling(strsplit(res$stdout, .Platform$path.sep, fixed = TRUE)[[
    1L
  ]])
  testthat::expect_true(any(parts %in% spelling(bin_dirs)))
  testthat::expect_lt(
    min(which(parts %in% spelling(bin_dirs))),
    match(spelling(fake_dir), parts)
  )
})

testthat::test_that("activate.d scripts get the TMPDIR, user cache and working directory of the command", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  # Regression test: the scripts ran with the TMPDIR of micromamba's own
  # process, deleted after the activation was recorded, and with
  # `XDG_CACHE_HOME=<root>/cache`, and the recorded values were reused for
  # every later command, also from another working directory.
  env_name <- "run-capture-vars-env"
  create_polyglot_env(env_name)
  env_dir <- get_env_dir(env_name)
  activate_dir <- fs::path(env_dir, "etc", "conda", "activate.d")
  fs::dir_create(activate_dir)
  writeLines(
    c(
      "export CDT_X=\"$TMPDIR/x\"",
      "export CDT_C=\"${XDG_CACHE_HOME:-$HOME/.cache}/x\"",
      "export CDT_P=\"$PWD\""
    ),
    fs::path(activate_dir, "condathis-capture.sh")
  )
  writeLines(
    c(
      "@set \"CDT_X=%TMPDIR%\\x\"",
      "@set \"CDT_C=%XDG_CACHE_HOME%\\x\"",
      "@set \"CDT_P=%CD%\""
    ),
    fs::path(activate_dir, "condathis-capture.bat")
  )
  reset_micromamba_activation_cache(env_name)
  user_cache <- normalizePath(withr::local_tempdir(), winslash = "/")
  withr::local_envvar(XDG_CACHE_HOME = user_cache)
  print_vars <- paste0(
    "cat(Sys.getenv('TMPDIR'), dir.exists(Sys.getenv('TMPDIR')), ",
    "Sys.getenv(c('CDT_X', 'CDT_C', 'CDT_P')), sep = '\\n')"
  )
  get_vars <- function() {
    res <- run(
      get_condathis_rscript_path(),
      "--vanilla",
      "-e",
      print_vars,
      env_name = env_name,
      verbose = "silent"
    )
    out <- gsub("\\\\", "/", parse_output(res))
    return(list(
      tmp = out[[1L]],
      tmp_exists = out[[2L]],
      x = out[[3L]],
      cache = out[[4L]],
      wd = out[[5L]]
    ))
  }
  same_dir <- function(a, b) {
    return(identical(
      normalizePath(a, winslash = "/", mustWork = FALSE),
      normalizePath(b, winslash = "/", mustWork = FALSE)
    ))
  }
  wd_a <- withr::local_tempdir()
  withr::local_dir(wd_a)
  first <- get_vars()
  testthat::expect_identical(first$tmp_exists, "TRUE")
  testthat::expect_identical(first$x, paste0(first$tmp, "/x"))
  testthat::expect_identical(first$cache, paste0(user_cache, "/x"))
  testthat::expect_true(same_dir(first$wd, wd_a))
  # The next command has a TMPDIR of its own, and the scripts' value follows.
  second <- get_vars()
  testthat::expect_false(identical(second$tmp, first$tmp))
  testthat::expect_identical(second$x, paste0(second$tmp, "/x"))
  # Another working directory.
  wd_b <- withr::local_tempdir()
  withr::local_dir(wd_b)
  testthat::expect_true(same_dir(get_vars()$wd, wd_b))
  # Without XDG_CACHE_HOME, the scripts read it as unset, never as
  # micromamba's own `<root>/cache`: the default of the XDG specification
  # in a shell script, nothing in a batch file.
  withr::local_envvar(XDG_CACHE_HOME = NA)
  unset_cache <- get_vars()$cache
  if (isTRUE(is_windows())) {
    testthat::expect_identical(unset_cache, "/x")
  } else {
    testthat::expect_identical(
      unset_cache,
      paste0(Sys.getenv("HOME"), "/.cache/x")
    )
  }
})

testthat::test_that("run() keeps the session's TMP, unless an activate.d script sets one", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  # Regression test: on Windows, micromamba's own processes get `TMP` = a
  # directory in their `TMPDIR`, and the activation dump inherits it. Recorded
  # as an activation variable, it gave every later command of the
  # environment a deleted directory as `TMP`. A `TMP` that an `activate.d`
  # script sets is the activation's.
  rscript <- get_condathis_rscript_path()
  print_tmp <- c("--vanilla", "-e", "cat(Sys.getenv('TMP', unset = '<unset>'))")
  slashes <- function(x) gsub("\\\\", "/", as.character(x))
  plain_env <- "run-session-tmp-env"
  create_polyglot_env(plain_env)
  reset_micromamba_activation_cache(plain_env)
  session_tmp <- Sys.getenv("TMP", unset = "<unset>")
  # The second call reuses the recorded activation.
  for (i in 1:2) {
    res <- run(rscript, print_tmp, env_name = plain_env, verbose = "silent")
    testthat::expect_identical(res$stdout, session_tmp, info = paste("call", i))
  }
  res <- run_bin(rscript, print_tmp, env_name = plain_env, verbose = "silent")
  testthat::expect_identical(res$stdout, session_tmp)

  script_env <- "run-script-tmp-env"
  create_polyglot_env(script_env)
  script_tmp <- slashes(fs::path(withr::local_tempdir(), "tmp-from-activate"))
  activate_dir <- fs::path(
    get_env_dir(script_env),
    "etc",
    "conda",
    "activate.d"
  )
  fs::dir_create(activate_dir)
  writeLines(
    paste0("export TMP='", script_tmp, "'"),
    fs::path(activate_dir, "condathis-tmp.sh")
  )
  writeLines(
    paste0("@set \"TMP=", gsub("/", "\\\\", script_tmp), "\""),
    fs::path(activate_dir, "condathis-tmp.bat")
  )
  reset_micromamba_activation_cache(script_env)
  withr::defer(reset_micromamba_activation_cache(script_env))
  for (i in 1:2) {
    res <- run(rscript, print_tmp, env_name = script_env, verbose = "silent")
    testthat::expect_identical(
      slashes(res$stdout),
      script_tmp,
      info = paste("call", i)
    )
  }

  # Also a `TMP` that names the command's `TMPDIR`, which differs for each
  # call. micromamba's own `TMP` is a directory in it, not the `TMPDIR`
  # itself, or this one was taken for micromamba's and left out.
  writeLines(
    "export TMP=\"$TMPDIR\"",
    fs::path(activate_dir, "condathis-tmp.sh")
  )
  writeLines(
    "@set \"TMP=%TMPDIR%\"",
    fs::path(activate_dir, "condathis-tmp.bat")
  )
  reset_micromamba_activation_cache(script_env)
  print_both <- c(
    "--vanilla",
    "-e",
    "cat(Sys.getenv(c('TMP', 'TMPDIR'), unset = '<unset>'), sep = '|')"
  )
  for (i in 1:3) {
    res <- if (identical(i, 3L)) {
      run_bin(rscript, print_both, env_name = script_env, verbose = "silent")
    } else {
      run(rscript, print_both, env_name = script_env, verbose = "silent")
    }
    both <- strsplit(slashes(res$stdout), "|", fixed = TRUE)[[1L]]
    testthat::expect_length(both, 2L)
    testthat::expect_true(nzchar(both[[2L]]), info = paste("call", i))
    testthat::expect_identical(both[[1L]], both[[2L]], info = paste("call", i))
  }
})

testthat::test_that("run() gets a value that an activate.d script builds from TMP", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  # Regression test: on Windows, an `activate.d` script that built a value
  # from `%TMP%` got micromamba's own `TMP`, a directory in the call's
  # `TMPDIR` that was deleted before the command started. The command got
  # a path in a missing directory, and the activation was recorded again
  # for every command. Before micromamba had a `TMP` of its own, the value
  # named the session's `TMP`, and the activation was cached.
  rscript <- get_condathis_rscript_path()
  slashes <- function(x) gsub("\\\\", "/", as.character(x))
  session_tmp <- as.character(withr::local_tempdir())
  withr::local_envvar(TMP = session_tmp)
  env_name <- "run-tmp-value-env"
  create_polyglot_env(env_name)
  activate_dir <- fs::path(get_env_dir(env_name), "etc", "conda", "activate.d")
  fs::dir_create(activate_dir)
  write_scripts <- function(sh, bat) {
    writeLines(sh, fs::path(activate_dir, "condathis-tmp.sh"))
    writeLines(bat, fs::path(activate_dir, "condathis-tmp.bat"))
    reset_micromamba_activation_cache(env_name)
  }
  withr::defer(reset_micromamba_activation_cache(env_name))
  print_vars <- c(
    "--vanilla",
    "-e",
    paste(
      "x <- Sys.getenv(c('FOO', 'TMP', 'TMPDIR'), unset = '<unset>')",
      "cat(x, dir.exists(dirname(x[[1L]])), sep = '|')",
      sep = "; "
    )
  )
  # FOO, TMP, TMPDIR and whether the directory of FOO exists, per call: two
  # `run()` calls, the second with the cached activation, and `run_bin()`.
  run_calls <- function() {
    return(lapply(1:3, function(i) {
      res <- if (identical(i, 3L)) {
        run_bin(rscript, print_vars, env_name = env_name, verbose = "silent")
      } else {
        run(rscript, print_vars, env_name = env_name, verbose = "silent")
      }
      vars <- strsplit(slashes(res$stdout), "|", fixed = TRUE)[[1L]]
      testthat::expect_length(vars, 4L)
      return(as.list(rlang::set_names(vars, c("FOO", "TMP", "TMPDIR", "dir"))))
    }))
  }
  is_cached <- function() {
    return(exists(env_name, envir = condathis_activation_cache))
  }

  write_scripts(
    "export FOO=\"$TMP/foo\"",
    "@set \"FOO=%TMP%\\foo\""
  )
  for (vars in run_calls()) {
    testthat::expect_identical(vars$FOO, paste0(slashes(session_tmp), "/foo"))
    testthat::expect_identical(vars$dir, "TRUE")
    testthat::expect_identical(vars$TMP, slashes(session_tmp))
  }
  testthat::expect_true(is_cached())

  # A script that extends `TMP`.
  write_scripts(
    "export TMP=\"$TMP/x\"",
    "@set \"TMP=%TMP%\\x\""
  )
  for (vars in run_calls()) {
    testthat::expect_identical(vars$TMP, paste0(slashes(session_tmp), "/x"))
  }
  testthat::expect_true(is_cached())

  # A script that writes to `TMP`. On Windows, it writes in the call's
  # `TMPDIR`, which the command shares, not in the session's `TMP`, and
  # the activation is not cached, as with `TMPDIR`.
  write_scripts(
    c("mkdir -p \"$TMP/bar\"", "export FOO=\"$TMP/bar/x\""),
    c("@mkdir \"%TMP%\\bar\" 2>nul", "@set \"FOO=%TMP%\\bar\\x\"")
  )
  for (vars in run_calls()) {
    testthat::expect_identical(vars$dir, "TRUE")
    if (isTRUE(is_windows())) {
      testthat::expect_true(startsWith(vars$FOO, paste0(vars$TMPDIR, "/")))
    } else {
      testthat::expect_identical(
        vars$FOO,
        paste0(slashes(session_tmp), "/bar/x")
      )
    }
  }
  testthat::expect_identical(is_cached(), isFALSE(is_windows()))
  testthat::expect_identical(
    dir.exists(file.path(session_tmp, "bar")),
    isFALSE(is_windows())
  )
})

testthat::test_that("run(timeout =) also bounds a slow activation", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  # Regression test: `timeout` covered only the command, so an activate.d
  # script that hangs made run() hang too.
  env_name <- "run-slow-activation-env"
  create_polyglot_env(env_name)
  activate_dir <- fs::path(get_env_dir(env_name), "etc", "conda", "activate.d")
  fs::dir_create(activate_dir)
  writeLines("sleep 30", fs::path(activate_dir, "condathis-slow.sh"))
  writeLines(
    "@ping -n 31 127.0.0.1 > nul",
    fs::path(activate_dir, "condathis-slow.bat")
  )
  reset_micromamba_activation_cache(env_name)
  withr::defer(reset_micromamba_activation_cache(env_name))
  # Regression test: on Windows, each `micromamba run` stopped by the time
  # limit left its two batch files (`mamba_act*.bat`, `mamba_bat_*.bat`)
  # in the session's `%TEMP%`. They name the environment. The per-call
  # directories, where micromamba now writes them, are deleted.
  env_key <- tolower(gsub("[/\\\\]+", "/", as.character(get_env_dir(env_name))))
  leftover_bat_files <- function() {
    dirs <- unique(Filter(nzchar, Sys.getenv(c("TEMP", "TMP"))))
    dirs <- dirs[fs::dir_exists(dirs)]
    if (identical(length(dirs), 0L)) {
      return(character(0L))
    }
    files <- as.character(fs::dir_ls(
      dirs,
      regexp = "mamba_[^/\\\\]*[.]bat$",
      type = "file"
    ))
    names_env <- vapply(
      files,
      function(file) {
        text <- tryCatch(readLines(file, warn = FALSE), error = function(e) "")
        return(any(grepl(
          env_key,
          tolower(gsub("[/\\\\]+", "/", text)),
          fixed = TRUE
        )))
      },
      logical(1L)
    )
    return(files[names_env])
  }
  call_tmp_dirs <- function() {
    return(as.character(fs::dir_ls(
      tempdir(),
      regexp = "condathis-(tmp|activation|baseline|prime)|mamba-tmp",
      type = "directory"
    )))
  }
  bat_files_before <- leftover_bat_files()
  tmp_dirs_before <- call_tmp_dirs()
  rscript <- get_condathis_rscript_path()
  started <- Sys.time()
  res <- run(
    rscript,
    "--vanilla",
    "-e",
    "cat('ran')",
    env_name = env_name,
    timeout = 3,
    error = "continue",
    verbose = "silent"
  )
  took <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  testthat::expect_true(res$timeout)
  testthat::expect_identical(res$status, -9L)
  testthat::expect_false(grepl("ran", res$stdout, fixed = TRUE))
  testthat::expect_match(res$stderr, "activating environment", fixed = TRUE)
  testthat::expect_lt(took, 25)
  cnd <- testthat::expect_error(
    run(
      rscript,
      "--vanilla",
      "-e",
      "cat('ran')",
      env_name = env_name,
      timeout = 3,
      verbose = "silent"
    ),
    class = "condathis_run_timeout_error"
  )
  testthat::expect_s3_class(cnd, "condathis_timeout_error")
  testthat::expect_true(cnd$timeout)
  testthat::expect_identical(cnd$status, -9L)
  res <- run_bin(
    rscript,
    "--vanilla",
    "-e",
    "cat('ran')",
    env_name = env_name,
    activate = TRUE,
    timeout = 3,
    error = "continue",
    verbose = "silent"
  )
  testthat::expect_true(res$timeout)
  testthat::expect_identical(res$status, -9L)
  testthat::expect_error(
    run_bin(
      rscript,
      "--vanilla",
      "-e",
      "cat('ran')",
      env_name = env_name,
      activate = TRUE,
      timeout = 3,
      verbose = "silent"
    ),
    class = "condathis_run_bin_timeout_error"
  )
  copy_stage <- run_step(
    rscript,
    "--vanilla",
    "-e",
    "cat(readLines(file('stdin')), sep = '\\n')"
  )
  pipe <- run_pipeline(
    run_step(rscript, "--vanilla", "-e", "cat('ran')"),
    copy_stage,
    env_name = env_name,
    timeout = 3,
    error = "continue",
    verbose = "silent"
  )
  testthat::expect_true(pipe$timeout)
  testthat::expect_identical(pipe$processes[[1L]]$status, -9L)
  testthat::expect_error(
    run_pipeline(
      run_step(rscript, "--vanilla", "-e", "cat('ran')"),
      copy_stage,
      env_name = env_name,
      timeout = 3,
      verbose = "silent"
    ),
    class = "condathis_run_pipeline_timeout_error"
  )
  testthat::expect_identical(
    setdiff(leftover_bat_files(), bat_files_before),
    character(0L)
  )
  testthat::expect_identical(
    setdiff(call_tmp_dirs(), tmp_dirs_before),
    character(0L)
  )
  # Without the slow script, the activation is fast and the command runs.
  fs::file_delete(fs::dir_ls(activate_dir))
  res <- run(
    rscript,
    "--vanilla",
    "-e",
    "cat('ran')",
    env_name = env_name,
    timeout = 60,
    verbose = "silent"
  )
  testthat::expect_identical(res$stdout, "ran")
  testthat::expect_false(res$timeout)
})
