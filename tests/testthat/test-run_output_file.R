library(testthat)

create_env(env_name = "condathis-test-env", verbose = FALSE)

test_that("Output redirection to file", {
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
})

test_that("Internal output", {
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
  testthat::expect_equal(
    object = px_res$stdout,
    expected = "Hello World!\n"
  )
})

remove_env(env_name = "condathis-test-env", verbose = FALSE)
