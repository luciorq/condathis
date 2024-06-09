# tests/testthat/test-get_sys_arch.R
library(testthat)

# Mocking `Sys.info()` to return specific values
mock_sys_info <- function(os, machine) {
  list(sysname = os, machine = machine)
}

test_that("`get_sys_arch()` returns correct OS and CPU architecture", {
  # Mock Sys.info() for different scenarios
  testthat::local_mocked_bindings(
    Sys.info = function() mock_sys_info("Linux", "x86_64"), .package = "base"
  )
  expect_equal(get_sys_arch(), "Linux-x86_64")

  testthat::local_mocked_bindings(
    Sys.info = function() mock_sys_info("Windows", "amd64"), .package = "base"
  )
  expect_equal(get_sys_arch(), "Windows-amd64")

  testthat::local_mocked_bindings(
    Sys.info = function() mock_sys_info("Darwin", "arm64"), .package = "base"
  )
  expect_equal(get_sys_arch(), "Darwin-arm64")
})
