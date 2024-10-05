#' Install Micromamba binaries in a `condathis` controlled path.
#'
#' This function downloads and installs the Micromamba binaries in the path
#'   managed by the `condathis` package. Micromamba is a lightweight
#'   implementation of the Conda package manager and provides an efficient way
#'   to create and manage conda environments.
#'
#' @param micromamba_version Character. Version string used for downloading
#'   `micromamba`.
#'
#' @param timeout_limit Numeric. Timeout limit for downloading the Micromamba
#'   binaries, in seconds. Defaults to 3600 seconds (1 hour).
#'
#' @param download_method  Character. Argument passed to the `method` argument
#'   of the `utils::download.file()` function used for downloading the binaries.
#'   Defaults to "auto".
#'
#' @param force Logical. If set to TRUE, the download and installation of the
#'   Micromamba binaries will be forced, even if they already exist in the
#'   system or `condathis` controlled path. Defaults to FALSE.
#'
#' @export
install_micromamba <- function(micromamba_version = "2.0.2-0",
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

  # TODO: @luciorq Native windows support is not working.
  # + The output of `get_sys_arch()` is "Windows-x86-64" replace with `win-64`
  sys_arch_str <- is_micromamba_available_for_arch()

  # TODO: @luciorq Replace with GitHub releases URL:
  # + <https://github.com/mamba-org/micromamba-releases/releases/>
  # + Also implemented in `luciorq/shell-lib` as:
  # + `conda_platform="$(get_conda_platform)";`
  # + `download_url="https://github.com/mamba-org/micromamba-releases/releases/latest/download/micromamba-${conda_platform}";`
  # + Versioned URL: <https://github.com/mamba-org/micromamba-releases/releases/download/2.0.1-0/micromamba-linux-64.tar.bz2>
  # + <https://github.com/mamba-org/micromamba-releases>
  # base_url <- "https://micromamba.snakepit.net/api/micromamba/"

  # TODO: @luciorq Additional URL on conda.anaconda.org server
  # + MacOS ARM64: <https://conda.anaconda.org/conda-forge/osx-arm64/micromamba-1.5.8-0.tar.bz2>
  # + Linux AMD64: <https://conda.anaconda.org/conda-forge/linux-64/micromamba-1.5.8-0.tar.bz2>
  # + Windows AMD64: <https://conda.anaconda.org/conda-forge/win-64/micromamba-1.5.8-0.tar.bz2>

  # TODO: @luciorq Also check <https://micro.mamba.pm/api/micromamba/linux-64/latest>

  # TODO: @luciorq check if GitHub URL is reachable, otherwise use
  # + snakepit URL
  # + Set main download to be from GitHub releases

  # Snakepit URLs
  # base_url <- "https://micromamba.snakepit.net/api/micromamba/"
  # download_url <- paste0(base_url, sys_arch_str, "/latest")

  # GitHub URLs
  base_url <- "https://github.com/mamba-org/micromamba-releases/releases/download/"
  umamba_version <- micromamba_version
  download_url <- paste0(
    base_url, umamba_version, "/micromamba-", sys_arch_str, ".tar.bz2"
  )


  output_dir <- get_install_dir()
  output_dir <- fs::path_abs(output_dir)

  if (isFALSE(fs::dir_exists(output_dir))) {
    fs::dir_create(output_dir)
  }

  full_dl_path <- as.character(fs::path(output_dir, "micromamba-dl.tar.bz2"))

  # NOTE: @luciorq Windows needs `mode = "wb"` for
  # + downloading binary files.
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

  if (!fs::dir_exists(untar_dir)) {
    fs::dir_create(untar_dir)
  }

  # TODO: @luciorq GitHub release binaries will also remove
  # + the need to uncompress the bundle
  utils::untar(
    tarfile = full_dl_path,
    exdir = fs::path_expand(untar_dir)
  )

  # if (fs::file_exists(Sys.getenv("R_BZIPCMD"))) {
  # } else {
  #   output_bin_dir <- fs::path(output_dir, "micromamba", "bin")
  #   if (isFALSE(fs::dir_exists(output_bin_dir))) {
  #
  #   }
  #   full_dl_path <- as.character(fs::path(output_bin_dir, "micromamba"))
  #
  # }
  #

  if (fs::file_exists(full_dl_path)) {
    fs::file_delete(full_dl_path)
  }

  # TODO: (@luciorq) Check for necessity of changing permissions on Unix/Linux
  # if (fs::file_exists(full_output_path)) {
  #  fs::file_chmod(full_output_path, mode = "u+x")
  # }

  # umamba_bin_path <- micromamba_bin_path()
  if (isTRUE(dl_res == 0) && fs::file_exists(umamba_bin_path)) {
    cli::cli_inform(
      c(
        `v` = "{.pkg micromamba} successfully downloaded."
      )
    )
  }

  create_base_env()

  invisible(umamba_bin_path)
}
