#' Get the system-dependent condathis data path
#'
#' Returns the user data directory used by `condathis`.
#' On macOS, this helper avoids paths with spaces when possible.
#'
#' @returns A character string with the `condathis` data directory path.
#'
#' @keywords internal
#' @noRd
get_condathis_path <- function() {
  if (
    identical(Sys.getenv(x = "XDG_DATA_HOME", unset = "", names = FALSE), "") &&
      isTRUE(stringr::str_detect(get_sys_arch(), pattern = "^Darwin"))
  ) {
    withr::local_envvar(
      .new = list(
        `XDG_DATA_HOME` = fs::path_home(".local", "share")
      )
    )
  }
  dir_path <- tools::R_user_dir(package = "condathis", which = "data")
  return(fs::path(dir_path))
}
