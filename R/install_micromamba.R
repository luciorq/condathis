#' Install Micromamba Binaries in the `condathis` Controlled Path
#'
#' Downloads and installs the Micromamba binaries in the path managed by the `condathis` package.
#' Micromamba is a lightweight implementation of the Conda package manager and provides an efficient way
#' to create and manage conda environments.
#'
#' @param micromamba_version Character string specifying the version of Micromamba to download.
#'   Defaults to `"2.0.4-0"`.
#'
#' @param timeout_limit Numeric value specifying the timeout limit for downloading the Micromamba
#'   binaries, in seconds. Defaults to `3600` seconds (1 hour).
#'
#' @param download_method Character string passed to the `method` argument of
#'   the `utils::download.file()` function used for downloading the binaries.
#'   Defaults to `"auto"`.
#'
#' @param force Logical. If set to TRUE, the download and installation of the
#'   Micromamba binaries will be forced, even if they already exist in the
#'   system or `condathis` controlled path. Defaults to FALSE.
#'
#' @return
#' Invisibly returns the path to the installed Micromamba binary.
#'
#' @details
#' This function checks if Micromamba is already installed in the `condathis` controlled path.
#' If not, it downloads the specified version from the official GitHub releases and installs it.
#' On Windows, it ensures the binary is downloaded correctly by setting the download mode to `"wb"`.
#' If the download fails, appropriate error messages are displayed.
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
install_micromamba <- function(micromamba_version = "2.0.5-0",
                               timeout_limit = 3600,
                               download_method = "auto",
                               force = FALSE) {
  umamba_bin_path <- micromamba_bin_path()

  if (isTRUE(fs::file_exists(umamba_bin_path)) && isFALSE(force)) {
    cli::cli_inform(c(
      "i" = "{.pkg micromamba} is already installed at {.path {umamba_bin_path}}."
    ))
    return(invisible(umamba_bin_path))
  }
  sys_arch_str <- is_micromamba_available_for_arch()
  base_url <- "https://github.com/mamba-org/micromamba-releases/releases/"
  if (isFALSE(check_connection(base_url))) {
    cli::cli_abort(
      message = c(
        `x` = "{.url {base_url}} is not reachable."
      ),
      class = "condathis_github_not_reachable"
    )
  }
  download_url <- paste0(
    base_url, "download/", micromamba_version, "/micromamba-", sys_arch_str, ".tar.bz2"
  )

  output_dir <- fs::path_abs(get_install_dir())

  if (isFALSE(fs::dir_exists(output_dir))) {
    fs::dir_create(output_dir)
  }

  full_dl_path <- as.character(fs::path(output_dir, "micromamba-dl.tar.bz2"))

  withr::with_options(
    new = base::list(
      timeout = base::max(
        base::unlist(base::options("timeout")),
        timeout_limit
      )
    ),
    code = {
      dl_res <- utils::download.file(
        url = download_url,
        destfile = full_dl_path,
        method = download_method,
        mode = "wb"
      )
    }
  )

  untar_dir <- fs::path(output_dir, "micromamba")

  if (isFALSE(fs::dir_exists(untar_dir))) {
    fs::dir_create(untar_dir)
  }

  utils::untar(
    tarfile = full_dl_path,
    exdir = fs::path_expand(untar_dir)
  )

  if (fs::file_exists(full_dl_path)) {
    fs::file_delete(full_dl_path)
  }

  if (isFALSE(nzchar(Sys.which("bzip2")) && fs::file_exists(umamba_bin_path))) {
    download_url <- paste0(
      base_url, "download/", micromamba_version, "/micromamba-", sys_arch_str
    )
    full_dl_path <- umamba_bin_path
    base_dl_dir <- fs::path(output_dir, "micromamba", "bin")
    if (isFALSE(fs::dir_exists(base_dl_dir))) {
      fs::dir_create(base_dl_dir)
    }
    withr::with_options(
      new = base::list(
        timeout = base::max(
          base::unlist(base::options("timeout")),
          timeout_limit
        )
      ),
      code = {
        dl_res <- utils::download.file(
          url = download_url,
          destfile = full_dl_path,
          method = download_method,
          mode = "wb"
        )
      }
    )
    fs::file_chmod(full_dl_path, mode = "u+x")
  }

  if (isFALSE(fs::file_exists(umamba_bin_path))) {
    cli::cli_abort(
      message = c(
        `x` = "{.file {umamba_bin_path}} was not extracted succesfully.",
        `!` = "This error may be caused by missing `bzip2` system library."
      ),
      class = "condathis_install_error_missing_bzip2"
    )
  }

  if (isTRUE(dl_res == 0) && fs::file_exists(umamba_bin_path)) {
    cli::cli_inform(
      c(
        `v` = "{.pkg micromamba} successfully downloaded."
      )
    )
  }

  if (isTRUE(fs::file_exists(umamba_bin_path))) {
    create_base_env()
  }

  invisible(umamba_bin_path)
}
