test_that("Micromamba install path", {
  umamba_bin_path <- micromamba_bin_path()
  expect_true(stringr::str_detect(umamba_bin_path, "micromamba"))
})
