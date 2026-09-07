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
  # backend_has_env() so the missing-env check doesn't fire first - it
  # would otherwise also see the mocked native_cmd() failure via
  # backend_list_envs() and swallow it as "doesn't exist", per
  # backend_has_env()'s own never-errors contract) to exercise
  # list_packages()'s own defensive handling of that case directly.
  testthat::local_mocked_bindings(
    backend_has_env = function(...) TRUE,
    native_cmd = function(...) {
      list(status = 1L, stdout = "", stderr = "boom", timeout = FALSE)
    }
  )
  testthat::expect_error(
    list_packages(env_name = "condathis-env", verbose = "silent"),
    class = "condathis_cmd_status_error"
  )
})

testthat::test_that("list_packages parses both micromamba list --json output shapes", {
  # micromamba 2.9.0 changed `list --json` from a bare package array to
  # `{"log_history": [...], "packages": [...]}`. Which binary answers
  # depends on the discovery chain (a system-installed 2.9+ can win over
  # the pinned internal version), so both shapes must parse.
  old_shape <- '[{"base_url":"u","build_number":1,"build_string":"b","channel":"c","dist_name":"d","name":"zlib","platform":"linux-64","version":"1.3"}]'
  new_shape <- paste0('{"log_history":[],"packages":', old_shape, "}")

  for (shape in c(old_shape, new_shape)) {
    testthat::local_mocked_bindings(
      backend_has_env = function(...) TRUE,
      native_cmd = function(...) {
        list(status = 0L, stdout = shape, stderr = "", timeout = FALSE)
      }
    )
    pkgs <- list_packages(env_name = "condathis-env", verbose = "silent")
    testthat::expect_equal(pkgs$name, "zlib")
    testthat::expect_equal(pkgs$version, "1.3")
  }
})
