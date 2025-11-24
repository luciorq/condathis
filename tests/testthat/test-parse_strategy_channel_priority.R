testthat::test_that("parse_strategy_channel_priority returns correct arguments for 'disabled'", {
  testthat::expect_equal(
    parse_strategy_channel_priority("disabled"),
    c("--no-channel-priority", "--channel-priority=0")
  )
})

testthat::test_that("parse_strategy_channel_priority returns correct arguments for 'strict'", {
  testthat::expect_equal(
    parse_strategy_channel_priority("strict"),
    c("--strict-channel-priority", "--channel-priority=2")
  )
})

testthat::test_that("parse_strategy_channel_priority returns correct arguments for 'flexible'", {
  testthat::expect_equal(
    parse_strategy_channel_priority("flexible"),
    c("--channel-priority=1")
  )
})

testthat::test_that("parse_strategy_channel_priority throws error for invalid input", {
  testthat::expect_error(
    parse_strategy_channel_priority("invalid_strategy"),
    class = "rlang_error"
  )
})

testthat::test_that("parse_strategy_channel_priority handles vector input correctly", {
  testthat::expect_error(
    parse_strategy_channel_priority(
      channel_priority = c("disabled", "flexible")
    ),
    class = "rlang_error"
  )
})

testthat::test_that("parse_strategy_channel_priority handles non-character input correctly", {
  testthat::expect_error(
    parse_strategy_channel_priority(123),
    class = "rlang_error"
  )
})

testthat::test_that("parse_strategy_channel_priority handles missing input correctly", {
  testthat::expect_equal(
    parse_strategy_channel_priority(),
    c("--no-channel-priority", "--channel-priority=0")
  )
})

testthat::test_that("parse_strategy_channel_priority error caller environment", {
  outer_fun <- function(x) {
    parse_strategy_channel_priority(x)
  }

  cnd_res <- rlang::catch_cnd({
    outer_fun(1)
  })
  testthat::expect_equal(cnd_res$call, base::str2lang("outer_fun(1)"))

  outer_outer_fun <- function(x) {
    outer_fun(x)
  }
  cnd_res <- rlang::catch_cnd({
    outer_outer_fun(1)
  })
  testthat::expect_equal(cnd_res$call, base::str2lang("outer_fun(x)"))
})
