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
  env_bin_dir <- fs::path(get_env_dir("run-bin-cli-tools-env"), "bin")

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

  testthat::expect_match(res_run$stdout, env_bin_dir, fixed = TRUE)
  testthat::expect_match(res_bin$stdout, env_bin_dir, fixed = TRUE)
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
