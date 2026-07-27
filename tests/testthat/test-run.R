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

testthat::test_that("Run with unexpected error argument", {
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
    env_name = "run-cli-tools-env",
    verbose = "silent"
  )
  res <- run(
    "bash",
    "-c",
    "cat; exit 1",
    stdin = "|",
    input = "boom\n",
    env_name = "run-cli-tools-env",
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
      env_name = "run-cli-tools-env",
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
  res <- run(
    "echo",
    "hi",
    supervise = TRUE,
    cleanup_tree = TRUE,
    linux_pdeathsig = TRUE,
    env_name = "run-cli-tools-env",
    verbose = "silent"
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
  testthat::expect_true(is.raw(res$stdout))
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
  testthat::expect_true(is.character(res$stdout))

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
  # the OS pipe buffer (64KB on Linux, smaller on macOS/Windows) — the
  # child blocks on write() to whichever stream isn't read yet, so it never
  # exits, so wait() never returns.
  #
  # Byte generation uses `head -c N /dev/zero | tr '\0' 'X'`, not
  # `printf '%*s' N ''` — `run()` always spawns `bash` via `micromamba run`
  # (through `native_cmd()`), and confirmed directly on Windows: literal
  # `%` characters are silently stripped somewhere in `micromamba run`'s
  # own Windows argument handling (even a bare `echo '100% done'` comes
  # back as `100 done`), corrupting `printf`'s format string and any
  # command containing one. `head`/`tr` invoked directly (bypassing
  # `micromamba run`, e.g. from `run_pipeline()`) are unaffected — this is
  # specific to arguments that cross that wrapper, not a `condathis` bug.
  create_env(
    c(test_os_pkg("coreutils"), test_os_pkg("bash")),
    env_name = "run-cli-tools-env",
    verbose = "silent"
  )
  res <- run(
    "bash",
    "-c",
    "cat; head -c 200000 /dev/zero | tr '\\0' 'B' 1>&2",
    stdin = "|",
    input = strrep("A", 200000),
    env_name = "run-cli-tools-env",
    verbose = "silent"
  )
  testthat::expect_equal(nchar(res$stdout), 200000L)
  testthat::expect_equal(nchar(res$stderr), 200000L)
})

test_that("Run with stdin = '|' does not truncate large input", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  # Regression test: write_input() once, then close immediately, silently
  # truncates `input` past the OS pipe buffer — confirmed empirically: only
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
