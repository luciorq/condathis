# Regression tests for the mirror loop of install_micromamba().
#
# The extraction, run and checksum checks ran after
# try_download_from_mirrors() had returned on the first download that was
# not empty. A bad file from one mirror (an HTML error page served with
# status 200, a truncated archive, or a binary that failed the checks)
# ended the whole strategy, and the remaining mirrors were never tried.
#
# Downloads are mocked, so these tests need no network.

# A `.tar.bz2` archive with `content` at `rel_path`, written with R's
# internal tar so the test needs no system tools.
local_mirror_archive <- function(
  rel_path,
  content,
  .local_envir = parent.frame()
) {
  src <- withr::local_tempdir(.local_envir = .local_envir)
  bin_file <- fs::path(src, rel_path)
  fs::dir_create(fs::path_dir(bin_file))
  writeLines(content, bin_file)
  archive <- withr::local_tempfile(
    fileext = ".tar.bz2",
    .local_envir = .local_envir
  )
  top_dir <- strsplit(as.character(rel_path), "/", fixed = TRUE)[[1L]][1L]
  withr::with_dir(src, {
    utils::tar(
      archive,
      files = top_dir,
      compression = "bzip2",
      tar = "internal"
    )
  })
  return(archive)
}

# A plain file with `content`.
local_mirror_file <- function(content, .local_envir = parent.frame()) {
  path <- withr::local_tempfile(.local_envir = .local_envir)
  writeLines(content, path)
  return(path)
}

# The first half of `path`, as a truncated download would leave it.
local_truncated_copy <- function(path, .local_envir = parent.frame()) {
  bytes <- readBin(path, what = "raw", n = file.size(path))
  out <- withr::local_tempfile(
    fileext = ".tar.bz2",
    .local_envir = .local_envir
  )
  writeBin(bytes[seq_len(length(bytes) %/% 2L)], out)
  return(out)
}

# Replaces the network download. `serve` maps a URL to the file it serves,
# or to `NULL` for a failed download. Returns an environment that records
# the requested URLs.
local_mirror_downloads <- function(serve, .local_envir = parent.frame()) {
  log <- new.env(parent = emptyenv())
  log$urls <- character(0L)
  testthat::local_mocked_bindings(
    download_micromamba_file = function(url, destfile, ...) {
      log$urls <- c(log$urls, url)
      src <- serve(url)
      if (is.null(src)) {
        return(FALSE)
      }
      fs::file_copy(src, destfile, overwrite = TRUE)
      return(TRUE)
    },
    .env = .local_envir
  )
  return(log)
}

read_first_line <- function(path) {
  return(tryCatch(
    readLines(path, n = 1L, warn = FALSE),
    error = function(e) NA_character_
  ))
}

# A binary "runs" when it is the working fake, and its checksum matches
# unless it is the tampered fake.
local_mirror_checks <- function(.local_envir = parent.frame()) {
  testthat::local_mocked_bindings(
    candidate_micromamba_runs = function(path) {
      line <- read_first_line(path)
      return(isTRUE(line %in% c("working micromamba", "tampered micromamba")))
    },
    verify_micromamba_checksum = function(bin_path, ...) {
      return(isFALSE(identical(
        read_first_line(bin_path),
        "tampered micromamba"
      )))
    },
    .env = .local_envir
  )
  return(invisible(NULL))
}

mirror_urls <- c(
  "https://mirror-1.invalid/micromamba.tar.bz2",
  "https://mirror-2.invalid/micromamba.tar.bz2",
  "https://mirror-3.invalid/micromamba.tar.bz2"
)

testthat::test_that("download_compressed_and_extract() moves on from a mirror with a bad file", {
  rel_path <- fs::path("bin", "micromamba")
  good_archive <- local_mirror_archive(rel_path, "working micromamba")
  bad_files <- list(
    `HTML error page with status 200` = local_mirror_file(
      "<html>404 page served with status 200</html>"
    ),
    `truncated archive` = local_truncated_copy(good_archive),
    `binary that does not run` = local_mirror_archive(
      rel_path,
      "<html>not a binary</html>"
    ),
    `binary that fails the checksum` = local_mirror_archive(
      rel_path,
      "tampered micromamba"
    ),
    `archive without the binary` = local_mirror_archive(
      fs::path("other", "file"),
      "working micromamba"
    )
  )
  local_mirror_checks()

  for (bad_name in names(bad_files)) {
    root <- withr::local_tempdir()
    untar_dir <- fs::path(root, "micromamba")
    bin_path <- fs::path(untar_dir, rel_path)
    fs::dir_create(fs::path_dir(bin_path))
    writeLines("old working binary", bin_path)

    bad_file <- bad_files[[bad_name]]
    log <- local_mirror_downloads(function(url) {
      if (identical(url, mirror_urls[[1L]])) {
        return(bad_file)
      }
      return(good_archive)
    })
    result <- download_compressed_and_extract(
      compressed_urls = mirror_urls,
      output_dir = root,
      untar_dir = untar_dir,
      umamba_bin_path = bin_path,
      timeout_limit = 1,
      download_method = "auto",
      dl_quiet_flag = TRUE
    )

    testthat::expect_true(result, label = bad_name)
    testthat::expect_identical(
      readLines(bin_path),
      "working micromamba",
      label = bad_name
    )
    # Mirror 2 was tried after the bad file, and mirror 3 was not needed.
    testthat::expect_identical(log$urls, mirror_urls[1:2], label = bad_name)
    testthat::expect_length(
      fs::dir_ls(root, glob = "*micromamba-extract-*"),
      0L
    )
    testthat::expect_length(fs::dir_ls(root, glob = "*micromamba-dl-*"), 0L)
  }
})

testthat::test_that("download_compressed_and_extract() fails only after every mirror failed", {
  root <- withr::local_tempdir()
  untar_dir <- fs::path(root, "micromamba")
  bin_path <- fs::path(untar_dir, "bin", "micromamba")
  fs::dir_create(fs::path_dir(bin_path))
  writeLines("old working binary", bin_path)
  html_page <- local_mirror_file("<html>rate limited</html>")
  local_mirror_checks()
  log <- local_mirror_downloads(function(url) html_page)

  result <- download_compressed_and_extract(
    compressed_urls = mirror_urls,
    output_dir = root,
    untar_dir = untar_dir,
    umamba_bin_path = bin_path,
    timeout_limit = 1,
    download_method = "auto",
    dl_quiet_flag = TRUE
  )

  testthat::expect_false(result)
  testthat::expect_identical(log$urls, mirror_urls)
  testthat::expect_identical(readLines(bin_path), "old working binary")
  testthat::expect_length(fs::dir_ls(root, glob = "*micromamba-extract-*"), 0L)
  testthat::expect_length(fs::dir_ls(root, glob = "*micromamba-dl-*"), 0L)
})

testthat::test_that("download_uncompressed_binary() moves on from a mirror with a bad file", {
  bin_dir <- withr::local_tempdir()
  bin_path <- fs::path(bin_dir, "micromamba")
  writeLines("old working binary", bin_path)
  bad_binary <- local_mirror_file("<html>not a binary</html>")
  tampered_binary <- local_mirror_file("tampered micromamba")
  good_binary <- local_mirror_file("working micromamba")
  local_mirror_checks()

  for (bad_file in list(bad_binary, tampered_binary)) {
    log <- local_mirror_downloads(function(url) {
      if (identical(url, mirror_urls[[1L]])) {
        return(bad_file)
      }
      return(good_binary)
    })
    writeLines("old working binary", bin_path)

    result <- download_uncompressed_binary(
      uncompressed_urls = mirror_urls,
      umamba_bin_path = bin_path,
      timeout_limit = 1,
      download_method = "auto",
      dl_quiet_flag = TRUE
    )

    testthat::expect_true(result)
    testthat::expect_identical(readLines(bin_path), "working micromamba")
    testthat::expect_identical(log$urls, mirror_urls[1:2])
    testthat::expect_length(fs::dir_ls(bin_dir, glob = "*micromamba-dl-*"), 0L)
  }
})

testthat::test_that("install_micromamba() installs from a later mirror when the first serves an error page", {
  # End to end, with the real mirror list: the GitHub archive is an HTML
  # page, the Anaconda archive is good. The install must not fall through
  # to the uncompressed GitHub binary, and must not abort.
  condathis::with_sandbox_dir({
    bin_path <- micromamba_bin_path()
    rel_path <- fs::path_rel(
      bin_path,
      fs::path(install_dir_for_backend(micromamba_backend()), "micromamba")
    )
    good_archive <- local_mirror_archive(rel_path, "working micromamba")
    html_page <- local_mirror_file(
      "<html>404 page served with status 200</html>"
    )
    local_mirror_checks()
    log <- local_mirror_downloads(function(url) {
      if (isTRUE(grepl("github\\.com.*\\.tar\\.bz2$", url))) {
        return(html_page)
      }
      if (isTRUE(grepl("anaconda\\.org", url))) {
        return(good_archive)
      }
      return(NULL)
    })

    messages <- character(0L)
    result <- withCallingHandlers(
      install_micromamba(force = TRUE, verbose = "output"),
      message = function(m) {
        messages <<- c(messages, conditionMessage(m))
        invokeRestart("muffleMessage")
      }
    )
    messages <- gsub("[[:space:]]+", " ", paste(messages, collapse = " "))

    testthat::expect_identical(as.character(result), as.character(bin_path))
    testthat::expect_identical(readLines(bin_path), "working micromamba")
    testthat::expect_length(log$urls, 2L)
    testthat::expect_match(log$urls[[1L]], "github\\.com")
    testthat::expect_match(log$urls[[2L]], "anaconda\\.org")
    # The user is told which mirror was skipped, and that the install
    # succeeded.
    testthat::expect_match(messages, "not a valid micromamba archive")
    testthat::expect_match(messages, "successfully downloaded")
  })
})

testthat::test_that("install_micromamba() aborts and keeps the old binary when every mirror is bad", {
  condathis::with_sandbox_dir({
    bin_path <- micromamba_bin_path()
    fs::dir_create(fs::path_dir(bin_path))
    writeLines("old working binary", bin_path)
    html_page <- local_mirror_file("<html>rate limited</html>")
    local_mirror_checks()
    log <- local_mirror_downloads(function(url) {
      if (isTRUE(grepl("\\.sha256$", url))) {
        return(NULL)
      }
      return(html_page)
    })

    cnd <- testthat::expect_error(
      install_micromamba(force = TRUE, verbose = "silent"),
      class = "condathis_install_micromamba_download_failed"
    )
    # The old class is kept until 1.0 (decision D2).
    testthat::expect_identical(
      class(cnd)[1:3],
      c(
        "condathis_install_micromamba_download_failed",
        "condathis_install_error_missing_bzip2",
        "condathis_error"
      )
    )
    testthat::expect_identical(readLines(bin_path), "old working binary")
    # Every archive mirror, then the uncompressed binary, was tried.
    urls <- get_micromamba_urls(
      sys_arch_str = is_micromamba_available_for_arch(),
      micromamba_version = formals(install_micromamba)$micromamba_version
    )
    testthat::expect_identical(log$urls, c(urls$compressed, urls$uncompressed))
  })
})

testthat::test_that("install_micromamba() verifies win-arm64 2.8.1-0 through its archive", {
  # micromamba 2.8.1-0 has every win-arm64 file except
  # `micromamba-win-arm64.sha256`, and its `.tar.bz2.sha256` holds the hash
  # of the archive, not of the binary (checked 2026-10-29: the archive of
  # every compressed mirror is the same conda-forge package). The binary
  # installed unverified, with a warning. It is now verified through the
  # hash of the archive it was extracted from. Only the platform slug, the
  # downloads and the run check are mocked, so this runs on every OS.
  condathis::with_sandbox_dir({
    bin_path <- micromamba_bin_path()
    rel_path <- fs::path_rel(
      bin_path,
      fs::path(install_dir_for_backend(micromamba_backend()), "micromamba")
    )
    good_archive <- local_mirror_archive(rel_path, "working micromamba")
    archive_sha <- local_mirror_file(compute_sha256(good_archive))
    testthat::local_mocked_bindings(
      is_micromamba_available_for_arch = function(...) "win-arm64",
      candidate_micromamba_runs = function(path) {
        return(identical(read_first_line(path), "working micromamba"))
      }
    )
    log <- local_mirror_downloads(function(url) {
      if (
        isTRUE(grepl("/2\\.8\\.1-0/micromamba-win-arm64\\.tar\\.bz2$", url))
      ) {
        return(good_archive)
      }
      if (isTRUE(grepl("micromamba-win-arm64\\.tar\\.bz2\\.sha256$", url))) {
        return(archive_sha)
      }
      # The missing `.sha256` file: a 404.
      return(NULL)
    })

    testthat::expect_no_warning(
      result <- suppressMessages(install_micromamba(
        micromamba_version = "2.8.1-0",
        force = TRUE,
        verbose = "output"
      ))
    )
    testthat::expect_identical(as.character(result), as.character(bin_path))
    testthat::expect_identical(readLines(bin_path), "working micromamba")
    urls <- get_micromamba_urls(
      sys_arch_str = "win-arm64",
      micromamba_version = "2.8.1-0"
    )
    testthat::expect_identical(
      log$urls,
      c(urls$compressed[[1L]], urls$sha256, urls$archive_sha256)
    )
  })
})

testthat::test_that("an archive that does not match its published checksum is not installed", {
  # The other side of the archive check: with no checksum of the binary,
  # an archive whose hash is not the published one is refused, and every
  # mirror's archive is checked in turn. The uncompressed binary cannot be
  # checked against the hash of an archive, so it installs unverified, with
  # a warning, as before.
  condathis::with_sandbox_dir({
    bin_path <- micromamba_bin_path()
    rel_path <- fs::path_rel(
      bin_path,
      fs::path(install_dir_for_backend(micromamba_backend()), "micromamba")
    )
    good_archive <- local_mirror_archive(rel_path, "working micromamba")
    other_sha <- local_mirror_file(strrep("0", 64L))
    good_binary <- local_mirror_file("working micromamba")
    testthat::local_mocked_bindings(
      is_micromamba_available_for_arch = function(...) "win-arm64",
      candidate_micromamba_runs = function(path) {
        return(identical(read_first_line(path), "working micromamba"))
      }
    )
    urls <- get_micromamba_urls(
      sys_arch_str = "win-arm64",
      micromamba_version = "2.8.1-0"
    )
    log <- local_mirror_downloads(function(url) {
      if (isTRUE(url %in% urls$compressed)) {
        return(good_archive)
      }
      if (isTRUE(url %in% urls$archive_sha256)) {
        return(other_sha)
      }
      if (isTRUE(url %in% urls$uncompressed)) {
        return(good_binary)
      }
      return(NULL)
    })

    warnings <- character(0L)
    result <- withCallingHandlers(
      suppressMessages(install_micromamba(
        micromamba_version = "2.8.1-0",
        force = TRUE,
        verbose = "output"
      )),
      warning = function(w) {
        warnings <<- c(warnings, class(w)[[1L]])
        invokeRestart("muffleWarning")
      }
    )
    testthat::expect_identical(
      warnings,
      c(
        rep("condathis_install_micromamba_checksum_mismatch", 3L),
        "condathis_install_micromamba_checksum_unavailable"
      )
    )
    testthat::expect_identical(readLines(bin_path), "working micromamba")
    per_mirror <- c(urls$sha256, urls$archive_sha256)
    testthat::expect_identical(
      log$urls,
      c(
        urls$compressed[[1L]],
        per_mirror,
        urls$compressed[[2L]],
        per_mirror,
        urls$compressed[[3L]],
        per_mirror,
        urls$uncompressed,
        per_mirror
      )
    )
  })
})
