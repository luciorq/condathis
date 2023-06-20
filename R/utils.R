#' Return OS and CPU Architecture
get_sys_arch <- function() {
  os <- Sys.info()["sysname"]
  cpu_arch <- Sys.info()["machine"]
  return(paste0(os, "-", cpu_arch))
}

#' Retrieve `condathis` Data Creation Path
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
  if (isFALSE(fs::dir_exists(dir_path))) {
    fs::dir_create(dir_path)
  }
  return(fs::path_real(dir_path))
}

#' Retrieve `condathis` Cache Directory Path
get_cache_dir <- function() {
  sys_arch <- get_sys_arch()
  # TODO(luciorq): On MacOS micromamba run fail if there is space in the path
  # + as in ~/Library/Application Support/condathis"
  # + That is why we are using unix style for macos
  if (isTRUE(stringr::str_detect(sys_arch, "^Darwin"))) {
    dir_path <- rappdirs::user_cache_dir(
      appname = "condathis",
      appauthor = "luciorq",
      os = "unix"
    )
  } else {
    dir_path <- rappdirs::user_cache_dir(
      appname = "condathis",
      appauthor = "luciorq"
    )
  }
  if (isFALSE(fs::dir_exists(dir_path))) {
    fs::dir_create(dir_path)
  }
  return(fs::path_real(dir_path))
}

#' Retrieve the path to the `condathis` managed installation of `micromamba`.
#' @export
micromamba_bin_path <- function() {
  # umamba_bin_path <- micromamba_user_installed()
  # if (isFALSE(umamba_bin_path == "")) {
  #   return(umamba_bin_path)
  # }
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

#' Format Channels Arguments
#' @param ... Character. Channels to be used by `micromamba`.
format_channels_args <- function(...) {
  channels <- c(...)
  if (is.null(channels)) {
    channels <- c(
      "bioconda",
      "conda-forge",
      "defaults"
    )
  }
  channels_arg <- c()
  for (channel in channels) {
    channels_arg <- c(channels_arg, "-c", channel)
  }
  return(channels_arg)
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

#' Check If Environment Names Already exists
env_exists <- function(env_name = "condathis-env") {
  env_root_dir <- get_install_dir()
  available_envs <- condathis::list_envs()

  condathis_env_path <- fs::path(env_root_dir, "envs", env_name)

  if (isTRUE(condathis_env_path %in% available_envs)) {
    return(TRUE)
  } else {
    return(FALSE)
  }
}
