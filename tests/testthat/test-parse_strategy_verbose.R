testthat::test_that("Parse verbose strategy", {
  testthat::expect_equal(
    parse_strategy_verbose(FALSE),
    list(
      cmd = FALSE,
      output = FALSE,
      quiet_flag = c("--log-level", "error"),
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
      quiet_flag = c("--log-level", "error"),
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
      quiet_flag = c("--log-level", "error"),
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
      quiet_flag = c("--log-level", "error"),
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
      quiet_flag = c("--log-level", "error"),
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

testthat::test_that("parse_strategy_verbose() raises a classed error that names the caller", {
  # Regression test: an invalid verbose raised a plain rlang error, and
  # caller_env(n = 2L) named the caller of the caller (or NULL).
  f <- function(verbose) {
    parse_strategy_verbose(verbose = verbose)
  }
  for (bad in list("bogus", "TRUE", NA, 1, c("silent", "full"), list(1))) {
    cnd <- rlang::catch_cnd(f(bad), classes = "error")
    testthat::expect_identical(
      class(cnd),
      c(
        "condathis_invalid_verbose",
        "condathis_invalid_arg",
        "condathis_error",
        "rlang_error",
        "error",
        "condition"
      ),
      info = deparse(bad)
    )
    testthat::expect_identical(conditionCall(cnd), quote(f(bad)))
  }
})

testthat::test_that("parse_strategy_verbose() takes a default in any order", {
  # remove_env() declared its choices with "silent" first.
  testthat::expect_identical(
    parse_strategy_verbose(c(
      "silent",
      "cmd",
      "output",
      "spinner",
      "full"
    ))$strategy,
    "silent"
  )
  testthat::expect_identical(
    parse_strategy_verbose(condathis_verbose_values)$strategy,
    "output"
  )
  testthat::expect_identical(
    condathis_verbose_values,
    c("output", "silent", "cmd", "spinner", "full")
  )
})

testthat::test_that("parse_verbose_arg() rejects a parsed list and maps logicals", {
  # Regression test: any list with `internal_verbose` passed through, so an
  # exported function accepted list(internal_verbose = "x").
  f <- function(verbose) parse_verbose_arg(verbose)
  cnd <- rlang::catch_cnd(f(list(internal_verbose = "x")), classes = "error")
  testthat::expect_s3_class(cnd, "condathis_invalid_verbose")
  testthat::expect_s3_class(cnd, "condathis_invalid_arg")
  testthat::expect_s3_class(cnd, "condathis_error")
  testthat::expect_identical(
    conditionCall(cnd),
    quote(f(list(internal_verbose = "x")))
  )

  testthat::expect_identical(f(TRUE)$strategy, "output")
  testthat::expect_identical(f(FALSE)$strategy, "silent")
  for (value in condathis_verbose_values) {
    res <- f(value)
    testthat::expect_identical(res$strategy, value)
    testthat::expect_true(rlang::is_string(res$strategy))
  }
  testthat::expect_identical(
    f(c("output", "silent", "cmd", "spinner", "full"))$strategy,
    "output"
  )
  cnd <- rlang::catch_cnd(f("bogus"), classes = "error")
  testthat::expect_identical(conditionCall(cnd), quote(f("bogus")))
})
