testthat::test_that("micromamba not on system", {
  withr::with_path(
    new = getwd(),
    code = {
      umamba_sys_path <- micromamba_user_installed()
    },
    action = "replace"
  )
  testthat::expect_true(rlang::is_character(umamba_sys_path))
})
