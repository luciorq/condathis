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
#' \dontrun{
#' condathis::get_install_dir()
#' #> /Users/myself/.local/share/condathis
#' }
#' @export
get_install_dir <- function() {
  dir_path <- get_condathis_path()
  if (isFALSE(fs::dir_exists(dir_path))) {
    fs::dir_create(dir_path)
  }
  dir_path <- base::normalizePath(dir_path)
  return(fs::path_real(dir_path))
}


#' Retrieve System-Dependent Data Path for condathis
#'
#' Determines the appropriate user data directory for the `condathis` package based on the operating system. On macOS, it avoids using paths with spaces due to issues with `micromamba run` failing when there are spaces in the path.
#'
#' @details
#' This function uses the `rappdirs` package to determine the user data directory.
#' On macOS, it specifies `os = "unix"` to avoid paths like `~/Library/Application Support/condathis`, which contain spaces.
#'
#' @return
#' A character string representing the path to the user data directory for `condathis`.
#'
#' @keywords internal
get_condathis_path <- function() {
  sys_arch <- get_sys_arch()
  if (isTRUE(stringr::str_detect(sys_arch, "^Darwin"))) {
    dir_path <- rappdirs::user_data_dir(
      appname = "condathis",
      appauthor = "luciorq",
      os = "unix"
    )
  } else {
    dir_path <- rappdirs::user_data_dir(
      appname = "condathis",
      appauthor = "luciorq"
    )
  }
  return(dir_path)
}
