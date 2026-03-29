testthat::test_that("create_env invalid method arg", {
  testthat::expect_error(
    object = {
      create_env(NULL, method = NA)
    },
    class = "rlang_error"
  )
  # partial matching
  testthat::expect_error(
    object = {
      create_env(NULL, method = "na")
    },
    class = "rlang_error"
  )

  # invalid method
  testthat::expect_error(
    object = {
      create_env(NULL, method = "NonExisting")
    },
    class = "rlang_error"
  )
})

testthat::test_that("conda env is created", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  px_res <- create_env(
    packages = c("r-base>=4.1,<5.0"),
    env_name = "condathis-create-test-env",
    verbose = "silent"
  )
  testthat::expect_equal(px_res$status, 0L)

  withr::with_path(
    new = dirname(micromamba_bin_path()),
    code = {
      umamba_path <- micromamba_user_installed()
    },
    action = "replace"
  )

  testthat::expect_equal(
    micromamba_bin_path(),
    umamba_path
  )

  run_res <- run(
    "Rmissing",
    env_name = "condathis-create-test-env",
    error = "continue",
    verbose = "silent"
  )

  testthat::expect_false(identical(run_res$status, 0L))

  testthat::expect_error(
    object = {
      run(
        "Rmissing",
        env_name = "condathis-create-test-env",
        error = "cancel",
        verbose = "silent"
      )
    },
    class = "condathis_run_status_error"
  )

  run_res <- run(
    "R",
    "-s",
    "-q",
    "--version",
    env_name = "condathis-create-test-env",
    verbose = "silent",
    error = "continue"
  )

  run_bin_res <- run_bin(
    "R",
    "-s",
    "-q",
    "--version",
    env_name = "condathis-create-test-env",
    verbose = "silent",
    error = "continue"
  )

  testthat::expect_equal(run_res$status, run_bin_res$status)

  testthat::expect_equal(run_res$status, 0L)

  r_version_output <- run_res$stdout
  # Check both stdout and stderr for R version output
  # + On Windows that can vary
  if (isFALSE(nzchar(r_version_output))) {
    r_version_output <- run_res$stderr
  }
  testthat::expect_true(
    stringr::str_detect(
      r_version_output,
      stringr::regex("R version 4\\.\\d+\\.\\d+")
    )
  )

  pkgs_list_res <- list_packages(
    env_name = "condathis-create-test-env",
    verbose = "silent"
  )

  testthat::expect_true(ncol(pkgs_list_res) > 0L)

  testthat::expect_true(
    base::all(c("r-base") %in% pkgs_list_res$name)
  )

  testthat::expect_true("r-base" %in% pkgs_list_res$name)

  withr::with_envvar(
    new = list(`MY_VAR_1` = "HELLO FROM OUTSIDE"),
    code = {
      px_res <- run(
        "R",
        "-q",
        "-s",
        "-e",
        "print(Sys.getenv('MY_VAR_1'))",
        env_name = "condathis-create-test-env",
        verbose = "silent"
      )
    }
  )

  testthat::expect_equal(px_res$status, 0L)
  envvar_output <- px_res$stdout
  if (isFALSE(nzchar(envvar_output))) {
    envvar_output <- px_res$stderr
  }
  testthat::expect_true(
    stringr::str_detect(envvar_output, "HELLO FROM OUTSIDE")
  )

  install_res <- install_packages(
    packages = c("python>=3.11,<4.0"),
    env_name = "condathis-create-test-env",
    verbose = FALSE
  )
  testthat::expect_equal(install_res$status, 0L)

  inst_res <- run(
    "python",
    "--version",
    env_name = "condathis-create-test-env",
    verbose = FALSE
  )

  testthat::expect_equal(inst_res$status, 0L)

  testthat::expect_true(
    stringr::str_detect(
      inst_res$stdout,
      stringr::regex("Python 3\\.\\d+\\.\\d+")
    )
  )

  testthat::expect_true(env_exists(env_name = "condathis-create-test-env"))

  px_res <- remove_env(env_name = "condathis-create-test-env", verbose = FALSE)

  testthat::expect_equal(px_res$status, 0L)
  testthat::expect_false(env_exists(env_name = "condathis-create-test-env"))
  testthat::expect_false("condathis-create-test-env" %in% list_envs())
})

testthat::test_that("Create conda env from file", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  px_res <- create_env(
    env_file = fs::path_package("condathis", "extdata", "stat-env.yml"),
    method = "native",
    env_name = "condathis-create-file-test-env",
    verbose = "silent"
  )
  expect_equal(px_res$status, 0L)

  current_envs <- list_envs()

  expect_true("condathis-create-file-test-env" %in% current_envs)

  expect_true(env_exists(env_name = "condathis-create-file-test-env"))

  px_res <- remove_env(
    env_name = "condathis-create-file-test-env",
    verbose = "silent"
  )

  expect_equal(px_res$status, 0L)

  current_envs <- list_envs()

  testthat::expect_false("condathis-create-file-test-env" %in% current_envs)

  testthat::expect_false(env_exists(
    env_name = "condathis-create-file-test-env"
  ))
})
