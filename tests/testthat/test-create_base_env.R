testthat::test_that("Create base env", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  install_dir <- get_install_dir(method = "micromamba")$path
  if (fs::dir_exists(fs::path(install_dir, "envs", "condathis-env"))) {
    fs::dir_delete(fs::path(install_dir, "envs", "condathis-env"))
  }
  create_base_env(verbose = "silent")
  testthat::expect_true(
    fs::file_exists(
      fs::path(
        install_dir,
        "envs",
        "condathis-env",
        "conda-meta",
        "history"
      )
    )
  )
})
