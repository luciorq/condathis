testthat::test_that("run - verbose outputs", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  if (env_exists("verbose-true-env")) {
    remove_env("verbose-true-env", verbose = "silent")
  }
  if (env_exists("test-verbose-env")) {
    remove_env("test-verbose-env", verbose = FALSE)
  }

  create_env(env_name = "test-verbose-env", verbose = "output") |>
    testthat::expect_message(regexp = "Environment .* successfully created")

  remove_env("test-verbose-env", verbose = "output") |>
    testthat::expect_message(regexp = "Environment .* successfully removed")

  create_env(env_name = "test-verbose-env", verbose = "full") |>
    testthat::expect_message(regexp = "Environment .* successfully created") |>
    testthat::capture_output() |>
    stringr::str_detect(pattern = stringr::fixed("Running ")) |>
    testthat::expect_true()

  remove_env("test-verbose-env", verbose = "full") |>
    testthat::expect_message(regexp = "Environment .* successfully removed") |>
    testthat::capture_output() |>
    stringr::str_detect(pattern = stringr::fixed("Running ")) |>
    testthat::expect_true()

  remove_env("test-verbose-fake-env", verbose = TRUE) |>
    testthat::expect_error("does not exist")

  remove_env("test-verbose-fake-env", verbose = "output") |>
    testthat::expect_error("does not exist")

  remove_env("test-verbose-fake-env", verbose = FALSE) |>
    testthat::expect_error("does not exist")

  create_env(env_name = "test-verbose-env", verbose = FALSE) |>
    testthat::expect_no_message()

  remove_env("test-verbose-env", verbose = FALSE) |>
    testthat::expect_no_message()

  remove_env("test-verbose-env", verbose = FALSE) |>
    testthat::expect_error("does not exist")

  # Decision D5: remove_env() changes state, so by default it reports what
  # it did, as create_env() does.
  create_env(env_name = "test-verbose-env", verbose = FALSE)
  remove_env("test-verbose-env") |>
    testthat::expect_message(regexp = "Environment .* successfully removed")

  create_env(
    "polyglot",
    env_name = "test-verbose-env",
    channels = polyglot_channel(),
    verbose = TRUE
  ) |>
    testthat::expect_message(regexp = "Environment .* successfully created")

  create_env(
    "polyglot",
    env_name = "test-verbose-env",
    channels = polyglot_channel(),
    verbose = TRUE
  ) |>
    testthat::expect_message(regexp = "already has the requested packages")

  create_env(
    "polyglot",
    env_name = "test-verbose-env",
    channels = polyglot_channel(),
    verbose = "output"
  ) |>
    testthat::expect_message(regexp = "already has the requested packages")

  create_env(
    "polyglot",
    env_name = "test-verbose-env",
    channels = polyglot_channel(),
    verbose = "silent"
  ) |>
    testthat::expect_no_message()

  run(
    "polyglot",
    env_name = "test-verbose-env",
    verbose = "output"
  ) |>
    testthat::expect_no_message() |>
    testthat::expect_output(polyglot_expected_line(), fixed = TRUE)

  run(
    "polyglot",
    env_name = "test-verbose-env",
    verbose = TRUE
  ) |>
    testthat::expect_no_message() |>
    testthat::expect_output(polyglot_expected_line(), fixed = TRUE)

  withr::with_options(
    list(
      rlang.intective = FALSE
    ),
    code = {
      run(
        "polyglot",
        env_name = "test-verbose-env",
        verbose = "silent"
      ) |>
        testthat::expect_no_message()
    }
  )
  withr::with_options(
    list(
      rlang.intective = FALSE
    ),
    code = {
      run(
        "polyglot",
        env_name = "test-verbose-env",
        verbose = FALSE
      ) |>
        testthat::expect_no_message()
    }
  )
})
