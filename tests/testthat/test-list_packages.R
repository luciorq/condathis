test_that("list packages on absent environment", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  testthat::expect_error(
    object = {
      list_packages(
        env_name = "non-existing-env",
        verbose = "silent"
      )
    },
    class = "condathis_list_packages_missing_env"
  )

  testthat::expect_message(
    object = {
      pkgs_df <- list_packages(verbose = "silent")
    },
    regexp = "Retrieved [0-9]+ packages from environment"
  )
  testthat::expect_s3_class(pkgs_df, "tbl_df")
})
