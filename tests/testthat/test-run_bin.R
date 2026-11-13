test_that("run_bin() never runs a binary from PATH for a missing environment", {
  # Regression test (decision D3): with a missing environment, run_bin()
  # fell back to `Sys.which(cmd)`, so run_bin("R", env_name = "typo") ran
  # the R on PATH and returned status 0.
  stub <- local_run_family_stub()
  rscript <- run_family_rscript()
  res <- run_bin(
    rscript,
    "--version",
    env_name = "fake-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_identical(res$status, 127L)
  testthat::expect_identical(
    res$stderr,
    "Conda environment 'fake-env' does not exist.\n"
  )
  testthat::expect_identical(res$env_name, "fake-env")
  testthat::expect_identical(
    res$cmd,
    paste(shQuote(c(rscript, "--version")), collapse = " ")
  )

  cnd <- testthat::expect_error(
    run_bin(rscript, "--version", env_name = "fake-env", verbose = "silent"),
    class = "condathis_run_bin_env_not_found"
  )
  testthat::expect_identical(
    class(cnd)[1:3],
    c(
      "condathis_run_bin_env_not_found",
      "condathis_env_not_found",
      "condathis_error"
    )
  )
  testthat::expect_identical(rlang::call_name(conditionCall(cnd)), "run_bin")

  # Nothing was resolved, created or run.
  testthat::expect_length(stub_calls(stub, "backend_resolve_run"), 0L)
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
  testthat::expect_false(fs::dir_exists(fs::path(
    stub$root,
    "envs",
    "fake-env"
  )))
})

test_that("run_bin() never runs a binary from PATH for a missing micromamba environment", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  res <- run_bin(
    run_family_rscript(),
    "--version",
    env_name = "run-bin-missing-micromamba-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_identical(res$status, 127L)
  testthat::expect_match(res$stderr, "does not exist", fixed = TRUE)
  testthat::expect_error(
    run_bin(
      run_family_rscript(),
      "--version",
      env_name = "run-bin-missing-micromamba-env",
      verbose = "silent"
    ),
    class = "condathis_env_not_found"
  )
  testthat::expect_false(
    env_exists("run-bin-missing-micromamba-env", verbose = "silent")
  )
})

test_that("Check if error is being rethrown when binary is not in path", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(env_name = "fake-env", verbose = "silent")

  run_res <- run(
    "Rfakeexec",
    "--version",
    env_name = "fake-env",
    verbose = "silent",
    error = "continue"
  )

  testthat::expect_true(run_res$status != 0L)

  run_bin_res <- run_bin(
    "Rfakeexec",
    "--version",
    env_name = "fake-env",
    verbose = "silent",
    error = "continue"
  )

  testthat::expect_true(run_bin_res$status != 0L)
})

test_that("run_bin() returns a condathis_result object", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    test_os_pkg("coreutils"),
    env_name = "run-bin-cli-tools-env",
    verbose = "silent"
  )
  res <- run_bin(
    "echo",
    "hello",
    env_name = "run-bin-cli-tools-env",
    verbose = "silent"
  )
  testthat::expect_s3_class(res, "condathis_result")
  testthat::expect_equal(res$status, 0L)
  testthat::expect_true(is.numeric(res$pid))
  testthat::expect_equal(res$env_name, "run-bin-cli-tools-env")
})

test_that("run_bin() supports stdin = '|' with input", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    test_os_pkg("coreutils"),
    env_name = "run-bin-cli-tools-env",
    verbose = "silent"
  )
  res <- run_bin(
    "sort",
    stdin = "|",
    input = "b\na\nc\n",
    env_name = "run-bin-cli-tools-env",
    verbose = "silent"
  )
  sorted <- strsplit(trimws(res$stdout), "\n")[[1]]
  testthat::expect_equal(sorted, c("a", "b", "c"))
})

test_that("run_bin() rejects input without stdin = '|'", {
  testthat::expect_error(
    object = run_bin("echo", "hello", input = "x", verbose = "silent"),
    class = "condathis_run_invalid_input"
  )
})

test_that("run_bin() with binary = TRUE round-trips raw bytes from a file", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    test_os_pkg("coreutils"),
    env_name = "run-bin-cli-tools-env",
    verbose = "silent"
  )

  raw_bytes <- as.raw(c(0x00, 0x01, 0xFF, 0x41, 0x0A, 0xFE, 0x00))
  tmp_file <- withr::local_tempfile()
  writeBin(raw_bytes, tmp_file)

  res <- run_bin(
    "cat",
    tmp_file,
    env_name = "run-bin-cli-tools-env",
    binary = TRUE,
    verbose = "silent"
  )
  testthat::expect_type(res$stdout, "raw")
  testthat::expect_identical(res$stdout, raw_bytes)
})

test_that("run_bin() with binary = TRUE round-trips raw bytes through stdin", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    test_os_pkg("coreutils"),
    env_name = "run-bin-cli-tools-env",
    verbose = "silent"
  )

  raw_bytes <- as.raw(c(0x00, 0x01, 0xFF, 0x41, 0x0A, 0xFE, 0x00))
  res <- run_bin(
    "cat",
    stdin = "|",
    input = raw_bytes,
    env_name = "run-bin-cli-tools-env",
    binary = TRUE,
    verbose = "silent"
  )
  testthat::expect_identical(res$stdout, raw_bytes)
})

test_that("run_bin() rejects non-logical binary argument", {
  testthat::expect_error(
    object = run_bin("echo", "hello", binary = "yes", verbose = "silent"),
    class = "condathis_run_invalid_binary_arg"
  )
})

test_that("run_bin() accepts crash-safety parameters", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    test_os_pkg("coreutils"),
    env_name = "run-bin-cli-tools-env",
    verbose = "silent"
  )
  # `linux_pdeathsig` is ignored without a warning on platforms other than
  # Linux.
  testthat::expect_no_warning(
    res <- run_bin(
      "echo",
      "hi",
      supervise = TRUE,
      cleanup_tree = TRUE,
      linux_pdeathsig = TRUE,
      env_name = "run-bin-cli-tools-env",
      verbose = "silent"
    )
  )
  testthat::expect_equal(res$status, 0L)
})

test_that("run_bin() respects timeout under error = continue", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    test_os_pkg("coreutils"),
    env_name = "run-bin-cli-tools-env",
    verbose = "silent"
  )
  res <- run_bin(
    "sleep",
    "5",
    env_name = "run-bin-cli-tools-env",
    error = "continue",
    timeout = 1,
    verbose = "silent"
  )
  testthat::expect_equal(res$status, -9L)
  testthat::expect_true(res$timeout)
})

test_that("run_bin() respects timeout under error = cancel", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    test_os_pkg("coreutils"),
    env_name = "run-bin-cli-tools-env",
    verbose = "silent"
  )
  cnd_res <- rlang::catch_cnd(
    expr = {
      run_bin(
        "sleep",
        "5",
        env_name = "run-bin-cli-tools-env",
        error = "cancel",
        timeout = 1,
        verbose = "silent"
      )
    }
  )
  testthat::expect_s3_class(cnd_res, "condathis_run_timeout_error")
})

test_that("run_bin(activate = TRUE) resolves the same CONDA_PREFIX as run()", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    test_os_pkg("coreutils"),
    env_name = "run-bin-cli-tools-env",
    verbose = "silent"
  )

  res_run <- run(
    "printenv",
    "CONDA_PREFIX",
    env_name = "run-bin-cli-tools-env",
    verbose = "silent",
    error = "continue"
  )
  res_bin <- run_bin(
    "printenv",
    "CONDA_PREFIX",
    env_name = "run-bin-cli-tools-env",
    activate = TRUE,
    verbose = "silent",
    error = "continue"
  )

  testthat::expect_equal(res_run$status, 0L)
  testthat::expect_equal(res_bin$status, 0L)
  testthat::expect_equal(trimws(res_bin$stdout), trimws(res_run$stdout))
  testthat::expect_match(
    trimws(res_bin$stdout),
    "run-bin-cli-tools-env",
    fixed = TRUE
  )
})

test_that("run_bin(activate = TRUE) sets an activated PATH like run()", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    test_os_pkg("coreutils"),
    env_name = "run-bin-cli-tools-env",
    verbose = "silent"
  )
  env_dir <- get_env_dir("run-bin-cli-tools-env")
  is_windows <- isTRUE(stringr::str_detect(get_sys_arch(), "^Windows"))
  # Windows Conda environments put binaries directly in the prefix root
  # (plus `Library/...`/`Scripts`), not in a `bin` subdirectory like
  # Linux/macOS, so the directory PATH is expected to contain differs by
  # platform.
  env_marker_dir <- if (isTRUE(is_windows)) {
    env_dir
  } else {
    fs::path(env_dir, "bin")
  }
  # `fs::path()` always returns a leading drive letter (`C:/...`) on
  # Windows, but the actual PATH string is reported in whatever
  # msys/cygwin mount convention the reading subprocess uses (`/c/...` via
  # a direct native exe, `/cygdrive/c/...` via Rtools' own bash) - neither
  # of which matches `C:/...` verbatim. Everything after the drive letter
  # is unaffected by that translation, so match on that portion only.
  env_marker <- sub("^[A-Za-z]:", "", env_marker_dir)

  res_run <- run(
    "printenv",
    "PATH",
    env_name = "run-bin-cli-tools-env",
    verbose = "silent",
    error = "continue"
  )
  res_bin <- run_bin(
    "printenv",
    "PATH",
    env_name = "run-bin-cli-tools-env",
    activate = TRUE,
    verbose = "silent",
    error = "continue"
  )

  testthat::expect_match(res_run$stdout, env_marker, fixed = TRUE)
  testthat::expect_match(res_bin$stdout, env_marker, fixed = TRUE)
})

test_that("run_bin(activate = FALSE) does not set CONDA_PREFIX", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    test_os_pkg("coreutils"),
    env_name = "run-bin-cli-tools-env",
    verbose = "silent"
  )
  res <- run_bin(
    "printenv",
    "CONDA_PREFIX",
    env_name = "run-bin-cli-tools-env",
    activate = FALSE,
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_true(res$status != 0L || !nzchar(trimws(res$stdout)))
})

test_that("run_bin() reports a missing environment for both activate values", {
  stub <- local_run_family_stub()
  for (activate in c(TRUE, FALSE)) {
    res <- run_bin(
      "Rfakeexec",
      "--version",
      env_name = "fake-env-does-not-exist",
      activate = activate,
      verbose = "silent",
      error = "continue"
    )
    testthat::expect_identical(res$status, 127L)
    testthat::expect_match(res$stderr, "does not exist", fixed = TRUE)
  }
})

test_that("run_bin() honors error = continue when activation resolution fails", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  # Regression test: a failing activation resolution (e.g. a broken
  # activate.d hook) used to throw before the error-handling wrapper,
  # escaping error = "continue" entirely. It must behave like any other
  # failure: classed abort under "cancel", failed result under
  # "continue" - and never silently run the command unactivated.
  create_env(
    test_os_pkg("coreutils"),
    env_name = "run-cli-tools-env",
    verbose = "silent"
  )
  testthat::local_mocked_bindings(
    get_micromamba_activation_envvars = function(...) {
      cli::cli_abort(
        message = "Simulated activation failure.",
        class = "condathis_activation_dump_error"
      )
    }
  )
  res <- run_bin(
    "echo",
    "hi",
    env_name = "run-cli-tools-env",
    error = "continue",
    verbose = "silent"
  )
  testthat::expect_equal(res$status, 127L)
  testthat::expect_match(res$stderr, "Failed to resolve activation")

  testthat::expect_error(
    object = run_bin(
      "echo",
      "hi",
      env_name = "run-cli-tools-env",
      error = "cancel",
      verbose = "silent"
    ),
    class = "condathis_activation_dump_error"
  )
})

test_that("run_bin() keeps a symlinked PATH command's own name", {
  # Regression test: the PATH fallback resolved symlinks, so multicall
  # binaries and tools that dispatch on their own name saw the target's name.
  # The fallback applies to an existing environment that does not have the
  # command.
  stub <- local_run_family_stub()
  dir <- withr::local_tempdir()
  if (isTRUE(is_windows())) {
    # Symbolic links need extra privileges on Windows; a hard link is the
    # same name-versus-target case. `%~n0` is the name it was started as.
    real <- fs::path(dir, "real-tool.cmd")
    writeLines(c("@echo off", "echo argv0=%~n0"), real)
    fs::link_create(real, fs::path(dir, "my-linked-tool.cmd"), symbolic = FALSE)
  } else {
    real <- fs::path(dir, "real-tool.sh")
    writeLines(c("#!/bin/sh", "echo \"argv0=$(basename \"$0\")\""), real)
    fs::file_chmod(real, "u+x")
    fs::link_create(real, fs::path(dir, "my-linked-tool"))
  }
  withr::local_envvar(
    PATH = paste(dir, Sys.getenv("PATH"), sep = .Platform$path.sep)
  )
  for (activate in c(TRUE, FALSE)) {
    res <- run_bin(
      "my-linked-tool",
      env_name = "stub-env",
      activate = activate,
      verbose = "silent"
    )
    testthat::expect_identical(parse_output(res), "argv0=my-linked-tool")
  }
})

# --- Argument checks (rules R1 and R2) --------------------------------------

test_that("run_bin() rejects a cmd that is not a single, non-empty string", {
  # Regression test: run_bin() did not check cmd, and run_bin(NULL)
  # returned a status-0 result through a stub backend.
  local_no_backend_calls()
  for (bad_cmd in list(NULL, 1, NA_character_, "", c("echo", "x"))) {
    cnd <- testthat::expect_error(
      run_bin(bad_cmd, verbose = "silent"),
      class = "condathis_run_bin_invalid_cmd"
    )
    testthat::expect_identical(
      class(cnd)[1:4],
      c(
        "condathis_run_bin_invalid_cmd",
        "condathis_invalid_cmd",
        "condathis_invalid_arg",
        "condathis_error"
      )
    )
    testthat::expect_identical(rlang::call_name(conditionCall(cnd)), "run_bin")
  }
  testthat::expect_error(run_bin(), class = "condathis_run_bin_invalid_cmd")
})

test_that("run_bin() checks timeout, activate and the process arguments before any backend call", {
  # Regression test: `activate = "yes"` silently skipped activation, and a
  # non-numeric timeout failed late with an unclassed processx error.
  local_no_backend_calls()
  bad_args <- list(
    timeout = list("10", NA, -1, c(1, 2)),
    supervise = list(NA),
    cleanup_tree = list("yes"),
    linux_pdeathsig = list(NA),
    activate = list("yes", NA),
    stdout = list(1),
    stderr = list(TRUE),
    stdin = list("/nonexistent/condathis-stdin-file")
  )
  for (arg in names(bad_args)) {
    for (value in bad_args[[arg]]) {
      call_args <- c(
        list("echo", verbose = "silent"),
        rlang::set_names(list(value), arg)
      )
      cnd <- testthat::expect_error(
        do.call(run_bin, call_args),
        class = paste0("condathis_run_bin_invalid_", arg),
        info = arg
      )
      testthat::expect_s3_class(cnd, paste0("condathis_invalid_", arg))
      testthat::expect_s3_class(cnd, "condathis_invalid_arg")
      testthat::expect_s3_class(cnd, "condathis_error")
    }
  }
})

test_that("run_bin() has its own classes for input, binary, error, verbose and named arguments", {
  local_no_backend_calls()
  cnd <- testthat::expect_error(
    run_bin("echo", input = "x"),
    class = "condathis_run_bin_invalid_input"
  )
  # run()'s old class stays.
  testthat::expect_identical(
    class(cnd)[1:5],
    c(
      "condathis_run_bin_invalid_input",
      "condathis_run_invalid_input",
      "condathis_invalid_input",
      "condathis_invalid_arg",
      "condathis_error"
    )
  )
  testthat::expect_identical(rlang::call_name(conditionCall(cnd)), "run_bin")
  cnd <- testthat::expect_error(
    run_bin("echo", binary = NA),
    class = "condathis_run_bin_invalid_binary"
  )
  testthat::expect_identical(
    class(cnd)[1:5],
    c(
      "condathis_run_bin_invalid_binary",
      "condathis_run_invalid_binary_arg",
      "condathis_invalid_binary",
      "condathis_invalid_arg",
      "condathis_error"
    )
  )
  testthat::expect_error(
    run_bin("echo", error = "bogus"),
    class = "condathis_invalid_error"
  )
  testthat::expect_error(
    run_bin("echo", verbose = "bogus"),
    class = "condathis_invalid_verbose"
  )
  cnd <- testthat::expect_error(
    run_bin("echo", env_name = 1),
    class = "condathis_run_bin_invalid_env_name"
  )
  testthat::expect_s3_class(cnd, "condathis_invalid_env_name")
  cnd <- testthat::expect_error(
    run_bin("echo", activat = FALSE),
    class = "condathis_run_bin_invalid_args"
  )
  testthat::expect_s3_class(cnd, "condathis_invalid_arg")
  testthat::expect_match(conditionMessage(cnd), "activate", fixed = TRUE)
  # The classes of the rlang error that run_bin() raised before stay, so
  # old handlers still match.
  testthat::expect_identical(
    setdiff(class(cnd), c("rlang_error", "error", "condition")),
    c(
      "condathis_run_bin_invalid_args",
      "condathis_invalid_cmd_args",
      "condathis_invalid_arg",
      "condathis_error",
      "rlib_error_dots_named",
      "rlib_error_dots"
    )
  )
  testthat::expect_error(
    run_bin("echo", activat = FALSE),
    class = "rlib_error_dots_named"
  )
})

# --- Missing environments (decision D3) -------------------------------------

test_that("run_bin() creates condathis-env with the backend that method names", {
  testthat::skip_on_cran()
  stub_a <- local_stub_backend("stub-a")
  stub_b <- local_stub_backend("stub-b")
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() c("stub-b", "stub-a")
  )
  testthat::expect_no_warning(
    res <- run_bin(
      run_family_rscript(),
      "--vanilla",
      "-e",
      "cat('created')",
      method = "stub-a",
      verbose = "silent"
    )
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(res$stdout, "created")
  testthat::expect_identical(res$env_name, "condathis-env")
  testthat::expect_true(
    fs::dir_exists(fs::path(stub_a$root, "envs", "condathis-env"))
  )
  testthat::expect_false(
    fs::dir_exists(fs::path(stub_b$root, "envs", "condathis-env"))
  )
})

# --- Activation and the backend_resolve_run() contract ----------------------

test_that("run_bin(activate = FALSE) calls no backend function to resolve the command", {
  testthat::skip_on_cran()
  # Regression test: with activate = FALSE, other backends still went
  # through backend_resolve_run(), so a broken activation made it fail.
  stub <- local_run_family_stub(
    backend_resolve_run = function(...) {
      stop("backend_resolve_run() must not be called.")
    }
  )
  res <- run_bin(
    run_family_rscript(),
    "--vanilla",
    "-e",
    "cat('no activation')",
    env_name = "stub-env",
    activate = FALSE,
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(res$stdout, "no activation")
  testthat::expect_length(stub_calls(stub, "backend_resolve_run"), 0L)

  # With activation, the backend describes the command once.
  stub <- local_run_family_stub("stub-run-active")
  res <- run_bin(
    run_family_rscript(),
    "--vanilla",
    "-e",
    "cat('activated')",
    env_name = "stub-env",
    verbose = "silent"
  )
  testthat::expect_identical(res$stdout, "activated")
  testthat::expect_length(stub_calls(stub, "backend_resolve_run"), 1L)
})

test_that("run_bin() reports the user's command line, not the backend's wrapper", {
  testthat::skip_on_cran()
  # Regression test: the reported cmd mixed the user's command with the
  # arguments of the backend's wrapper.
  rscript <- run_family_rscript()
  stub <- local_run_family_stub(
    backend_resolve_run = function(backend, cmd, args = character(0L), ...) {
      return(list(
        command = rscript,
        args = c("--vanilla", "-e", "cat('wrapped')"),
        env = c(CONDATHIS_TEST_WRAPPED = "yes"),
        dir = NULL
      ))
    }
  )
  res <- run_bin("echo", "hi", env_name = "stub-env", verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(res$stdout, "wrapped")
  testthat::expect_identical(
    res$cmd,
    paste(shQuote(c("echo", "hi")), collapse = " ")
  )
})

test_that("run_bin() runs in the dir that backend_resolve_run() returns, and checks it", {
  testthat::skip_on_cran()
  # Regression test: only run() applied `dir`, and its type was not
  # checked.
  work_dir <- withr::local_tempdir()
  stub <- local_run_family_stub(
    backend_resolve_run = function(backend, cmd, args = character(0L), ...) {
      return(list(command = cmd, args = args, env = NULL, dir = work_dir))
    }
  )
  res <- run_bin(
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

  bad_dir <- NULL
  stub <- local_run_family_stub(
    "stub-run-bad-dir",
    backend_resolve_run = function(backend, cmd, args = character(0L), ...) {
      return(list(command = cmd, args = args, env = NULL, dir = bad_dir))
    }
  )
  for (bad_dir in list(1, NA_character_, fs::path(work_dir, "no-such-dir"))) {
    cnd <- testthat::expect_error(
      run_bin("echo", env_name = "stub-env", verbose = "silent"),
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
    testthat::expect_identical(rlang::call_name(conditionCall(cnd)), "run_bin")
    testthat::expect_match(
      conditionMessage(cnd),
      "stub-run-bad-dir",
      fixed = TRUE
    )
  }
})

test_that("run_bin() gives one text for a failed resolution under error = continue", {
  # Regression test: run_bin() kept the ANSI codes of the message and ended
  # without a newline, unlike run() and run_pipeline().
  withr::local_options(cli.num_colors = 256L)
  stub <- local_run_family_stub(
    backend_resolve_run = function(...) {
      cli::cli_abort(
        "Hook {.val broken} failed.",
        class = "condathis_activation_dump_error"
      )
    }
  )
  res <- run_bin(
    "echo",
    env_name = "stub-env",
    error = "continue",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 127L)
  testthat::expect_identical(
    res$stderr,
    "Failed to resolve activation for environment 'stub-env': Hook \"broken\" failed.\n"
  )
  testthat::expect_error(
    run_bin("echo", env_name = "stub-env", verbose = "silent"),
    class = "condathis_activation_dump_error"
  )
})

test_that("run_bin() wraps a backend's resolution error with its own class", {
  # Regression test: under error = "cancel", run_bin() re-raised the
  # backend's error unchanged, with an internal call, and a backend that
  # calls stop() gave a bare simpleError without condathis_error.
  stub <- local_run_family_stub(
    backend_resolve_run = function(...) {
      stop("plain resolution failure")
    }
  )
  cnd <- rlang::catch_cnd(
    run_bin("echo", env_name = "stub-env", verbose = "silent"),
    classes = "error"
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_run_bin_resolve_failed",
      "condathis_backend_error",
      "condathis_error",
      "rlang_error",
      "error",
      "condition"
    )
  )
  testthat::expect_s3_class(cnd$parent, "simpleError")
  testthat::expect_identical(rlang::call_name(conditionCall(cnd)), "run_bin")
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "Backend stub-run failed to resolve command `echo` for environment stub-env.",
    fixed = TRUE
  )

  # A value that breaks the contract is not wrapped: its own error already
  # names the backend and the call.
  stub <- local_run_family_stub(
    "stub-run-bad-value",
    backend_resolve_run = function(...) list(command = 1)
  )
  cnd <- rlang::catch_cnd(
    run_bin("echo", env_name = "stub-env", verbose = "silent"),
    classes = "error"
  )
  testthat::expect_s3_class(cnd, "condathis_backend_resolve_run_invalid")
  testthat::expect_false(inherits(cnd, "condathis_run_bin_resolve_failed"))
  res <- run_bin(
    "echo",
    env_name = "stub-env",
    error = "continue",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 127L)
  testthat::expect_match(
    res$stderr,
    "Failed to resolve activation",
    fixed = TRUE
  )
})

# --- Errors of a failed command ----------------------------------------------

test_that("run_bin() status and timeout errors have its own and the shared classes", {
  testthat::skip_on_cran()
  stub <- local_run_family_stub()
  rscript <- run_family_rscript()
  cnd <- testthat::expect_error(
    run_bin(
      rscript,
      "--vanilla",
      "-e",
      "cat('out'); quit(status = 4)",
      env_name = "stub-env",
      verbose = "silent"
    ),
    class = "condathis_run_bin_status_error"
  )
  testthat::expect_identical(
    class(cnd)[1:4],
    c(
      "condathis_run_bin_status_error",
      "condathis_run_status_error",
      "condathis_status_error",
      "condathis_error"
    )
  )
  testthat::expect_identical(cnd$status, 4L)
  testthat::expect_identical(cnd$stdout, "out")
  testthat::expect_identical(rlang::call_name(conditionCall(cnd)), "run_bin")

  cnd <- testthat::expect_error(
    run_bin(
      rscript,
      "--vanilla",
      "-e",
      "Sys.sleep(30)",
      env_name = "stub-env",
      timeout = 1,
      verbose = "silent"
    ),
    class = "condathis_run_bin_timeout_error"
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
  testthat::expect_true(cnd$timeout)
  testthat::expect_identical(cnd$status, -9L)
})

test_that("run_bin() looks a bare command up on the child's PATH, not the session's", {
  # Regression test: with `activate = TRUE`, a bare command from
  # backend_resolve_run() was looked up with Sys.which(), on the PATH of
  # the R session. A same-named program there ran instead of the
  # environment's own.
  stub <- local_run_family_stub()
  env_bin <- fs::path(stub$root, "envs", "stub-env", "bin")
  fs::dir_create(env_bin)
  run_family_write_tool(env_bin, "condathis-shadow-tool", "from-environment")
  decoy_dir <- withr::local_tempdir()
  run_family_write_tool(decoy_dir, "condathis-shadow-tool", "from-session")
  withr::local_envvar(
    PATH = paste(decoy_dir, Sys.getenv("PATH"), sep = .Platform$path.sep)
  )
  for (activate in c(TRUE, FALSE)) {
    res <- run_bin(
      "condathis-shadow-tool",
      env_name = "stub-env",
      activate = activate,
      verbose = "silent"
    )
    testthat::expect_identical(
      parse_output(res),
      "from-environment",
      info = paste("activate:", activate)
    )
  }
})

test_that("run_bin() finds a command that only the activation PATH provides", {
  # Regression test: Sys.which() searched the PATH of the R session, so a
  # command on the PATH of the backend's activation was not found, and the
  # start failed with status 127.
  tool_dir <- withr::local_tempdir()
  run_family_write_tool(tool_dir, "condathis-activation-tool", "activated")
  stub <- local_run_family_stub(
    backend_resolve_run = function(backend, cmd, args = character(0L), ...) {
      activation_path <- paste(
        tool_dir,
        Sys.getenv("PATH"),
        sep = .Platform$path.sep
      )
      return(list(
        command = cmd,
        args = args,
        env = c(PATH = activation_path),
        dir = NULL
      ))
    }
  )
  res <- run_bin(
    "condathis-activation-tool",
    env_name = "stub-env",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(parse_output(res), "activated")
  # Without activation, the backend's PATH does not apply.
  res <- run_bin(
    "condathis-activation-tool",
    env_name = "stub-env",
    activate = FALSE,
    error = "continue",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 127L)
})

test_that("resolve_run_bin_command() keeps paths and searches the given PATH", {
  # Relative directories keep the `:` of the Linux and macOS rule apart
  # from Windows drive letters, so this runs on every OS. An `.exe` name
  # passes the execute check of R on Windows; elsewhere the file gets the
  # execute permission.
  withr::local_dir(withr::local_tempdir())
  env_dir <- fs::path(getwd(), "env")
  fs::dir_create(c("first", "second"))
  for (tool in c("first/tool.exe", "second/tool.exe")) {
    writeLines("", tool)
    Sys.chmod(tool, "755")
  }

  # An absolute path is kept as it is, whether it exists or not.
  abs_tool <- normalizePath("first/tool.exe", winslash = "/")
  testthat::expect_identical(
    resolve_run_bin_command(abs_tool, env_dir, path = "", on_windows = FALSE),
    abs_tool
  )
  missing_abs <- as.character(fs::path(getwd(), "missing-tool"))
  testthat::expect_identical(
    resolve_run_bin_command(
      missing_abs,
      env_dir,
      path = "first",
      on_windows = FALSE
    ),
    missing_abs
  )
  # A name with a directory part is never searched for on PATH.
  testthat::expect_identical(
    resolve_run_bin_command(
      "./tool.exe",
      env_dir,
      path = "second",
      on_windows = FALSE
    ),
    "./tool.exe"
  )
  testthat::expect_identical(
    resolve_run_bin_command(
      "sub\\tool",
      env_dir,
      path = "second",
      on_windows = TRUE
    ),
    "sub\\tool"
  )
  # A bare name: the first PATH entry that has it wins, kept as found.
  # Empty entries are skipped.
  testthat::expect_identical(
    resolve_run_bin_command(
      "tool.exe",
      env_dir,
      path = "first:second",
      on_windows = FALSE
    ),
    "first/tool.exe"
  )
  testthat::expect_identical(
    resolve_run_bin_command(
      "tool.exe",
      env_dir,
      path = "::second:",
      on_windows = FALSE
    ),
    "second/tool.exe"
  )
  # Only `path` is searched, never the PATH of the R session: found
  # nowhere, the command is a path under the environment, so the start
  # fails as "command not found".
  for (empty_path in list("", NULL, NA_character_)) {
    testthat::expect_identical(
      resolve_run_bin_command(
        "tool.exe",
        env_dir,
        path = empty_path,
        on_windows = FALSE
      ),
      as.character(fs::path(env_dir, "bin", "tool.exe"))
    )
    # With `keep_bare = TRUE` (run()), it stays bare instead.
    for (on_windows in c(FALSE, TRUE)) {
      testthat::expect_identical(
        resolve_run_bin_command(
          "tool.exe",
          env_dir,
          path = empty_path,
          on_windows = on_windows,
          keep_bare = TRUE
        ),
        "tool.exe"
      )
    }
  }
  # A hit is a hit, whatever `keep_bare` is.
  testthat::expect_identical(
    resolve_run_bin_command(
      "tool.exe",
      env_dir,
      path = "first:second",
      on_windows = FALSE,
      keep_bare = TRUE
    ),
    "first/tool.exe"
  )

  # The Windows rule: `;` separates entries, quotes are removed, PATHEXT
  # extensions are tried, and the hit is normalized.
  fs::dir_create("win")
  writeLines("", "win/tool.cmd")
  win_dir <- normalizePath("win", winslash = "/")
  testthat::expect_identical(
    resolve_run_bin_command(
      "tool",
      env_dir,
      path = paste0("\"", win_dir, "\";", getwd(), "/first"),
      on_windows = TRUE,
      pathext = ".EXE;.CMD"
    ),
    normalizePath(file.path(win_dir, "tool.cmd"), mustWork = FALSE)
  )
})

test_that("find_command_on_path() skips directories and files that cannot run", {
  withr::local_dir(withr::local_tempdir())
  # A directory with the name of the command does not count.
  fs::dir_create(c("a/tool.exe", "b", "c"))
  writeLines("", "b/tool.exe")
  Sys.chmod("b/tool.exe", "755")
  testthat::expect_identical(
    find_command_on_path("tool.exe", "a:b", on_windows = FALSE),
    "b/tool.exe"
  )
  # Without the execute permission (and, for R on Windows, without an
  # executable extension), a file does not count on Linux and macOS.
  writeLines("", "c/plain-tool")
  Sys.chmod("c/plain-tool", "644")
  testthat::expect_null(
    find_command_on_path("plain-tool", "c", on_windows = FALSE)
  )
  # On Windows, any file with a name of command_candidate_names() counts.
  # A file without an extension never counts for a name without one:
  # processx starts it only as `<name>.com` or `<name>.exe`. Regression
  # test: `cmd`, the MSYS2 shell script that Rtools puts ahead of
  # `C:/Windows/System32`, was found instead of `cmd.exe`.
  testthat::expect_null(
    find_command_on_path(
      "plain-tool",
      "c",
      on_windows = TRUE,
      pathext = ".EXE"
    )
  )
  fs::dir_create("d")
  writeLines("", "d/plain-tool.exe")
  testthat::expect_identical(
    find_command_on_path(
      "plain-tool",
      "c;d",
      on_windows = TRUE,
      pathext = ".EXE"
    ),
    "d/plain-tool.exe"
  )
  # A name with an extension is tried as it is first.
  writeLines("", "c/plain-tool.x")
  testthat::expect_identical(
    find_command_on_path(
      "plain-tool.x",
      "c;d",
      on_windows = TRUE,
      pathext = ".EXE"
    ),
    "c/plain-tool.x"
  )
  testthat::expect_null(find_command_on_path("tool.exe", NULL))
  testthat::expect_null(find_command_on_path("tool.exe", NA_character_))
})

test_that("command_candidate_names() adds PATHEXT extensions only on Windows", {
  testthat::expect_identical(
    command_candidate_names("tool", on_windows = FALSE, pathext = ".EXE"),
    "tool"
  )
  # Without an extension, the name itself is not a candidate on Windows,
  # as for processx and `CreateProcess()`.
  testthat::expect_identical(
    command_candidate_names("tool", on_windows = TRUE, pathext = ".EXE;;.CMD"),
    c("tool.exe", "tool.cmd", "tool.EXE", "tool.CMD")
  )
  for (cmd in c("tool.exe", "python3.12", "sub/tool.x")) {
    testthat::expect_identical(
      command_candidate_names(cmd, on_windows = TRUE, pathext = ".EXE"),
      c(cmd, paste0(cmd, ".exe"), paste0(cmd, ".EXE")),
      info = cmd
    )
  }
  # A dot only at the end, or in a directory, is not an extension.
  for (cmd in c("tool.", "dir.d/tool", "dir.d\\tool", "c:tool")) {
    testthat::expect_false(command_has_extension(cmd), info = cmd)
  }
  testthat::expect_true(command_has_extension("C:/dir/tool.exe"))
})

test_that("run_bin() gives backend_resolve_run() the child's block before activation", {
  # The backend computes its activation against `base_env`: the session's
  # environment with the clean conda overlay, the per-call TMPDIR and the
  # backend's conda directories. The child's block is that block with the
  # activation variables, and the environment's directories in front of
  # its PATH.
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
        env = c(CONDATHIS_TEST_ACTIVATED = "yes"),
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
    MAMBA_ROOT_PREFIX = "/caller/root"
  )
  env_dir <- as.character(fs::path(stub$root, "envs", "stub-env"))
  path_of <- function(env) {
    return(unname(env[[match_env_name(names(env), "PATH")]]))
  }

  res <- run_bin(
    run_family_rscript(),
    "--version",
    env_name = "stub-env",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  base_env <- seen$base_env
  testthat::expect_type(base_env, "character")
  testthat::expect_identical(
    unname(base_env[["CONDATHIS_TEST_SESSION"]]),
    "kept"
  )
  testthat::expect_identical(unname(base_env[["CONDARC"]]), "")
  testthat::expect_identical(unname(base_env[["MAMBA_ROOT_PREFIX"]]), "")
  testthat::expect_match(base_env[["TMPDIR"]], "condathis-tmp", fixed = TRUE)
  testthat::expect_identical(
    unname(base_env[["CONDA_ENVS_PATH"]]),
    as.character(fs::path(stub$root, "envs"))
  )
  testthat::expect_identical(
    unname(base_env[["CONDA_PKGS_DIRS"]]),
    as.character(fs::path(stub$root, "conda-pkgs"))
  )
  # `base_env` has no environment directory on its PATH: the activation
  # adds what it needs.
  testthat::expect_identical(path_of(base_env), Sys.getenv("PATH"))

  child_env <- seen$env
  testthat::expect_identical(
    unname(child_env[["CONDATHIS_TEST_ACTIVATED"]]),
    "yes"
  )
  testthat::expect_identical(
    path_of(child_env),
    compose_path(env_bin_search_dirs(env_dir), path_of(base_env))
  )
  path_names <- names(base_env)[toupper(names(base_env)) == "PATH"]
  kept <- setdiff(names(base_env), path_names)
  testthat::expect_identical(child_env[kept], base_env[kept])
  testthat::expect_setequal(
    names(child_env),
    c(names(base_env), "CONDATHIS_TEST_ACTIVATED")
  )

  # Without activation, no backend function runs: the child's block is the
  # same block, with the environment's directories in front of its PATH.
  seen$base_env <- NULL
  res <- run_bin(
    run_family_rscript(),
    "--version",
    env_name = "stub-env",
    activate = FALSE,
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_null(seen$base_env)
  testthat::expect_false("CONDATHIS_TEST_ACTIVATED" %in% names(seen$env))
  testthat::expect_identical(
    seen$env[kept[kept != "TMPDIR"]],
    base_env[kept[kept != "TMPDIR"]]
  )
  testthat::expect_identical(
    path_of(seen$env),
    compose_path(env_bin_search_dirs(env_dir), Sys.getenv("PATH"))
  )
})

test_that("run_bin() puts each directory of the environment once on the command's PATH", {
  # Regression test: on Windows, the activation of micromamba spells the
  # environment's directories with `\`, and `run_bin()` put them in front
  # again spelled with `/`, so the command's PATH had two copies of each.
  # The activation of this stub puts them in front of the PATH as
  # micromamba does on each OS.
  seen <- new.env(parent = emptyenv())
  stub <- local_run_family_stub(
    backend_resolve_run = function(
      backend,
      cmd,
      args = character(0L),
      ...,
      env_name,
      base_env = NULL
    ) {
      env_dir <- as.character(fs::path(stub$root, "envs", env_name))
      dirs <- as.character(env_bin_search_dirs(env_dir))
      if (isTRUE(is_windows())) {
        dirs <- gsub("/", "\\", dirs, fixed = TRUE)
      }
      base_path <- unname(base_env[[match_env_name(names(base_env), "PATH")]])
      return(list(
        command = cmd,
        args = args,
        env = c(PATH = compose_path(dirs, base_path)),
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
  env_dir <- as.character(fs::path(stub$root, "envs", "stub-env"))
  dirs <- as.character(env_bin_search_dirs(env_dir))
  res <- run_bin(
    run_family_rscript(),
    "--version",
    env_name = "stub-env",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  child_path <- unname(seen$env[[match_env_name(names(seen$env), "PATH")]])
  entries <- strsplit(child_path, .Platform$path.sep, fixed = TRUE)[[1L]]
  copies <- vapply(
    path_entry_key(dirs),
    function(key) sum(path_entry_key(entries) == key),
    integer(1L)
  )
  testthat::expect_identical(unname(copies), rep(1L, length(dirs)))
  # The environment's directories come first, spelled as `run_bin()`
  # spells them, then the PATH of the session.
  testthat::expect_identical(entries[seq_along(dirs)], dirs)
  testthat::expect_identical(
    child_path,
    compose_path(dirs, Sys.getenv("PATH"))
  )
})

test_that("run_bin() starts a command given as an absolute path, for both activate values", {
  # Regression test: on Windows, `run_bin()` started an absolute command
  # with `/` in its path, and `cmd.exe` started that way failed with "The
  # syntax of the command is incorrect.".
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  env_name <- "run-bin-absolute-path-env"
  create_polyglot_env(env_name)
  if (isTRUE(is_windows())) {
    cmd <- gsub(
      "/",
      "\\",
      file.path(Sys.getenv("SystemRoot"), "System32", "cmd.exe"),
      fixed = TRUE
    )
    args <- c("/d", "/c", "echo", "condathis-ok")
  } else {
    cmd <- run_family_rscript()
    args <- c("-e", "cat('condathis-ok')")
  }
  for (activate in c(TRUE, FALSE)) {
    res <- run_bin(
      cmd,
      args,
      env_name = env_name,
      activate = activate,
      verbose = "silent",
      error = "continue"
    )
    testthat::expect_identical(
      res$status,
      0L,
      info = paste("activate", activate)
    )
    testthat::expect_match(
      res$stdout,
      "condathis-ok",
      fixed = TRUE,
      info = paste("activate", activate)
    )
  }
})
