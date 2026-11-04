testthat::test_that("Create base env", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  install_dir <- get_install_dir(method = "micromamba")$path
  if (fs::dir_exists(fs::path(install_dir, "envs", "condathis-env"))) {
    fs::dir_delete(fs::path(install_dir, "envs", "condathis-env"))
  }
  create_base_env(verbose = "silent")
  testthat::expect_true(
    fs::file_exists(
      fs::path(
        install_dir,
        "envs",
        "condathis-env",
        "conda-meta",
        "history"
      )
    )
  )
})

testthat::test_that("create_base_env() creates the environment with the given backend", {
  # Regression test: create_base_env() had no `method` and always created
  # through "auto", so run(method = "a") created condathis-env under the
  # first backend in priority order and then warned that the environment
  # belonged to another backend.
  stub_a <- local_stub_backend("stub-base-a")
  stub_b <- local_stub_backend("stub-base-b")
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() c("stub-base-b", "stub-base-a")
  )

  testthat::expect_no_warning(
    create_base_env(method = "stub-base-a", verbose = "silent")
  )
  testthat::expect_true(
    fs::dir_exists(fs::path(stub_a$root, "envs", "condathis-env"))
  )
  testthat::expect_false(
    fs::dir_exists(fs::path(stub_b$root, "envs", "condathis-env"))
  )
  testthat::expect_length(stub_calls(stub_a, "backend_create_env"), 1L)
  testthat::expect_length(stub_calls(stub_b, "backend_create_env"), 0L)

  # An existing environment is kept: no second creation.
  create_base_env(method = "stub-base-a", verbose = "silent")
  testthat::expect_length(stub_calls(stub_a, "backend_create_env"), 1L)
})

testthat::test_that("create_base_env() returns NULL invisibly", {
  local_stub_backend("stub-base-invisible", envs = "condathis-env")
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() "stub-base-invisible"
  )
  res <- withVisible(create_base_env(method = "stub-base-invisible"))
  testthat::expect_false(res$visible)
  testthat::expect_null(res$value)
})
