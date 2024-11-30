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
