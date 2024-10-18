#' Assert `condathis` Data Creation Path
#' @export
get_install_dir <- function() {
  dir_path <- get_condathis_path()
  if (isFALSE(fs::dir_exists(dir_path))) {
    fs::dir_create(dir_path)
  }
  return(fs::path_real(dir_path))
}

#' Retrieve System Dependent Data Path
#' @keywords internal
get_condathis_path <- function() {
  sys_arch <- get_sys_arch()
  # NOTE: @luciorq On MacOS `micromamba run` fail if there is space in the path
  # + as in "~/Library/Application Support/condathis"
  # + That is why we are using Unix style for MacOS
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
