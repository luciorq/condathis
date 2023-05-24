#' Install Micromamba binaries in a `condathis` controlled path.
#'
#' This function downloads and installs the Micromamba binaries in the path
#'   managed by the `condathis` package. Micromamba is a lightweight
#'   implementation of the Conda package manager and provides an efficient way
#'   to create and manage conda environments.
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
install_micromamba <- function(timeout_limit = 3600,
                               download_method = "auto",
                               force = FALSE) {
  umamba_bin_path <- micromamba_bin_path()
  if (isTRUE(fs::file_exists(umamba_bin_path)) & isFALSE(force)) {
    cli::cli_inform(c(
      "i" = "{.pkg micromamba} is already installed at {.path {umamba_bin_path}}."
    ))
    return(invisible(umamba_bin_path))
  }
  # if (isFALSE(force)) {
  #   user_bin_path <- micromamba_user_installed()
  #   if (isFALSE(user_bin_path == "")) {
  #     micromamba_version <- system(
  #       paste0(umamba_bin_path, " --version"),
  #       intern = TRUE
  #     )
  #     cli::cli_inform(c(
  #       `!` = "Using {.file {umamba_bin_path}} version {.field {micromamba_version}}."
  #     ))
  #     return(invisible(user_bin_path))
  #   }
  # }
  sys_arch <- get_sys_arch()
  sys_arch_str <- ifelse(
    test = sys_arch == "Linux-x86_64", yes = "linux-64",
    no = ifelse(
      test = sys_arch == "Darwin-x86_64" | sys_arch == "MacOSX-x86_64",
      yes = "osx-64",
      no = ifelse(
        test = sys_arch == "Windows-x86_64",
        yes = "win-64",
        no = ifelse(
          test = sys_arch == "Darwin-arm64" | sys_arch == "MacOSX-arm64",
          yes = "osx-arm64",
          no = ifelse(
            test = sys_arch == "Linux-aarch64",
            yes = "linux-aarch64",
            no = ifelse(
              test = sys_arch == "Linux-ppc64le",
              yes = "linux-ppc64le",
              no = ""
            )
          )
        )
      )
    )
  )
  if (isTRUE(sys_arch_str == "")) {
    cli::cli_abort(c(
     `x` = "{.pkg micromamba} is not available for {.field {sys_arch}} CPU architecture."
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
    exdir = fs::path_expand(untar_dir)
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
        `v` = "{.pkg micromamba} successfully downloaded."
      )
    )
  }
  invisible(umamba_bin_path)
}
