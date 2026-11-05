pipeline_cli_pkgs <- function() {
  c(test_os_pkg("coreutils"), test_os_pkg("bash"), test_os_pkg("util-linux"))
}

test_that("Pipeline rejects an unnamed value that is not a run_step()", {
  # A bare command vector, as in the removed list-of-commands API.
  testthat::expect_error(
    object = run_pipeline(c("echo", "hello"), run_step("cat")),
    class = "condathis_pipeline_invalid_step"
  )
  # The removed API itself: one list holding every command.
  testthat::expect_error(
    object = run_pipeline(list(c("echo", "hello"), c("cat"))),
    class = "condathis_pipeline_invalid_step"
  )
  # The message names the position of the offending value, also when the
  # steps are spliced in.
  cnd <- testthat::expect_error(
    object = run_pipeline(!!!list(run_step("echo", "hello"), "cat")),
    class = "condathis_pipeline_invalid_step"
  )
  testthat::expect_match(conditionMessage(cnd), "Argument 2", fixed = TRUE)
})

test_that("Pipeline rejects a named value that is not a run_step()", {
  # A misspelled option is collected by `...` and must not be ignored.
  cnd <- testthat::expect_error(
    object = run_pipeline(
      run_step("echo", "hello"),
      run_step("cat"),
      eror = "continue"
    ),
    class = "condathis_pipeline_invalid_step"
  )
  testthat::expect_match(conditionMessage(cnd), "eror", fixed = TRUE)
})

test_that("Pipeline rejects zero steps", {
  testthat::expect_error(
    object = run_pipeline(),
    class = "condathis_pipeline_too_few_commands"
  )
  testthat::expect_error(
    object = run_pipeline(!!!list()),
    class = "condathis_pipeline_too_few_commands"
  )
})

test_that("Pipeline rejects a single step", {
  testthat::expect_error(
    object = run_pipeline(run_step("echo", "hello")),
    class = "condathis_pipeline_too_few_commands"
  )
})

test_that("Pipeline rejects an invalid default env_name", {
  testthat::expect_error(
    object = run_pipeline(
      run_step("echo", "hello"),
      run_step("cat"),
      env_name = c("env-a", "env-b")
    ),
    class = "condathis_pipeline_invalid_env_name"
  )
  testthat::expect_error(
    object = run_pipeline(
      run_step("echo", "hello"),
      run_step("cat"),
      env_name = "../outside"
    ),
    class = "condathis_pipeline_invalid_env_name"
  )
})

test_that("run_step() rejects an invalid cmd", {
  testthat::expect_error(
    object = run_step(1:3),
    class = "condathis_run_step_invalid_cmd"
  )
  # `cmd` is one command; its arguments go in `...`.
  testthat::expect_error(
    object = run_step(c("echo", "hello")),
    class = "condathis_run_step_invalid_cmd"
  )
  testthat::expect_error(
    object = run_step(character(0L)),
    class = "condathis_run_step_invalid_cmd"
  )
  testthat::expect_error(
    object = run_step(""),
    class = "condathis_run_step_invalid_cmd"
  )
  testthat::expect_error(
    object = run_step(NA_character_),
    class = "condathis_run_step_invalid_cmd"
  )
  testthat::expect_error(
    object = run_step(NULL),
    class = "condathis_run_step_invalid_cmd"
  )
})

test_that("run_step() requires cmd", {
  testthat::expect_error(
    object = run_step(env_name = "condathis-env"),
    regexp = "cmd"
  )
})

test_that("run_step() rejects invalid command arguments", {
  testthat::expect_error(
    object = run_step("echo", list("a")),
    class = "condathis_run_step_invalid_args"
  )
  testthat::expect_error(
    object = run_step("echo", "a", NA),
    class = "condathis_run_step_invalid_args"
  )
  testthat::expect_error(
    object = run_step("echo", NA_character_),
    class = "condathis_run_step_invalid_args"
  )
})

test_that("run_step() stores arguments as a character vector", {
  step <- run_step("head", "-n", 1)
  testthat::expect_s3_class(step, "condathis_run_step")
  testthat::expect_identical(step$cmd, "head")
  testthat::expect_identical(step$args, c("-n", "1"))
  testthat::expect_identical(run_step("cat")$args, character(0L))
})

test_that("run_step() has no per-step stdout", {
  # Replaces the removed per-command `stdout` override: only the last
  # command's stdout can be redirected, with `run_pipeline(stdout = )`.
  testthat::expect_error(
    object = run_step("echo", "hello", stdout = "somefile"),
    class = "condathis_run_step_invalid_args"
  )
})

test_that("run_step() rejects an invalid env_name", {
  testthat::expect_error(
    object = run_step("cat", env_name = c("env-a", "env-b")),
    class = "condathis_run_step_invalid_env_name"
  )
  testthat::expect_error(
    object = run_step("cat", env_name = NA_character_),
    class = "condathis_run_step_invalid_env_name"
  )
  testthat::expect_error(
    object = run_step("cat", env_name = "../outside"),
    class = "condathis_run_step_invalid_env_name"
  )
  testthat::expect_error(
    object = run_step("cat", env_name = 1L),
    class = "condathis_run_step_invalid_env_name"
  )
  # No env_name means the env_name of run_pipeline().
  testthat::expect_null(run_step("cat")$env_name)
})

test_that("run_step() rejects an invalid method", {
  testthat::expect_error(
    object = run_step("cat", method = 1L),
    class = "condathis_run_step_invalid_method"
  )
  testthat::expect_error(
    object = run_step("cat", method = c("auto", "micromamba")),
    class = "condathis_run_step_invalid_method"
  )
  testthat::expect_error(
    object = run_step("cat", method = NA_character_),
    class = "condathis_run_step_invalid_method"
  )
  testthat::expect_null(run_step("cat")$method)
})

test_that("run_step() rejects an invalid stderr", {
  testthat::expect_error(
    object = run_step("cat", stderr = 1L),
    class = "condathis_run_step_invalid_stderr"
  )
  testthat::expect_error(
    object = run_step("cat", stderr = c("a.txt", "b.txt")),
    class = "condathis_run_step_invalid_stderr"
  )
  testthat::expect_error(
    object = run_step("cat", stderr = NA_character_),
    class = "condathis_run_step_invalid_stderr"
  )
})

test_that("run_step() tells an explicit stderr = NULL from a missing one", {
  unset <- run_step("cat")
  testthat::expect_false(unset$stderr_set)

  discard <- run_step("cat", stderr = NULL)
  testthat::expect_true(discard$stderr_set)
  testthat::expect_null(discard$stderr)

  to_file <- run_step("cat", stderr = "err.txt")
  testthat::expect_true(to_file$stderr_set)
  testthat::expect_identical(to_file$stderr, "err.txt")
})

test_that("Pipeline rejects non-existent environment", {
  testthat::expect_error(
    object = run_pipeline(
      run_step("echo", "hello"),
      run_step("cat"),
      env_name = "non-existent-env",
      verbose = "silent"
    ),
    class = "condathis_pipeline_env_not_found"
  )
})

test_that("Pipeline rejects conflicting per-command methods for a shared env_name", {
  # Every command sharing an env_name must resolve to the same backend, so
  # two different explicit `method`s for the same env_name is a
  # self-contradictory spec that must fail fast, regardless of `error`.
  testthat::expect_error(
    object = run_pipeline(
      run_step(
        "echo",
        "hello",
        env_name = "shared-conflicting-env",
        method = "micromamba"
      ),
      run_step(
        "cat",
        env_name = "shared-conflicting-env",
        method = "some-other-backend"
      ),
      verbose = "silent"
    ),
    class = "condathis_pipeline_conflicting_method"
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
    run_step("echo", "hello world"),
    run_step("tr", "[:lower:]", "[:upper:]"),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_s3_class(res, "condathis_pipeline")
  testthat::expect_length(res$statuses, 2L)
  testthat::expect_type(res$statuses, "integer")
  testthat::expect_length(res$processes, 2L)

  # Steps without their own env_name inherit run_pipeline(env_name = ).
  for (p in res$processes) {
    testthat::expect_identical(p$env_name, "run-pipeline-cli-tools-env")
  }

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
    run_step("echo", "hello"),
    run_step("cat"),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
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
        run_step("false"),
        run_step("echo", "never reached"),
        env_name = "run-pipeline-cli-tools-env",
        verbose = "silent",
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
    run_step("false"),
    run_step("echo", "still runs"),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_s3_class(res, "condathis_pipeline")
  testthat::expect_equal(res$statuses[[1]], 1L)
  # `false | echo`: the first failure is the status of the pipeline.
  testthat::expect_identical(res$status, 1L)
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
    run_step("this-cmd-does-not-exist-xyz"),
    run_step("cat"),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
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
      run_step("this-cmd-does-not-exist-xyz"),
      run_step("cat"),
      env_name = "run-pipeline-cli-tools-env",
      verbose = "silent",
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
      run_step("bash", "-c", "echo 'boom {curly} }brace{' >&2; exit 1"),
      run_step("cat"),
      env_name = "run-pipeline-cli-tools-env",
      verbose = "silent",
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
    run_step("echo", "hi"),
    run_step("cat"),
    env_name = "totally-custom-missing-env",
    verbose = "silent",
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
  cnd <- testthat::expect_error(
    object = run_pipeline(
      run_step("echo", "hi"),
      run_step("cat"),
      env_name = "totally-custom-missing-env",
      verbose = "silent",
      error = "cancel"
    ),
    class = "condathis_pipeline_env_not_found"
  )
  # The new name and the shared class.
  testthat::expect_s3_class(cnd, "condathis_run_pipeline_env_not_found")
  testthat::expect_s3_class(cnd, "condathis_env_not_found")
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
    run_step("sort"),
    run_step("uniq"),
    stdin = tmpfile,
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_s3_class(res, "condathis_pipeline")
  last_stdout <- res$processes[[2]]$stdout
  sorted_unique <- strsplit(trimws(last_stdout), "\n")[[1]]
  testthat::expect_equal(sorted_unique, c("a", "b", "c"))
})

test_that("Pipeline rejects input without stdin = '|'", {
  testthat::expect_error(
    object = run_pipeline(
      run_step("echo", "hello"),
      run_step("cat"),
      input = "hello",
      verbose = "silent"
    ),
    class = "condathis_pipeline_invalid_input"
  )
})

test_that("Pipeline auto-creates the default environment when missing", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  res <- run_pipeline(
    run_step("echo", "auto created"),
    run_step("cat"),
    verbose = "silent",
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
    run_step("echo", "hello"),
    run_step("cat"),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
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
    run_step("echo", "hello world"),
    run_step("tr", "[:lower:]", "[:upper:]"),
    run_step("rev"),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_length(res$statuses, 3L)
  testthat::expect_length(res$processes, 3L)
  last_stdout <- res$processes[[3]]$stdout
  testthat::expect_match(last_stdout, "DLROW OLLEH")
})

test_that("Pipeline accepts steps spliced in with !!!", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  steps <- list(
    run_step("echo", "hello world"),
    run_step("tr", "[:lower:]", "[:upper:]")
  )
  steps <- c(steps, list(run_step("rev")))
  res <- run_pipeline(
    !!!steps,
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_length(res$statuses, 3L)
  testthat::expect_match(res$processes[[3]]$stdout, "DLROW OLLEH")
})

test_that("Pipeline steps can each set their own env_name", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    run_step("echo", "named spec", env_name = "run-pipeline-cli-tools-env"),
    run_step("cat", env_name = "run-pipeline-cli-tools-env"),
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_s3_class(res, "condathis_pipeline")
  testthat::expect_match(res$processes[[2]]$stdout, "named spec")
  for (p in res$processes) {
    testthat::expect_identical(p$env_name, "run-pipeline-cli-tools-env")
  }
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
    run_step("echo", "hello"),
    run_step("cat"),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
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
    run_step("echo", "hello"),
    run_step("cat"),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_type(res$timeout, "logical")
  testthat::expect_false(res$timeout)
})

test_that("Pipeline respects timeout under error = continue", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    run_step("sleep", "5"),
    run_step("cat"),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
    error = "continue",
    timeout = 1
  )
  testthat::expect_true(res$timeout)
  testthat::expect_equal(res$statuses[1], -9L)
  testthat::expect_true(res$processes[[1]]$timeout)
  # The status of the whole pipeline, as for a timeout of run().
  testthat::expect_identical(res$status, -9L)
})

test_that("Pipeline respects timeout under error = cancel", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  cnd_res <- rlang::catch_cnd(
    expr = {
      run_pipeline(
        run_step("sleep", "5"),
        run_step("cat"),
        env_name = "run-pipeline-cli-tools-env",
        verbose = "silent",
        error = "cancel",
        timeout = 1
      )
    }
  )
  testthat::expect_s3_class(cnd_res, "condathis_pipeline_timeout_error")
  testthat::expect_s3_class(cnd_res, "condathis_run_pipeline_timeout_error")
  testthat::expect_s3_class(cnd_res, "condathis_timeout_error")
  testthat::expect_identical(cnd_res$status, -9L)
})

test_that("Pipeline does not deadlock when data volume exceeds pipe buffers across stages", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  # Regression test: the previous sequential per-stage draining left the
  # last stage's stdout-to-R pipe unread while waiting for stage 1's
  # stderr EOF; once the flowing data exceeded the OS pipe buffer (~64KB)
  # the whole pipeline froze on backpressure, permanently - reproduced
  # with exactly this workload. `timeout` is a safety net so a regression
  # fails the test instead of hanging CI: the (also fixed) deadline
  # enforcement kills the pipeline and the status assertions fail.
  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    run_step("seq", "1", "200000"),
    run_step("cat"),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
    error = "continue",
    timeout = 120
  )
  testthat::expect_false(res$timeout)
  testthat::expect_equal(res$statuses, c(0L, 0L))
  n_lines <- length(strsplit(trimws(res$processes[[2]]$stdout), "\n")[[1]])
  testthat::expect_equal(n_lines, 200000L)

  # Same, through an extra relay stage (multi-hop backpressure).
  res3 <- run_pipeline(
    run_step("seq", "1", "200000"),
    run_step("cat"),
    run_step("cat"),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
    error = "continue",
    timeout = 120
  )
  testthat::expect_false(res3$timeout)
  testthat::expect_equal(res3$statuses, c(0L, 0L, 0L))
  n_lines3 <- length(strsplit(trimws(res3$processes[[3]]$stdout), "\n")[[1]])
  testthat::expect_equal(n_lines3, 200000L)
})

test_that("Pipeline timeout is enforced for stages with no R-side streams", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  # Regression test: with `stderr = NULL` a non-last stage has no R-side
  # pipes at all, so the stream pump cannot observe it; the per-stage
  # settle used a bare `wait()`, which blocked until the child exited on
  # its own - silently disabling `timeout` (measured: a 1-second deadline
  # waiting out the full sleep). Only stage 1's status is asserted:
  # whether the downstream stage exits 0 (EOF after the kill) or is
  # killed itself is a timing race that differs across platforms.
  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  t_start <- Sys.time()
  res <- run_pipeline(
    run_step("sleep", "30"),
    run_step("cat"),
    stderr = NULL,
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
    error = "continue",
    timeout = 2
  )
  elapsed <- as.numeric(Sys.time() - t_start, units = "secs")
  testthat::expect_true(res$timeout)
  testthat::expect_equal(res$statuses[1], -9L)
  testthat::expect_true(res$processes[[1]]$timeout)
  testthat::expect_lt(elapsed, 20)
})

test_that("Pipeline preserves output a killed downstream stage already produced", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  # Regression test: an earlier draft killed every process in the pipeline
  # as soon as the first stage timed out, discarding output later stages
  # had already produced but not yet drained - `processx` invalidates a
  # process's own connection immediately on `kill()`, so anything unread at
  # that point is lost for good, confirmed empirically.
  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  # `timeout = 5` (not 1): the deadline clock starts at run_pipeline()
  # entry, before backend resolution and spawning, and every stream is
  # cut at the deadline - so the budget must comfortably cover
  # spawn + `echo` on a slow, loaded runner, while staying far below the
  # sleep so the kill is still what ends the pipeline.
  res <- run_pipeline(
    run_step("bash", "-c", "echo hello; sleep 30"),
    run_step("cat"),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
    error = "continue",
    timeout = 5
  )
  testthat::expect_true(res$timeout)
  testthat::expect_match(res$processes[[2]]$stdout, "hello")
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
    run_step("sort"),
    run_step("uniq"),
    stdin = "|",
    input = "b\na\nc\na\nb\n",
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
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
    run_step("cat"),
    run_step("cat"),
    stdin = "|",
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
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
    run_step("cat", tmp_file),
    run_step("cat"),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
    binary = TRUE
  )
  last_stdout <- res$processes[[2]]$stdout
  testthat::expect_type(last_stdout, "raw")
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
    run_step("echo", "hi"),
    run_step("cat"),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  testthat::expect_type(res$processes[[2]]$stdout, "character")
})

test_that("Pipeline rejects non-logical binary argument", {
  testthat::expect_error(
    object = run_pipeline(
      run_step("echo", "hi"),
      run_step("cat"),
      binary = "yes",
      verbose = "silent"
    ),
    class = "condathis_pipeline_invalid_binary_arg"
  )
})

test_that("Pipeline does not deadlock when the last command's stdout and stderr are both large", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  # Regression test: draining stdout and stderr sequentially (or calling
  # wait() before draining either) deadlocks once combined output exceeds
  # the OS pipe buffer (64KB on Linux, smaller on macOS/Windows) - the
  # child blocks on write() to whichever stream isn't being read yet, so it
  # never reaches EOF on the stream that IS being read either. 200KB on
  # each stream comfortably exceeds every platform's default pipe buffer.
  # `printf '%*s' N '' | tr ' ' 'X'` (not `yes X | head -c N`) generates
  # exactly N bytes: `yes | head -c` doesn't reliably stop `yes` under
  # MSYS2/Windows bash (SIGPIPE from `head` closing its read end isn't
  # delivered the same way), so `yes` keeps writing well past N bytes -
  # confirmed directly on Windows (600KB+ and still growing).
  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    run_step("echo", "start"),
    run_step(
      "bash",
      "-c",
      paste(
        "printf '%*s' 200000 '' | tr ' ' 'A';",
        "printf '%*s' 200000 '' | tr ' ' 'B' 1>&2"
      )
    ),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
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
    run_step(
      "bash",
      "-c",
      "echo hi; printf '%*s' 200000 '' | tr ' ' 'B' 1>&2"
    ),
    run_step("cat"),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
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
    run_step("wc", "-c"),
    run_step("cat"),
    stdin = "|",
    input = strrep("A", 200000),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
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
    run_step("bash", "-c", "echo to-file-err >&2", stderr = errfile),
    run_step("cat"),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
    error = "continue"
  )
  # Not captured: NA, as in a run() result.
  testthat::expect_identical(res$processes[[1]]$stderr, NA_character_)
  testthat::expect_identical(res$processes[[2]]$stderr, "")
  testthat::expect_match(readLines(errfile), "to-file-err", all = FALSE)
})

test_that("parse_output() reports pipeline stderr that was not captured", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  # Regression test: an uncaptured stage stderr was "", so
  # parse_output(stream = "stderr") returned character(0) instead of
  # erroring as it does for a run() result.
  create_polyglot_env("run-pipeline-no-stderr-env")
  res <- run_pipeline(
    run_step("polyglot"),
    run_step("polyglot"),
    env_name = "run-pipeline-no-stderr-env",
    stderr = NULL,
    verbose = "silent"
  )
  testthat::expect_identical(
    vapply(res$processes, `[[`, character(1L), "stderr"),
    c(NA_character_, NA_character_)
  )
  testthat::expect_error(
    parse_output(res, stream = "stderr"),
    class = "condathis_parse_output_invalid_res"
  )
  testthat::expect_identical(parse_output(res)[[1L]], polyglot_expected_line())
})

test_that("Pipeline stdout file target redirects the last command", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  outfile <- withr::local_tempfile()
  res <- run_pipeline(
    run_step("echo", "to a file"),
    run_step("cat"),
    stdout = outfile,
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
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
    run_step("grep", "-i", "a", env_name = "pipeline-grep-env"),
    run_step("sed", "s/a/A/g", env_name = "pipeline-sed-env"),
    stdin = tmpfile,
    verbose = "silent",
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
    run_step("echo", "test"),
    run_step("cat"),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
    error = "continue"
  )
  formatted <- format(res)
  testthat::expect_type(formatted, "character")
  testthat::expect_match(formatted, "condathis_pipeline")
  testthat::expect_match(formatted, "status: OK", fixed = TRUE)
})

test_that("Pipeline per-process entries are condathis_result objects", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    run_step("echo", "test"),
    run_step("cat"),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
    error = "continue"
  )
  for (p in res$processes) {
    testthat::expect_s3_class(p, "condathis_result")
    testthat::expect_false(p$timeout)
  }

  # format()/print() work directly on an individual stage, not just on the
  # whole pipeline result.
  formatted <- format(res$processes[[1]])
  testthat::expect_type(formatted, "character")
  testthat::expect_match(formatted, "condathis_result")
})

test_that("Pipeline accepts overridden crash-safety parameters", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  # `linux_pdeathsig` is ignored without a warning on platforms other than
  # Linux.
  testthat::expect_no_warning(
    res <- run_pipeline(
      run_step("echo", "hi"),
      run_step("cat"),
      env_name = "run-pipeline-cli-tools-env",
      verbose = "silent",
      supervise = FALSE,
      cleanup_tree = FALSE,
      linux_pdeathsig = TRUE,
      error = "continue"
    )
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
    run_step("printenv", "CONDA_PREFIX"),
    run_step("cat"),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
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
    run_step("printenv", "CONDA_PREFIX"),
    run_step("cat"),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
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

test_that("Pipeline with activate = FALSE never resolves backend activation", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  # Regression test: `activate = FALSE` still called
  # `backend_resolve_run()`, whose micromamba implementation performs the
  # full activation resolution (two subprocess spawns on a cache miss,
  # plus any activate.d failure mode) before the flag discarded the
  # result - so opting out of activation neither skipped its cost nor its
  # failure modes.
  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  testthat::local_mocked_bindings(
    backend_resolve_run = function(...) {
      cli::cli_abort(
        "backend_resolve_run() must not be called when activate = FALSE."
      )
    },
    get_micromamba_activation_envvars = function(...) {
      cli::cli_abort("activation must not be resolved when activate = FALSE.")
    }
  )
  res <- run_pipeline(
    run_step("echo", "hello"),
    run_step("cat"),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
    error = "continue",
    activate = FALSE
  )
  testthat::expect_equal(res$statuses, c(0L, 0L))
  testthat::expect_match(res$processes[[2]]$stdout, "hello")
})

test_that("Pipeline stderr file target collects every stage's stderr", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  # Regression test: the same file path used to be handed to every
  # stage's process$new(), each of which opened (and truncated) it
  # independently - so stages clobbered each other and the surviving
  # content was whichever stage wrote last, from offset 0.
  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  err_file <- withr::local_tempfile()
  res <- run_pipeline(
    run_step("bash", "-c", "echo stage-one-stderr >&2"),
    run_step("bash", "-c", "cat; echo stage-two-stderr >&2"),
    stderr = err_file,
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_equal(res$statuses, c(0L, 0L))
  err_content <- readLines(err_file)
  testthat::expect_match(err_content[[1]], "stage-one-stderr")
  testthat::expect_match(err_content[[2]], "stage-two-stderr")
})

test_that("Pipeline survives the first stage exiting before consuming input", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  # Regression test for the broken-pipe guard in pump_pipeline_io():
  # writing a large `input` into a first stage that exits immediately
  # raises a low-level broken-pipe error, which used to escape even under
  # `error = "continue"`, abandoning the still-running downstream stages.
  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    run_step("false"),
    run_step("cat"),
    stdin = "|",
    input = strrep("x", 200000L),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_s3_class(res, "condathis_pipeline")
  testthat::expect_equal(res$statuses[[1]], 1L)
})

test_that("Pipeline routes activation-resolution failures through error = continue", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  # Regression test: a failing backend_resolve_run() (activation) threw
  # outside the spawn tryCatch, aborting the whole pipeline regardless of
  # error = "continue". It must land in the spawn-failure channel like a
  # missing binary.
  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  testthat::local_mocked_bindings(
    backend_resolve_run = function(...) {
      cli::cli_abort(
        message = "Simulated activation failure.",
        class = "condathis_activation_dump_error"
      )
    }
  )
  res <- run_pipeline(
    run_step("echo", "hi"),
    run_step("cat"),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_s3_class(res, "condathis_pipeline")
  testthat::expect_equal(res$statuses, c(127L, 127L))
  testthat::expect_match(
    res$processes[[1]]$stderr,
    "Failed to resolve command"
  )
  # Under error = "cancel" an activation failure aborts with the resolve
  # class, and keeps the condathis class of the backend's error; before,
  # it became a pipeline status error.
  cnd <- testthat::expect_error(
    run_pipeline(
      run_step("echo", "hi"),
      run_step("cat"),
      env_name = "run-pipeline-cli-tools-env",
      verbose = "silent",
      error = "cancel"
    ),
    class = "condathis_run_pipeline_resolve_failed"
  )
  testthat::expect_s3_class(cnd, "condathis_activation_dump_error")
  testthat::expect_s3_class(cnd, "condathis_backend_error")
  testthat::expect_false(inherits(cnd, "condathis_status_error"))
  testthat::expect_identical(
    rlang::call_name(conditionCall(cnd)),
    "run_pipeline"
  )
})

test_that("Pipeline reaps spawned stages when an unexpected error escapes", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  # Regression test: an error thrown outside the spawn tryCatch's caught
  # classes used to leave already-spawned stages running until garbage
  # collection. The on.exit() reaper must let the error propagate while
  # killing what was spawned. (Only propagation is asserted directly;
  # process reaping is enforced by kill_processes() on exit.)
  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  call_count <- 0L
  testthat::local_mocked_bindings(
    build_child_env = function(...) {
      call_count <<- call_count + 1L
      if (call_count >= 2L) {
        stop("unexpected internal failure", call. = FALSE)
      }
      Sys.getenv()
    }
  )
  testthat::expect_error(
    run_pipeline(
      run_step("sleep", "30"),
      run_step("cat"),
      env_name = "run-pipeline-cli-tools-env",
      verbose = "silent",
      error = "continue"
    )
  )
})

test_that("an upstream SIGPIPE is not a pipeline failure", {
  # Regression tests:
  # - `seq | head` aborted with condathis_pipeline_status_error because
  #   `seq`, killed by SIGPIPE once `head` stopped reading, counted as a
  #   failed command.
  # - On Windows the same pipeline never returned: every stage inherited
  #   the read end of its own stdout pipe, so `seq` blocked forever once
  #   `head` exited. Windows now reproduces SIGPIPE, with the same status.
  testthat::skip_on_cran()
  testthat::skip_if_offline()
  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  for (stderr in list("|", NULL)) {
    res <- run_pipeline(
      run_step("seq", "1", "1000000"),
      run_step("head", "-n", "1"),
      env_name = "run-pipeline-cli-tools-env",
      verbose = "silent",
      stderr = stderr,
      timeout = 120
    )
    testthat::expect_false(res$timeout)
    testthat::expect_identical(parse_output(res), "1")
    testthat::expect_identical(res$statuses, c(-13L, 0L))
    # `seq | head`: the upstream SIGPIPE does not fail the pipeline.
    testthat::expect_identical(res$status, 0L)
  }

  # A writer that already finished when its reader exits keeps its own
  # status.
  res <- run_pipeline(
    run_step("seq", "1", "3"),
    run_step("head", "-n", "1"),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  testthat::expect_identical(res$statuses, c(0L, 0L))
})

test_that("broken_pipe_transition() ends a writer only when it writes again", {
  # Regression test: the Windows SIGPIPE emulation killed every non-last
  # stage still alive one second after its reader exited, also one that
  # never wrote to stdout again (for example a stage that keeps writing an
  # output file after `head -n 1` exited), which left a truncated file and
  # reported success. SIGPIPE only ends a writer when it writes again.
  move <- function(phase, ...) {
    broken_pipe_transition(phase = phase, ...)
  }
  # While the reader runs, nothing happens.
  testthat::expect_identical(
    move("reader", writer_alive = TRUE, reader_alive = TRUE, can_watch = TRUE),
    list(phase = "reader", action = "none")
  )
  # The reader exits: the pipe is watched, and the writer keeps running
  # however long it takes, as long as the watcher reports nothing.
  testthat::expect_identical(
    move("reader", writer_alive = TRUE, reader_alive = FALSE, can_watch = TRUE),
    list(phase = "watching", action = "watch")
  )
  testthat::expect_identical(
    move(
      "watching",
      writer_alive = TRUE,
      reader_alive = FALSE,
      can_watch = TRUE,
      watcher_status = NA_integer_,
      waited = 3600
    ),
    list(phase = "watching", action = "none")
  )
  # The writer wrote after its reader exited: it is ended.
  testthat::expect_identical(
    move(
      "watching",
      writer_alive = TRUE,
      reader_alive = FALSE,
      watcher_status = orphan_pipe_new_output_status
    ),
    list(phase = "broken", action = "kill")
  )
  # The writer closed its end: it can never write again.
  testthat::expect_identical(
    move(
      "watching",
      writer_alive = TRUE,
      reader_alive = FALSE,
      watcher_status = 0L
    ),
    list(phase = "closed", action = "none")
  )
  # A failed watcher falls back to the grace period.
  testthat::expect_identical(
    move(
      "watching",
      writer_alive = TRUE,
      reader_alive = FALSE,
      watcher_status = 1L
    ),
    list(phase = "grace", action = "none")
  )
  # Without a watcher, the grace period applies.
  testthat::expect_identical(
    move("reader", writer_alive = TRUE, reader_alive = FALSE),
    list(phase = "grace", action = "none")
  )
  testthat::expect_identical(
    move(
      "grace",
      writer_alive = TRUE,
      reader_alive = FALSE,
      waited = windows_broken_pipe_grace / 2
    ),
    list(phase = "grace", action = "none")
  )
  testthat::expect_identical(
    move(
      "grace",
      writer_alive = TRUE,
      reader_alive = FALSE,
      waited = windows_broken_pipe_grace
    ),
    list(phase = "broken", action = "kill")
  )
  # A writer that exited keeps its own status, from every phase.
  for (phase in c("reader", "watching", "grace")) {
    testthat::expect_identical(
      move(
        phase,
        writer_alive = FALSE,
        reader_alive = FALSE,
        watcher_status = orphan_pipe_new_output_status,
        waited = 3600
      ),
      list(phase = "exited", action = "none")
    )
  }
  # Final phases never change.
  for (phase in c("exited", "closed", "broken")) {
    testthat::expect_identical(
      move(
        phase,
        writer_alive = TRUE,
        reader_alive = FALSE,
        watcher_status = orphan_pipe_new_output_status,
        waited = 3600
      ),
      list(phase = phase, action = "none")
    )
  }
})

test_that("reap_windows_broken_pipes() watches a writer whose reader is gone", {
  fake_proc <- function(alive, tree_ok = TRUE) {
    env <- rlang::env(alive = alive, killed = FALSE, tree_killed = FALSE)
    env$is_alive <- function() env$alive
    env$kill <- function() {
      env$killed <- TRUE
      env$alive <- FALSE
    }
    env$kill_tree <- function() {
      if (isFALSE(tree_ok)) {
        stop("kill_tree is not supported on this platform")
      }
      env$tree_killed <- TRUE
      env$kill()
    }
    env
  }
  fake_watch <- function(start_ok = TRUE) {
    env <- rlang::env(started = integer(0L), statuses = list())
    env$start <- function(i) {
      env$started <- c(env$started, i)
      start_ok
    }
    env$status <- function(i) env$statuses[[as.character(i)]] %||% NA_integer_
    env
  }
  testthat::local_mocked_bindings(is_windows = function() TRUE)

  # a | b | c, where c has exited and a and b are still running.
  procs <- list(fake_proc(TRUE), fake_proc(TRUE), fake_proc(FALSE))
  watch <- fake_watch()
  drained <- integer(0L)
  before_kill <- function(i) drained <<- c(drained, i)
  state <- new_broken_pipe_state(3L)

  state <- reap_windows_broken_pipes(procs, state, before_kill, watch, now = 0)
  testthat::expect_identical(watch$started, 2L)
  testthat::expect_identical(state$phase[1:2], c("reader", "watching"))

  # b keeps running without writing: never killed, however long.
  state <- reap_windows_broken_pipes(procs, state, before_kill, watch, now = 60)
  testthat::expect_false(procs[[2L]]$killed)
  testthat::expect_identical(state$phase[[2L]], "watching")

  # b writes again: it is killed, after its streams are drained. Its child
  # processes too: on Windows a stage is often a launcher (`Rscript.exe`,
  # a conda entry point `.exe`) whose child does the writing.
  watch$statuses[["2"]] <- orphan_pipe_new_output_status
  state <- reap_windows_broken_pipes(procs, state, before_kill, watch, now = 61)
  testthat::expect_true(procs[[2L]]$killed)
  testthat::expect_true(procs[[2L]]$tree_killed)
  testthat::expect_identical(state$killed, c(FALSE, TRUE, FALSE))
  testthat::expect_identical(drained, 2L)

  # Then a has no reader either, and is watched in turn.
  state <- reap_windows_broken_pipes(procs, state, before_kill, watch, now = 62)
  testthat::expect_identical(watch$started, c(2L, 1L))
  testthat::expect_false(procs[[1L]]$killed)

  # a closes its end (it exits soon after): never killed.
  watch$statuses[["1"]] <- 0L
  state <- reap_windows_broken_pipes(procs, state, before_kill, watch, now = 63)
  testthat::expect_identical(state$phase[[1L]], "closed")
  state <- reap_windows_broken_pipes(procs, state, before_kill, watch, now = 99)
  testthat::expect_false(procs[[1L]]$killed)
  testthat::expect_identical(state$killed, c(FALSE, TRUE, FALSE))

  # A reader that never started counts as gone.
  watch <- fake_watch()
  state <- reap_windows_broken_pipes(
    list(fake_proc(TRUE), NULL),
    new_broken_pipe_state(2L),
    watch = watch,
    now = 0
  )
  testthat::expect_identical(watch$started, 1L)

  # When `kill_tree()` fails, `kill()` still ends the stage.
  procs <- list(fake_proc(TRUE, tree_ok = FALSE), fake_proc(FALSE))
  watch <- fake_watch()
  watch$statuses[["1"]] <- orphan_pipe_new_output_status
  state <- reap_windows_broken_pipes(
    procs,
    new_broken_pipe_state(2L),
    watch = watch,
    now = 0
  )
  state <- reap_windows_broken_pipes(procs, state, watch = watch, now = 1)
  testthat::expect_true(procs[[1L]]$killed)
  testthat::expect_false(procs[[1L]]$tree_killed)
  testthat::expect_true(state$killed[[1L]])

  # Without a watcher (none can start), the old grace period applies.
  procs <- list(fake_proc(TRUE), fake_proc(FALSE))
  watch <- fake_watch(start_ok = FALSE)
  state <- reap_windows_broken_pipes(
    procs,
    new_broken_pipe_state(2L),
    watch = watch,
    now = 0
  )
  testthat::expect_identical(state$phase[[1L]], "grace")
  state <- reap_windows_broken_pipes(procs, state, watch = watch, now = 0.5)
  testthat::expect_false(procs[[1L]]$killed)
  state <- reap_windows_broken_pipes(
    procs,
    state,
    watch = watch,
    now = windows_broken_pipe_grace
  )
  testthat::expect_true(procs[[1L]]$killed)
  testthat::expect_true(state$killed[[1L]])

  # Outside Windows it is a no-op.
  testthat::local_mocked_bindings(is_windows = function() FALSE)
  procs <- list(fake_proc(TRUE), fake_proc(TRUE), fake_proc(FALSE))
  testthat::expect_identical(
    reap_windows_broken_pipes(procs, new_broken_pipe_state(3L), watch = watch),
    new_broken_pipe_state(3L)
  )
})

test_that("the orphaned-pipe watcher reports only output written after the reader exited", {
  # The watcher of the Windows SIGPIPE emulation, run with a pipe the test
  # writes to, the same way on every platform. No case depends on how long
  # `Rscript` takes to start: output written before the watcher runs is
  # only more output already in the pipe.
  testthat::skip_on_cran()
  watchers <- list()
  withr::defer(
    for (watcher in watchers) {
      try(watcher$kill(), silent = TRUE)
    }
  )
  spawn <- function(...) {
    watcher <- spawn_orphan_pipe_watcher("|", ...)
    watchers[[length(watchers) + 1L]] <<- watcher
    watcher
  }
  watcher_status <- function(watcher) {
    watcher$wait(timeout = 60000)
    testthat::expect_false(watcher$is_alive())
    watcher$get_exit_status()
  }
  write_all <- function(watcher, data) {
    repeat {
      data <- watcher$write_input(data)
      if (identical(length(data), 0L) || isFALSE(watcher$is_alive())) {
        break
      }
      Sys.sleep(0.01)
    }
  }
  # Writes `data` every `period` seconds until the watcher exits, for at
  # most `limit` seconds. Returns the number of bytes written.
  write_until_exit <- function(watcher, data, period, limit = 30) {
    started <- proc.time()[["elapsed"]]
    written <- 0
    while (
      isTRUE(watcher$is_alive()) &&
        proc.time()[["elapsed"]] - started < limit
    ) {
      # The watcher can exit between the check and the write.
      tryCatch(
        {
          write_all(watcher, data)
          written <- written + length(data)
        },
        error = function(e) NULL
      )
      Sys.sleep(period)
    }
    written
  }

  # Output already in the pipe, up to the backlog allowance, then end of
  # file: the writer exited without writing again. The cases that expect
  # status 0 test the byte count alone: a long `wait` keeps a busy machine,
  # where the watcher can go without CPU time for a while, out of them.
  watcher <- spawn(backlog = 1000L, wait = 60)
  write_all(watcher, as.raw(rep(0x1aL, 1000L)))
  close(watcher$get_input_connection())
  testthat::expect_identical(watcher_status(watcher), 0L)

  # Nothing at all, then end of file.
  watcher <- spawn(backlog = 1000L)
  close(watcher$get_input_connection())
  testthat::expect_identical(watcher_status(watcher), 0L)

  # More than the allowance: a writer that keeps writing (`seq 1 1e9`).
  # `0x1A` ends a text-mode read on Windows: the watcher reads in binary
  # mode, so it sees every byte.
  watcher <- spawn(backlog = 1000L)
  write_all(watcher, as.raw(rep(0x1aL, 1001L)))
  testthat::expect_identical(
    watcher_status(watcher),
    orphan_pipe_new_output_status
  )

  # Regression test: the default allowance was 16 KiB, so a writer that
  # had 30 KiB of output still unread when its reader exited (blocked on a
  # Windows pipe, which holds 4 KiB) was ended although it never wrote
  # again. A Linux pipe holds 64 KiB, and that output never causes SIGPIPE.
  watcher <- spawn(wait = 60)
  write_all(watcher, as.raw(rep(0x79L, 60000L)))
  Sys.sleep(1)
  testthat::expect_true(watcher$is_alive())
  close(watcher$get_input_connection())
  testthat::expect_identical(watcher_status(watcher), 0L)

  # A little output, then more after the pipe was empty for a while: the
  # writer wrote again after its reader exited.
  watcher <- spawn()
  write_all(watcher, charToRaw("line-2\nline-3\n"))
  written <- write_until_exit(watcher, charToRaw("x"), period = 0.3)
  testthat::expect_identical(
    watcher_status(watcher),
    orphan_pipe_new_output_status
  )
  # At most 9 seconds of writing, start-up of `Rscript` included.
  testthat::expect_lt(written, 30)

  # Regression test: a byte counted as new output only after a single wait
  # of 0.25 seconds, so a writer that writes a line every 0.1 seconds, with
  # no pause, was ended only after the whole allowance (41 seconds for 40
  # bytes every 0.1 seconds). Waiting now adds up, and the writer is ended
  # long before it writes the allowance.
  watcher <- spawn()
  written <- write_until_exit(
    watcher,
    charToRaw(paste0(strrep("z", 39L), "\n")),
    period = 0.1
  )
  testthat::expect_identical(
    watcher_status(watcher),
    orphan_pipe_new_output_status
  )
  # At most 10 seconds of writing, start-up of `Rscript` included.
  testthat::expect_lt(written, 4000)
})

test_that("a killed orphaned-pipe watcher leaves its R temporary directory in the session's", {
  # Regression test: the watcher, an `Rscript` that `run_pipeline()` starts
  # on Windows, had the session's environment, which has no `TMPDIR` there,
  # so R made its temporary directory in the user's `%TEMP%`. A watcher
  # that is killed (a child of a stage keeps the pipe open) cannot remove
  # it. It is now in the session's temporary directory, which the session
  # removes when it ends. The same on every platform.
  testthat::skip_on_cran()
  r_tmp_dirs <- function() {
    return(as.character(fs::dir_ls(
      tempdir(),
      regexp = "[/\\\\]Rtmp[^/\\\\]*$",
      type = "directory"
    )))
  }
  before <- r_tmp_dirs()
  watcher <- spawn_orphan_pipe_watcher("|")
  withr::defer(try(watcher$kill(), silent = TRUE))
  # R makes its temporary directory when it starts.
  deadline <- proc.time()[["elapsed"]] + 30
  while (
    identical(length(setdiff(r_tmp_dirs(), before)), 0L) &&
      isTRUE(watcher$is_alive()) &&
      proc.time()[["elapsed"]] < deadline
  ) {
    Sys.sleep(0.05)
  }
  testthat::expect_true(watcher$is_alive())
  watcher$kill_tree()
  new_dirs <- setdiff(r_tmp_dirs(), before)
  testthat::expect_length(new_dirs, 1L)
  unlink(new_dirs, recursive = TRUE)
})

test_that("an upstream stage keeps working after its reader exits", {
  # Regression test: on Windows, a stage still alive one second after its
  # reader exited was killed even when it never wrote to stdout again, so
  # its output file was truncated and the pipeline still reported success.
  # As with SIGPIPE on Linux and macOS, the stage must finish its work.
  # Both stages are R scripts run by R's own `Rscript`, in a directory
  # that only looks like a Conda environment: no micromamba is needed.
  # The first run is native. The second forces the Windows emulation (the
  # R process keeps each pipe's read end, so SIGPIPE never fires, which
  # reproduces the Windows situation) on every platform.
  # The writer also leaves output unread in the pipe. In the emulated run
  # it is 30 KB: a regression test for an allowance of 16 KiB, which ended
  # a writer that never wrote again (a Linux pipe holds 64 KiB, so SIGPIPE
  # never fires for that output). The native run writes less, because a
  # macOS pipe can hold only 16 KiB and a writer blocked on a full pipe
  # gets SIGPIPE when its reader exits.
  testthat::skip_on_cran()
  work_dir <- withr::local_tempdir()
  fake_env <- fs::path(work_dir, "fake-env")
  fs::dir_create(fs::path(fake_env, "conda-meta"))
  writer_script <- fs::path(work_dir, "writer.R")
  reader_script <- fs::path(work_dir, "reader.R")
  writeLines(
    c(
      "args <- commandArgs(trailingOnly = TRUE)",
      "writeLines(c(\"line-1\", \"line-2\", \"line-3\"))",
      "cat(strrep(\"y\\n\", as.integer(args[[3L]])))",
      "flush(stdout())",
      "started <- proc.time()[[3L]]",
      "while (!file.exists(args[[2L]]) && proc.time()[[3L]] - started < 60) {",
      "  Sys.sleep(0.05)",
      "}",
      "for (i in 1:6) {",
      "  Sys.sleep(0.25)",
      "  cat(\"chunk\", i, \"\\n\", file = args[[1L]], append = TRUE)",
      "}",
      "cat(\"done\\n\", file = args[[1L]], append = TRUE)"
    ),
    writer_script
  )
  writeLines(
    c(
      "args <- commandArgs(trailingOnly = TRUE)",
      "con <- file(\"stdin\")",
      "open(con)",
      "writeLines(readLines(con, n = 1L))",
      "flush(stdout())",
      "invisible(file.create(args[[1L]]))"
    ),
    reader_script
  )
  rscript <- file.path(R.home("bin"), "Rscript")

  run_scenario <- function(label, unread_lines) {
    out_file <- fs::path(work_dir, paste0(label, "-out.txt"))
    marker <- fs::path(work_dir, paste0(label, "-reader-done"))
    res <- run_pipeline(
      run_step(
        rscript,
        "--vanilla",
        writer_script,
        out_file,
        marker,
        unread_lines
      ),
      run_step(rscript, "--vanilla", reader_script, marker),
      env_name = env_path(fake_env),
      activate = FALSE,
      verbose = "silent",
      timeout = 120
    )
    testthat::expect_false(res$timeout, label = label)
    testthat::expect_identical(res$statuses, c(0L, 0L), label = label)
    testthat::expect_identical(parse_output(res), "line-1", label = label)
    testthat::expect_identical(
      trimws(readLines(out_file)),
      c(paste("chunk", 1:6), "done"),
      label = label
    )
  }

  run_scenario("native", unread_lines = 4000L)
  testthat::local_mocked_bindings(is_windows = function() TRUE)
  run_scenario("emulated", unread_lines = 15000L)
})

test_that("a stage that keeps writing after its reader exits is ended soon", {
  # Regression test: on Windows, output counted as new only after the
  # watcher waited 0.25 seconds for one byte, so a stage that wrote a line
  # every 0.1 seconds ran on for about 20 seconds after its reader exited.
  # On Linux and macOS, SIGPIPE ends it at its next write. The scenarios
  # are as in the test above. The writer stops on its own, with status 0,
  # 10 seconds after its reader exited: only a broken pipe ends it sooner.
  # In the emulated run, the writer ignores the error of a broken pipe. On
  # Windows it also holds the read end of its own pipe, so only the
  # emulation can end it. On Linux and macOS the pipe really breaks when
  # the watcher exits, and that error could end the writer, with status 1,
  # before the emulation does.
  testthat::skip_on_cran()
  work_dir <- withr::local_tempdir()
  fake_env <- fs::path(work_dir, "fake-env")
  fs::dir_create(fs::path(fake_env, "conda-meta"))
  writer_script <- fs::path(work_dir, "ticker.R")
  reader_script <- fs::path(work_dir, "reader.R")
  writeLines(
    c(
      "args <- commandArgs(trailingOnly = TRUE)",
      "started <- proc.time()[[3L]]",
      "reader_done <- NA",
      "while (proc.time()[[3L]] - started < 60) {",
      "  tryCatch(",
      "    {",
      "      cat(strrep(\"z\", 39L), \"\\n\", sep = \"\")",
      "      flush(stdout())",
      "    },",
      "    error = function(e) {",
      "      if (identical(args[[2L]], \"native\")) stop(e)",
      "    }",
      "  )",
      "  if (is.na(reader_done) && file.exists(args[[1L]])) {",
      "    reader_done <- proc.time()[[3L]]",
      "  }",
      "  if (!is.na(reader_done) && proc.time()[[3L]] - reader_done > 10) {",
      "    break",
      "  }",
      "  Sys.sleep(0.1)",
      "}"
    ),
    writer_script
  )
  writeLines(
    c(
      "args <- commandArgs(trailingOnly = TRUE)",
      "con <- file(\"stdin\")",
      "open(con)",
      "writeLines(readLines(con, n = 1L))",
      "flush(stdout())",
      "invisible(file.create(args[[1L]]))"
    ),
    reader_script
  )
  rscript <- file.path(R.home("bin"), "Rscript")

  run_scenario <- function(label) {
    marker <- fs::path(work_dir, paste0(label, "-reader-done"))
    started <- proc.time()[["elapsed"]]
    res <- run_pipeline(
      run_step(rscript, "--vanilla", writer_script, marker, label),
      run_step(rscript, "--vanilla", reader_script, marker),
      env_name = env_path(fake_env),
      activate = FALSE,
      verbose = "silent",
      # A native R writer ends with status 1: R turns SIGPIPE into an error.
      error = "continue",
      timeout = 120
    )
    testthat::expect_lt(proc.time()[["elapsed"]] - started, 30, label = label)
    testthat::expect_false(res$timeout, label = label)
    testthat::expect_identical(res$statuses[[2L]], 0L, label = label)
    testthat::expect_false(identical(res$statuses[[1L]], 0L), label = label)
    testthat::expect_identical(
      parse_output(res),
      strrep("z", 39L),
      label = label
    )
    res
  }

  run_scenario("native")
  testthat::local_mocked_bindings(is_windows = function() TRUE)
  res <- run_scenario("emulated")
  testthat::expect_identical(res$statuses[[1L]], broken_pipe_status)
})

test_that("pipeline input is validated and delivered in binary mode", {
  # Regression test: character input with binary = TRUE, and any input that
  # was neither character nor raw, was silently dropped as a "broken pipe".
  testthat::skip_on_cran()
  testthat::skip_if_offline()
  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    run_step("cat"),
    run_step("wc", "-c"),
    stdin = "|",
    input = "hello",
    binary = TRUE,
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  testthat::expect_identical(trimws(rawToChar(res$processes[[2]]$stdout)), "5")
  testthat::expect_error(
    run_pipeline(
      run_step("cat"),
      run_step("wc", "-c"),
      stdin = "|",
      input = 1:10,
      env_name = "run-pipeline-cli-tools-env",
      verbose = "silent"
    ),
    class = "condathis_pipeline_invalid_input"
  )
})

test_that("a pipeline timeout flags every stage that was still running", {
  # Regression test: stages were killed one at a time, so downstream stages
  # saw EOF and exited cleanly before their own check, reporting status 0
  # and timeout = FALSE although they were running at the deadline.
  testthat::skip_on_cran()
  testthat::skip_if_offline()
  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    run_step("sleep", "30"),
    run_step("cat"),
    run_step("cat"),
    timeout = 2,
    error = "continue",
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  testthat::expect_true(res$timeout)
  testthat::expect_identical(
    vapply(res$processes, function(p) p$timeout, logical(1L)),
    c(TRUE, TRUE, TRUE)
  )
  testthat::expect_identical(res$statuses, c(-9L, -9L, -9L))
})

test_that("an explicit per-command stderr = NULL discards stderr", {
  # Regression test: `spec$stderr %||% NULL` could not tell an explicit NULL
  # from "not set", so the stage fell back to the top-level target.
  testthat::skip_on_cran()
  testthat::skip_if_offline()
  create_env(
    pipeline_cli_pkgs(),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  res <- run_pipeline(
    run_step("bash", "-c", "echo noisy >&2; echo a", stderr = NULL),
    run_step("cat"),
    env_name = "run-pipeline-cli-tools-env",
    verbose = "silent"
  )
  testthat::expect_false(grepl(
    "noisy",
    res$processes[[1]]$stderr,
    fixed = TRUE
  ))
  testthat::expect_identical(parse_output(res), "a")
})

test_that("kill_processes() keeps going when a process handle fails", {
  # Regression test: on Windows `is_alive()` can fail with "The handle is
  # invalid", which aborted the cleanup of every later stage.
  killed <- character()
  fake_proc <- function(name, alive) {
    list(
      is_alive = function() {
        if (identical(alive, "error")) {
          stop("failed to get exit code (system error 6)")
        }
        alive
      },
      kill = function() killed <<- c(killed, name)
    )
  }
  testthat::expect_no_error(kill_processes(list(
    fake_proc("broken", "error"),
    NULL,
    fake_proc("done", FALSE),
    fake_proc("running", TRUE)
  )))
  testthat::expect_identical(killed, "running")
})

testthat::test_that("run_pipeline() validates its own method", {
  for (bad in list(NULL, 1, NA_character_, c("auto", "micromamba"), "nope")) {
    testthat::expect_error(
      object = run_pipeline(
        run_step("a"),
        run_step("b"),
        method = bad,
        verbose = "silent"
      ),
      class = "condathis_invalid_method_arg"
    )
  }
})

testthat::test_that("steps sharing an environment may spell micromamba as native", {
  missing_dir <- fs::path(withr::local_tempdir(), "no-such-env")
  res <- suppressWarnings(run_pipeline(
    run_step("a", method = "micromamba"),
    run_step("b", method = "native"),
    env_name = env_path(missing_dir),
    error = "continue",
    verbose = "silent"
  ))
  # Not `condathis_pipeline_conflicting_method`: both name one backend.
  testthat::expect_identical(res$statuses, c(127L, 127L))
})

testthat::test_that("a step built or edited by hand is checked again", {
  s <- run_step("echo")
  s$env_name <- "../.."
  testthat::expect_error(
    object = run_pipeline(s, run_step("cat"), verbose = "silent"),
    class = "condathis_pipeline_invalid_step"
  )

  s <- run_step("echo")
  s$args <- 1
  testthat::expect_error(
    object = run_pipeline(s, run_step("cat"), verbose = "silent"),
    class = "condathis_pipeline_invalid_step"
  )

  forged <- structure(list(cmd = "echo"), class = "condathis_run_step")
  testthat::expect_error(
    object = run_pipeline(forged, run_step("cat"), verbose = "silent"),
    class = "condathis_pipeline_invalid_step"
  )
})

testthat::test_that("the invalid-step error points at a list passed without !!! or built with c()", {
  steps <- list(run_step("a"), run_step("b"))
  cnd <- testthat::expect_error(
    object = run_pipeline(steps, run_step("c")),
    class = "condathis_pipeline_invalid_step"
  )
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "run_pipeline(!!!steps)",
    fixed = TRUE
  )

  # A list of steps built with `c()`, passed without `!!!`.
  cnd <- testthat::expect_error(
    object = run_pipeline(c(run_step("a"), run_step("b")), run_step("c")),
    class = "condathis_pipeline_invalid_step"
  )
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "run_pipeline(!!!steps)",
    fixed = TRUE
  )

  # A step field passed on its own, as `c()` with a plain list first
  # leaves a step.
  for (steps in list(
    rlang::list2(run_step("a"), cmd = "b"),
    c(list(run_step("a")), run_step("b"))
  )) {
    cnd <- testthat::expect_error(
      object = run_pipeline(!!!steps),
      class = "condathis_pipeline_invalid_step"
    )
    testthat::expect_match(
      cli::ansi_strip(conditionMessage(cnd)),
      "c(steps, list(step))",
      fixed = TRUE
    )
  }
})

testthat::test_that("c() combines steps into a list of steps", {
  combined <- c(run_step("a"), run_step("b"), list(run_step("c")))
  testthat::expect_s3_class(combined, "condathis_run_steps", exact = TRUE)
  testthat::expect_length(combined, 3L)
  testthat::expect_true(all(vapply(combined, is_run_step, logical(1L))))
  testthat::expect_identical(
    vapply(combined, `[[`, character(1L), "cmd"),
    c("a", "b", "c")
  )
  testthat::expect_null(names(combined))

  # A value that is not a step gives a plain list, as the default `c()`
  # does, and `run_pipeline()` reports it.
  mixed <- c(run_step("a"), "b")
  testthat::expect_false(is.object(mixed))
  testthat::expect_identical(mixed, list(run_step("a"), "b"))
  testthat::expect_error(
    object = run_pipeline(!!!mixed),
    class = "condathis_pipeline_invalid_step"
  )
  mixed <- c(combined, list(1))
  testthat::expect_false(is.object(mixed))
  testthat::expect_length(mixed, 4L)
  testthat::expect_error(
    object = run_pipeline(!!!mixed),
    class = "condathis_pipeline_invalid_step"
  )
})

testthat::test_that("c() of steps and options gives the arguments for do.call()", {
  # Regression test: `c()` on a list of steps aborted for any value that
  # was not a step, so the common `do.call(run_pipeline, c(steps,
  # list(<options>)))` failed with "Argument 2 is not a pipeline step".
  steps <- c(run_step("a"), run_step("b"))
  args <- c(steps, list(error = "continue", verbose = "silent"))
  testthat::expect_false(is.object(args))
  testthat::expect_identical(
    names(args),
    c("", "", "error", "verbose")
  )
  testthat::expect_identical(unname(args[1:2]), as.list(steps))
  testthat::expect_identical(
    c(run_step("a"), verbose = "silent"),
    list(run_step("a"), verbose = "silent")
  )

  # The steps run in an environment directory that does not exist, so
  # each one fails with status 127 and nothing needs micromamba.
  missing_dir <- fs::path(withr::local_tempdir(), "no-such-env")
  res <- do.call(
    run_pipeline,
    c(
      steps,
      list(
        env_name = env_path(missing_dir),
        error = "continue",
        verbose = "silent"
      )
    )
  )
  testthat::expect_identical(res$statuses, c(127L, 127L))
})

testthat::test_that("the invalid-step error names c() from NULL", {
  # `c(NULL, step)` uses the default `c()` (the first value has no class),
  # so an accumulator that starts from `NULL` splits each step into its
  # fields. No `c()` method can change that; the error says how to fix it.
  steps <- NULL
  for (step in list(run_step("a"), run_step("b"))) {
    steps <- c(steps, step)
  }
  testthat::expect_false(is_run_step_list(steps))
  # Called through a function, as in user code: `expect_error()` would
  # splice `!!!` when it captures the call, and the fields of two steps
  # (two `env_name` values) would then fail R's own argument matching.
  run_spliced <- function(x) run_pipeline(!!!x)
  cnd <- testthat::expect_error(
    object = run_spliced(steps),
    class = "condathis_pipeline_invalid_step"
  )
  message <- cli::ansi_strip(conditionMessage(cnd))
  # cli can wrap the line anywhere between words.
  testthat::expect_match(message, "plain list or\\s+`?NULL`?\\s+first")
  testthat::expect_match(message, "c(steps, list(step))", fixed = TRUE)
})

testthat::test_that("c() keeps a list of steps however steps are combined", {
  # Regression test: `c()` on steps returned a plain list, so the next
  # `c()` used the default method and spliced the fields of the new step:
  # `c(c(s1, s2), s3)` had 8 elements, and `run_pipeline(!!!steps)` aborted
  # with "not a pipeline step".
  s1 <- run_step("a")
  s2 <- run_step("b", "x")
  s3 <- run_step("c", 1, env_name = "c-env")
  s4 <- run_step("d")
  cmds <- function(steps) {
    testthat::expect_true(all(vapply(steps, is_run_step, logical(1L))))
    vapply(steps, `[[`, character(1L), "cmd")
  }
  abc <- c("a", "b", "c")

  steps <- c(s1, s2)
  steps <- c(steps, s3)
  testthat::expect_s3_class(steps, "condathis_run_steps")
  testthat::expect_identical(cmds(steps), abc)
  testthat::expect_identical(cmds(c(s1, c(s2, s3))), abc)
  testthat::expect_identical(cmds(c(c(s1, s2), c(s3, s4))), c(abc, "d"))
  testthat::expect_identical(cmds(Reduce(c, list(s1, s2, s3))), abc)
  testthat::expect_identical(cmds(append(c(s1, s2), s3)), abc)
  testthat::expect_identical(cmds(append(c(s1, s3), s2, after = 1L)), abc)
  testthat::expect_identical(cmds(append(list(s1, s2), list(s3))), abc)
  testthat::expect_identical(cmds(c(list(s1, s2), list(s3))), abc)
  testthat::expect_identical(cmds(c(s1, list(s2, s3))), abc)
  # `NULL` values are dropped, as by `c()`.
  testthat::expect_identical(cmds(c(s1, NULL, s2, if (FALSE) s4, s3)), abc)
  # Subsetting keeps the class; `as.list()` drops it.
  testthat::expect_s3_class(steps[2:3], "condathis_run_steps")
  testthat::expect_identical(cmds(steps[2:3]), c("b", "c"))
  testthat::expect_identical(cmds(rev(steps)), rev(abc))
  testthat::expect_false(is.object(as.list(steps)))
  testthat::expect_identical(as.list(steps), list(s1, s2, s3))
  testthat::expect_identical(steps[[3L]], s3)

  # Spliced into `run_pipeline()`'s `...`, a list of steps gives the steps.
  testthat::expect_identical(rlang::list2(!!!steps), list(s1, s2, s3))
  testthat::expect_identical(
    rlang::list2(s4, !!!c(s1, s2)),
    list(s4, s1, s2)
  )
})

testthat::test_that("a list of steps has format and print methods", {
  steps <- c(run_step("a", "x"), run_step("b", env_name = "b-env"))
  testthat::expect_identical(
    format(steps),
    c(
      "<run_steps> 2 steps",
      "[1] <run_step> a x [env: pipeline default]",
      "[2] <run_step> b [env: b-env]"
    )
  )
  out <- utils::capture.output(visible <- withVisible(print(steps)))
  testthat::expect_identical(out, format(steps))
  testthat::expect_false(visible$visible)
  testthat::expect_identical(visible$value, steps)
  testthat::expect_identical(format(steps[1L])[[1L]], "<run_steps> 1 step")
})

# --- base_env, command lookup and the environment directory (backend
# contract v2) ----------------------------------------------------------------

testthat::test_that("run_pipeline() gives backend_resolve_run() the stage's block before activation", {
  seen <- new.env(parent = emptyenv())
  seen$base_envs <- list()
  stub <- local_run_family_stub(
    backend_resolve_run = function(
      backend,
      cmd,
      args = character(0L),
      ...,
      base_env = NULL
    ) {
      seen$base_envs[[length(seen$base_envs) + 1L]] <- base_env
      return(list(
        command = cmd,
        args = args,
        env = c(CONDATHIS_TEST_ACTIVATED = "yes"),
        dir = NULL
      ))
    }
  )
  withr::local_envvar(
    CONDATHIS_TEST_SESSION = "kept",
    CONDARC = "/caller/condarc.yml"
  )
  dump_path <- withr::local_tempfile(fileext = ".rds")
  dump_code <- paste0(
    "saveRDS(Sys.getenv(c('TMPDIR', 'CONDATHIS_TEST_ACTIVATED', ",
    "'CONDATHIS_TEST_SESSION', 'CONDARC', 'CONDA_PKGS_DIRS')), ",
    deparse(as.character(dump_path)),
    "); cat('done')"
  )
  res <- run_pipeline(
    run_step(run_family_rscript(), "--vanilla", "-e", dump_code),
    run_step(
      run_family_rscript(),
      "--vanilla",
      "-e",
      "cat(readLines(file('stdin')))"
    ),
    env_name = "stub-env",
    verbose = "silent"
  )
  testthat::expect_identical(res$statuses, c(0L, 0L))
  testthat::expect_length(seen$base_envs, 2L)
  for (base_env in seen$base_envs) {
    testthat::expect_type(base_env, "character")
    testthat::expect_identical(
      unname(base_env[["CONDATHIS_TEST_SESSION"]]),
      "kept"
    )
    testthat::expect_identical(unname(base_env[["CONDARC"]]), "")
    testthat::expect_identical(unname(base_env[["CONDA_PREFIX"]]), "")
    testthat::expect_identical(
      unname(base_env[["CONDA_ENVS_PATH"]]),
      as.character(fs::path(stub$root, "envs"))
    )
    testthat::expect_identical(
      unname(base_env[["CONDA_PKGS_DIRS"]]),
      as.character(fs::path(stub$root, "conda-pkgs"))
    )
    testthat::expect_false("CONDATHIS_TEST_ACTIVATED" %in% names(base_env))
  }
  # The stage got that block with the activation variables on top.
  stage_env <- readRDS(dump_path)
  base_env <- seen$base_envs[[1L]]
  testthat::expect_identical(
    unname(stage_env),
    c(
      unname(base_env[["TMPDIR"]]),
      "yes",
      "kept",
      "",
      unname(base_env[["CONDA_PKGS_DIRS"]])
    )
  )
})

testthat::test_that("run_pipeline() starts a stage's bare command as run() does", {
  # Regression tests: a bare command from backend_resolve_run() went to
  # processx unchanged. On Linux and macOS, where processx searches the
  # child's PATH, it is still kept bare. On Windows, the environment's
  # binary directories are searched first, and any other name goes to
  # processx as for the micromamba backend: looking it up on the child's
  # PATH found `cmd`, the MSYS2 shell script that Rtools puts ahead of
  # `C:/Windows/System32`, so a stage running `cmd` failed with status 127.
  session_path <- Sys.getenv("PATH")
  tool_dir <- withr::local_tempdir()
  run_family_write_tool(tool_dir, "condathis-pipe-activation-tool", "activated")
  decoy_dir <- withr::local_tempdir()
  run_family_write_tool(decoy_dir, "condathis-pipe-activation-tool", "decoy")
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
  reader <- run_step(
    run_family_rscript(),
    "--vanilla",
    "-e",
    "cat(readLines(file('stdin')), sep = '\\n')"
  )
  if (isTRUE(is_windows())) {
    scripts_dir <- fs::path(stub$root, "envs", "stub-env", "Scripts")
    fs::dir_create(scripts_dir)
    run_family_write_tool(scripts_dir, "condathis-pipe-env-tool", "in env")
    res <- run_pipeline(
      run_step("condathis-pipe-env-tool"),
      reader,
      env_name = "stub-env",
      verbose = "silent"
    )
    testthat::expect_identical(res$statuses, c(0L, 0L))
    testthat::expect_match(res$processes[[2L]]$stdout, "in env", fixed = TRUE)
    fake_rtools <- withr::local_tempdir()
    writeLines(
      c("#!/usr/bin/env bash", "echo rtools"),
      fs::path(fake_rtools, "cmd")
    )
    withr::local_envvar(PATH = paste(fake_rtools, session_path, sep = ";"))
    res <- run_pipeline(
      run_step("cmd", "/c", "echo hi"),
      reader,
      env_name = "stub-env",
      verbose = "silent"
    )
    testthat::expect_identical(res$statuses, c(0L, 0L))
    testthat::expect_match(res$processes[[2L]]$stdout, "hi", fixed = TRUE)
  } else {
    withr::local_envvar(
      PATH = paste(decoy_dir, session_path, sep = .Platform$path.sep)
    )
    res <- run_pipeline(
      run_step("condathis-pipe-activation-tool"),
      reader,
      env_name = "stub-env",
      verbose = "silent"
    )
    testthat::expect_identical(res$statuses, c(0L, 0L))
    testthat::expect_match(
      res$processes[[2L]]$stdout,
      "activated",
      fixed = TRUE
    )
    testthat::expect_no_match(res$processes[[2L]]$stdout, "decoy", fixed = TRUE)
  }

  # Found nowhere: the command stays bare and fails to start.
  res <- run_pipeline(
    run_step("condathis-pipe-missing-tool"),
    reader,
    env_name = "stub-env",
    error = "continue",
    verbose = "silent"
  )
  testthat::expect_identical(res$statuses[[1L]], 127L)
  testthat::expect_match(
    res$processes[[1L]]$stderr,
    "System command 'condathis-pipe-missing-tool' not found",
    fixed = TRUE
  )
})

testthat::test_that("run_pipeline() checks the environment directory that a backend gives", {
  # Regression test: the stage's directory came from `backend_get_env_dir()`
  # unchecked, so a relative path reached processx and the activation.
  stub <- local_run_family_stub(
    backend_get_env_dir = function(backend, env_name = "condathis-env") {
      return("relative/env-dir")
    }
  )
  # The owner search checks the directory too, when it compares the
  # environment's marker: leave that out, to reach the stage.
  testthat::local_mocked_bindings(
    warn_on_backend_marker_mismatch = function(...) invisible(NULL)
  )
  cnd <- testthat::expect_error(
    run_pipeline(
      run_step(run_family_rscript(), "--vanilla", "-e", "cat(1)"),
      run_step(run_family_rscript(), "--vanilla", "-e", "cat(2)"),
      env_name = "stub-env",
      verbose = "silent"
    ),
    class = "condathis_backend_invalid_return"
  )
  testthat::expect_s3_class(cnd, "condathis_backend_contract_violation")
  testthat::expect_identical(
    rlang::call_name(conditionCall(cnd)),
    "run_pipeline"
  )
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "stub-run",
    fixed = TRUE
  )
})
