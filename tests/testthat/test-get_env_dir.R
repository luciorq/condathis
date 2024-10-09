test_that("get_env_dir() works", {
  env_name <- "condathis-test-env"
  testthat::expect_equal(
    fs::path(get_install_dir(), "envs", env_name),
    get_env_dir(env_name)
  )
})
