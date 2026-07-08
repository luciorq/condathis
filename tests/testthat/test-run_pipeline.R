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
