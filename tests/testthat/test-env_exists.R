test_that("env_exists missing env_name", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  expect_error(env_exists())
})

test_that("env_exists rejects invalid env_name instead of silently returning FALSE", {
  testthat::expect_error(
    env_exists(NULL),
    class = "condathis_env_exists_invalid_env_name"
  )
  testthat::expect_error(
    env_exists(NA),
    class = "condathis_env_exists_invalid_env_name"
  )
  testthat::expect_error(
    env_exists(NA_character_),
    class = "condathis_env_exists_invalid_env_name"
  )
  testthat::expect_error(
    env_exists(c("a", "b")),
    class = "condathis_env_exists_invalid_env_name"
  )
  testthat::expect_error(
    env_exists(42),
    class = "condathis_env_exists_invalid_env_name"
  )
})
