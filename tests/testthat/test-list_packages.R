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
      pkgs_df <- list_packages()
    },
    regexp = "Retrieved [0-9]+ packages from environment"
  )
  testthat::expect_s3_class(pkgs_df, "tbl_df")
})

test_that("list_packages raises condathis_cmd_status_error on failure instead of a raw error", {
  # As with list_envs(): rethrow_error_cmd() normally already aborts before
  # list_packages() ever sees a non-zero status. Mock native_cmd() (and
  # env_exists() so the missing-env check doesn't fire first) to exercise
  # list_packages()'s own defensive handling of that case directly.
  testthat::local_mocked_bindings(
    env_exists = function(...) TRUE,
    native_cmd = function(...) {
      list(status = 1L, stdout = "", stderr = "boom", timeout = FALSE)
    }
  )
  testthat::expect_error(
    list_packages(env_name = "condathis-env", verbose = "silent"),
    class = "condathis_cmd_status_error"
  )
})
