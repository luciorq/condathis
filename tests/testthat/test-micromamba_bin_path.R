test_that("Micromamba install path", {
  umamba_bin_path <- micromamba_bin_path()
  expect_true(stringr::str_detect(umamba_bin_path, "micromamba"))
})

testthat::test_that("condathis looks for the binary where the Windows archives have it", {
  # The win-64 and the win-arm64 archives of micromamba 2.10.0-0 both hold
  # the binary at `Library/bin/micromamba.exe` (checked 2026-10-27).
  condathis::with_sandbox_dir({
    untar_dir <- fs::path(
      install_dir_for_backend(micromamba_backend()),
      "micromamba"
    )
    bin_path <- testthat::with_mocked_bindings(
      micromamba_bin_path(),
      is_windows = function() TRUE
    )
    testthat::expect_identical(
      as.character(fs::path_rel(bin_path, untar_dir)),
      "Library/bin/micromamba.exe"
    )
  })
})
