testthat::test_that("list_envs returns a character vector", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  create_base_env(verbose = "silent")
  envs <- list_envs(verbose = "silent")
  testthat::expect_type(envs, "character")
})

testthat::test_that("condathis_env_names matches the install root literally, not as a regex", {
  # Regression: the root was previously used as a regex pattern, so the `.`
  # in a real install path (e.g. `~/.local/...`) matched any character and
  # could pull in unrelated environments. `condathis_env_names()` must match
  # the root as a literal substring.
  root <- "/root/a.b/condathis"
  envs <- c(
    "/root/a.b/condathis", # the root itself -> basename "condathis" -> dropped
    "/root/a.b/condathis/envs/foo", # a real child -> kept
    "/root/aXb/condathis/envs/decoy" # NOT under root; `.` regex would match `X`
  )
  result <- condathis_env_names(envs, root)
  testthat::expect_equal(result, "foo")
  testthat::expect_false("decoy" %in% result)
  testthat::expect_false("condathis" %in% result)
})

testthat::test_that("list_envs excludes the condathis root pseudo-environment", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  create_base_env(verbose = "silent")
  envs <- list_envs(verbose = "silent")
  testthat::expect_false("condathis" %in% envs)
  testthat::expect_true("condathis-env" %in% envs)
})

testthat::test_that("list_envs reflects environment creation and removal", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  condathis::with_sandbox_dir({
    testthat::expect_false(
      "list-envs-test-env" %in% list_envs(verbose = "silent")
    )

    create_env(NULL, env_name = "list-envs-test-env", verbose = "silent")
    testthat::expect_true(
      "list-envs-test-env" %in% list_envs(verbose = "silent")
    )

    remove_env("list-envs-test-env", verbose = "silent")
    testthat::expect_false(
      "list-envs-test-env" %in% list_envs(verbose = "silent")
    )
  })
})

testthat::test_that("list_envs raises condathis_cmd_status_error on failure instead of returning a number", {
  # `rethrow_error_cmd()` normally already aborts before list_envs() ever
  # sees a non-zero status (native_cmd()'s default error = "cancel" makes
  # the underlying processx::run() throw, not return, on failure) — mock
  # native_cmd() directly so it *returns* a non-zero status instead, to
  # exercise list_envs()'s own defensive handling of that case.
  testthat::local_mocked_bindings(
    native_cmd = function(...) {
      list(status = 1L, stdout = "", stderr = "boom", timeout = FALSE)
    }
  )
  testthat::expect_error(
    list_envs(verbose = "silent"),
    class = "condathis_cmd_status_error"
  )
})

testthat::test_that("list_envs echoes the underlying command at verbose = 'full'", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  create_base_env(verbose = "silent")
  captured <- testthat::capture_output(list_envs(verbose = "full"))
  testthat::expect_true(stringr::str_detect(
    captured,
    stringr::fixed("Running")
  ))
})
