pipeline_cli_pkgs <- function() {
  c(test_os_pkg("coreutils"), test_os_pkg("bash"), test_os_pkg("util-linux"))
}

test_that("Pipeline rejects non-list cmds", {
  testthat::expect_error(
    object = run_pipeline(c("echo", "hello")),
    class = "condathis_pipeline_invalid_cmds"
  )
})

test_that("Pipeline rejects empty cmds", {
  testthat::expect_error(
    object = run_pipeline(list()),
    class = "condathis_pipeline_invalid_cmds"
  )
})

test_that("Pipeline rejects single command", {
  testthat::expect_error(
    object = run_pipeline(list(c("echo", "hello"))),
    class = "condathis_pipeline_too_few_commands"
  )
})

test_that("Pipeline rejects invalid command spec", {
  testthat::expect_error(
    object = run_pipeline(list(1:3)),
    class = "condathis_pipeline_invalid_cmd_type"
  )
})

test_that("Pipeline rejects a named list spec missing cmd", {
  testthat::expect_error(
    object = run_pipeline(
      list(list(env_name = "condathis-env"), c("cat"))
    ),
    class = "condathis_pipeline_invalid_cmd_spec"
  )
})

test_that("Pipeline rejects empty command vector", {
  testthat::expect_error(
    object = run_pipeline(list(character(0L), c("echo", "hello"))),
    class = "condathis_pipeline_empty_cmd"
  )
})

test_that("Pipeline rejects non-existent environment", {
  testthat::expect_error(
    object = run_pipeline(
      list(
        c("echo", "hello"),
        c("cat")
      ),
      env_name = "non-existent-env"
    ),
    class = "condathis_pipeline_env_not_found"
  )
})

test_that("Pipeline runs two commands in same environment", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    cmds = list(
      c("echo", "hello world"),
      c("tr", "[:lower:]", "[:upper:]")
    ),
    env_name = "run-pipeline-cli-tools-env",
    error = "continue"
  )
  testthat::expect_s3_class(res, "condathis_pipeline")
  testthat::expect_length(res$statuses, 2L)
  testthat::expect_true(is.integer(res$statuses))
  testthat::expect_length(res$processes, 2L)

  last_stdout <- res$processes[[2]]$stdout
  testthat::expect_match(last_stdout, "HELLO WORLD")
})

test_that("Pipeline returns per-process stderr", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    cmds = list(
      c("echo", "hello"),
      c("cat")
    ),
    env_name = "run-pipeline-cli-tools-env",
    error = "continue"
  )
  testthat::expect_type(res$processes[[1]]$stderr, "character")
  testthat::expect_type(res$processes[[2]]$stderr, "character")
})

test_that("Pipeline with error = cancel throws on failure", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  testthat::expect_error(
    object = {
      run_pipeline(
        cmds = list(
          c("false"),
          c("echo", "never reached")
        ),
        env_name = "run-pipeline-cli-tools-env",
        error = "cancel"
      )
    },
    class = "condathis_pipeline_status_error"
  )
})

test_that("Pipeline with error = continue does not throw on failure", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    cmds = list(
      c("false"),
      c("echo", "still runs")
    ),
    env_name = "run-pipeline-cli-tools-env",
    error = "continue"
  )
  testthat::expect_s3_class(res, "condathis_pipeline")
  testthat::expect_equal(res$statuses[[1]], 1L)
})

test_that("Pipeline with missing command and error = continue returns a result", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    cmds = list(
      c("this-cmd-does-not-exist-xyz"),
      c("cat")
    ),
    env_name = "run-pipeline-cli-tools-env",
    error = "continue"
  )
  testthat::expect_s3_class(res, "condathis_pipeline")
  testthat::expect_equal(res$statuses[[1]], 127L)
  testthat::expect_match(
    res$processes[[1]]$stderr,
    "System command 'this-cmd-does-not-exist-xyz' not found"
  )
  testthat::expect_equal(res$statuses[[2]], 0L)
})

test_that("Pipeline with missing command and error = cancel throws a condathis error", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  cnd <- testthat::expect_error(
    object = run_pipeline(
      cmds = list(
        c("this-cmd-does-not-exist-xyz"),
        c("cat")
      ),
      env_name = "run-pipeline-cli-tools-env",
      error = "cancel"
    ),
    class = "condathis_pipeline_status_error"
  )
  testthat::expect_match(conditionMessage(cnd), "not found")
})

test_that("Pipeline error message escapes curly braces in stderr", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  cnd <- testthat::expect_error(
    object = run_pipeline(
      cmds = list(
        c("bash", "-c", "echo 'boom {curly} }brace{' >&2; exit 1"),
        c("cat")
      ),
      env_name = "run-pipeline-cli-tools-env",
      error = "cancel"
    ),
    class = "condathis_pipeline_status_error"
  )
  testthat::expect_match(
    conditionMessage(cnd),
    "boom \\{curly\\} \\}brace\\{",
    fixed = FALSE
  )
})

test_that("Pipeline with missing custom env and error = continue returns a result", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  res <- run_pipeline(
    cmds = list(
      c("echo", "hi"),
      c("cat")
    ),
    env_name = "totally-custom-missing-env",
    error = "continue"
  )
  testthat::expect_s3_class(res, "condathis_pipeline")
  testthat::expect_equal(res$statuses, c(127L, 127L))
  testthat::expect_match(
    res$processes[[1]]$stderr,
    "Conda environment 'totally-custom-missing-env' does not exist"
  )
})

test_that("Pipeline with missing custom env and error = cancel still fails fast", {
  testthat::expect_error(
    object = run_pipeline(
      cmds = list(
        c("echo", "hi"),
        c("cat")
      ),
      env_name = "totally-custom-missing-env",
      error = "cancel"
    ),
    class = "condathis_pipeline_env_not_found"
  )
})

test_that("Pipeline with stdin file", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  tmpfile <- withr::local_tempfile(lines = c("b", "a", "c", "a", "b"))
  res <- run_pipeline(
    cmds = list(
      c("sort"),
      c("uniq")
    ),
    stdin = tmpfile,
    env_name = "run-pipeline-cli-tools-env",
    error = "continue"
  )
  testthat::expect_s3_class(res, "condathis_pipeline")
  last_stdout <- res$processes[[2]]$stdout
  sorted_unique <- strsplit(trimws(last_stdout), "\n")[[1]]
  testthat::expect_equal(sorted_unique, c("a", "b", "c"))
})

test_that("Pipeline rejects stdout override on non-last command", {
  testthat::expect_error(
    object = run_pipeline(
      list(
        list(cmd = c("echo", "hello"), stdout = "somefile"),
        c("cat")
      )
    ),
    class = "condathis_pipeline_invalid_stdout_override"
  )
})

test_that("Pipeline rejects input without stdin = '|'", {
  testthat::expect_error(
    object = run_pipeline(
      list(c("echo", "hello"), c("cat")),
      input = "hello"
    ),
    class = "condathis_pipeline_invalid_input"
  )
})

test_that("Pipeline auto-creates the default environment when missing", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  res <- run_pipeline(
    cmds = list(
      c("echo", "auto created"),
      c("cat")
    ),
    error = "continue"
  )
  testthat::expect_s3_class(res, "condathis_pipeline")
  testthat::expect_true(env_exists("condathis-env"))
})

test_that("Pipeline intermediate processes report NA stdout", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    cmds = list(
      c("echo", "hello"),
      c("cat")
    ),
    env_name = "run-pipeline-cli-tools-env",
    error = "continue"
  )
  testthat::expect_true(is.na(res$processes[[1]]$stdout))
  testthat::expect_false(is.na(res$processes[[2]]$stdout))
})

test_that("Pipeline supports three chained commands", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    cmds = list(
      c("echo", "hello world"),
      c("tr", "[:lower:]", "[:upper:]"),
      c("rev")
    ),
    env_name = "run-pipeline-cli-tools-env",
    error = "continue"
  )
  testthat::expect_length(res$statuses, 3L)
  testthat::expect_length(res$processes, 3L)
  last_stdout <- res$processes[[3]]$stdout
  testthat::expect_match(last_stdout, "DLROW OLLEH")
})

test_that("Pipeline accepts fully named list specs", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    cmds = list(
      list(
        cmd = c("echo", "named spec"),
        env_name = "run-pipeline-cli-tools-env"
      ),
      list(cmd = c("cat"), env_name = "run-pipeline-cli-tools-env")
    ),
    error = "continue"
  )
  testthat::expect_s3_class(res, "condathis_pipeline")
  testthat::expect_match(res$processes[[2]]$stdout, "named spec")
})

test_that("Pipeline reports a positive integer pid per process", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    cmds = list(
      c("echo", "hello"),
      c("cat")
    ),
    env_name = "run-pipeline-cli-tools-env",
    error = "continue"
  )
  for (p in res$processes) {
    testthat::expect_true(is.numeric(p$pid))
    testthat::expect_gt(p$pid, 0L)
  }
})

test_that("Pipeline result has a logical timeout field", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    cmds = list(
      c("echo", "hello"),
      c("cat")
    ),
    env_name = "run-pipeline-cli-tools-env",
    error = "continue"
  )
  testthat::expect_type(res$timeout, "logical")
  testthat::expect_false(res$timeout)
})

test_that("Pipeline stdin = '|' writes input to the first process", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    cmds = list(
      c("sort"),
      c("uniq")
    ),
    stdin = "|",
    input = "b\na\nc\na\nb\n",
    env_name = "run-pipeline-cli-tools-env",
    error = "continue"
  )
  last_stdout <- res$processes[[2]]$stdout
  sorted_unique <- strsplit(trimws(last_stdout), "\n")[[1]]
  testthat::expect_equal(sorted_unique, c("a", "b", "c"))
})

test_that("Pipeline stdin = '|' with no input closes cleanly", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    cmds = list(
      c("cat"),
      c("cat")
    ),
    stdin = "|",
    env_name = "run-pipeline-cli-tools-env",
    error = "continue"
  )
  testthat::expect_equal(res$statuses, c(0L, 0L))
  testthat::expect_equal(res$processes[[2]]$stdout, "")
})

test_that("Pipeline with binary = TRUE round-trips raw bytes", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )

  raw_bytes <- as.raw(c(0x00, 0x01, 0xFF, 0x41, 0x0A, 0xFE, 0x00))
  tmp_file <- withr::local_tempfile()
  writeBin(raw_bytes, tmp_file)

  res <- run_pipeline(
    cmds = list(
      c("cat", tmp_file),
      c("cat")
    ),
    env_name = "run-pipeline-cli-tools-env",
    binary = TRUE
  )
  last_stdout <- res$processes[[2]]$stdout
  testthat::expect_true(is.raw(last_stdout))
  testthat::expect_identical(last_stdout, raw_bytes)

  formatted <- format(res)
  testthat::expect_type(formatted, "character")
  testthat::expect_match(formatted, "binary data, 7 bytes")
})

test_that("Pipeline with binary = FALSE (default) still captures text", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    cmds = list(
      c("echo", "hi"),
      c("cat")
    ),
    env_name = "run-pipeline-cli-tools-env"
  )
  testthat::expect_true(is.character(res$processes[[2]]$stdout))
})

test_that("Pipeline rejects non-logical binary argument", {
  testthat::expect_error(
    object = run_pipeline(
      cmds = list(c("echo", "hi"), c("cat")),
      binary = "yes"
    ),
    class = "condathis_pipeline_invalid_binary_arg"
  )
})

test_that("Pipeline does not deadlock when the last command's stdout and stderr are both large", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  # Regression test: draining stdout and stderr sequentially (or calling
  # wait() before draining either) deadlocks once combined output exceeds
  # the OS pipe buffer (64KB on Linux, smaller on macOS/Windows) — the
  # child blocks on write() to whichever stream isn't being read yet, so it
  # never reaches EOF on the stream that IS being read either. 200KB on
  # each stream comfortably exceeds every platform's default pipe buffer.
  # `printf '%*s' N '' | tr ' ' 'X'` (not `yes X | head -c N`) generates
  # exactly N bytes: `yes | head -c` doesn't reliably stop `yes` under
  # MSYS2/Windows bash (SIGPIPE from `head` closing its read end isn't
  # delivered the same way), so `yes` keeps writing well past N bytes —
  # confirmed directly on Windows (600KB+ and still growing).
  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    cmds = list(
      c("echo", "start"),
      c(
        "bash",
        "-c",
        paste(
          "printf '%*s' 200000 '' | tr ' ' 'A';",
          "printf '%*s' 200000 '' | tr ' ' 'B' 1>&2"
        )
      )
    ),
    env_name = "run-pipeline-cli-tools-env"
  )
  last <- res$processes[[2]]
  testthat::expect_equal(nchar(last$stdout), 200000L)
  testthat::expect_equal(nchar(last$stderr), 200000L)
})

test_that("Pipeline does not deadlock on a large stderr from a non-last command", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    cmds = list(
      c("bash", "-c", "echo hi; printf '%*s' 200000 '' | tr ' ' 'B' 1>&2"),
      c("cat")
    ),
    env_name = "run-pipeline-cli-tools-env"
  )
  testthat::expect_equal(nchar(res$processes[[1]]$stderr), 200000L)
  testthat::expect_match(trimws(res$processes[[2]]$stdout), "hi")
})

test_that("Pipeline stdin = '|' does not truncate large input to the first command", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  # Regression test: writing `input` once and closing immediately silently
  # truncates it past the OS pipe buffer (confirmed empirically: only 8192
  # of 200000 bytes delivered on macOS, no error). `wc -c` independently
  # counts exactly how many bytes the first command actually received on
  # its stdin, isolating this from any read-side accounting.
  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    cmds = list(
      c("wc", "-c"),
      c("cat")
    ),
    stdin = "|",
    input = strrep("A", 200000),
    env_name = "run-pipeline-cli-tools-env"
  )
  testthat::expect_equal(trimws(res$processes[[2]]$stdout), "200000")
})

test_that("Pipeline supports per-command stderr override to a file", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  errfile <- withr::local_tempfile()
  res <- run_pipeline(
    cmds = list(
      list(cmd = c("bash", "-c", "echo to-file-err >&2"), stderr = errfile),
      c("cat")
    ),
    env_name = "run-pipeline-cli-tools-env",
    error = "continue"
  )
  testthat::expect_equal(res$processes[[1]]$stderr, "")
  testthat::expect_match(readLines(errfile), "to-file-err", all = FALSE)
})

test_that("Pipeline supports per-command stdout override on the last command", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  outfile <- withr::local_tempfile()
  res <- run_pipeline(
    cmds = list(
      c("echo", "to a file"),
      list(cmd = c("cat"), stdout = outfile)
    ),
    env_name = "run-pipeline-cli-tools-env",
    error = "continue"
  )
  testthat::expect_true(is.na(res$processes[[2]]$stdout))
  testthat::expect_match(readLines(outfile), "to a file", all = FALSE)
})

test_that("Pipeline runs commands across two different Conda environments", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  is_windows <- isTRUE(stringr::str_detect(get_sys_arch(), "^Windows"))
  grep_pkg <- if (is_windows) "conda-forge::m2-grep" else "conda-forge::grep"
  sed_pkg <- if (is_windows) "conda-forge::m2-sed" else "conda-forge::sed"

  create_env(
    grep_pkg,
    env_name = "pipeline-grep-env",
    verbose = "silent"
  )
  create_env(
    sed_pkg,
    env_name = "pipeline-sed-env",
    verbose = "silent"
  )

  tmpfile <- withr::local_tempfile(
    lines = c("apple", "banana", "cherry", "dog")
  )
  res <- run_pipeline(
    cmds = list(
      list(cmd = c("grep", "-i", "a"), env_name = "pipeline-grep-env"),
      list(cmd = c("sed", "s/a/A/g"), env_name = "pipeline-sed-env")
    ),
    stdin = tmpfile,
    error = "continue"
  )
  testthat::expect_equal(res$statuses, c(0L, 0L))
  testthat::expect_equal(res$processes[[1]]$env_name, "pipeline-grep-env")
  testthat::expect_equal(res$processes[[2]]$env_name, "pipeline-sed-env")
  last_stdout <- res$processes[[2]]$stdout
  testthat::expect_match(last_stdout, "Apple")
  testthat::expect_match(last_stdout, "bAnAnA")
})

test_that("Pipeline format and print methods work", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    cmds = list(
      c("echo", "test"),
      c("cat")
    ),
    env_name = "run-pipeline-cli-tools-env",
    error = "continue"
  )
  formatted <- format(res)
  testthat::expect_type(formatted, "character")
  testthat::expect_match(formatted, "condathis_pipeline")
})

test_that("Pipeline accepts overridden crash-safety parameters", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    cmds = list(
      c("echo", "hi"),
      c("cat")
    ),
    env_name = "run-pipeline-cli-tools-env",
    supervise = FALSE,
    cleanup_tree = FALSE,
    linux_pdeathsig = TRUE,
    error = "continue"
  )
  testthat::expect_equal(res$statuses, c(0L, 0L))
})

test_that("Pipeline with activate = TRUE resolves real micromamba activation", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    cmds = list(
      c("printenv", "CONDA_PREFIX"),
      c("cat")
    ),
    env_name = "run-pipeline-cli-tools-env",
    activate = TRUE,
    error = "continue"
  )
  testthat::expect_equal(res$statuses, c(0L, 0L))
  testthat::expect_match(
    trimws(res$processes[[2]]$stdout),
    "run-pipeline-cli-tools-env",
    fixed = TRUE
  )
})

test_that("Pipeline with activate = FALSE uses the hand-rolled activation", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    cmds = list(
      c("printenv", "CONDA_PREFIX"),
      c("cat")
    ),
    env_name = "run-pipeline-cli-tools-env",
    activate = FALSE,
    error = "continue"
  )
  testthat::expect_equal(res$statuses, c(0L, 0L))
  testthat::expect_match(
    trimws(res$processes[[2]]$stdout),
    "run-pipeline-cli-tools-env",
    fixed = TRUE
  )
})
