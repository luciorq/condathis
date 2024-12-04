#' Retrieve System-Dependent Data Path for condathis
#'
#' Determines the appropriate user data directory for the `condathis` package based on the operating system.
#'   On macOS, it avoids using paths with spaces due to issues with `micromamba run` failing when there are spaces in the path.
#'
#' @details
#' This function uses the `[tools::R_user_dir()]` function to determine the user data directory.
#'
#' @return
#' A character string representing the path to the user data directory for `condathis`.
#'
#' @keywords internal
#' @noRd
get_condathis_path <- function() {
  if (isTRUE(Sys.getenv(x = "XDG_DATA_HOME") == "") && isTRUE(stringr::str_detect(get_sys_arch(), pattern = "^Darwin"))) {
    withr::local_envvar(
      .new = list(
        `XDG_DATA_HOME` = fs::path_home(".local", "share")
      )
    )
  }
  dir_path <- tools::R_user_dir(package = "condathis", which = "data")
  return(dir_path)
}
