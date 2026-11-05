# Regression tests for the download timeout.
#
# `curl::new_handle(timeout = Inf)` throws "Invalid or unsupported value",
# and `utils::download.file()` warns "NAs introduced by coercion to integer
# range" under `options(timeout = Inf)`. download_micromamba_file() turns
# both into `FALSE`, so `install_micromamba(timeout_limit = Inf)`, or
# `options(timeout = Inf)`, made every download fail at once, and the
# install aborted with a misleading "network issues or checksum" error.
#
# The downloads here read `file://` URLs, so no network is needed.

# The `file://` URL of a local file.
file_url <- function(path) {
  abs_path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  # A Windows path starts with a drive letter, not a slash.
  if (isFALSE(startsWith(abs_path, "/"))) {
    abs_path <- paste0("/", abs_path)
  }
  return(paste0("file://", utils::URLencode(abs_path)))
}

# A `file://` URL for a local file with `content`.
local_file_url <- function(content, .local_envir = parent.frame()) {
  path <- withr::local_tempfile(fileext = ".txt", .local_envir = .local_envir)
  writeLines(content, path)
  return(file_url(path))
}

testthat::test_that("max_download_timeout_secs() is the INT_MAX / 1000 limit of libcurl", {
  # libcurl before 8.15.0 rejects CURLOPT_TIMEOUT above INT_MAX / 1000.
  testthat::expect_identical(max_download_timeout_secs(), 2147483L)
  # R's download.file() multiplies the option by 1000 in a C long, which
  # is 32 bits on Windows. The limit must not overflow it.
  testthat::expect_true(1000 * max_download_timeout_secs() <= 2^31 - 1)
})

testthat::test_that("curl_timeout_options() maps no limit to curl's 0", {
  testthat::expect_identical(
    curl_timeout_options(Inf),
    list(timeout = 0L, connecttimeout = 60L)
  )
  testthat::expect_identical(
    curl_timeout_options(0),
    list(timeout = 0L, connecttimeout = 60L)
  )
  testthat::expect_identical(
    curl_timeout_options(3600),
    list(timeout = 3600L, connecttimeout = 60L)
  )
  testthat::expect_identical(
    curl_timeout_options(10),
    list(timeout = 10L, connecttimeout = 10L)
  )
  # A limit below one second is not rounded down to 0, no limit.
  testthat::expect_identical(
    curl_timeout_options(0.5),
    list(timeout = 1L, connecttimeout = 1L)
  )
})

testthat::test_that("curl_timeout_options() lowers a large finite limit to what libcurl accepts", {
  # Regression: values up to .Machine$integer.max were passed to curl, but
  # libcurl before 8.15.0 (bundled by curl on Windows and macOS) rejects
  # more than 2147483 seconds, so install_micromamba(timeout_limit = 2592000)
  # failed every download.
  max_secs <- max_download_timeout_secs()
  testthat::expect_identical(
    curl_timeout_options(max_secs),
    list(timeout = max_secs, connecttimeout = 60L)
  )
  for (secs in list(2147484, 2592000, 1e7, .Machine$integer.max, 1e12)) {
    testthat::expect_identical(
      curl_timeout_options(secs),
      list(timeout = max_secs, connecttimeout = 60L),
      label = format(secs)
    )
  }
})

testthat::test_that("curl accepts the handle options for every valid timeout", {
  testthat::skip_if_not_installed("curl", minimum_version = "5.0.0")
  values <- list(
    Inf,
    0,
    0.5,
    10,
    3600,
    2147483,
    2147484,
    2592000,
    1e7,
    .Machine$integer.max,
    1e12
  )
  for (secs in values) {
    testthat::expect_no_error(
      do.call(curl::new_handle, curl_timeout_options(secs)),
      message = format(secs)
    )
  }
})

testthat::test_that("r_download_timeout() gives download.file() a finite integer", {
  max_secs <- max_download_timeout_secs()
  testthat::expect_identical(r_download_timeout(Inf), max_secs)
  testthat::expect_identical(r_download_timeout(0), max_secs)
  testthat::expect_identical(r_download_timeout(3600), 3600L)
  testthat::expect_identical(r_download_timeout(0.5), 1L)
  testthat::expect_identical(r_download_timeout(max_secs), max_secs)
  # Regression: a limit above INT_MAX / 1000 overflowed the C long that R
  # multiplies the option by 1000 in on Windows.
  for (secs in list(2147484, 2592000, .Machine$integer.max, 1e12)) {
    testthat::expect_identical(
      r_download_timeout(secs),
      max_secs,
      label = format(secs)
    )
  }
  # R reads the option as an integer without a warning.
  for (secs in c(Inf, 0, 1e12, 3600)) {
    testthat::expect_no_warning(as.integer(r_download_timeout(secs)))
  }
})

testthat::test_that("download_timeout_secs() uses the larger of the limit and the session option", {
  testthat::expect_identical(download_timeout_secs(3600, 60), 3600)
  testthat::expect_identical(download_timeout_secs(10, 600), 600)
  testthat::expect_identical(download_timeout_secs(3600, Inf), Inf)
  testthat::expect_identical(download_timeout_secs(Inf, 60), Inf)
  testthat::expect_identical(download_timeout_secs(0, 60), 60)
  # Base R accepts any value in options(). Invalid ones are ignored, so
  # max() does not return a character string or NA.
  for (bad in list(NULL, NA, NA_real_, -1, "a", c(1, 2), TRUE)) {
    testthat::expect_identical(download_timeout_secs(3600, bad), 3600)
  }
})

testthat::test_that("download_micromamba_file() works with timeout_limit = Inf through curl", {
  testthat::skip_if_not_installed("curl", minimum_version = "5.0.0")
  url <- local_file_url("downloaded")
  destfile <- withr::local_tempfile()
  testthat::local_mocked_bindings(use_curl_download = function() TRUE)

  testthat::expect_true(
    download_micromamba_file(
      url = url,
      destfile = destfile,
      timeout_limit = Inf
    )
  )
  testthat::expect_identical(readLines(destfile), "downloaded")

  # The same with a session timeout of Inf.
  fs::file_delete(destfile)
  withr::local_options(timeout = Inf)
  testthat::expect_true(
    download_micromamba_file(url = url, destfile = destfile)
  )
  testthat::expect_identical(readLines(destfile), "downloaded")
})

# Regression: 30 days (2592000 s) passed the timeout_limit check, but
# libcurl before 8.15.0 rejected it, so every mirror failed.
expect_large_timeout_downloads <- function(method = "auto") {
  url <- local_file_url("downloaded")
  destfile <- withr::local_tempfile()
  for (secs in list(2592000, .Machine$integer.max)) {
    if (fs::file_exists(destfile)) {
      fs::file_delete(destfile)
    }
    testthat::expect_true(
      download_micromamba_file(
        url = url,
        destfile = destfile,
        timeout_limit = secs,
        method = method
      ),
      label = format(secs)
    )
    testthat::expect_identical(readLines(destfile), "downloaded")
  }
  # The same with the session option.
  fs::file_delete(destfile)
  withr::local_options(timeout = .Machine$integer.max)
  testthat::expect_true(
    download_micromamba_file(url = url, destfile = destfile, method = method)
  )
  testthat::expect_identical(readLines(destfile), "downloaded")
  return(invisible(NULL))
}

testthat::test_that("download_micromamba_file() works with a timeout_limit above the libcurl limit through curl", {
  testthat::skip_if_not_installed("curl", minimum_version = "5.0.0")
  testthat::local_mocked_bindings(use_curl_download = function() TRUE)
  expect_large_timeout_downloads()
})

testthat::test_that("download_micromamba_file() works with a timeout_limit above the libcurl limit through download.file()", {
  testthat::local_mocked_bindings(use_curl_download = function() FALSE)
  expect_large_timeout_downloads(method = "libcurl")
})

testthat::test_that("download_micromamba_file() works with timeout_limit = Inf through download.file()", {
  url <- local_file_url("downloaded")
  destfile <- withr::local_tempfile()
  testthat::local_mocked_bindings(use_curl_download = function() FALSE)

  testthat::expect_true(
    download_micromamba_file(
      url = url,
      destfile = destfile,
      timeout_limit = Inf,
      method = "libcurl"
    )
  )
  testthat::expect_identical(readLines(destfile), "downloaded")

  fs::file_delete(destfile)
  withr::local_options(timeout = Inf)
  testthat::expect_true(
    download_micromamba_file(url = url, destfile = destfile, method = "libcurl")
  )
  testthat::expect_identical(readLines(destfile), "downloaded")
  # The session option is restored.
  testthat::expect_identical(getOption("timeout"), Inf)
})

testthat::test_that("install_micromamba() accepts timeout = Inf", {
  # End to end with local mirrors: the real download code runs, with no
  # network.
  testthat::skip_if_not_installed("curl", minimum_version = "5.0.0")
  condathis::with_sandbox_dir({
    bin_path <- micromamba_bin_path()
    rel_path <- fs::path_rel(
      bin_path,
      fs::path(install_dir_for_backend(micromamba_backend()), "micromamba")
    )
    src <- withr::local_tempdir()
    fs::dir_create(fs::path_dir(fs::path(src, rel_path)))
    writeLines("working micromamba", fs::path(src, rel_path))
    archive <- withr::local_tempfile(fileext = ".tar.bz2")
    top_dir <- strsplit(as.character(rel_path), "/", fixed = TRUE)[[1L]][1L]
    withr::with_dir(src, {
      utils::tar(
        archive,
        files = top_dir,
        compression = "bzip2",
        tar = "internal"
      )
    })
    archive_url <- file_url(archive)
    testthat::local_mocked_bindings(
      get_micromamba_urls = function(...) {
        return(list(
          compressed = archive_url,
          uncompressed = character(0L),
          sha256 = character(0L)
        ))
      },
      candidate_micromamba_runs = function(path) TRUE,
      verify_micromamba_checksum = function(...) NA
    )

    testthat::expect_no_error(
      install_micromamba(force = TRUE, timeout = Inf, verbose = "silent")
    )
    testthat::expect_identical(readLines(bin_path), "working micromamba")

    fs::file_delete(bin_path)
    withr::local_options(timeout = Inf)
    testthat::expect_no_error(
      install_micromamba(force = TRUE, verbose = "silent")
    )
    testthat::expect_identical(readLines(bin_path), "working micromamba")
  })
})

testthat::test_that("install_micromamba() refuses an invalid timeout", {
  testthat::local_mocked_bindings(
    download_micromamba_file = function(...) {
      stop("no download may start for an invalid timeout")
    }
  )
  condathis::with_sandbox_dir({
    for (bad in list(-1, -Inf, NA, NA_real_, "60", c(1, 2), NULL, TRUE)) {
      cnd <- testthat::expect_error(
        install_micromamba(force = TRUE, timeout = bad),
        class = "condathis_install_micromamba_invalid_timeout"
      )
      # The old class is kept until 1.0 (decision D2).
      testthat::expect_identical(
        class(cnd)[1:5],
        c(
          "condathis_install_micromamba_invalid_timeout",
          "condathis_install_micromamba_invalid_timeout_limit",
          "condathis_invalid_timeout",
          "condathis_invalid_arg",
          "condathis_error"
        )
      )
    }
    # The deprecated alias is checked the same way.
    for (bad in list(-1, "60", NA)) {
      testthat::expect_error(
        suppressWarnings(install_micromamba(force = TRUE, timeout_limit = bad)),
        class = "condathis_install_micromamba_invalid_timeout_limit"
      )
    }
    testthat::expect_false(fs::dir_exists(get_condathis_path()))
  })
  for (good in list(Inf, 0, 3600L)) {
    testthat::expect_no_error(
      validate_timeout_arg(good, class = "condathis_test_invalid_timeout")
    )
  }
})
