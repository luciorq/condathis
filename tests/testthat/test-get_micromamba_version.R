testthat::test_that("get_micromamba_version errors when the binary path does not exist", {
  testthat::expect_error(
    get_micromamba_version(
      umamba_path = "/definitely/does/not/exist/micromamba"
    ),
    class = "condathis_umamba_bin_path_not_executable"
  )
})

testthat::test_that("get_micromamba_version errors when no version can be parsed from output", {
  fake_bin <- withr::local_tempfile()
  fs::file_touch(fake_bin)

  testthat::local_mocked_bindings(
    run = function(...) {
      list(status = 0L, stdout = "no version here", stderr = "")
    },
    .package = "processx"
  )

  testthat::expect_error(
    get_micromamba_version(umamba_path = fake_bin),
    class = "condathis_umamba_version_not_detected"
  )
})
