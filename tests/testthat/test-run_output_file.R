test_that("Output redirection to file", {
  temp_output_file <- fs::file_temp("test_output", ext = "txt")
  px_res <- condathis::run(
    "ls", "-lah",
    echo = FALSE,
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
  px_res <- condathis::run(
    "echo", "Hello World!",
    echo = FALSE,
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
