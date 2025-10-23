testthat::test_that("run - verbose outputs", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  if (env_exists("verbose-true-env")) {
    remove_env("verbose-true-env", verbose = "silent")
  }
  if (env_exists("test-verbose-env")) {
    remove_env("test-verbose-env", verbose = FALSE)
  }

  create_env(NULL, env_name = "test-verbose-env", verbose = "output") |>
    testthat::expect_message(regexp = "Environment .* succesfully created")

  remove_env("test-verbose-env", verbose = "output") |>
    testthat::expect_message(regexp = "Environment .* succesfully removed")

  create_env(NULL, env_name = "test-verbose-env", verbose = "full") |>
    testthat::expect_message(regexp = "Environment .* succesfully created") |>
    testthat::capture_output() |>
    stringr::str_detect("Running ") |>
    testthat::expect_true()

  remove_env("test-verbose-env", verbose = "full") |>
    testthat::expect_message(regexp = "Environment .* succesfully removed") |>
    testthat::capture_output() |>
    stringr::str_detect("Running ") |>
    testthat::expect_true()

  remove_env("test-verbose-fake-env", verbose = TRUE) |>
    testthat::expect_error("does not exist")

  remove_env("test-verbose-fake-env", verbose = "output") |>
    testthat::expect_error("does not exist")

  remove_env("test-verbose-fake-env", verbose = FALSE) |>
    testthat::expect_error("does not exist")

  create_env(NULL, env_name = "test-verbose-env", verbose = FALSE) |>
    testthat::expect_no_message()

  remove_env("test-verbose-env", verbose = FALSE) |>
    testthat::expect_no_message()

  remove_env("test-verbose-env", verbose = FALSE) |>
    testthat::expect_error("does not exist")

  create_env(
    packages = "python=3.8.16",
    env_name = "test-verbose-env",
    verbose = TRUE
  ) |>
    testthat::expect_message(regexp = "Environment .* succesfully created")

  create_env(
    packages = "python=3.8.16",
    env_name = "test-verbose-env",
    verbose = TRUE
  ) |>
    testthat::expect_message(regexp = "already exists")

  create_env(
    packages = "python=3.8.16",
    env_name = "test-verbose-env",
    verbose = "output"
  ) |>
    testthat::expect_message(regexp = "already exists")

  run(
    "python",
    "-c",
    "print('Hello')",
    env_name = "test-verbose-env",
    verbose = "output"
  ) |>
    testthat::expect_no_message() |>
    testthat::expect_output("Hello")

  run(
    "python",
    "-c",
    "print('Hello')",
    env_name = "test-verbose-env",
    verbose = TRUE
  ) |>
    testthat::expect_no_message() |>
    testthat::expect_output("Hello")

  withr::with_options(
    list(
      rlang.intective = FALSE
    ),
    code = {
      run(
        "python",
        "-c",
        "print('Hello')",
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
        "python",
        "-c",
        "print('Hello')",
        env_name = "test-verbose-env",
        verbose = FALSE
      ) |>
        testthat::expect_no_message()
    }
  )
})
