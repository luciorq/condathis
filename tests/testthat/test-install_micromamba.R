testthat::test_that("Micromamba installation", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()
  withr::local_path(new = list(base::tempdir()), action = "replace")
  umamba_bin_path <- install_micromamba(force = FALSE, verbose = FALSE)
  testthat::expect_true(fs::file_exists(umamba_bin_path))
})

testthat::test_that("Micromamba is already installed", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()
  testthat::expect_message(
    object = {
      umamba_bin_path <- install_micromamba(force = FALSE, verbose = "output")
    },
    regexp = "installed"
  )
  testthat::expect_true(fs::file_exists(umamba_bin_path))
})

testthat::test_that("Connection not available", {
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
  captured_output <- testthat::expect_message(
    object = {
      install_micromamba(verbose = "output")
    }
  ) |>
    testthat::capture_output()
  testthat::expect_true(fs::file_exists(micromamba_bin_path()))

  captured_output <- suppressMessages(
    testthat::expect_message(
      install_micromamba(micromamba_version = "1.5.9-0", verbose = "full"),
      regexp = ".*already.*"
    )
  ) |>
    testthat::capture_output()
  captured_output <- testthat::expect_message(
    install_micromamba(micromamba_version = "1.5.9-0", verbose = "output"),
    regexp = ".*already.*"
  ) |>
    testthat::capture_output()

  install_micromamba(micromamba_version = "1.5.9-0", verbose = "silent")

  suppressMessages(
    testthat::expect_error(
      object = {
        suppressWarnings(
          install_micromamba(
            micromamba_version = "0.0.0-0",
            force = TRUE
          )
        )
      }
    )
  )
})

testthat::test_that("Fallback to uncompressed when tar/bzip2 unavailable", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  # Mock can_extract_tar_bz2 to return FALSE, simulating missing tar/bzip2
  testthat::local_mocked_bindings(can_extract_tar_bz2 = function() FALSE)

  if (isTRUE(fs::dir_exists(fs::path(get_install_dir(), "micromamba")))) {
    fs::dir_delete(fs::path(get_install_dir(), "micromamba"))
  }

  captured_output <- suppressMessages(
    suppressWarnings(
      install_micromamba(force = TRUE, verbose = "silent")
    )
  ) |>
    testthat::capture_output()

  testthat::expect_true(fs::file_exists(micromamba_bin_path()))
})

testthat::test_that("Mirror failover works when primary source fails", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  call_count <- 0L
  original_download <- download_micromamba_file

  # Mock download_micromamba_file to fail on the first URL (GitHub)
  # and succeed on subsequent URLs (conda-forge mirror)
  testthat::local_mocked_bindings(
    download_micromamba_file = function(url, destfile, ...) {
      call_count <<- call_count + 1L
      if (call_count == 1L) {
        return(FALSE)
      }
      return(original_download(url = url, destfile = destfile, ...))
    }
  )

  if (isTRUE(fs::dir_exists(fs::path(get_install_dir(), "micromamba")))) {
    fs::dir_delete(fs::path(get_install_dir(), "micromamba"))
  }

  captured_output <- suppressMessages(
    suppressWarnings(
      install_micromamba(force = TRUE, verbose = "silent")
    )
  ) |>
    testthat::capture_output()

  testthat::expect_true(fs::file_exists(micromamba_bin_path()))
  # Verify that multiple download attempts were made (failover happened)
  testthat::expect_gt(call_count, 1L)
})

testthat::test_that("get_micromamba_urls returns correct structure", {
  urls <- get_micromamba_urls(
    sys_arch_str = "linux-64",
    micromamba_version = "2.5.0-2"
  )

  testthat::expect_type(urls, "list")
  testthat::expect_named(
    urls,
    c("compressed", "uncompressed", "sha256", "check_urls")
  )

  # Compressed URLs should include GitHub, micro.mamba.pm, Anaconda, and prefix.dev
  testthat::expect_length(urls$compressed, 4L)
  testthat::expect_true(grepl("github.com", urls$compressed[1L]))
  testthat::expect_true(grepl("micro.mamba.pm", urls$compressed[2L]))
  testthat::expect_true(grepl("anaconda.org", urls$compressed[3L]))
  testthat::expect_true(grepl("prefix.dev", urls$compressed[4L]))

  # Uncompressed URL should be from GitHub only
  testthat::expect_length(urls$uncompressed, 1L)
  testthat::expect_true(grepl("github.com", urls$uncompressed[1L]))

  # SHA256 URL should be from GitHub
  testthat::expect_true(grepl("\\.sha256$", urls$sha256[1L]))

  # Check URLs should include all four mirrors
  testthat::expect_length(urls$check_urls, 4L)
})

testthat::test_that("has_system_tar and has_system_bzip2 return logical", {
  testthat::expect_type(has_system_tar(), "logical")
  testthat::expect_type(has_system_bzip2(), "logical")
  testthat::expect_type(can_extract_tar_bz2(), "logical")
})

testthat::test_that("No warnings when tar is unavailable", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  # Mock can_extract_tar_bz2 to return FALSE
  testthat::local_mocked_bindings(can_extract_tar_bz2 = function() FALSE)

  if (isTRUE(fs::dir_exists(fs::path(get_install_dir(), "micromamba")))) {
    fs::dir_delete(fs::path(get_install_dir(), "micromamba"))
  }

  # This should NOT produce any warnings about tar or bzip2
  captured_output <- testthat::capture_output(
    result <- testthat::expect_no_warning(
      suppressMessages(
        install_micromamba(force = TRUE, verbose = "silent")
      )
    )
  )

  testthat::expect_true(fs::file_exists(micromamba_bin_path()))
})
