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

test_that("Run returns a condathis_result object", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(verbose = "silent")
  res <- run("echo", "hello", env_name = "condathis-env", verbose = "silent")
  testthat::expect_s3_class(res, "condathis_result")
  testthat::expect_equal(res$status, 0L)
  testthat::expect_match(res$stdout, "hello")
  testthat::expect_true(is.numeric(res$pid))
  testthat::expect_match(res$cmd, "echo")
  testthat::expect_equal(res$env_name, "condathis-env")

  formatted <- format(res)
  testthat::expect_type(formatted, "character")
  testthat::expect_match(formatted, "condathis_result")
})

test_that("Run supports stdin = '|' with input", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(verbose = "silent")
  res <- run(
    "sort",
    stdin = "|",
    input = "b\na\nc\na\nb\n",
    env_name = "condathis-env",
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

  create_env(verbose = "silent")
  res <- run(
    "sh",
    "-c",
    "cat; exit 1",
    stdin = "|",
    input = "boom\n",
    error = "continue",
    verbose = "silent"
  )
  testthat::expect_equal(res$status, 1L)
  testthat::expect_match(res$stdout, "boom")

  testthat::expect_error(
    object = run(
      "sh",
      "-c",
      "cat >&2; exit 1",
      stdin = "|",
      input = "boom\n",
      error = "cancel",
      verbose = "silent"
    ),
    class = "condathis_run_status_error"
  )
})

test_that("Run accepts crash-safety parameters", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(verbose = "silent")
  res <- run(
    "echo",
    "hi",
    supervise = TRUE,
    cleanup_tree = TRUE,
    linux_pdeathsig = TRUE,
    env_name = "condathis-env",
    verbose = "silent"
  )
  testthat::expect_equal(res$status, 0L)
})
