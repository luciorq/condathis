testthat::test_that("Create base env", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  if (fs::dir_exists(fs::path(get_install_dir(), "envs", "condathis-env"))) {
    fs::dir_delete(fs::path(get_install_dir(), "envs", "condathis-env"))
  }
  create_base_env()
  testthat::expect_true(fs::file_exists(fs::path(get_install_dir(), "envs", "condathis-env", "conda-meta", "history")))
})
