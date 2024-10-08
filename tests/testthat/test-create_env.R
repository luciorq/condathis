test_that("conda env is created", {
  px_res <- create_env(
    packages = c("r-base=4.1.3", "r-devtools"),
    env_name = "condathis-test-env",
    verbose = FALSE
  )
  expect_equal(px_res$status, 0)

  run_res <- run(
    "R", "-s", "-q", "--version",
    env_name = "condathis-test-env",
    verbose = FALSE
  )

  expect_equal(run_res$status, 0)

  r_version_output <- run_res$stdout
  if (isFALSE(nzchar(r_version_output))) {
    r_version_output <- run_res$stderr
  }
  expect_true(stringr::str_detect(r_version_output, "R version 4.1.3"))

  pkgs_list_res <- list_packages(env_name = "condathis-test-env")

  testthat::expect_equal(ncol(pkgs_list_res), 8)

  testthat::expect_true("r-base" %in% pkgs_list_res$name)

  testthat::expect_true("4.1.3" %in% pkgs_list_res$version)

  withr::with_envvar(
    new = list(`MY_VAR_1` = "HELLO FROM OUTSIDE"),
    code = {
      px_res <- run(
        "R", "-q", "-s", "-e", "print(Sys.getenv('MY_VAR_1'))",
        env_name = "condathis-test-env",
        verbose = FALSE
      )
    }
  )
  testthat::expect_equal(px_res$status, 0)
  envvar_output <- px_res$stdout
  if (isFALSE(nzchar(envvar_output))) {
    r_version_output <- px_res$stderr
  }
  testthat::expect_true(
    stringr::str_detect(px_res$stdout, "HELLO FROM OUTSIDE")
  )

  install_res <- install_packages(
    packages = c("python=3.8.16"),
    env_name = "condathis-test-env",
    verbose = FALSE
  )
  expect_equal(install_res, 0)

  inst_res <- run(
    "python", "--version",
    env_name = "condathis-test-env",
    verbose = FALSE
  )

  expect_equal(inst_res$status, 0)

  expect_true(stringr::str_detect(inst_res$stdout, "Python 3.8.16"))

  expect_true(env_exists(env_name = "condathis-test-env"))

  px_res <- remove_env(env_name = "condathis-test-env", verbose = FALSE)

  expect_equal(px_res$status, 0)

  expect_false("condathis-test-env" %in% list_envs())
})

test_that("Create conda env from file", {
  px_res <- create_env(
    env_file = fs::path_package("condathis", "extdata", "stat-env.yml"),
    method = "native",
    env_name = "condathis-test-env",
    verbose = FALSE
  )
  expect_equal(px_res$status, 0)

  current_envs <- list_envs()

  expect_true("condathis-test-env" %in% current_envs)

  expect_true(env_exists(env_name = "condathis-test-env"))

  px_res <- remove_env(env_name = "condathis-test-env", verbose = FALSE)

  expect_equal(px_res$status, 0)

  current_envs <- list_envs()

  expect_false("condathis-test-env" %in% current_envs)

  expect_false(env_exists(env_name = "condathis-test-env"))
})
