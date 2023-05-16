get_sys_arch <- function() {
  os <- Sys.info()["sysname"]
  cpu_arch <- Sys.info()["machine"]
  return(paste0(os, "-", cpu_arch))
}


get_install_dir <- function() {
  sys_arch <- get_sys_arch()
  # TODO(luciorq): On MacOS micromamba run fail if there is space in the path
  # + as in ~/Library/Application Support/condathis"
  # + That is why we are using unix style for macos
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

#' Retrive the path to the `condathis` managed installation of `micromamba`.
#' @export
micromamba_bin_path <- function() {
  sys_arch <- get_sys_arch()

  output_dir <- get_install_dir()
  if (isTRUE(stringr::str_detect(sys_arch, "^Windows"))) {
    umamba_bin_path <- fs::path(
      output_dir, "micromamba", "Library", "bin", "micromamba.exe"
    )
  } else {
    umamba_bin_path <- fs::path(output_dir, "micromamba", "bin", "micromamba")
  }
  return(umamba_bin_path)
}
