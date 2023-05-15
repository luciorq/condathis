get_sys_arch <- function() {
  os <- Sys.info()["sysname"]
  cpu_arch <- Sys.info()["machine"]
  return(paste0(os, "-", cpu_arch))
}

get_install_dir <- function() {
  dir_path <- rappdirs::user_data_dir(
    appname = "condathis",
    appauthor = "luciorq"
  )
  return(dir_path)
}
