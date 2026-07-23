testthat::test_that("remove_env errors when the environment does not exist", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  testthat::expect_error(
    remove_env(env_name = "definitely-does-not-exist-condathis-test-env"),
    class = "condathis_error_env_remove"
  )
})

testthat::test_that("remove_env cleans up a stray directory even when not tracked as an environment", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  # A directory can exist under the envs root without micromamba actually
  # tracking it as a real environment (e.g. left over from an interrupted
  # create). remove_env() clears the directory as a side effect but still
  # reports the removal as failed, since there was never a real environment
  # to remove.
  stray_dir <- get_env_dir("stray-dir-remove-test-env")
  fs::dir_create(stray_dir)
  testthat::expect_true(fs::dir_exists(stray_dir))

  testthat::expect_error(
    remove_env("stray-dir-remove-test-env", verbose = "silent"),
    class = "condathis_error_env_remove"
  )
  testthat::expect_false(fs::dir_exists(stray_dir))
})

testthat::test_that("remove_env removes a real environment", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  create_env(NULL, env_name = "condathis-remove-test-env", verbose = "silent")
  testthat::expect_true(env_exists("condathis-remove-test-env"))

  px_res <- remove_env(
    env_name = "condathis-remove-test-env",
    verbose = "silent"
  )
  testthat::expect_equal(px_res$status, 0L)
  testthat::expect_false(env_exists("condathis-remove-test-env"))
  testthat::expect_false(fs::dir_exists(get_env_dir(
    "condathis-remove-test-env"
  )))
})

testthat::test_that("remove_env reports success via message at verbose = 'output'", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  create_env(
    NULL,
    env_name = "condathis-remove-verbose-test-env",
    verbose = "silent"
  )

  testthat::expect_message(
    remove_env(
      env_name = "condathis-remove-verbose-test-env",
      verbose = "output"
    ),
    regexp = "succesfully removed"
  )
  testthat::expect_false(env_exists("condathis-remove-verbose-test-env"))
})

testthat::test_that("remove_env emits no message at verbose = 'silent'", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  create_env(
    NULL,
    env_name = "condathis-remove-silent-test-env",
    verbose = "silent"
  )

  testthat::expect_no_message(
    remove_env(
      env_name = "condathis-remove-silent-test-env",
      verbose = "silent"
    )
  )
})
