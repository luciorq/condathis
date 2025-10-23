testthat::test_that("parse_output works", {
  res <- list(
    stdout = "line1\nline2\nline3\n",
    stderr = "error1\nerror2\n",
    both = "this\nis\nrandom\ntext\n",
    status = 1L
  )

  testthat::expect_error(
    parse_output(res, stream = "plain"),
    class = "condathis_parse_output_invalid_res"
  )

  parsed_out <- parse_output(res, stream = "stdout")

  testthat::expect_true(rlang::is_character(parsed_out))

  parsed_err <- parse_output(res, stream = "stderr")
  testthat::expect_true(rlang::is_character(parsed_err))

  parsed_both <- parse_output(res, stream = "both")
  testthat::expect_true(rlang::is_character(parsed_both))

  testthat::expect_equal(
    parsed_out,
    c("line1", "line2", "line3")
  )

  testthat::expect_equal(
    parsed_err,
    c("error1", "error2")
  )

  testthat::expect_equal(
    parsed_both,
    c("line1", "line2", "line3", "error1", "error2")
  )

  testthat::expect_equal(
    parse_output(
      "This is line one.\nThis is line two.\nThis is line three.\n",
      stream = "plain"
    ),
    c("This is line one.", "This is line two.", "This is line three.")
  )

  res_empty <- list(
    stdout = "",
    stderr = ""
  )

  res_empty_parsed <- parse_output(res_empty, stream = "both")
  testthat::expect_equal(res_empty_parsed, "")

  testthat::expect_error(
    parse_output(NULL, stream = "stdout"),
    class = "condathis_parse_output_invalid_res"
  )

  testthat::expect_error(
    parse_output(list(1), stream = "stdout"),
    class = "condathis_parse_output_invalid_res"
  )

  testthat::expect_error(
    parse_output(c("invalid", "input"), stream = "stdout"),
    class = "condathis_parse_output_invalid_res"
  )

  testthat::expect_equal(
    parse_output(c("invalid", "input"), stream = "plain"),
    c("invalid", "input")
  )
})
