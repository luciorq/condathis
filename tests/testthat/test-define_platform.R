testthat::test_that("Mocked define_platform", {
  testthat::expect_error(define_platform())


  # define_platform(platform = NA)

  # testthat::expect_error(define_platform(platform = NA))

  # testthat::expect_equal(2 * 2, 4)
})
