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


test_that("Run with unexpected error argument", {
  testthat::expect_error(
    object = {
      run("R", error = "Drawing")
    },
    class = "rlang_error"
  )
})

test_that("Run with unexpected error argument", {
  testthat::expect_error(
    object = {
      run("R", error = "co")
    },
    class = "rlang_error"
  )
})

test_that("Run with NULL cmd", {
  cnd_res <- rlang::catch_cnd(
    expr = {
      run(cmd = NULL)
    }
  )
  testthat::expect_s3_class(cnd_res, "condathis_run_null_cmd")

  testthat::expect_error(
    object = {
      run(NULL)
    },
    class = "condathis_run_null_cmd"
  )
})


test_that("Run empty cmd", {
  cnd_res <- rlang::catch_cnd(
    expr = {
      run()
    }
  )
  testthat::expect_s3_class(cnd_res, "rlang_error")

  testthat::expect_error(
    object = {
      run(NULL)
    },
    class = "condathis_run_null_cmd"
  )
})
