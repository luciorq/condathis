test_that("create nested environment", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  create_res <- create_env(
    packages = NULL,
    env_name = "test-nested-env",
    verbose = FALSE
  )
  testthat::expect_true(env_exists("test-nested-env"))

  pkgs_res <- list_packages(env_name = "test-nested-env")

  testthat::expect_equal(nrow(pkgs_res), 0)
  testthat::expect_equal(ncol(pkgs_res), 8)

  nested_create_res <- run(
    cmd = micromamba_bin_path(),
    "--no-rc",
    "--no-env",
    "create",
    "--quiet",
    "--yes",
    "-r", get_install_dir(),
    "-n", "test-inside-env",
    env_name = "test-nested-env",
    verbose = FALSE
  )
  testthat::expect_true(env_exists("test-inside-env"))
  remove_env("test-nested-env", verbose = FALSE)
  remove_env("test-inside-env", verbose = FALSE)

  testthat::expect_false(any(c("test-nested-env", "test-inside-env") %in% list_envs()))
})
