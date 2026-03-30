#' Install Micromamba Binaries in the `condathis` Controlled Path
#'
#' Downloads and installs the Micromamba binaries in the path managed by the
#' `condathis` package.
#'   Micromamba is a lightweight implementation of the Conda package manager
#'   and provides an efficient way
#'   to create and manage conda environments.
#'
#' @param micromamba_version Character string specifying the version of
#'   Micromamba to download. Defaults to `"2.5.0-2"`.
#'
#' @param timeout_limit Numeric value specifying the timeout limit for
#'   downloading the Micromamba
#'   binaries, in seconds. Defaults to `3600` seconds (1 hour).
#'
#' @param download_method Character string passed to the `method` argument of
#'   the `utils::download.file()` function used for downloading the binaries
#'   when the `curl` package is not available.
#'   Defaults to `"auto"`.
#'
#' @param force Logical. If set to TRUE, the download and installation of the
#'   Micromamba binaries will be forced, even if they already exist in the
#'   system or `condathis` controlled path. Defaults to FALSE.
#'
#' @param verbose Character string indicating the verbosity level of the
#'   function.
#'   Can be one of `"full"`, `"output"`, `"silent"`. Defaults to `"output"`.
#'
#' @return
#' Invisibly returns the path to the installed Micromamba binary.
#'
#' @details
#' This function checks if Micromamba is already installed in the `condathis`
#'   controlled path. If not, it downloads the specified version from multiple
#'   mirror sources and installs it.
#'
#' The download strategy is:
#'
#' - If system `tar` and `bzip2` are available, download the compressed
#'   `.tar.bz2` archive (smaller download) and extract it.
#' - If `tar` or `bzip2` are not available, or if extraction fails,
#'   download the uncompressed standalone binary directly.
#'
#' Multiple mirror sources are tried in order:
#'
#' - GitHub Releases
#'   (`https://github.com/mamba-org/micromamba-releases/releases/`)
#' - micro.mamba.pm (official CDN)
#'   (`https://micro.mamba.pm/api/micromamba/`)
#' - conda-forge via Anaconda
#'   (`https://api.anaconda.org/download/conda-forge/`)
#' - conda-forge via prefix.dev
#'    (`https://repo.prefix.dev/conda-forge/`)
#'
#' The downloaded binary is verified against the SHA256 checksum published on
#'   GitHub releases. The `curl` package is preferred for downloads when
#'   available, with `utils::download.file()` as a fallback.
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
  micromamba_version = "2.5.0-2",
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

  if (
    isTRUE(fs::file_exists(umamba_bin_path)) &&
      isFALSE(force) &&
      isFALSE(dl_quiet_flag)
  ) {
    cli::cli_inform(c(
      `i` = "{.pkg micromamba} is already installed at {.path {umamba_bin_path}}."
    ))
    return(invisible(umamba_bin_path))
  }

  if (isTRUE(fs::file_exists(umamba_bin_path)) && isFALSE(force)) {
    return(invisible(umamba_bin_path))
  }

  sys_arch_str <- is_micromamba_available_for_arch()

  # Build mirror URLs for this platform and version
  mirror_urls <- get_micromamba_urls(
    sys_arch_str = sys_arch_str,
    micromamba_version = micromamba_version
  )

  # Verify at least one mirror is reachable
  any_reachable <- FALSE
  for (check_url in mirror_urls$check_urls) {
    if (isTRUE(check_connection(check_url))) {
      any_reachable <- TRUE
      break
    }
  }
  if (isFALSE(any_reachable)) {
    cli::cli_abort(
      message = c(
        `x` = "No download mirrors are reachable.",
        `i` = "Tried: {.url {mirror_urls$check_urls}}"
      ),
      class = "condathis_github_not_reachable"
    )
  }

  output_dir <- fs::path_abs(get_install_dir())
  if (isFALSE(fs::dir_exists(output_dir))) {
    fs::dir_create(output_dir)
  }

  untar_dir <- fs::path(output_dir, "micromamba")
  if (isFALSE(fs::dir_exists(untar_dir))) {
    fs::dir_create(untar_dir)
  }

  extraction_succeeded <- FALSE

  # --- Strategy 1: Download compressed .tar.bz2 and extract ---
  # Only attempt if tar and bzip2 are available on the system
  if (isTRUE(can_extract_tar_bz2())) {
    full_dl_path <- as.character(
      fs::path(output_dir, "micromamba-dl.tar.bz2")
    )
    compressed_ok <- try_download_from_mirrors(
      urls = mirror_urls$compressed,
      destfile = full_dl_path,
      timeout_limit = timeout_limit,
      method = download_method,
      quiet = dl_quiet_flag
    )

    if (isTRUE(compressed_ok)) {
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

      if (isTRUE(extract_result) && isTRUE(fs::file_exists(umamba_bin_path))) {
        extraction_succeeded <- TRUE
      }
    } else {
      # Clean up any partial download
      if (file.exists(full_dl_path)) {
        try(fs::file_delete(full_dl_path), silent = TRUE)
      }
    }
  }

  # --- Strategy 2: Download uncompressed binary directly ---
  # Used when tar/bzip2 are not available, or when extraction failed
  if (isFALSE(extraction_succeeded)) {
    base_dl_dir <- fs::path(output_dir, "micromamba", "bin")
    if (isFALSE(fs::dir_exists(base_dl_dir))) {
      fs::dir_create(base_dl_dir)
    }

    uncompressed_ok <- try_download_from_mirrors(
      urls = mirror_urls$uncompressed,
      destfile = umamba_bin_path,
      timeout_limit = timeout_limit,
      method = download_method,
      quiet = dl_quiet_flag
    )

    if (isTRUE(uncompressed_ok)) {
      fs::file_chmod(umamba_bin_path, mode = "u+x")
      extraction_succeeded <- TRUE
    }
  }

  # --- Verify the binary exists ---
  if (isFALSE(fs::file_exists(umamba_bin_path))) {
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

  if (isTRUE(fs::file_exists(umamba_bin_path))) {
    create_base_env(verbose = verbose_list$internal_verbose)
  }

  invisible(umamba_bin_path)
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
#' for checksums. The SHA256 is downloaded dynamically from:
#' ```
#' https://github.com/mamba-org/micromamba-releases/releases/download/<version>/micromamba-<arch>.sha256
#' ```
#' To manually verify a release checksum:
#' ```
#' curl -sL https://github.com/mamba-org/micromamba-releases/releases/download/2.5.0-2/micromamba-osx-arm64.sha256
#' ```
#'
#' @param bin_path Character string. Path to the micromamba binary to verify.
#' @param sha256_urls Character vector. URLs to try for downloading the
#'   SHA256 checksum file.
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

#' Compute SHA256 Hash of a File
#'
#' Computes the SHA256 hash of a file using the best available method:
#' 1. `digest` R package (if available)
#' 2. System `sha256sum` command (Linux)
#' 3. System `shasum -a 256` command (macOS)
#'
#' @param file_path Character string. Path to the file to hash.
#'
#' @returns Character string with the lowercase hex SHA256 hash, or
#'   `NA_character_` if computation failed.
#'
#' @keywords internal
#' @noRd
compute_sha256 <- function(file_path) {
  base::tryCatch(
    {
      if (requireNamespace("digest", quietly = TRUE)) {
        return(digest::digest(file = file_path, algo = "sha256"))
      }

      # Fall back to system command
      sha_cmd <- if (nzchar(Sys.which("sha256sum"))) {
        "sha256sum"
      } else if (nzchar(Sys.which("shasum"))) {
        "shasum"
      } else {
        return(NA_character_)
      }

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

      if (identical(sha_result$status, 0L)) {
        # Output format: "hash  filename\n"
        return(base::trimws(strsplit(sha_result$stdout, "\\s+")[[1L]][1L]))
      }

      NA_character_
    },
    error = function(e) {
      NA_character_
    }
  )
}
