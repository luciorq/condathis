# create_env(env_name = "condathis-test-env", verbose = FALSE)

test_that("Output redirection to file", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  create_env(env_name = "condathis-test-env", verbose = "silent")
  temp_output_file <- fs::file_temp("test_output", ext = "txt")
  px_res <- run(
    "ls", "-lah",
    env_name = "condathis-test-env",
    verbose = FALSE,
    stdout = temp_output_file
  )
  testthat::expect_equal(
    object = px_res$status,
    expected = 0
  )
  testthat::expect_true(
    fs::file_exists(temp_output_file)
  )
  testthat::expect_equal(
    px_res$stdout,
    NULL
  )
  fs::file_delete(temp_output_file)
  # })

  # test_that("Internal output", {
  px_res <- run(
    "echo", "Hello World!",
    env_name = "condathis-test-env",
    verbose = FALSE,
    stdout = "|"
  )
  testthat::expect_equal(
    object = px_res$status,
    expected = 0
  )
  testthat::expect_true(
    object = stringr::str_detect(px_res$stdout, "Hello World!"),
  )
  # })

  # test_that("Error/warning redirection to file", {
  temp_output_file <- fs::file_temp("test_stderr", ext = "txt")
  px_res <- run(
    "ls", "-lah", "MissingFILE",
    env_name = "condathis-test-env",
    verbose = FALSE,
    stderr = temp_output_file,
    error = "continue"
  )
  testthat::expect_true(
    object = px_res$status != 0L,
  )
  testthat::expect_true(
    fs::file_exists(temp_output_file)
  )
  testthat::expect_equal(
    px_res$stderr,
    NULL
  )
  fs::file_delete(temp_output_file)
  remove_env(env_name = "condathis-test-env", verbose = FALSE)
})

# remove_env(env_name = "condathis-test-env", verbose = FALSE)
