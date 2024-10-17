test_that("Micromamba install path", {
  umamba_bin_path <- micromamba_bin_path()
  expect_true(stringr::str_detect(umamba_bin_path, "micromamba"))
})

# Mocking `Sys.info()` to return specific values
mock_sys_info <- function(os, machine) {
  list(sysname = os, machine = machine)
}

test_that("Mocked Micromamba install path", {
  testthat::local_mocked_bindings(
    Sys.info = function() mock_sys_info("Windows", "amd64"), .package = "base"
  )
  # expect_equal(get_sys_arch(), "Windows-amd64")
  umamba_bin_path <- micromamba_bin_path()
  expect_true(stringr::str_detect(umamba_bin_path, "micromamba.exe"))
})

test_that("Mocked Micromamba install path wrong arch", {
  testthat::local_mocked_bindings(
    Sys.info = function() mock_sys_info("unknown", "pp"), .package = "base"
  )
  # expect_equal(get_sys_arch(), "Windows-amd64")
  umamba_bin_path <- micromamba_bin_path()
  expect_true(stringr::str_detect(umamba_bin_path, "micromamba"))
})
