#' Install Micromamba binaries in a `condathis` controlled path.
#' @param timeout_limit Timeout limit for downloading.
#' @param download_method Argument passed to `method` argument from
#'   `utils::download.file()` function.
#' @param force Force or overwrite the download of the micrommamba binaries.
#' @export
install_micromamba <- function(timeout_limit = 3600,
                               download_method = "auto",
                               force = FALSE) {
  # Implementation of:
  # + wget -qO- https://micromamba.snakepit.net/api/micromamba/linux-$ARCH/latest
  # + | tar -xvj bin/micromamba

  umamba_bin_path <- micromamba_bin_path()

  if (isTRUE(fs::file_exists(umamba_bin_path)) & isFALSE(force)) {
    cli::cli_inform(c(
      "i" = "{.var micromamba} is already installed at {.path {umamba_bin_path}}"
    ))
    return(invisible(umamba_bin_path))
  }

  sys_arch <- get_sys_arch()

  # CPU achitecture dictionary from:
  # + https://github.com/mamba-org/mamba/issues/1437#issue-1121921978
  sys_arch_str <- dplyr::case_when(
    sys_arch == "Linux-x86_64" ~ "linux-64",
    sys_arch == "Darwin-x86_64" ~ "osx-64",
    sys_arch == "MacOSX-x86_64" ~ "osx-64",
    sys_arch == "Windows-x86_64" ~ "win-64",
    sys_arch == "Darwin-arm64" ~ "osx-arm64",
    sys_arch == "MacOSX-arm64" ~ "osx-arm64",
    sys_arch == "Linux-aarch64" ~ "linux-aarch64",
    sys_arch == "Linux-ppc64le" ~ "linux-ppc64le",
    TRUE ~ ""
  )

  if (isTRUE(sys_arch_str == "")) {
    cli::cli_abort(c(
     `x` = "{.path micromamba} is not available for {.code {sys_arch}}. CPU architecture"
    ))
  }

  base_url <- "https://micromamba.snakepit.net/api/micromamba/"
  download_url <- paste0(base_url, sys_arch_str, "/latest")

  output_dir <- get_install_dir()
  output_dir <- fs::path_abs(output_dir)

  if (!fs::dir_exists(output_dir)) {
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
        method = download_method
      )
    }
  )

  untar_dir <- fs::path(output_dir, "micromamba")

  if (!fs::dir_exists(untar_dir)) {
    fs::dir_create(untar_dir)
  }

  utils::untar(
    tarfile = full_dl_path,
    exdir = fs::path_real(untar_dir)
  )

  if (fs::file_exists(full_dl_path)) {
    fs::file_delete(full_dl_path)
  }

  # TODO(luciorq): Check for necessity of changing permissions on Unix/Linux
  # if (fs::file_exists(full_output_path)) {
  #  fs::file_chmod(full_output_path, mode = "u+x")
  # }

  # umamba_bin_path <- micromamba_bin_path()
  if (isTRUE(dl_res == 0) & fs::file_exists(umamba_bin_path)) {
    cli::cli_inform(
      c(
        `v` = "{.var micromamba} successfully downloaded."
      )
    )
  }
  invisible(umamba_bin_path)
}

