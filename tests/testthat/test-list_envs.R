testthat::test_that("list_envs returns a tibble with backend/env_name/path", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  create_base_env(verbose = "silent")
  envs <- list_envs(verbose = "silent")
  testthat::expect_s3_class(envs, "data.frame")
  testthat::expect_named(envs, c("backend", "env_name", "path"))
  testthat::expect_type(envs$env_name, "character")
  testthat::expect_true(all(envs$backend == "micromamba"))
})

testthat::test_that("condathis_env_names matches the install root as an anchored literal prefix", {
  # Two regressions covered: the root was once used as a regex pattern
  # (the `.` in a real install path matched any character), and later as
  # an unanchored literal substring (any path merely *containing* the
  # root somewhere inside it - e.g. a backup copy - was claimed as
  # condathis-owned). It must be an anchored literal prefix.
  root <- "/root/a.b/condathis"
  envs <- c(
    "/root/a.b/condathis", # the root itself -> not a child -> dropped
    "/root/a.b/condathis/envs/foo", # a real child -> kept
    "/root/aXb/condathis/envs/decoy", # NOT under root; `.` regex would match
    "/backup/root/a.b/condathis/envs/copy", # contains root as infix only
    "/root/a.b/condathis-other/envs/sibling" # shares the prefix, no separator
  )
  result <- condathis_env_names(envs, root)
  testthat::expect_equal(result, "foo")
  testthat::expect_false("decoy" %in% result)
  testthat::expect_false("copy" %in% result)
  testthat::expect_false("sibling" %in% result)
  testthat::expect_false("condathis" %in% result)
})

testthat::test_that("list_envs excludes the condathis root pseudo-environment", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  create_base_env(verbose = "silent")
  envs <- list_envs(verbose = "silent")
  testthat::expect_false("condathis" %in% envs$env_name)
  testthat::expect_true("condathis-env" %in% envs$env_name)
})

testthat::test_that("list_envs reflects environment creation and removal", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  condathis::with_sandbox_dir({
    testthat::expect_false(
      "list-envs-test-env" %in% list_envs(verbose = "silent")$env_name
    )

    create_env(NULL, env_name = "list-envs-test-env", verbose = "silent")
    testthat::expect_true(
      "list-envs-test-env" %in% list_envs(verbose = "silent")$env_name
    )

    remove_env("list-envs-test-env", verbose = "silent")
    testthat::expect_false(
      "list-envs-test-env" %in% list_envs(verbose = "silent")$env_name
    )
  })
})

testthat::test_that("list_envs raises condathis_cmd_status_error on failure instead of returning a number", {
  # `rethrow_error_cmd()` normally already aborts before list_envs() ever
  # sees a non-zero status (native_cmd()'s default error = "cancel" makes
  # the underlying processx::run() throw, not return, on failure) - mock
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

testthat::test_that("realize_env_paths tolerates stale and vanished environment paths", {
  # Regression test: a vectorized fs::path_real() errors ENOENT on the
  # first stale registry entry (e.g. ~/.conda/environments.txt), which
  # aborted list_envs() for every environment at once and made
  # env_exists() report existing environments as absent through
  # backend_has_env()'s never-errors coercion.
  real_dir <- withr::local_tempdir()
  stale_path <- fs::path(real_dir, "definitely-gone-subdir", "old-env")
  out <- realize_env_paths(c(as.character(real_dir), as.character(stale_path)))
  testthat::expect_equal(out, as.character(fs::path_real(real_dir)))
  # All-stale input: empty result, no error.
  testthat::expect_equal(
    realize_env_paths(as.character(stale_path)),
    character(0L)
  )
})
