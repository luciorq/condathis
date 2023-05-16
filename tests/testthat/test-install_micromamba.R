test_that("Micromamba installation", {
  umamba_bin_path <- install_micromamba()

  expect_true(fs::file_exists(umamba_bin_path))
})
