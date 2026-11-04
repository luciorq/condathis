# tests/testthat/test-get_sys_arch.R
# library(testthat)

# Mocking `Sys.info()` to return specific values
mock_sys_info <- function(os, machine) {
  return(list(sysname = os, machine = machine))
}

testthat::test_that("`get_sys_arch()` returns correct OS and CPU architecture", {
  # Mock Sys.info() for different scenarios
  testthat::local_mocked_bindings(
    Sys.info = function() mock_sys_info("Linux", "x86_64"),
    .package = "base"
  )
  testthat::expect_equal(get_sys_arch(), "Linux-x86_64")

  testthat::local_mocked_bindings(
    Sys.info = function() mock_sys_info("Windows", "amd64"),
    .package = "base"
  )
  testthat::expect_equal(get_sys_arch(), "Windows-amd64")

  testthat::local_mocked_bindings(
    Sys.info = function() mock_sys_info("Darwin", "arm64"),
    .package = "base"
  )
  testthat::expect_equal(get_sys_arch(), "Darwin-arm64")
})

testthat::test_that("is_windows()/is_macos()/is_linux() agree with get_sys_arch(), single source of truth", {
  testthat::local_mocked_bindings(
    Sys.info = function() mock_sys_info("Linux", "x86_64"),
    .package = "base"
  )
  testthat::expect_false(is_windows())
  testthat::expect_false(is_macos())
  testthat::expect_true(is_linux())

  testthat::local_mocked_bindings(
    Sys.info = function() mock_sys_info("Windows", "x86_64"),
    .package = "base"
  )
  testthat::expect_true(is_windows())
  testthat::expect_false(is_macos())
  testthat::expect_false(is_linux())

  testthat::local_mocked_bindings(
    Sys.info = function() mock_sys_info("Darwin", "arm64"),
    .package = "base"
  )
  testthat::expect_false(is_windows())
  testthat::expect_true(is_macos())
  testthat::expect_false(is_linux())
})

testthat::test_that("processx_linux_pdeathsig() passes the value on Linux only", {
  # processx warns about a `linux_pdeathsig` other than FALSE on other
  # platforms, where condathis ignores the option silently.
  testthat::expect_true(processx_linux_pdeathsig(TRUE, on_linux = TRUE))
  testthat::expect_false(processx_linux_pdeathsig(FALSE, on_linux = TRUE))
  testthat::expect_false(processx_linux_pdeathsig(TRUE, on_linux = FALSE))
  testthat::expect_false(processx_linux_pdeathsig(FALSE, on_linux = FALSE))

  testthat::expect_identical(
    processx_linux_pdeathsig(TRUE),
    identical(Sys.info()[["sysname"]], "Linux")
  )
  testthat::expect_false(processx_linux_pdeathsig(FALSE))

  testthat::local_mocked_bindings(
    Sys.info = function() mock_sys_info("Darwin", "arm64"),
    .package = "base"
  )
  testthat::expect_false(processx_linux_pdeathsig(TRUE))
  testthat::local_mocked_bindings(
    Sys.info = function() mock_sys_info("Windows", "x86-64"),
    .package = "base"
  )
  testthat::expect_false(processx_linux_pdeathsig(TRUE))
  testthat::local_mocked_bindings(
    Sys.info = function() mock_sys_info("Linux", "aarch64"),
    .package = "base"
  )
  testthat::expect_true(processx_linux_pdeathsig(TRUE))
})

testthat::test_that("a native ARM64 R on Windows is Windows-aarch64, an x64 R is not", {
  # R on Windows reports "aarch64" for a native ARM64 build and "x86-64"
  # for an x64 build, also when that build runs on an ARM64 PC.
  testthat::local_mocked_bindings(
    Sys.info = function() mock_sys_info("Windows", "aarch64"),
    .package = "base"
  )
  testthat::expect_identical(get_sys_arch(), "Windows-aarch64")
  testthat::expect_true(is_windows())
  testthat::expect_true(is_windows_arm64())

  testthat::local_mocked_bindings(
    Sys.info = function() mock_sys_info("Windows", "x86-64"),
    .package = "base"
  )
  testthat::expect_identical(get_sys_arch(), "Windows-x86-64")
  testthat::expect_true(is_windows())
  testthat::expect_false(is_windows_arm64())

  testthat::expect_true(is_windows_arm64("Windows-arm64"))
  for (sys_arch in c("Linux-aarch64", "Darwin-arm64", "Windows-x86_64")) {
    testthat::expect_false(is_windows_arm64(sys_arch), info = sys_arch)
  }
  testthat::expect_false(is_windows_arm64(c("Windows-aarch64", "x")))
})
