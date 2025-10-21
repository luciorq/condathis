testthat::test_that("clean_cache outputs are captured", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  for (env_name in list_envs()) {
    remove_env(env_name = env_name, verbose = "silent")
  }

  clean_cache() |>
    testthat::expect_message("Cache succesfully removed")

  clean_cache(verbose = "output") |>
    testthat::expect_message("Cache succesfully removed")

  clean_cache(verbose = "full") |>
    testthat::expect_message("Cache succesfully removed") |>
    testthat::capture_output() |>
    stringr::str_detect(pattern = "^Running.*") |>
    testthat::expect_true()

  clean_cache(verbose = "full") |>
    testthat::expect_message("Cache succesfully removed") |>
    testthat::capture_output() |>
    stringr::str_detect(pattern = "^Running.*") |>
    testthat::expect_true()
})
