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

  create_env(verbose = "silent")
  res <- run_pipeline(
    cmds = list(
      c("echo", "hello world"),
      c("tr", "[:lower:]", "[:upper:]")
    ),
    env_name = "condathis-env",
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

  create_env(verbose = "silent")
  res <- run_pipeline(
    cmds = list(
      c("echo", "hello"),
      c("cat")
    ),
    env_name = "condathis-env",
    error = "continue"
  )
  testthat::expect_type(res$processes[[1]]$stderr, "character")
  testthat::expect_type(res$processes[[2]]$stderr, "character")
})

test_that("Pipeline with error = cancel throws on failure", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(verbose = "silent")
  testthat::expect_error(
    object = {
      run_pipeline(
        cmds = list(
          c("false"),
          c("echo", "never reached")
        ),
        env_name = "condathis-env",
        error = "cancel"
      )
    },
    class = "condathis_pipeline_status_error"
  )
})

test_that("Pipeline with error = continue does not throw on failure", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(verbose = "silent")
  res <- run_pipeline(
    cmds = list(
      c("false"),
      c("echo", "still runs")
    ),
    env_name = "condathis-env",
    error = "continue"
  )
  testthat::expect_s3_class(res, "condathis_pipeline")
  testthat::expect_equal(res$statuses[[1]], 1L)
})

test_that("Pipeline with missing command and error = continue returns a result", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(verbose = "silent")
  res <- run_pipeline(
    cmds = list(
      c("this-cmd-does-not-exist-xyz"),
      c("cat")
    ),
    env_name = "condathis-env",
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

  create_env(verbose = "silent")
  cnd <- testthat::expect_error(
    object = run_pipeline(
      cmds = list(
        c("this-cmd-does-not-exist-xyz"),
        c("cat")
      ),
      env_name = "condathis-env",
      error = "cancel"
    ),
    class = "condathis_pipeline_status_error"
  )
  testthat::expect_match(conditionMessage(cnd), "not found")
})

test_that("Pipeline error message escapes curly braces in stderr", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(verbose = "silent")
  cnd <- testthat::expect_error(
    object = run_pipeline(
      cmds = list(
        c("sh", "-c", "echo 'boom {curly} }brace{' >&2; exit 1"),
        c("cat")
      ),
      env_name = "condathis-env",
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

  create_env(verbose = "silent")
  tmpfile <- withr::local_tempfile(lines = c("b", "a", "c", "a", "b"))
  res <- run_pipeline(
    cmds = list(
      c("sort"),
      c("uniq")
    ),
    stdin = tmpfile,
    env_name = "condathis-env",
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

  create_env(verbose = "silent")
  res <- run_pipeline(
    cmds = list(
      c("echo", "hello"),
      c("cat")
    ),
    env_name = "condathis-env",
    error = "continue"
  )
  testthat::expect_true(is.na(res$processes[[1]]$stdout))
  testthat::expect_false(is.na(res$processes[[2]]$stdout))
})

test_that("Pipeline supports three chained commands", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(verbose = "silent")
  res <- run_pipeline(
    cmds = list(
      c("echo", "hello world"),
      c("tr", "[:lower:]", "[:upper:]"),
      c("rev")
    ),
    env_name = "condathis-env",
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

  create_env(verbose = "silent")
  res <- run_pipeline(
    cmds = list(
      list(cmd = c("echo", "named spec"), env_name = "condathis-env"),
      list(cmd = c("cat"), env_name = "condathis-env")
    ),
    error = "continue"
  )
  testthat::expect_s3_class(res, "condathis_pipeline")
  testthat::expect_match(res$processes[[2]]$stdout, "named spec")
})

test_that("Pipeline reports a positive integer pid per process", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(verbose = "silent")
  res <- run_pipeline(
    cmds = list(
      c("echo", "hello"),
      c("cat")
    ),
    env_name = "condathis-env",
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

  create_env(verbose = "silent")
  res <- run_pipeline(
    cmds = list(
      c("echo", "hello"),
      c("cat")
    ),
    env_name = "condathis-env",
    error = "continue"
  )
  testthat::expect_type(res$timeout, "logical")
  testthat::expect_false(res$timeout)
})

test_that("Pipeline stdin = '|' writes input to the first process", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(verbose = "silent")
  res <- run_pipeline(
    cmds = list(
      c("sort"),
      c("uniq")
    ),
    stdin = "|",
    input = "b\na\nc\na\nb\n",
    env_name = "condathis-env",
    error = "continue"
  )
  last_stdout <- res$processes[[2]]$stdout
  sorted_unique <- strsplit(trimws(last_stdout), "\n")[[1]]
  testthat::expect_equal(sorted_unique, c("a", "b", "c"))
})

test_that("Pipeline stdin = '|' with no input closes cleanly", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(verbose = "silent")
  res <- run_pipeline(
    cmds = list(
      c("cat"),
      c("cat")
    ),
    stdin = "|",
    env_name = "condathis-env",
    error = "continue"
  )
  testthat::expect_equal(res$statuses, c(0L, 0L))
  testthat::expect_equal(res$processes[[2]]$stdout, "")
})

test_that("Pipeline supports per-command stderr override to a file", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(verbose = "silent")
  errfile <- withr::local_tempfile()
  res <- run_pipeline(
    cmds = list(
      list(cmd = c("sh", "-c", "echo to-file-err >&2"), stderr = errfile),
      c("cat")
    ),
    env_name = "condathis-env",
    error = "continue"
  )
  testthat::expect_equal(res$processes[[1]]$stderr, "")
  testthat::expect_match(readLines(errfile), "to-file-err", all = FALSE)
})

test_that("Pipeline supports per-command stdout override on the last command", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(verbose = "silent")
  outfile <- withr::local_tempfile()
  res <- run_pipeline(
    cmds = list(
      c("echo", "to a file"),
      list(cmd = c("cat"), stdout = outfile)
    ),
    env_name = "condathis-env",
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

  create_env(verbose = "silent")
  res <- run_pipeline(
    cmds = list(
      c("echo", "test"),
      c("cat")
    ),
    env_name = "condathis-env",
    error = "continue"
  )
  formatted <- format(res)
  testthat::expect_type(formatted, "character")
  testthat::expect_match(formatted, "condathis_pipeline")
})

test_that("Pipeline accepts overridden crash-safety parameters", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(verbose = "silent")
  res <- run_pipeline(
    cmds = list(
      c("echo", "hi"),
      c("cat")
    ),
    env_name = "condathis-env",
    supervise = FALSE,
    cleanup_tree = FALSE,
    linux_pdeathsig = TRUE,
    error = "continue"
  )
  testthat::expect_equal(res$statuses, c(0L, 0L))
})
