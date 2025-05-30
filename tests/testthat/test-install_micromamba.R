test_that("Micromamba installation", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()
  withr::local_path(new = list(tempdir()), action = "replace")
  umamba_bin_path <- install_micromamba(force = FALSE, verbose = FALSE)
  testthat::expect_true(fs::file_exists(umamba_bin_path))
})

test_that("Micromamba is already installed", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()
  suppressMessages(
    testthat::expect_message(
      object = {
        umamba_bin_path <- install_micromamba(force = FALSE, verbose = "full")
      },
      regexp = "installed"
    )
  )
  testthat::expect_true(fs::file_exists(umamba_bin_path))
})

test_that("Connection not available", {
  testthat::local_mocked_bindings(check_connection = function(...) {
    return(FALSE)
  })
  testthat::expect_error(
    object = {
      umamba_bin_path <- install_micromamba(force = TRUE, verbose = FALSE)
    },
    class = "condathis_github_not_reachable"
  )
})

testthat::test_that("Install micromamba from scratch", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  if (isTRUE(fs::dir_exists(fs::path(get_install_dir(), "micromamba")))) {
    fs::dir_delete(fs::path(get_install_dir(), "micromamba"))
  }
  testthat::expect_message(
    object = {
      install_micromamba(verbose = "full")
    }
  )
  testthat::expect_true(fs::file_exists(micromamba_bin_path()))

  suppressMessages(
    testthat::expect_message(
      install_micromamba(micromamba_version = "1.5.9-0", verbose = "full"),
      regexp = ".*already.*"
    )
  )
  testthat::expect_message(
    install_micromamba(micromamba_version = "1.5.9-0", verbose = "full"),
    regexp = ".*already.*"
  )

  install_micromamba(micromamba_version = "1.5.9-0", verbose = "silent")

  suppressMessages(
    testthat::expect_error(
      object = {
        suppressWarnings(
          install_micromamba(
            micromamba_version = "1.5.9",
            force = TRUE
          )
        )
      },
      regexp = ".*cannot.*open.*"
    )
  )
})
