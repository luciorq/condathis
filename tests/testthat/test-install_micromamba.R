test_that("Micromamba installation", {
  withr::local_path(new = list(), action = "replace")
  umamba_bin_path <- install_micromamba(force = FALSE)
  expect_true(fs::file_exists(umamba_bin_path))
})

test_that("Micromamba already installed", {
  umamba_bin_path <- install_micromamba(force = FALSE)
  expect_true(fs::file_exists(umamba_bin_path))
})
