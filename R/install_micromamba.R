#' Install micromamba
#'
#' Downloads the `micromamba` binary that `condathis` uses and installs it
#' in the condathis data directory, at the path that
#' [micromamba_bin_path()] returns. The functions that need micromamba call
#' it when no usable binary is found (see *micromamba discovery* in
#' [condathis-options]), for the default version. They first show a message
#' of class `condathis_micromamba_downloading` that names the version and
#' the path, unless their `verbose` is `"silent"`. You need to call it only
#' to choose the version, or to install micromamba ahead of time.
#'
#' @param micromamba_version Character string with the micromamba version,
#'   in the format `"X.Y.Z-N"` (version and build number), for example
#'   `"2.10.0-0"`, the default. `condathis` does not use versions older
#'   than 2.8.1. Invalid values abort with these classes:
#'   * `condathis_install_micromamba_invalid_micromamba_version`: another
#'     format.
#'   * `condathis_install_micromamba_unsupported_version`: a version older
#'     than 2.8.1.
#'
#'   With `micromamba_version`, an installed binary is kept only when its
#'   version (`X.Y.Z`) is the requested one. When it reports another
#'   version, or its version cannot be read, `install_micromamba()` installs
#'   the requested version. Without `micromamba_version`, it always keeps an
#'   installed binary, unless `force = TRUE`.
#' @param timeout Numeric download timeout in seconds, a single
#'   non-negative number. `Inf` means no limit. Defaults to `3600`. Each
#'   download uses the larger of this value and `getOption("timeout")`, so
#'   `0` means no limit only when `getOption("timeout")` is `0` too. The
#'   function lowers values above 2147483 seconds (about 24.8 days) to
#'   2147483. Other values abort with class\cr
#'   `condathis_install_micromamba_invalid_timeout`.
#' @param download_method Character string with the download method of
#'   [utils::download.file()]: one of `"auto"` (the default), `"internal"`,
#'   `"libcurl"`, `"wget"`, `"curl"` or `"wininet"`. It is ignored when the
#'   `curl` package 5.0.0 or later is installed, because then
#'   [curl::curl_download()] is used. Other values abort with class\cr
#'   `condathis_install_micromamba_invalid_download_method`.
#' @param force Logical value. `TRUE` downloads micromamba also when a
#'   binary is already installed. Defaults to `FALSE`. A value that is not
#'   `TRUE` or `FALSE` aborts with class
#'   `condathis_install_micromamba_invalid_force`.
#' @param verbose Character string that controls the console output. One
#'   of `"output"`, `"silent"`, `"cmd"`, `"spinner"` or `"full"`.
#'   `"output"` and `"full"` show the progress of the download and the
#'   messages of `condathis`, for example that `micromamba` is already
#'   installed, that the file of a mirror failed the checks, or that the
#'   download succeeded. The other levels show none of them.
#'   Every level except `"silent"` shows the warning of class
#'   `condathis_install_micromamba_checksum_unavailable` (see Details and
#'   [condathis-conditions]).
#'
#'   `TRUE` means `"output"` and `FALSE` means `"silent"`. Invalid values
#'   abort with class `condathis_invalid_verbose`. The default is shown in
#'   Usage.
#' @param timeout_limit Deprecated. Use `timeout`. A value warns with class
#'   `condathis_deprecated_arg` and is used as `timeout`. Passing both
#'   aborts with class\cr
#'   `condathis_install_micromamba_conflicting_args`.
#'
#' @returns The path of the micromamba binary, an `fs_path`, invisibly: the
#'   path that [micromamba_bin_path()] returns. A failed download aborts
#'   with class `condathis_install_micromamba_download_failed`.
#'
#' @details
#' The binary is the build for the platform of the running R (see
#' [get_sys_arch()]): `linux-64`, `linux-aarch64`, `linux-ppc64le`,
#' `osx-64`, `osx-arm64`, `win-64` or `win-arm64`. A native ARM64 R on
#' Windows gets `win-arm64`. An x64 R on an ARM64 PC gets `win-64`, which
#' runs through x64 emulation. Every R of a user shares the installed
#' binary. So on an ARM64 PC, the binary installed first stays until you
#' replace it, for example with `force = TRUE`. Either binary works with
#' both builds of R: micromamba builds environments for its own platform.
#'
#' `install_micromamba()` tries the compressed archive first, from the
#' micromamba releases on GitHub, then from the conda-forge channel on
#' anaconda.org and prefix.dev. It extracts the archive with R's internal
#' `tar`, so no system `tar` or `bzip2` is needed. When every archive
#' fails, it downloads the standalone binary from GitHub. A mirror fails
#' when the download fails, or when the file does not extract, does not
#' run, or does not match the SHA256 checksum published with the release.
#' Then it tries the next mirror. It replaces an installed binary only with
#' a download that passed these checks, also with `force = TRUE`.
#'
#' The checksum is downloaded from the GitHub release when the binary is
#' installed. When it cannot be downloaded or read, or the SHA256 hash of
#' the binary cannot be computed, `install_micromamba()` still installs the
#' binary, so that mirrors work when GitHub cannot be reached, but warns
#' with class `condathis_install_micromamba_checksum_unavailable`. It warns
#' for every `verbose` level except `"silent"`, also when a function that
#' needs micromamba installs it. A checksum that does not match warns with
#' class `condathis_install_micromamba_checksum_mismatch`, also when
#' `verbose` is `"silent"`, and that binary is not installed. The hash is
#' computed with `tools::sha256sum()` on R 4.5.0 or later, else with the
#' `digest` package when it is installed, else with the `sha256sum` or
#' `shasum` program, or on Windows `certutil`.
#'
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   # Install the default version of micromamba
#'   condathis::install_micromamba()
#'
#'   # Install a specific version (2.8.1 or newer): it replaces a binary of
#'   # another version
#'   condathis::install_micromamba(micromamba_version = "2.9.0-0")
#'
#'   # Without `micromamba_version`, the installed binary is kept unless
#'   # `force = TRUE`
#'   condathis::install_micromamba(force = TRUE)
#' })
#' }
#'
#' @family setup
#'
#' @export
install_micromamba <- function(
  micromamba_version = "2.10.0-0",
  timeout = 3600,
  download_method = "auto",
  force = FALSE,
  verbose = c(
    "output",
    "silent",
    "cmd",
    "spinner",
    "full"
  ),
  timeout_limit = NULL
) {
  # Rule R2: every argument is checked before the first side effect.
  verbose_list <- parse_verbose_arg(verbose)
  if (isFALSE(is.null(timeout_limit))) {
    if (isFALSE(missing(timeout))) {
      condathis_abort(
        message = c(
          `x` = "{.arg timeout} and {.arg timeout_limit} cannot both be given.",
          `i` = "{.arg timeout_limit} is deprecated; use {.arg timeout}."
        ),
        class = c(
          "condathis_install_micromamba_conflicting_args",
          "condathis_invalid_arg"
        )
      )
    }
    condathis_warn(
      message = c(
        `!` = "{.arg timeout_limit} is deprecated; use {.arg timeout}."
      ),
      class = "condathis_deprecated_arg"
    )
    timeout <- timeout_limit
  }
  timeout <- validate_timeout_arg(
    timeout,
    class = arg_error_class(
      "install_micromamba",
      "timeout",
      aliases = "condathis_install_micromamba_invalid_timeout_limit"
    )
  )
  validate_bool_arg(
    force,
    class = arg_error_class("install_micromamba", "force"),
    arg_name = "force"
  )
  requested_version <- validate_micromamba_version_arg(micromamba_version)
  download_method <- arg_match_classed(
    download_method,
    values = c("auto", "internal", "libcurl", "wget", "curl", "wininet"),
    class = arg_error_class("install_micromamba", "download_method"),
    arg_name = "download_method"
  )

  dl_quiet_flag <- TRUE
  if (isTRUE(verbose_list$strategy %in% c("output", "full"))) {
    dl_quiet_flag <- FALSE
  }
  umamba_bin_path <- micromamba_bin_path()

  if (isTRUE(fs::file_exists(umamba_bin_path)) && isFALSE(force)) {
    # An explicit version is a request for that version, for
    # reproducibility, so a binary of another version does not satisfy it.
    installed_version <- if (isTRUE(missing(micromamba_version))) {
      NA_character_
    } else {
      tryCatch(
        get_micromamba_version(umamba_bin_path),
        error = function(e) NA_character_
      )
    }
    keep_installed <- isTRUE(missing(micromamba_version)) ||
      identical(installed_version, requested_version)
    if (isTRUE(keep_installed)) {
      if (isFALSE(dl_quiet_flag)) {
        condathis_inform(c(
          `i` = "{.pkg micromamba} is already installed at {.path {umamba_bin_path}}."
        ))
      }
      return(invisible(umamba_bin_path))
    }
    if (isFALSE(dl_quiet_flag)) {
      installed_line <- if (isTRUE(is.na(installed_version))) {
        "The version of the installed {.pkg micromamba} could not be read."
      } else {
        "The installed {.pkg micromamba} is version {.val {installed_version}}."
      }
      condathis_inform(c(
        `i` = installed_line,
        `i` = "Installing the requested version {.val {requested_version}}."
      ))
    }
  }

  sys_arch_str <- is_micromamba_available_for_arch()

  # Build mirror URLs for this platform and version
  mirror_urls <- get_micromamba_urls(
    sys_arch_str = sys_arch_str,
    micromamba_version = micromamba_version
  )

  output_dir <- fs::path_abs(install_dir_for_backend(micromamba_backend()))
  if (isFALSE(fs::dir_exists(output_dir))) {
    fs::dir_create(output_dir)
  }

  untar_dir <- fs::path(output_dir, "micromamba")
  if (isFALSE(fs::dir_exists(untar_dir))) {
    fs::dir_create(untar_dir)
  }

  # Strategy 1: download the compressed .tar.bz2 and extract it.
  # Strategy 2: download the uncompressed binary when Strategy 1 failed.
  # Each strategy produces a candidate binary away from the live path and
  # installs it only after it runs and matches the published checksum (see
  # install_candidate_micromamba()), so a failed attempt never replaces or
  # corrupts a working installation.
  extraction_succeeded <- download_compressed_and_extract(
    compressed_urls = mirror_urls$compressed,
    output_dir = output_dir,
    untar_dir = untar_dir,
    umamba_bin_path = umamba_bin_path,
    timeout_limit = timeout,
    download_method = download_method,
    dl_quiet_flag = dl_quiet_flag,
    sha256_urls = mirror_urls$sha256,
    archive_sha256_urls = mirror_urls$archive_sha256 %||% character(0L),
    verbose = verbose_list
  )
  if (isFALSE(extraction_succeeded)) {
    extraction_succeeded <- download_uncompressed_binary(
      uncompressed_urls = mirror_urls$uncompressed,
      umamba_bin_path = umamba_bin_path,
      timeout_limit = timeout,
      download_method = download_method,
      dl_quiet_flag = dl_quiet_flag,
      sha256_urls = mirror_urls$sha256,
      archive_sha256_urls = mirror_urls$archive_sha256 %||% character(0L),
      verbose = verbose_list
    )
  }

  # Check the strategies' success flag, not only file existence: a failed
  # `force = TRUE` reinstall preserves the previous binary at
  # `umamba_bin_path` (see `download_uncompressed_binary()`), so existence
  # does not imply this call installed anything. Abort on failure and leave
  # the old binary intact.
  if (
    isFALSE(extraction_succeeded) ||
      isFALSE(file_exists_retry(umamba_bin_path))
  ) {
    condathis_abort(
      message = c(
        `x` = "{.pkg micromamba} {.val {micromamba_version}} was not downloaded or installed.",
        `i` = "Every download mirror was tried.",
        `i` = paste0(
          "A network problem, a release that does not exist, or a file ",
          "that failed the checks can cause this."
        )
      ),
      # The old class named bzip2, which the install does not need.
      class = c(
        "condathis_install_micromamba_download_failed",
        "condathis_install_error_missing_bzip2"
      )
    )
  }

  if (
    isTRUE(extraction_succeeded) &&
      verbose_list$strategy %in% c("full", "output")
  ) {
    condathis_inform(
      message = c(
        `v` = "{.pkg micromamba} successfully downloaded."
      )
    )
  }

  return(invisible(umamba_bin_path))
}

#' The micromamba version that `install_micromamba()` installs by default
#'
#' The same string as the default of its `micromamba_version` argument,
#' which stays a literal so that the usage in `?install_micromamba` shows
#' the version. A test checks that the two agree. `native_cmd()` names this
#' version when it installs micromamba (see
#' `install_micromamba_for_command()`).
#'
#' @keywords internal
#' @noRd
micromamba_default_version <- "2.10.0-0"

#' Check the `micromamba_version` argument of `install_micromamba()`
#'
#' @param micromamba_version The value to check. It must be a single string
#'   `"X.Y.Z-N"`: the version and the build number of a micromamba release.
#'   The version must be `micromamba_minimum_version` or newer.
#' @param call Environment of the function the error is reported for.
#'
#' @returns The version part `"X.Y.Z"`. A wrong format aborts with
#'   `c("condathis_install_micromamba_invalid_micromamba_version",
#'   "condathis_invalid_micromamba_version", "condathis_invalid_arg",
#'   "condathis_error")`. An older version aborts with
#'   `c("condathis_install_micromamba_unsupported_version",
#'   "condathis_micromamba_version_unsupported", "condathis_error")`.
#'
#' @keywords internal
#' @noRd
validate_micromamba_version_arg <- function(
  micromamba_version,
  call = rlang::caller_env()
) {
  # Without the build number, the download URLs end in "-NA" (see
  # `get_micromamba_urls()`), and "latest" passed unchecked.
  if (
    isFALSE(rlang::is_string(micromamba_version)) ||
      isTRUE(is.na(micromamba_version)) ||
      isFALSE(grepl("^[0-9]+\\.[0-9]+\\.[0-9]+-[0-9]+$", micromamba_version))
  ) {
    message <- if (isTRUE(rlang::is_string(micromamba_version))) {
      c(
        `x` = "{.arg micromamba_version} must be a version and a build number, such as {.val 2.10.0-0}, not {.val {micromamba_version}}."
      )
    } else {
      c(
        `x` = "{.arg micromamba_version} must be a version and a build number, such as {.val 2.10.0-0}, not {.obj_type_friendly {micromamba_version}}."
      )
    }
    condathis_abort(
      message = message,
      class = arg_error_class("install_micromamba", "micromamba_version"),
      call = call
    )
  }
  requested_version <- sub("-[0-9]+$", "", micromamba_version)
  # Discovery skips anything older than the minimum, so an older install
  # was replaced by the pinned version on the next command without a word.
  if (
    isTRUE(
      utils::compareVersion(requested_version, micromamba_minimum_version) < 0L
    )
  ) {
    condathis_abort(
      message = c(
        `x` = "{.pkg micromamba} {.val {requested_version}} is not supported.",
        `i` = "{.pkg condathis} requires {.pkg micromamba} {.val {micromamba_minimum_version}} or newer."
      ),
      class = c(
        "condathis_install_micromamba_unsupported_version",
        "condathis_micromamba_version_unsupported"
      ),
      call = call
    )
  }
  return(requested_version)
}

#' Tell the user that a mirror's file was not installed
#'
#' The next mirror or strategy is tried after this, so it is a message,
#' not a warning.
#'
#' @param url Character string. The mirror endpoint.
#' @param problem Character string. What was wrong with the file, as a
#'   `cli` format string that can use `{.url {url}}`.
#' @param verbose List. Parsed verbose flags from `parse_strategy_verbose()`.
#'
#' @returns `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
inform_rejected_download <- function(url, problem, verbose) {
  # A message, so an information bullet: `!` is only for warnings (rule R3).
  if (isTRUE(verbose$strategy %in% c("full", "output"))) {
    condathis_inform(c(`i` = problem))
  }
  return(invisible(NULL))
}

#' Download and extract the compressed micromamba archive
#'
#' Strategy 1 of `install_micromamba()`'s two download strategies: fetch the
#' `.tar.bz2` archive from the given mirrors and extract it with
#' `extract_tar_bz2()`, which needs no system tools. When this fails,
#' `install_micromamba()` falls back to `download_uncompressed_binary()`.
#'
#' Each mirror's file is extracted and checked before the next mirror is
#' considered. A mirror that serves an error page with status 200, a
#' truncated archive, or a binary that does not run or match the checksum
#' moves the search to the next mirror. It does not end the strategy.
#'
#' @param compressed_urls Character vector of `.tar.bz2` mirror endpoints.
#' @param output_dir Directory the archive is downloaded into.
#' @param untar_dir Directory of the live installation. The binary's path
#'   relative to it locates the binary inside the extracted archive.
#' @param umamba_bin_path Path of the live binary.
#' @param timeout_limit,download_method,dl_quiet_flag Passed through to
#'   `try_download_from_mirrors()`.
#' @param sha256_urls,verbose Passed to `install_candidate_micromamba()`.
#' @param archive_sha256_urls Character vector, the endpoints of the
#'   published checksum of the archive. With the SHA256 hash of each
#'   downloaded archive, they are the `archive` of
#'   `install_candidate_micromamba()`.
#'
#' @returns Logical. `TRUE` only if the archive from one mirror was
#'   downloaded, extracted cleanly into a temporary directory, and its
#'   binary passed `install_candidate_micromamba()` and replaced the live
#'   one.
#'
#' @keywords internal
#' @noRd
download_compressed_and_extract <- function(
  compressed_urls,
  output_dir,
  untar_dir,
  umamba_bin_path,
  timeout_limit,
  download_method,
  dl_quiet_flag,
  sha256_urls = character(0L),
  archive_sha256_urls = character(0L),
  verbose = list(strategy = "silent")
) {
  full_dl_path <- as.character(
    fs::path(output_dir, paste0("micromamba-dl-", Sys.getpid(), ".tar.bz2"))
  )
  extract_dir <- fs::path(
    output_dir,
    paste0("micromamba-extract-", Sys.getpid())
  )
  on.exit(
    {
      if (fs::file_exists(full_dl_path)) {
        try(fs::file_delete(full_dl_path), silent = TRUE)
      }
      if (fs::dir_exists(extract_dir)) {
        try(fs::dir_delete(extract_dir), silent = TRUE)
      }
    },
    add = TRUE
  )

  # The checks run inside the mirror loop. Run after it, they ended the
  # strategy on the first mirror that served a bad file, and the other
  # mirrors were never tried.
  accept_archive <- function(destfile, url) {
    # Hashed before the extraction, for a release that publishes only the
    # checksum of the archive (see `verify_micromamba_checksum()`).
    archive <- list(
      hash = if (isTRUE(length(archive_sha256_urls) > 0L)) {
        compute_sha256(destfile)
      } else {
        NA_character_
      },
      sha256_urls = archive_sha256_urls
    )
    # Extract into a temporary directory, never over the live
    # installation: a truncated or invalid archive used to overwrite a
    # working binary in place.
    if (isFALSE(extract_tar_bz2(destfile, extract_dir))) {
      inform_rejected_download(
        url = url,
        problem = "The file from {.url {url}} is not a valid {.pkg micromamba} archive.",
        verbose = verbose
      )
      return(FALSE)
    }
    candidate <- fs::path(
      extract_dir,
      fs::path_rel(umamba_bin_path, untar_dir)
    )
    installed <- install_candidate_micromamba(
      candidate = candidate,
      umamba_bin_path = umamba_bin_path,
      sha256_urls = sha256_urls,
      timeout_limit = timeout_limit,
      download_method = download_method,
      verbose = verbose,
      archive = archive
    )
    if (isFALSE(installed)) {
      inform_rejected_download(
        url = url,
        problem = "The archive from {.url {url}} has no working {.pkg micromamba} binary.",
        verbose = verbose
      )
    }
    return(installed)
  }

  return(try_download_from_mirrors(
    urls = compressed_urls,
    destfile = full_dl_path,
    timeout_limit = timeout_limit,
    method = download_method,
    quiet = dl_quiet_flag,
    accept = accept_archive
  ))
}

#' Download the standalone micromamba binary directly
#'
#' Strategy 2 of `install_micromamba()`'s two download strategies: used when
#' `download_compressed_and_extract()` failed.
#'
#' Each mirror's binary is checked before the next mirror is considered, so
#' a bad file from one mirror moves the search to the next one.
#'
#' @param uncompressed_urls Character vector of raw binary mirror endpoints.
#' @param umamba_bin_path Final destination path for the binary. Never
#'   written to (or deleted) until a complete download exists at a
#'   temporary sibling path - see the comment in the body: an existing
#'   working installation must survive a total download failure.
#' @param timeout_limit,download_method,dl_quiet_flag Passed through to
#'   `try_download_from_mirrors()`.
#' @param sha256_urls,verbose Passed to `install_candidate_micromamba()`.
#' @param archive_sha256_urls Character vector, the endpoints of the
#'   published checksum of the archive. Without an archive, it verifies the
#'   binary only when it holds the hash of the binary (see
#'   `verify_micromamba_checksum()`).
#'
#' @returns Logical. `TRUE` if the binary from one mirror was downloaded,
#'   passed `install_candidate_micromamba()`, and replaced the live one.
#'
#' @keywords internal
#' @noRd
download_uncompressed_binary <- function(
  uncompressed_urls,
  umamba_bin_path,
  timeout_limit,
  download_method,
  dl_quiet_flag,
  sha256_urls = character(0L),
  archive_sha256_urls = character(0L),
  verbose = list(strategy = "silent")
) {
  # This is not the right path on Windows
  base_dl_dir <- fs::path(base::dirname(umamba_bin_path))
  if (isFALSE(fs::dir_exists(base_dl_dir))) {
    fs::dir_create(base_dl_dir)
  }

  # Download to a temporary sibling path, never onto the live binary:
  # try_download_from_mirrors() deletes its destfile after every failed
  # mirror, and a partial download would corrupt the destination. Writing
  # to `umamba_bin_path` would delete a working installation when all
  # mirrors fail. A sibling in the same directory (not `tempfile()`) keeps
  # the final move a same-filesystem rename.
  tmp_dl_path <- fs::path(
    base_dl_dir,
    paste0("micromamba-dl-", Sys.getpid(), ".tmp")
  )

  on.exit(
    if (isTRUE(fs::file_exists(tmp_dl_path))) {
      try(fs::file_delete(tmp_dl_path), silent = TRUE)
    },
    add = TRUE
  )

  # The complete new binary exists on disk, and is checked, before the old
  # one is touched. The check runs inside the mirror loop, so a mirror that
  # serves a bad file does not end the strategy.
  accept_binary <- function(destfile, url) {
    installed <- install_candidate_micromamba(
      candidate = destfile,
      umamba_bin_path = umamba_bin_path,
      sha256_urls = sha256_urls,
      timeout_limit = timeout_limit,
      download_method = download_method,
      verbose = verbose,
      archive = list(hash = NA_character_, sha256_urls = archive_sha256_urls)
    )
    if (isFALSE(installed)) {
      inform_rejected_download(
        url = url,
        problem = "The file from {.url {url}} is not a working {.pkg micromamba} binary.",
        verbose = verbose
      )
    }
    return(installed)
  }

  return(try_download_from_mirrors(
    urls = uncompressed_urls,
    destfile = tmp_dl_path,
    timeout_limit = timeout_limit,
    method = download_method,
    quiet = dl_quiet_flag,
    accept = accept_binary
  ))
}

#' Extract a `.tar.bz2` archive
#'
#' Uses R's internal tar first. It decompresses bzip2 itself, so it needs
#' neither a system `tar` nor a `bzip2` program, which Windows usually
#' lacks. A system `tar` is the fallback when the internal one fails. It is
#' the program from `system_tar_program()`, the rule `has_system_tar()`
#' also uses. It reads the archive on stdin, so a Windows drive letter in
#' the path cannot be taken for a remote host, and its output is captured
#' instead of printed.
#'
#' Only an error or a non-zero status counts as failure. Warnings are
#' dropped: R warns about harmless details such as pax headers, which
#' conda-forge archives use. A truncated archive cannot install a broken
#' binary, because `install_candidate_micromamba()` runs the extracted
#' binary and checks its SHA256 checksum. A failed attempt removes `exdir`.
#'
#' @param tarfile Path to the archive.
#' @param exdir Directory to extract into.
#'
#' @returns Logical scalar. `TRUE` when an extraction succeeded.
#'
#' @keywords internal
#' @noRd
extract_tar_bz2 <- function(tarfile, exdir) {
  exdir <- fs::path_expand(exdir)
  extractors <- list(function() {
    rc <- suppressWarnings(
      utils::untar(tarfile = tarfile, exdir = exdir, tar = "internal")
    )
    identical(as.integer(rc), 0L)
  })
  # `TAR` used to be run as given, so `TAR=internal`, or a `TAR` that is not
  # a program, made the fallback fail although `has_system_tar()` had found
  # `tar` on `PATH`.
  tar_program <- system_tar_program()
  if (isFALSE(is.null(tar_program))) {
    extractors[[2L]] <- function() {
      res <- processx::run(
        command = tar_program,
        args = c("-xjf", "-"),
        stdin = as.character(tarfile),
        wd = as.character(exdir),
        error_on_status = FALSE
      )
      identical(res$status, 0L)
    }
  }
  for (extractor in extractors) {
    if (fs::dir_exists(exdir)) {
      fs::dir_delete(exdir)
    }
    fs::dir_create(exdir)
    if (isTRUE(tryCatch(extractor(), error = function(e) FALSE))) {
      return(TRUE)
    }
  }
  if (fs::dir_exists(exdir)) {
    fs::dir_delete(exdir)
  }
  return(FALSE)
}

#' Check a downloaded micromamba binary, then put it in place
#'
#' The candidate must run and report a version, and must match the
#' published SHA256 checksum when one can be downloaded. Only then does it
#' replace the live binary. A failed check leaves the live binary untouched
#' and returns `FALSE`, so `install_micromamba()` tries the next mirror,
#' then the next strategy, then aborts. A checksum that cannot be downloaded
#' or computed does not block the install (mirrors without `.sha256` files
#' exist); a mismatch does.
#'
#' @param candidate Path to the downloaded or extracted binary.
#' @param umamba_bin_path Path of the live binary.
#' @param sha256_urls,timeout_limit,download_method,verbose,archive Passed
#'   to `verify_micromamba_checksum()`.
#'
#' @returns Logical scalar. `TRUE` when the candidate was installed.
#'
#' @keywords internal
#' @noRd
install_candidate_micromamba <- function(
  candidate,
  umamba_bin_path,
  sha256_urls,
  timeout_limit,
  download_method,
  verbose,
  archive = NULL
) {
  if (isFALSE(file_exists_retry(candidate))) {
    return(FALSE)
  }
  if (isFALSE(is_windows())) {
    fs::file_chmod(candidate, mode = "u+x")
  }
  if (isFALSE(candidate_micromamba_runs(candidate))) {
    return(FALSE)
  }
  checksum_ok <- verify_micromamba_checksum(
    bin_path = candidate,
    sha256_urls = sha256_urls,
    timeout_limit = timeout_limit,
    method = download_method,
    verbose = verbose,
    archive = archive
  )
  if (isFALSE(checksum_ok)) {
    return(FALSE)
  }
  bin_dir <- fs::path_dir(umamba_bin_path)
  if (isFALSE(fs::dir_exists(bin_dir))) {
    fs::dir_create(bin_dir)
  }
  if (isTRUE(fs::file_exists(umamba_bin_path))) {
    fs::file_delete(umamba_bin_path)
  }
  fs::file_move(path = candidate, new_path = umamba_bin_path)
  return(isTRUE(file_exists_retry(umamba_bin_path)))
}

#' Does a candidate micromamba binary run and report a version?
#'
#' @param path Path to the candidate binary.
#'
#' @returns Logical scalar.
#'
#' @keywords internal
#' @noRd
candidate_micromamba_runs <- function(path) {
  version <- tryCatch(
    get_micromamba_version(path),
    error = function(e) NA_character_
  )
  return(rlang::is_string(version) && isFALSE(is.na(version)))
}

#' Verify Micromamba Binary SHA256 Checksum
#'
#' Downloads the published SHA256 checksum from GitHub releases and compares
#' it against a candidate binary. Emits a warning if the checksums do not
#' match, and, unless `verbose$strategy` is `"silent"`, when the candidate
#' could not be verified. It never aborts: `install_candidate_micromamba()`
#' decides, and it refuses a mismatching candidate but installs one that
#' could not be verified.
#'
#' The SHA256 checksum files on GitHub releases always contain the hash of the
#' standalone binary (not the archive). This means the same checksum works
#' regardless of whether the compressed or uncompressed download was used.
#'
#' One release has no such file: 2.8.1-0 on win-arm64 publishes no
#' `.sha256`, and its `.tar.bz2.sha256` holds the hash of the archive. When
#' the checksum of the binary cannot be downloaded or read, the
#' `.tar.bz2.sha256` file of `archive` is read instead, and it verifies the
#' candidate when it holds the hash of the binary, as for most releases, or
#' the hash of the archive that the candidate was extracted from. A hash
#' that matches neither is a mismatch only for an extracted binary: for a
#' binary downloaded on its own, it can be the hash of an archive, so the
#' binary is not verified.
#'
#' @section Updating checksums for a new release:
#' When updating the default `micromamba_version`, no code changes are needed
#' for checksums. The SHA256 file is downloaded dynamically from the matching
#' release artifact for the selected version and platform.
#'
#' @param bin_path Character string. Path to the micromamba binary to verify.
#' @param sha256_urls Character vector. Mirror endpoints to try for downloading
#'   the SHA256 checksum file.
#' @param timeout_limit Numeric. Timeout in seconds.
#' @param method Character string. Download method.
#' @param verbose List. Parsed verbose flags from `parse_strategy_verbose()`.
#' @param archive `NULL`, or a list with `hash`, the SHA256 hash of the
#'   archive the binary was extracted from (`NA` for a binary downloaded on
#'   its own), and `sha256_urls`, the endpoints of the published checksum
#'   of the archive.
#'
#' @returns Invisible `TRUE` if the checksum matches, `FALSE` on a
#'   mismatch, and `NA` when verification was not possible (no published
#'   checksum could be downloaded, or no hash could be computed).
#'
#' @keywords internal
#' @noRd
verify_micromamba_checksum <- function(
  bin_path,
  sha256_urls,
  timeout_limit = 3600,
  method = "auto",
  verbose = list(strategy = "silent"),
  archive = NULL
) {
  if (isFALSE(fs::file_exists(bin_path))) {
    return(invisible(NA))
  }
  # An unverified binary is still installed (mirrors without a checksum
  # file, and hosts that block GitHub, must keep working), so the warning
  # is the only sign of it: it shows at every level but `"silent"`. It
  # showed only for `"output"` and `"full"`, so the automatic install of
  # `native_cmd()`, at the internal level `"spinner"`, gave no warning.
  warn_unverified <- function(problem) {
    if (isFALSE(identical(verbose$strategy, "silent"))) {
      condathis_warn(
        message = c(
          `!` = problem,
          `i` = "Skipping checksum verification."
        ),
        class = "condathis_install_micromamba_checksum_unavailable"
      )
    }
    return(invisible(NA))
  }
  warn_mismatch <- function(subject, expected_hash, actual_hash) {
    condathis_warn(
      message = c(
        `!` = subject,
        `i` = "Expected: {.val {expected_hash}}",
        `i` = "Actual:   {.val {actual_hash}}",
        `!` = paste0(
          "The binary may be corrupted or tampered with. ",
          "It was not installed."
        )
      ),
      class = "condathis_install_micromamba_checksum_mismatch"
    )
    return(invisible(FALSE))
  }

  published <- download_published_sha256(
    urls = sha256_urls,
    timeout_limit = timeout_limit,
    method = method
  )
  if (
    isTRUE(is.na(published$hash)) &&
      isTRUE(length(archive$sha256_urls) > 0L)
  ) {
    archive_published <- download_published_sha256(
      urls = archive$sha256_urls,
      timeout_limit = timeout_limit,
      method = method
    )
    if (isFALSE(is.na(archive_published$hash))) {
      actual_hash <- compute_sha256(bin_path)
      if (is.na(actual_hash)) {
        return(warn_unverified(
          "Could not compute the SHA256 hash of the downloaded binary."
        ))
      }
      archive_hash <- tolower(archive$hash %||% NA_character_)
      if (
        isTRUE(identical(archive_published$hash, tolower(actual_hash))) ||
          isTRUE(identical(archive_published$hash, archive_hash))
      ) {
        return(invisible(TRUE))
      }
      if (isFALSE(is.na(archive_hash))) {
        return(warn_mismatch(
          "SHA256 checksum mismatch for the archive of {.path {bin_path}}.",
          archive_published$hash,
          archive_hash
        ))
      }
    }
  }
  if (identical(published$problem, "download")) {
    return(warn_unverified(
      "Could not download the SHA256 checksum for verification."
    ))
  }
  # Not a checksum file at all (e.g. an HTML error page served with a 200
  # status by a proxy): verification is not possible, which is not a
  # mismatch.
  if (identical(published$problem, "invalid")) {
    return(warn_unverified(
      "The downloaded SHA256 checksum file is not valid."
    ))
  }
  expected_hash <- published$hash

  # Compute SHA256 of the candidate binary (see `compute_sha256()` for the
  # methods it tries).
  actual_hash <- compute_sha256(bin_path)

  if (is.na(actual_hash)) {
    return(warn_unverified(
      "Could not compute the SHA256 hash of the downloaded binary."
    ))
  }

  if (!identical(tolower(actual_hash), tolower(expected_hash))) {
    return(warn_mismatch(
      "SHA256 checksum mismatch for {.path {bin_path}}.",
      expected_hash,
      actual_hash
    ))
  }

  return(invisible(TRUE))
}

#' Download and read a published SHA256 checksum file
#'
#' @param urls Character vector of mirror endpoints.
#' @param timeout_limit,method Passed to `try_download_from_mirrors()`.
#'
#' @returns A list with `hash`, the lower-case hash or `NA_character_`, and
#'   `problem`: `NA` when `hash` was read, `"download"` when no endpoint
#'   gave a file, `"invalid"` when the file holds no hash.
#'
#' @keywords internal
#' @noRd
download_published_sha256 <- function(urls, timeout_limit, method) {
  sha256_tmpfile <- base::tempfile(fileext = ".sha256")
  on.exit(
    if (file.exists(sha256_tmpfile)) {
      try(base::file.remove(sha256_tmpfile), silent = TRUE)
    },
    add = TRUE
  )
  downloaded <- try_download_from_mirrors(
    urls = urls,
    destfile = sha256_tmpfile,
    timeout_limit = timeout_limit,
    method = method,
    quiet = TRUE
  )
  if (isFALSE(downloaded)) {
    return(list(hash = NA_character_, problem = "download"))
  }
  hash <- tryCatch(
    parse_sha256_file(sha256_tmpfile),
    error = function(e) NA_character_
  )
  if (is.na(hash)) {
    return(list(hash = NA_character_, problem = "invalid"))
  }
  return(list(hash = tolower(hash), problem = NA_character_))
}

#' Read the hash from a published SHA256 checksum file
#'
#' Accepts a bare hash (the format of the micromamba release files) and the
#' `sha256sum` format `<hash>  <file name>`.
#'
#' @param path Path to the checksum file.
#'
#' @returns The lower-case 64-digit hex hash, or `NA_character_` when the
#'   file does not start with one.
#'
#' @keywords internal
#' @noRd
parse_sha256_file <- function(path) {
  first_line <- base::readLines(path, n = 1L, warn = FALSE)
  if (length(first_line) == 0L) {
    return(NA_character_)
  }
  token <- strsplit(base::trimws(first_line), "[[:space:]]+")[[1L]][1L]
  if (isFALSE(grepl("^[0-9a-fA-F]{64}$", token))) {
    return(NA_character_)
  }
  return(tolower(token))
}

#' Check whether `tools::sha256sum()` is available
#'
#' Base R provides `tools::sha256sum()` from R 4.5.0 onward. Checks both the
#' R version and the function's presence in the `tools` namespace. The
#' double-check is needed because `condathis` requires only R >= 4.3 and a
#' patched or vendored R build can claim a high version without a matching
#' `tools`.
#'
#' @returns Logical.
#'
#' @keywords internal
#' @noRd
has_tools_sha256sum <- function() {
  return(
    isTRUE(getRversion() >= "4.5.0") &&
      isTRUE(exists(
        "sha256sum",
        where = asNamespace("tools"),
        inherits = FALSE
      ))
  )
}

#' Known-answer test for a system SHA256 command
#'
#' Shelling out to an external `sha256sum`/`shasum` binary means trusting
#' whatever happens to be on `PATH` under that name. It could be a
#' different tool, a broken build, or a shadowing binary. This runs the
#' command against the standard SHA-256 test vector for the ASCII string
#' `"abc"` (`ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`)
#' and trusts the command only if it reproduces that exact hash. On Linux,
#' a `certutil` on `PATH` is the unrelated NSS tool, which fails this test.
#'
#' @param sha_cmd Character string. `"sha256sum"`, `"shasum"` or
#'   `"certutil"`.
#'
#' @returns Logical. `TRUE` only if the command exists, runs successfully,
#'   and reproduces the known-answer hash.
#'
#' @keywords internal
#' @noRd
sha256_command_is_trustworthy <- function(sha_cmd) {
  if (isFALSE(nzchar(sha256_command_path(sha_cmd)))) {
    return(FALSE)
  }
  known_answer <- "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  test_file <- base::tempfile()
  on.exit(
    if (file.exists(test_file)) {
      try(base::file.remove(test_file), silent = TRUE)
    },
    add = TRUE
  )
  writeBin(charToRaw("abc"), test_file)
  actual <- run_sha256_command(sha_cmd, test_file)
  return(isTRUE(identical(actual, known_answer)))
}

#' Where a system SHA256 command is
#'
#' `certutil` is looked up in `%SystemRoot%\System32` first, where Windows
#' always has it, so a program of that name earlier on `PATH` is not used.
#' The other commands, and `certutil` when that file does not exist, are
#' looked up on `PATH`.
#'
#' @param sha_cmd Character string. `"sha256sum"`, `"shasum"` or
#'   `"certutil"`.
#'
#' @returns Character string, the path of the program, or `""` when it was
#'   not found.
#'
#' @keywords internal
#' @noRd
sha256_command_path <- function(sha_cmd) {
  if (identical(sha_cmd, "certutil") && isTRUE(is_windows())) {
    system_root <- Sys.getenv("SystemRoot", unset = "")
    if (isTRUE(nzchar(system_root))) {
      system_certutil <- file.path(system_root, "System32", "certutil.exe")
      if (isTRUE(file.exists(system_certutil))) {
        return(system_certutil)
      }
    }
  }
  return(unname(Sys.which(sha_cmd)))
}

#' Run a system SHA256 command and extract a validated hash from its output
#'
#' `sha256sum` and `shasum -a 256` print `<hash>  <file name>`.
#' `certutil -hashfile <file> SHA256`, which every Windows has, prints a
#' header line, the hash, and a line that says the command succeeded (see
#' `parse_certutil_sha256()`).
#'
#' @param sha_cmd Character string. `"sha256sum"`, `"shasum"` or
#'   `"certutil"`.
#' @param file_path Character string. Path to the file to hash.
#'
#' @returns Character string with the lowercase hex SHA256 hash, or
#'   `NA_character_` on any failure - including output that doesn't look
#'   like a real SHA-256 digest (exactly 64 hex characters), which is
#'   rejected outright rather than passed along as a "hash".
#'
#' @keywords internal
#' @noRd
run_sha256_command <- function(sha_cmd, file_path) {
  sha_args <- switch(
    sha_cmd,
    shasum = c("-a", "256", file_path),
    certutil = c("-hashfile", file_path, "SHA256"),
    file_path
  )
  # `certutil` runs from its full path (see `sha256_command_path()`). The
  # other commands run by name, as before.
  sha_program <- if (identical(sha_cmd, "certutil")) {
    sha256_command_path(sha_cmd)
  } else {
    sha_cmd
  }
  sha_result <- base::tryCatch(
    {
      processx::run(sha_program, sha_args, error_on_status = FALSE)
    },
    error = function(e) {
      list(status = 1L, stdout = "")
    }
  )
  if (isFALSE(identical(sha_result$status, 0L))) {
    return(NA_character_)
  }
  if (identical(sha_cmd, "certutil")) {
    return(parse_certutil_sha256(sha_result$stdout))
  }
  # Output format: "hash  filename\n". GNU coreutils prefixes the hash with
  # a backslash ("\hash  filename\n") when the filename contains a backslash
  # or newline. This happens on Windows, where every absolute path contains
  # backslashes. Strip the backslash, or the 64-hex-char check below
  # rejects a valid hash. It is rare on Linux and macOS.
  hash_field <- base::trimws(strsplit(sha_result$stdout, "\\s+")[[1L]][1L])
  hash_field <- base::sub("^\\\\", "", hash_field)
  if (isFALSE(grepl("^[0-9a-fA-F]{64}$", hash_field))) {
    return(NA_character_)
  }
  return(tolower(hash_field))
}

#' Read the hash from the output of `certutil -hashfile <file> SHA256`
#'
#' The output is, on Windows 10 and 11:
#'
#' ```
#' SHA256 hash of C:\path\file:
#' ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
#' CertUtil: -hashfile command completed successfully.
#' ```
#'
#' Older Windows separate the bytes of the hash with spaces, and the first
#' and last lines are in the language of the system, in its code page. So
#' the hash is the one line that is 64 hexadecimal digits once its white
#' space is removed. The first line cannot be one: it has a colon.
#'
#' @param stdout Character string, the standard output of `certutil`.
#'
#' @returns The lower-case 64-digit hex hash, or `NA_character_` when no
#'   line, or more than one line, holds a hash.
#'
#' @keywords internal
#' @noRd
parse_certutil_sha256 <- function(stdout) {
  if (isFALSE(rlang::is_string(stdout)) || isTRUE(is.na(stdout))) {
    return(NA_character_)
  }
  # `useBytes`: the localized lines need not be valid in the session's
  # encoding.
  hashes <- base::tryCatch(
    {
      lines <- strsplit(stdout, "\r\n|\r|\n", useBytes = TRUE)[[1L]]
      lines <- gsub("[[:space:]]", "", lines, useBytes = TRUE)
      lines[grepl("^[0-9a-fA-F]{64}$", lines, useBytes = TRUE)]
    },
    error = function(e) character(0L)
  )
  if (isFALSE(identical(length(hashes), 1L))) {
    return(NA_character_)
  }
  return(tolower(hashes[[1L]]))
}

#' Compute SHA256 Hash of a File
#'
#' Computes the SHA256 hash of a file using the best available method, in
#' order:
#' 1. `tools::sha256sum()` - base R (since R 4.5.0, see
#'    `has_tools_sha256sum()`), no subprocess, no system dependency.
#' 2. `digest::digest()` - a `Suggests` dependency, also pure R, no
#'    subprocess.
#' 3. A system `sha256sum` (Linux) or `shasum -a 256` (macOS) command -
#'    the least reliable option, since it shells out to whatever binary
#'    happens to be on `PATH`, so it's tried last and only trusted after
#'    passing `sha256_command_is_trustworthy()`'s known-answer test.
#' 4. On Windows, `certutil -hashfile <file> SHA256`, which every Windows
#'    has, also only after the known-answer test. On R 4.3 and 4.4 without
#'    `digest`, and without Rtools or Git on `PATH`, nothing else works
#'    there.
#'
#' Never errors: any failure at any step falls through to the next, and
#' returns `NA_character_` if every method is unavailable or untrustworthy.
#' Checksum verification is warn-and-continue by design (see
#' `verify_micromamba_checksum()`) - a missing or broken hashing tool must
#' never block an install.
#'
#' @param file_path Character string. Path to the file to hash.
#'
#' @returns Character string with the lowercase hex SHA256 hash, or
#'   `NA_character_` if computation failed.
#'
#' @keywords internal
#' @noRd
compute_sha256 <- function(file_path) {
  if (isTRUE(has_tools_sha256sum())) {
    # Looked up at run time: `tools::sha256sum` would be a static reference,
    # which `R CMD check` flags on R < 4.5.0.
    sha256sum <- get(
      "sha256sum",
      envir = asNamespace("tools"),
      inherits = FALSE
    )
    result <- base::tryCatch(
      unname(sha256sum(file_path)),
      error = function(e) NA_character_
    )
    if (isTRUE(!is.na(result) && nzchar(result))) {
      return(tolower(result))
    }
  }

  if (isTRUE(base::requireNamespace("digest", quietly = TRUE))) {
    result <- base::tryCatch(
      digest::digest(file = file_path, algo = "sha256"),
      error = function(e) NA_character_
    )
    if (isTRUE(!is.na(result) && nzchar(result))) {
      return(tolower(result))
    }
  }

  sha_cmds <- c("sha256sum", "shasum")
  if (isTRUE(is_windows())) {
    sha_cmds <- c(sha_cmds, "certutil")
  }
  for (sha_cmd in sha_cmds) {
    if (isTRUE(sha256_command_is_trustworthy(sha_cmd))) {
      result <- run_sha256_command(sha_cmd, file_path)
      if (isFALSE(is.na(result))) {
        return(result)
      }
    }
  }

  return(NA_character_)
}

#' Poll for a file's existence with a short backoff
#'
#' On Windows, antivirus real-time scanning can briefly hold a handle on a
#' just-extracted or just-downloaded executable. `fs::file_exists()` then
#' returns `FALSE` for a few hundred milliseconds, which caused intermittent
#' `install_micromamba()` failures. A short poll absorbs that race. It still
#' returns `FALSE` if the file does not appear within `attempts * delay_secs`.
#'
#' @keywords internal
#' @noRd
file_exists_retry <- function(path, attempts = 5L, delay_secs = 0.2) {
  for (i in seq_len(attempts)) {
    if (isTRUE(fs::file_exists(path))) {
      return(TRUE)
    }
    if (i < attempts) {
      Sys.sleep(delay_secs)
    }
  }
  return(FALSE)
}
