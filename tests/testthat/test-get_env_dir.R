test_that("get_env_dir() works", {
  env_name <- "condathis-get-test-env"
  testthat::expect_equal(
    fs::path(get_install_dir(), "envs", env_name),
    get_env_dir(env_name)
  )
})

test_that("get_env_dir() validates env_name", {
  testthat::expect_error(
    object = get_env_dir(env_name = c("a", "b")),
    class = "condathis_get_env_dir_invalid_env_name"
  )
  testthat::expect_error(
    object = get_env_dir(env_name = NA),
    class = "condathis_get_env_dir_invalid_env_name"
  )
  testthat::expect_error(
    object = get_env_dir(env_name = 123),
    class = "condathis_get_env_dir_invalid_env_name"
  )
})
