test_that("list packages on absent environment", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  testthat::expect_error(
    object = {
      list_packages(env_name = "non-existing-env")
    },
    class = "condathis_list_packages_missing_env"
  )
})
