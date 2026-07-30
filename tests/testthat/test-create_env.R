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

testthat::test_that("create_env rejects a non-logical overwrite argument", {
  testthat::expect_error(
    object = {
      create_env(NULL, overwrite = "yes")
    },
    class = "condathis_create_invalid_overwrite_arg"
  )
})

testthat::test_that("create_env rejects a missing env_file", {
  testthat::expect_error(
    object = {
      create_env(env_file = "definitely-does-not-exist.yml")
    },
    class = "condathis_create_missing_env_file"
  )
})

testthat::test_that("create_env returns a condathis_result when dependencies are already satisfied", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  create_env(
    packages = "zlib",
    env_name = "condathis-already-satisfied-test-env",
    channels = "conda-forge",
    verbose = "silent"
  )

  # Second call with the same package: satisfies_dependencies() short-circuits
  # before ever calling native_cmd(), so this return value is hand-built
  # rather than derived from a real process result.
  px_res <- create_env(
    packages = "zlib",
    env_name = "condathis-already-satisfied-test-env",
    channels = "conda-forge",
    verbose = "silent"
  )
  testthat::expect_s3_class(px_res, "condathis_result")
  testthat::expect_equal(px_res$status, 0L)
  testthat::expect_equal(
    px_res$env_name,
    "condathis-already-satisfied-test-env"
  )

  remove_env(
    env_name = "condathis-already-satisfied-test-env",
    verbose = "silent"
  )
})

testthat::test_that("create_env rethrows a failing micromamba command", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  testthat::expect_error(
    object = {
      create_env(
        packages = "this-package-definitely-does-not-exist-xyz-condathis-test",
        env_name = "condathis-cmd-status-error-test-env",
        channels = "conda-forge",
        verbose = "silent"
      )
    },
    class = "condathis_cmd_status_error"
  )

  if (fs::dir_exists(get_env_dir("condathis-cmd-status-error-test-env"))) {
    fs::dir_delete(get_env_dir("condathis-cmd-status-error-test-env"))
  }
})

testthat::test_that("conda env is created", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  px_res <- create_env(
    packages = c("r-base>=4.1,<5.0"),
    env_name = "condathis-create-test-env",
    verbose = "silent"
  )
  testthat::expect_s3_class(px_res, "condathis_result")
  testthat::expect_equal(px_res$status, 0L)
  testthat::expect_equal(px_res$env_name, "condathis-create-test-env")

  # Ensure micromamba is installed at the internal path for further tests.
  # With the discovery chain, native_cmd() may use an external micromamba
  # and skip installing to the internal path. Install explicitly here.
  if (isFALSE(fs::file_exists(micromamba_bin_path()))) {
    suppressMessages(install_micromamba(verbose = "silent"))
  }

  withr::with_path(
    new = dirname(micromamba_bin_path()),
    code = {
      umamba_path <- micromamba_user_installed()
    },
    action = "replace"
  )

  testthat::expect_true(fs::file_exists(umamba_path))

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
  testthat::expect_false("condathis-create-test-env" %in% list_envs()$env_name)
})

testthat::test_that("Create conda env from file", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  px_res <- create_env(
    env_file = fs::path_package("condathis", "extdata", "stat-env.yml"),
    method = "micromamba",
    env_name = "condathis-create-file-test-env",
    verbose = "silent"
  )
  expect_equal(px_res$status, 0L)

  current_envs <- list_envs()

  expect_true("condathis-create-file-test-env" %in% current_envs$env_name)

  expect_true(env_exists(env_name = "condathis-create-file-test-env"))

  px_res <- remove_env(
    env_name = "condathis-create-file-test-env",
    verbose = "silent"
  )

  expect_equal(px_res$status, 0L)

  current_envs <- list_envs()

  testthat::expect_false(
    "condathis-create-file-test-env" %in% current_envs$env_name
  )

  testthat::expect_false(env_exists(
    env_name = "condathis-create-file-test-env"
  ))
})
