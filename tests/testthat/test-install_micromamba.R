test_that("Micromamba installation", {
  withr::local_path(new = list(), action = "replace")
  umamba_bin_path <- install_micromamba(force = FALSE)
  testthat::expect_true(fs::file_exists(umamba_bin_path))
})

test_that("Micromamba already installed", {
  testthat::expect_message(
    object = {
      umamba_bin_path <- install_micromamba(force = FALSE)
    },
    regexp = "installed"
  )
  testthat::expect_true(fs::file_exists(umamba_bin_path))
})

test_that("Connection not available", {
  testthat::local_mocked_bindings(check_connection = function(...) {
    return(FALSE)
  })
  testthat::expect_error(
    object = {
      umamba_bin_path <- install_micromamba(force = TRUE)
    },
    class = "condathis_github_not_reachable"
  )
})
