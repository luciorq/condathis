testthat::test_that("list_envs returns a character vector", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  create_base_env(verbose = "silent")
  envs <- list_envs(verbose = "silent")
  testthat::expect_type(envs, "character")
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
