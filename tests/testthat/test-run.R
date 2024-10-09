test_that("Run with partial match argument", {
  testthat::expect_error(
    object = {
      run("R", method = "nat")
    },
    class = "rlang_error"
  )
})


test_that("Run with missing argument", {
  testthat::expect_error(
    object = {
      run("R", method = "Drawing")
    },
    class = "rlang_error"
  )
})
