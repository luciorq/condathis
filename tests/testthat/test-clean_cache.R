testthat::test_that("clean_cache outputs are captured", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  # This is needed for a full cache clean otherwhise, micromamba keeps
  # + the packages that are used in envs.
  for (env_name in list_envs(verbose = "silent")) {
    remove_env(env_name = env_name, verbose = "silent")
  }
  r_user_cache <- fs::path(
    tools::R_user_dir(package = "condathis", which = "cache")
  )
  if (isFALSE(fs::dir_exists(r_user_cache))) {
    fs::dir_create(r_user_cache, recurse = TRUE)
  }
  fs::file_touch(fs::path(r_user_cache, "dummy-file", ext = "txt"))

  testthat::expect_message(
    object = {
      clean_cache()
    },
    class = "rlang_message",
    regexp = ".*Cache successfully removed.*"
  ) |>
    testthat::capture_output()

  testthat::expect_message(
    object = {
      clean_cache(verbose = "output")
    },
    class = "rlang_message",
    regexp = ".*Cache successfully removed.*"
  ) |>
    testthat::capture_output()

  testthat::expect_message(
    object = {
      clean_cache(verbose = "full")
    },
    class = "rlang_message",
    regexp = ".*Cache successfully removed.*"
  ) |>
    testthat::capture_output() |>
    stringr::str_detect(pattern = "^Running.*") |>
    testthat::expect_true()

  testthat::expect_message(
    object = {
      clean_cache(verbose = "full")
    },
    class = "rlang_message",
    regexp = ".*Cache successfully removed.*"
  ) |>
    testthat::capture_output() |>
    stringr::str_detect(pattern = "^Running.*") |>
    testthat::expect_true()

  testthat::expect_false(
    fs::file_exists(fs::path(r_user_cache, "dummy-file", ext = "txt"))
  )
  testthat::expect_true(fs::dir_exists(r_user_cache))
})
