#' Install micromamba binaries in the managed condathis path
#'
#' Downloads and installs the `micromamba` executable used by `condathis`.
#'
#' @param micromamba_version Character string with the micromamba version.
#'   Defaults to `"2.8.1-0"`.
#' @param timeout_limit Numeric download timeout in seconds.
#'   Defaults to `3600`.
#' @param download_method Character string passed as the download method when
#'   `utils::download.file()` is used. Defaults to `"auto"`.
#' @param force Logical value that controls forced reinstallation.
#'   Defaults to `FALSE`.
#' @param verbose Character string controlling console output.
#'   Supported values are `"output"`, `"silent"`, `"cmd"`, `"spinner"`,
#'   and `"full"`. Defaults to `"output"`.
#'
#' @returns The installed micromamba binary path (a `fs_path`/character
#'   string), invisibly — not a `condathis_result` object like `run()`,
#'   `run_bin()`, `create_env()`, `install_packages()`, `remove_env()`, and
#'   `clean_cache()` return. This is intentional, not an oversight: those
#'   functions each wrap a single `micromamba` subprocess call, so a real
#'   status/stdout/stderr/pid is available to report. `install_micromamba()`
#'   downloads and extracts a binary directly (no `micromamba` subprocess
#'   involved at all), so there is no real process result to expose — the
#'   installed path is the only meaningful thing to return, exactly like
#'   `get_env_dir()`/`get_install_dir()`/`micromamba_bin_path()`. On
#'   failure, this function always raises an error rather than returning a
#'   partial or invalid path.
#'
#' @details
#' Download mirrors are tried in order until one succeeds.
#' When system `tar` and `bzip2` are available, a compressed archive may be
#' used first. Otherwise, or when extraction fails, a standalone binary is
#' downloaded.
#'
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   # Install the default version of Micromamba
#'   condathis::install_micromamba()
#'
#'   # Install a specific version of Micromamba
#'   condathis::install_micromamba(micromamba_version = "2.0.2-2")
#'
#'   # Force reinstallation of Micromamba
#'   condathis::install_micromamba(force = TRUE)
#' })
#' }
#'
#' @export
install_micromamba <- function(
  micromamba_version = "2.8.1-0",
  timeout_limit = 3600,
  download_method = "auto",
  force = FALSE,
  verbose = c(
    "output",
    "silent",
    "cmd",
    "spinner",
    "full"
  )
) {
  verbose_list <- parse_strategy_verbose(verbose = verbose)
  dl_quiet_flag <- TRUE
  if (isTRUE(verbose_list$strategy %in% c("output", "full"))) {
    dl_quiet_flag <- FALSE
  }
  umamba_bin_path <- micromamba_bin_path()

  if (isTRUE(fs::file_exists(umamba_bin_path)) && isFALSE(force)) {
    if (isFALSE(dl_quiet_flag)) {
      cli::cli_inform(c(
        `i` = "{.pkg micromamba} is already installed at {.path {umamba_bin_path}}."
      ))
    }
    return(invisible(umamba_bin_path))
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

  # --- Strategy 1: Download compressed .tar.bz2 and extract ---
  # --- Strategy 2 (fallback): Download uncompressed binary directly ---
  # Strategy 2 is used when tar/bzip2 are not available, or when Strategy 1
  # failed to extract.
  extraction_succeeded <- download_compressed_and_extract(
    compressed_urls = mirror_urls$compressed,
    output_dir = output_dir,
    untar_dir = untar_dir,
    umamba_bin_path = umamba_bin_path,
    timeout_limit = timeout_limit,
    download_method = download_method,
    dl_quiet_flag = dl_quiet_flag
  )
  if (isFALSE(extraction_succeeded)) {
    extraction_succeeded <- download_uncompressed_binary(
      uncompressed_urls = mirror_urls$uncompressed,
      umamba_bin_path = umamba_bin_path,
      timeout_limit = timeout_limit,
      download_method = download_method,
      dl_quiet_flag = dl_quiet_flag
    )
  }

  # --- Verify the binary exists ---
  if (isFALSE(file_exists_retry(umamba_bin_path))) {
    cli::cli_abort(
      message = c(
        `x` = "{.file {umamba_bin_path}} was not downloaded or extracted successfully.",
        `!` = paste0(
          "This error may be caused by missing system tools ",
          "({.code tar}, {.code bzip2}), network issues, or an ",
          "invalid version string."
        )
      ),
      class = "condathis_install_error_missing_bzip2"
    )
  }

  # --- Verify SHA256 checksum ---
  # Warn-and-continue by design (see verify_micromamba_checksum()): a
  # mismatch, or a failure to even compute/download a hash to compare,
  # never blocks the install. The GitHub-published .sha256 is fetched
  # dynamically for the exact version + platform, so this needs no
  # hardcoded hashes and no per-release maintenance.
  verify_micromamba_checksum(
    bin_path = umamba_bin_path,
    sha256_urls = mirror_urls$sha256,
    timeout_limit = timeout_limit,
    method = download_method,
    verbose = verbose_list
  )

  if (
    isTRUE(extraction_succeeded) &&
      verbose_list$strategy %in% c("full", "output")
  ) {
    cli::cli_inform(
      message = c(
        `v` = "{.pkg micromamba} successfully downloaded."
      )
    )
  }

  invisible(umamba_bin_path)
}

#' Download and extract the compressed micromamba archive
#'
#' Strategy 1 of `install_micromamba()`'s two download strategies: fetch the
#' `.tar.bz2` archive from the given mirrors and extract it with the system
#' `tar`/`bzip2` tools. A no-op (returns `FALSE` immediately) when those
#' tools aren't available — `install_micromamba()` falls back to
#' `download_uncompressed_binary()` in that case.
#'
#' @param compressed_urls Character vector of `.tar.bz2` mirror endpoints.
#' @param output_dir Directory the archive is downloaded into.
#' @param untar_dir Directory the archive is extracted into.
#' @param umamba_bin_path Expected path of the extracted binary, used to
#'   confirm extraction actually produced it.
#' @param timeout_limit,download_method,dl_quiet_flag Passed through to
#'   `try_download_from_mirrors()`.
#'
#' @returns Logical. `TRUE` only if the archive was downloaded *and*
#'   extracted *and* the binary is present afterward.
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
  dl_quiet_flag
) {
  if (isFALSE(can_extract_tar_bz2())) {
    return(FALSE)
  }

  full_dl_path <- as.character(
    fs::path(output_dir, "micromamba-dl.tar.bz2")
  )
  compressed_ok <- try_download_from_mirrors(
    urls = compressed_urls,
    destfile = full_dl_path,
    timeout_limit = timeout_limit,
    method = download_method,
    quiet = dl_quiet_flag
  )

  if (isFALSE(compressed_ok)) {
    # Clean up any partial download
    if (fs::file_exists(full_dl_path)) {
      try(fs::file_delete(full_dl_path), silent = TRUE)
    }
    return(FALSE)
  }

  # Extract the archive, suppressing warnings from tar/bzip2
  extract_result <- tryCatch(
    {
      suppressWarnings(
        utils::untar(
          tarfile = full_dl_path,
          exdir = fs::path_expand(untar_dir)
        )
      )
      TRUE
    },
    error = function(e) {
      FALSE
    },
    warning = function(w) {
      FALSE
    }
  )

  # Clean up the downloaded archive
  if (fs::file_exists(full_dl_path)) {
    try(fs::file_delete(full_dl_path), silent = TRUE)
  }

  return(
    isTRUE(extract_result) && isTRUE(file_exists_retry(umamba_bin_path))
  )
}

#' Download the standalone micromamba binary directly
#'
#' Strategy 2 of `install_micromamba()`'s two download strategies: used when
#' `tar`/`bzip2` are unavailable, or when `download_compressed_and_extract()`
#' failed to extract.
#'
#' @param uncompressed_urls Character vector of raw binary mirror endpoints.
#' @param umamba_bin_path Destination path for the downloaded binary.
#' @param timeout_limit,download_method,dl_quiet_flag Passed through to
#'   `try_download_from_mirrors()`.
#'
#' @returns Logical. `TRUE` if the binary was downloaded and made
#'   executable.
#'
#' @keywords internal
#' @noRd
download_uncompressed_binary <- function(
  uncompressed_urls,
  umamba_bin_path,
  timeout_limit,
  download_method,
  dl_quiet_flag
) {
  # This is not the right path on Windows
  base_dl_dir <- fs::path(base::dirname(umamba_bin_path))
  if (isFALSE(fs::dir_exists(base_dl_dir))) {
    fs::dir_create(base_dl_dir)
  }

  uncompressed_ok <- try_download_from_mirrors(
    urls = uncompressed_urls,
    destfile = umamba_bin_path,
    timeout_limit = timeout_limit,
    method = download_method,
    quiet = dl_quiet_flag
  )

  if (isFALSE(uncompressed_ok)) {
    return(FALSE)
  }

  fs::file_chmod(umamba_bin_path, mode = "u+x")
  return(TRUE)
}

#' Verify Micromamba Binary SHA256 Checksum
#'
#' Downloads the published SHA256 checksum from GitHub releases and compares
#' it against the locally installed binary. Emits a warning if the checksums
#' do not match, but does not abort (to allow manual override).
#'
#' The SHA256 checksum files on GitHub releases always contain the hash of the
#' standalone binary (not the archive). This means the same checksum works
#' regardless of whether the compressed or uncompressed download was used.
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
#'
#' @returns Invisible `TRUE` if checksum matches, `FALSE` if verification
#'   failed or was skipped.
#'
#' @keywords internal
#' @noRd
verify_micromamba_checksum <- function(
  bin_path,
  sha256_urls,
  timeout_limit = 3600,
  method = "auto",
  verbose = list(strategy = "silent")
) {
  if (isFALSE(fs::file_exists(bin_path))) {
    return(invisible(FALSE))
  }

  # Download the published checksum to a temporary file
  sha256_tmpfile <- base::tempfile(fileext = ".sha256")
  on.exit(
    if (file.exists(sha256_tmpfile)) {
      try(base::file.remove(sha256_tmpfile), silent = TRUE)
    },
    add = TRUE
  )

  sha256_ok <- try_download_from_mirrors(
    urls = sha256_urls,
    destfile = sha256_tmpfile,
    timeout_limit = timeout_limit,
    method = method,
    quiet = TRUE
  )

  if (isFALSE(sha256_ok)) {
    if (verbose$strategy %in% c("full", "output")) {
      cli::cli_warn(c(
        `!` = "Could not download SHA256 checksum for verification.",
        `i` = "Skipping checksum verification."
      ))
    }
    return(invisible(FALSE))
  }

  expected_hash <- tryCatch(
    {
      hash_content <- base::readLines(sha256_tmpfile, n = 1L, warn = FALSE)
      base::trimws(hash_content)
    },
    error = function(e) {
      NA_character_
    }
  )

  if (is.na(expected_hash) || !nzchar(expected_hash)) {
    return(invisible(FALSE))
  }

  # Compute SHA256 of the installed binary.
  # R base does not have a built-in SHA256 function.
  # Try the digest package first, then fall back to system commands
  # (sha256sum on Linux, shasum on macOS).
  actual_hash <- compute_sha256(bin_path)

  if (is.na(actual_hash)) {
    if (verbose$strategy %in% c("full", "output")) {
      cli::cli_warn(c(
        `!` = "Could not compute SHA256 hash of the downloaded binary.",
        `i` = "Skipping checksum verification."
      ))
    }
    return(invisible(FALSE))
  }

  if (!identical(tolower(actual_hash), tolower(expected_hash))) {
    cli::cli_warn(c(
      `!` = "SHA256 checksum mismatch for {.file {bin_path}}.",
      `i` = "Expected: {.val {expected_hash}}",
      `i` = "Actual:   {.val {actual_hash}}",
      `!` = paste0(
        "The binary may be corrupted or tampered with. ",
        "Consider reinstalling with {.code install_micromamba(force = TRUE)}."
      )
    ))
    return(invisible(FALSE))
  }

  return(invisible(TRUE))
}

#' Check whether `tools::sha256sum()` is available
#'
#' Added to base R in version 4.5.0 (confirmed against R's own `NEWS`:
#' "Added function sha256sum() in package tools analogous to md5sum()",
#' under "CHANGES IN R 4.5.0"). Checks both the R version and the
#' function's actual presence in the `tools` namespace — belt and
#' suspenders, since `condathis` only requires R >= 4.3 and must not
#' assume a newer `tools` is present just because the running R claims a
#' high enough version (e.g. a patched/vendored R build).
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
#' whatever happens to be on `PATH` under that name — it could be a
#' different tool entirely, a broken build, or something else shadowing
#' the real one, and behavior has been observed to differ across mirrors,
#' download strategies, and operating systems during development. Rather
#' than trusting the exit status alone, this runs the command against the
#' standard SHA-256 test vector for the ASCII string `"abc"`
#' (`ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`,
#' cross-checked directly against `tools::sha256sum()`, `digest::digest()`,
#' `openssl::sha256()`, and Python's `hashlib`, which all agree) and only
#' trusts the command if it reproduces that exact hash.
#'
#' @param sha_cmd Character string. `"sha256sum"` or `"shasum"`.
#'
#' @returns Logical. `TRUE` only if the command exists, runs successfully,
#'   and reproduces the known-answer hash.
#'
#' @keywords internal
#' @noRd
sha256_command_is_trustworthy <- function(sha_cmd) {
  if (isFALSE(nzchar(Sys.which(sha_cmd)))) {
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

#' Run a system SHA256 command and extract a validated hash from its output
#'
#' @param sha_cmd Character string. `"sha256sum"` or `"shasum"`.
#' @param file_path Character string. Path to the file to hash.
#'
#' @returns Character string with the lowercase hex SHA256 hash, or
#'   `NA_character_` on any failure — including output that doesn't look
#'   like a real SHA-256 digest (exactly 64 hex characters), which is
#'   rejected outright rather than passed along as a "hash".
#'
#' @keywords internal
#' @noRd
run_sha256_command <- function(sha_cmd, file_path) {
  sha_args <- if (identical(sha_cmd, "shasum")) {
    c("-a", "256", file_path)
  } else {
    file_path
  }
  sha_result <- base::tryCatch(
    {
      processx::run(sha_cmd, sha_args, error_on_status = FALSE)
    },
    error = function(e) {
      list(status = 1L, stdout = "")
    }
  )
  if (isFALSE(identical(sha_result$status, 0L))) {
    return(NA_character_)
  }
  # Output format: "hash  filename\n", or "\hash  filename\n" (a leading
  # backslash directly prefixing the hash, no space) when the filename
  # contains a backslash or newline — GNU coreutils' sha256sum/md5sum
  # escaping convention, flagging that the filename part has embedded
  # "\\"/"\n" escapes. Essentially guaranteed on Windows, where every
  # absolute path contains backslashes (confirmed on real Windows CI: the
  # unstripped leading "\" failed the 64-hex-char check below and made a
  # perfectly valid hash look untrustworthy), vs. almost never on Linux/
  # macOS, where backslash isn't a path separator.
  hash_field <- base::trimws(strsplit(sha_result$stdout, "\\s+")[[1L]][1L])
  hash_field <- base::sub("^\\\\", "", hash_field)
  if (isFALSE(grepl("^[0-9a-fA-F]{64}$", hash_field))) {
    return(NA_character_)
  }
  return(tolower(hash_field))
}

#' Compute SHA256 Hash of a File
#'
#' Computes the SHA256 hash of a file using the best available method, in
#' order:
#' 1. `tools::sha256sum()` — base R (since R 4.5.0, see
#'    `has_tools_sha256sum()`), no subprocess, no system dependency.
#' 2. `digest::digest()` — a `Suggests` dependency, also pure R, no
#'    subprocess.
#' 3. A system `sha256sum` (Linux) or `shasum -a 256` (macOS) command —
#'    the least reliable option, since it shells out to whatever binary
#'    happens to be on `PATH`, so it's tried last and only trusted after
#'    passing `sha256_command_is_trustworthy()`'s known-answer test.
#'
#' Never errors: any failure at any step falls through to the next, and
#' returns `NA_character_` if every method is unavailable or untrustworthy.
#' Checksum verification is warn-and-continue by design (see
#' `verify_micromamba_checksum()`) — a missing or broken hashing tool must
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
    result <- base::tryCatch(
      unname(tools::sha256sum(file_path)),
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

  for (sha_cmd in c("sha256sum", "shasum")) {
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
#' On Windows, antivirus real-time scanning can briefly hold its own handle
#' on a just-extracted or just-downloaded executable, making
#' `fs::file_exists()` return `FALSE` for a few hundred milliseconds even
#' though extraction/download already succeeded — observed directly as an
#' intermittent `install_micromamba()` failure on a real Windows machine
#' (`force = TRUE` failed once, then succeeded on immediate retry with no
#' code change in between). A short poll absorbs that race without masking
#' a genuine missing file: it still returns `FALSE` if the file never shows
#' up within `attempts * delay_secs`.
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
