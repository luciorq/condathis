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

testthat::test_that("get_micromamba_version errors on empty output", {
  # Regression test: empty output parsed to character(0), which passed the
  # `NA` check, so the function returned character(0).
  fake_bin <- withr::local_tempfile()
  fs::file_touch(fake_bin)
  for (out in c("", "  \n", "\n\n")) {
    testthat::local_mocked_bindings(
      run = function(...) list(status = 1L, stdout = out, stderr = NULL),
      .package = "processx"
    )
    testthat::expect_error(
      get_micromamba_version(umamba_path = fake_bin),
      class = "condathis_umamba_version_not_detected"
    )
  }
})

testthat::test_that("get_micromamba_version reads a version on a later line", {
  fake_bin <- withr::local_tempfile()
  fs::file_touch(fake_bin)
  testthat::local_mocked_bindings(
    run = function(...) {
      list(status = 0L, stdout = "warning: x\r\n  2.9.0 \r\n", stderr = NULL)
    },
    .package = "processx"
  )
  testthat::expect_identical(
    get_micromamba_version(umamba_path = fake_bin),
    "2.9.0"
  )
})

testthat::test_that("get_micromamba_version reads a two-digit minor version", {
  # micromamba 2.10.0 prints `2.10.0` and a newline for `--version`.
  fake_bin <- withr::local_tempfile()
  fs::file_touch(fake_bin)
  testthat::local_mocked_bindings(
    run = function(...) {
      list(status = 0L, stdout = "2.10.0\n", stderr = NULL)
    },
    .package = "processx"
  )
  testthat::expect_identical(
    get_micromamba_version(umamba_path = fake_bin),
    "2.10.0"
  )
})

testthat::test_that("get_micromamba_version() errors have the renamed classes and the old ones", {
  # Decision D2: condathis_umamba_* became condathis_micromamba_*.
  cnd <- testthat::expect_error(
    get_micromamba_version(
      umamba_path = "/definitely/does/not/exist/micromamba"
    ),
    class = "condathis_micromamba_bin_path_not_executable"
  )
  testthat::expect_identical(
    class(cnd)[1:3],
    c(
      "condathis_micromamba_bin_path_not_executable",
      "condathis_umamba_bin_path_not_executable",
      "condathis_error"
    )
  )

  fake_bin <- withr::local_tempfile()
  fs::file_touch(fake_bin)
  testthat::local_mocked_bindings(
    run = function(...) list(status = 0L, stdout = "no version", stderr = ""),
    .package = "processx"
  )
  cnd <- testthat::expect_error(
    get_micromamba_version(umamba_path = fake_bin),
    class = "condathis_micromamba_version_not_detected"
  )
  testthat::expect_identical(
    class(cnd)[1:3],
    c(
      "condathis_micromamba_version_not_detected",
      "condathis_umamba_version_not_detected",
      "condathis_error"
    )
  )
})
