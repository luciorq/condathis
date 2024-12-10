#' Retrieve and Create the `condathis` Data Directory
#'
#' Retrieves the installation directory for the `condathis` package, creating it if it does not exist.
#' This function ensures that the package data directory complies with the [freedesktop's XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/latest/).
#' The base path can be controlled by the `XDG_DATA_HOME` environment variable.
#' Additionally, on Windows, `%LOCALAPPDATA%` is also accepted as the base installation directory.
#'
#' @details
#' If the directory does not exist, it will be created. On macOS,
#' special handling is applied to avoid spaces in the path,
#' as `micromamba run` fails if there are spaces in the path (e.g., in `~/Library/Application Support/condathis`).
#' Therefore, Unix-style paths are used on macOS.
#'
#' @return
#' A character string representing the normalized, real path to the `condathis` data directory.
#'
#' @examples
#' condathis::with_sandbox_dir({
#'   condathis::get_install_dir()
#'   #> /home/username/.local/share/condathis
#' })
#'
#' @export
get_install_dir <- function() {
  dir_path <- get_condathis_path()
  if (isFALSE(fs::dir_exists(dir_path))) {
    fs::dir_create(dir_path)
  }
  dir_path <- base::normalizePath(dir_path, mustWork = FALSE)
  return(fs::path_real(dir_path))
}
