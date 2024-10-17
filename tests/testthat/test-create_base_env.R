testthat::test_that("Create base env", {
  if (fs::dir_exists(fs::path(get_install_dir(), "envs", "condathis-env"))) {
    fs::dir_delete(fs::path(get_install_dir(), "envs", "condathis-env"))
  }
  create_base_env()
  testthat::expect_true(fs::file_exists(fs::path(get_install_dir(), "envs", "condathis-env", "conda-meta", "history")))
})
