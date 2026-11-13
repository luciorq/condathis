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
  testthat::skip_on_cran()
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

# Records the conditions of `expr` and muffles them. Errors of class
# `test_install_stop` end `expr`.
record_conditions <- function(expr) {
  out <- new.env(parent = emptyenv())
  out$messages <- list()
  out$warnings <- list()
  out$value <- withCallingHandlers(
    tryCatch(expr, test_install_stop = function(e) "stopped"),
    message = function(m) {
      out$messages <- c(out$messages, list(m))
      invokeRestart("muffleMessage")
    },
    warning = function(w) {
      out$warnings <- c(out$warnings, list(w))
      invokeRestart("muffleWarning")
    }
  )
  return(out)
}

# The text of a condition on one line: no ANSI styles, and the
# non-breaking spaces of cli and the line breaks of the wrapping turned
# into single spaces.
plain_message_text <- function(cnd) {
  text <- cli::ansi_strip(conditionMessage(cnd))
  text <- gsub("\u00a0", " ", text, fixed = TRUE)
  return(gsub("[[:space:]]+", " ", text))
}

testthat::test_that("a command that installs micromamba says so unless silent", {
  # Regression test: with no usable micromamba, the first create_env() or
  # run() downloaded and installed it without a message at the default
  # verbose level, because native_cmd() passes the internal level
  # "spinner" to install_micromamba().
  condathis::with_sandbox_dir({
    calls <- list()
    testthat::local_mocked_bindings(
      get_best_micromamba_path = function(...) NULL,
      install_micromamba = function(...) {
        calls <<- c(calls, list(list(...)))
        rlang::abort("no download in tests", class = "test_install_stop")
      },
      execute_command = function(...) stop("No process may start here.")
    )
    internal <- c(
      output = "spinner",
      cmd = "spinner",
      spinner = "spinner",
      full = "full"
    )
    for (level in names(internal)) {
      calls <- list()
      res <- record_conditions(native_cmd(
        conda_cmd = "create",
        verbose = level
      ))
      testthat::expect_identical(res$value, "stopped")
      testthat::expect_length(res$messages, 1L)
      cnd <- res$messages[[1L]]
      testthat::expect_s3_class(cnd, "condathis_micromamba_downloading")
      text <- plain_message_text(cnd)
      testthat::expect_match(
        text,
        "No usable micromamba binary was found.",
        fixed = TRUE
      )
      testthat::expect_match(
        text,
        paste0("Downloading micromamba \"", micromamba_default_version, "\""),
        fixed = TRUE
      )
      testthat::expect_match(
        text,
        as.character(micromamba_bin_path()),
        fixed = TRUE
      )
      testthat::expect_length(calls, 1L)
      testthat::expect_identical(calls[[1L]]$verbose, internal[[level]])
      testthat::expect_true(calls[[1L]]$force)
    }

    calls <- list()
    res <- record_conditions(native_cmd(
      conda_cmd = "create",
      verbose = "silent"
    ))
    testthat::expect_identical(res$value, "stopped")
    testthat::expect_length(res$messages, 0L)
    testthat::expect_length(calls, 1L)
    testthat::expect_identical(calls[[1L]]$verbose, "silent")
  })
})

testthat::test_that("the automatic install announces itself and warns when unverified", {
  # End to end through install_micromamba(), with the downloads mocked:
  # the archive is served, but no published checksum can be downloaded (a
  # host that blocks GitHub). At the default verbose level, the command
  # says that it downloads micromamba, installs the binary, and warns that
  # it was not verified. Silent stays silent and still installs.
  condathis::with_sandbox_dir({
    bin_path <- micromamba_bin_path()
    rel_path <- fs::path_rel(
      bin_path,
      fs::path(install_dir_for_backend(micromamba_backend()), "micromamba")
    )
    good_archive <- local_mirror_archive(rel_path, "working micromamba")
    urls <- get_micromamba_urls(
      sys_arch_str = is_micromamba_available_for_arch(),
      micromamba_version = micromamba_default_version
    )
    log <- local_mirror_downloads(function(url) {
      if (isTRUE(identical(url, urls$compressed[[1L]]))) {
        return(good_archive)
      }
      return(NULL)
    })
    testthat::local_mocked_bindings(
      get_best_micromamba_path = function(...) NULL,
      candidate_micromamba_runs = function(path) {
        return(identical(read_first_line(path), "working micromamba"))
      },
      execute_command = function(...) {
        list(status = 0L, stdout = "", stderr = "", timeout = FALSE)
      }
    )

    res <- record_conditions(native_cmd(conda_cmd = "info"))
    testthat::expect_identical(readLines(bin_path), "working micromamba")
    testthat::expect_identical(
      vapply(res$messages, function(m) class(m)[[1L]], character(1L)),
      "condathis_micromamba_downloading"
    )
    testthat::expect_identical(
      vapply(res$warnings, function(w) class(w)[[1L]], character(1L)),
      "condathis_install_micromamba_checksum_unavailable"
    )
    testthat::expect_identical(
      log$urls,
      c(urls$compressed[[1L]], urls$sha256, urls$archive_sha256)
    )

    fs::file_delete(bin_path)
    res <- record_conditions(native_cmd(conda_cmd = "info", verbose = "silent"))
    testthat::expect_identical(readLines(bin_path), "working micromamba")
    testthat::expect_length(res$messages, 0L)
    testthat::expect_length(res$warnings, 0L)
  })
})

testthat::test_that("a silent probe of a call installs micromamba at the level of the call", {
  # Regression test: on macOS arm64 and Windows, the first micromamba
  # command of create_env() is a silent probe (the dry-run solves of
  # define_platform(), the platform query of micromamba_native_platform()),
  # so the automatic install happened there, without a message and without
  # the warning about an unverified binary.
  condathis::with_sandbox_dir({
    calls <- character(0L)
    testthat::local_mocked_bindings(
      get_best_micromamba_path = function(...) NULL,
      install_micromamba = function(..., verbose) {
        calls <<- c(calls, verbose)
        rlang::abort("no download in tests", class = "test_install_stop")
      },
      execute_command = function(...) stop("No process may start here.")
    )
    # An exported function records its level, as create_env() does.
    exported_call <- function(verbose) {
      parse_verbose_arg(verbose)
      expected <- parse_strategy_verbose(verbose)$strategy
      testthat::expect_identical(call_verbose(), expected)
      native_cmd(conda_cmd = "create", verbose = "silent")
    }
    res <- record_conditions(exported_call("output"))
    testthat::expect_identical(res$value, "stopped")
    testthat::expect_identical(
      vapply(res$messages, function(m) class(m)[[1L]], character(1L)),
      "condathis_micromamba_downloading"
    )
    testthat::expect_identical(calls, "spinner")

    calls <- character(0L)
    res <- record_conditions(exported_call("full"))
    testthat::expect_length(res$messages, 1L)
    testthat::expect_identical(calls, "full")

    calls <- character(0L)
    res <- record_conditions(exported_call("silent"))
    testthat::expect_length(res$messages, 0L)
    testthat::expect_identical(calls, "silent")

    # The level is restored when the call exits, also on an error.
    testthat::expect_null(call_verbose())
    outer_call <- function() {
      parse_verbose_arg("cmd")
      try(exported_call("silent"), silent = TRUE)
      testthat::expect_identical(call_verbose(), "cmd")
    }
    record_conditions(outer_call())
    testthat::expect_null(call_verbose())
  })
})
