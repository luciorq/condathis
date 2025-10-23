testthat::test_that("Parse verbose strategy", {
  testthat::expect_equal(
    parse_strategy_verbose(FALSE),
    list(
      cmd = FALSE,
      output = FALSE,
      quiet_flag = "--quiet",
      internal_verbose = "silent",
      spinner_flag = FALSE,
      strategy = "silent"
    )
  )
  testthat::expect_equal(
    parse_strategy_verbose("silent"),
    list(
      cmd = FALSE,
      output = FALSE,
      quiet_flag = "--quiet",
      internal_verbose = "silent",
      spinner_flag = FALSE,
      strategy = "silent"
    )
  )
  testthat::expect_equal(
    parse_strategy_verbose("cmd"),
    list(
      cmd = TRUE,
      output = FALSE,
      quiet_flag = "--quiet",
      internal_verbose = "spinner",
      spinner_flag = rlang::is_interactive(),
      strategy = "cmd"
    )
  )
  testthat::expect_equal(
    parse_strategy_verbose("output"),
    list(
      cmd = FALSE,
      output = TRUE,
      quiet_flag = "--quiet",
      internal_verbose = "spinner",
      spinner_flag = rlang::is_interactive(),
      strategy = "output"
    )
  )
  testthat::expect_equal(
    parse_strategy_verbose(TRUE),
    list(
      cmd = FALSE,
      output = TRUE,
      quiet_flag = "--quiet",
      internal_verbose = "spinner",
      spinner_flag = rlang::is_interactive(),
      strategy = "output"
    )
  )

  testthat::expect_equal(
    parse_strategy_verbose("full"),
    list(
      cmd = TRUE,
      output = TRUE,
      quiet_flag = NULL,
      internal_verbose = "full",
      spinner_flag = rlang::is_interactive(),
      strategy = "full"
    )
  )

  testthat::expect_error(
    parse_strategy_verbose("TRUE"),
    class = "rlang_error"
  )

  testthat::expect_error(
    parse_strategy_verbose(verbose = c(TRUE, "silent")),
    class = "rlang_error"
  )

  testthat::expect_error(
    parse_strategy_verbose(verbose = c("silent", "full")),
    class = "rlang_error"
  )

  testthat::expect_error(
    parse_strategy_verbose(verbose = c("output", "full")),
    class = "rlang_error"
  )

  testthat::expect_error(
    parse_strategy_verbose(verbose = c(TRUE, FALSE)),
    class = "rlang_error"
  )

  testthat::expect_error(
    parse_strategy_verbose(verbose = c(TRUE, TRUE, FALSE)),
    class = "rlang_error"
  )

  testthat::expect_error(
    parse_strategy_verbose(verbose = list()),
    class = "rlang_error"
  )

  testthat::expect_error(
    parse_strategy_verbose(verbose = list(1)),
    class = "rlang_error"
  )
  testthat::expect_error(
    parse_strategy_verbose(verbose = list(a = "silent")),
    class = "rlang_error"
  )

  testthat::expect_equal(
    parse_strategy_verbose(
      verbose = list(
        cmd = TRUE,
        output = TRUE,
        quiet_flag = NULL,
        internal_verbose = "full",
        spinner_flag = TRUE
      )
    ),
    list(
      cmd = TRUE,
      output = TRUE,
      quiet_flag = NULL,
      internal_verbose = "full",
      spinner_flag = TRUE
    )
  )
  testthat::expect_equal(
    parse_strategy_verbose(
      verbose = list(internal_verbose = "NOT_A_STRATEGY")
    ),
    list(internal_verbose = "NOT_A_STRATEGY")
  )
})
