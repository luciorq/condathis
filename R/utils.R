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

#' Retrieve the path to the `condathis` managed installation of `micromamba`.
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

#' List Installed Environments
#' @export
list_envs <- function() {
  umamba_bin_path <- micromamba_bin_path()
  env_root_dir <- get_install_dir()
  px_res <- processx::run(
    command = fs::path_real(umamba_bin_path),
    args = c(
      "env",
      "list",
      "-r",
      env_root_dir,
      "-q",
      "--json"
    ),
    spinner = TRUE
  )
  if (isTRUE(px_res$status == 0)) {
    envs_list <- jsonlite::fromJSON(px_res$stdout)
    return(envs_list$envs)
  } else {
    return(px_res$status)
  }
}

#' List Packages Installed Inside Environment
#' @inheritParams run
#' @export
list_packages <- function(env_name = "condathis-env") {
  umamba_bin_path <- micromamba_bin_path()
  env_root_dir <- get_install_dir()
  px_res <- processx::run(
    command = fs::path_real(umamba_bin_path),
    args = c(
      "list",
      "-r",
      env_root_dir,
      "-n",
      env_name
    ),
    spinner = TRUE
  )
  if (isTRUE(px_res$status == 0)) {
    cat(px_res$stdout)
    invisible(px_res)
  } else(
    return(px_res)
  )
}
