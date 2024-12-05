testthat::test_that("Parse verbose strategy", {
  testthat::expect_equal(parse_strategy_verbose(FALSE), list(cmd = FALSE, output = FALSE))
  testthat::expect_equal(parse_strategy_verbose(TRUE), list(cmd = TRUE, output = TRUE))
  testthat::expect_equal(parse_strategy_verbose("silent"), list(cmd = FALSE, output = FALSE))
  testthat::expect_equal(parse_strategy_verbose("cmd"), list(cmd = TRUE, output = FALSE))
  testthat::expect_equal(parse_strategy_verbose("output"), list(cmd = FALSE, output = TRUE))
  testthat::expect_equal(parse_strategy_verbose("full"), list(cmd = TRUE, output = TRUE))
  testthat::expect_error(
    parse_strategy_verbose("TRUE"),
    class = "condathis_error_invalid_verbose"
  )
  testthat::expect_equal(parse_strategy_verbose(strategy = c("silent", " full")), list(cmd = FALSE, output = FALSE))
})
