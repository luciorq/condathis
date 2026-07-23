test_that("Accept binary outside of environment", {
  # `error = "continue"` Should not error even when R is not on PATH
  run_bin_res <- run_bin(
    "R",
    "--version",
    env_name = "fake-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_true(is.numeric(run_bin_res$status))

  run_bin_fake_res <- run_bin(
    "Rfakeexec",
    "--version",
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
        "R",
        "--version",
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
        "Rfakeexec",
        "--version",
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
  testthat::expect_true(is.raw(res$stdout))
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
  res <- run_bin(
    "echo",
    "hi",
    supervise = TRUE,
    cleanup_tree = TRUE,
    linux_pdeathsig = TRUE,
    env_name = "run-bin-cli-tools-env",
    verbose = "silent"
  )
  testthat::expect_equal(res$status, 0L)
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
  # a direct native exe, `/cygdrive/c/...` via Rtools' own bash) — neither
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

test_that("run_bin(activate = TRUE) falls back gracefully for a missing env", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  res <- run_bin(
    "Rfakeexec",
    "--version",
    env_name = "fake-env-does-not-exist",
    activate = TRUE,
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_true(is.numeric(res$status))
  testthat::expect_true(res$status != 0L)
})
