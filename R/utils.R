#' Retrieve `condathis` Data Creation Path
#' @export
get_install_dir <- function() {
  sys_arch <- get_sys_arch()
  # TODO: @luciorq On MacOS `micromamba run` fail if there is space in the path
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
  if (isFALSE(fs::dir_exists(dir_path))) {
    fs::dir_create(dir_path)
  }
  return(fs::path_real(dir_path))
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

#' Format Channels Arguments
#' @param ... Character. Channels to be used by `micromamba`.
format_channels_args <- function(...) {
  channels <- c(...)
  if (is.null(channels)) {
    channels <- c(
      "bioconda",
      "conda-forge"
    )
  }
  channels_arg <- c()
  for (channel in channels) {
    channels_arg <- c(channels_arg, "-c", channel)
  }
  return(channels_arg)
}

#' Check If Environment Names Already exists
#'
#' @inheritParams create_env
#'
#' @export
env_exists <- function(env_name = "condathis-env") {
  available_envs <- list_envs()
  condathis_env_path <- env_name
  if (isTRUE(condathis_env_path %in% available_envs)) {
    return(TRUE)
  } else {
    return(FALSE)
  }
}

#' Create Package Base Environment
#' @keywords internal
create_base_env <- function() {
  if (isFALSE(env_exists(env_name = "condathis-env"))) {
    create_env(env_name = "condathis-env", verbose = "silent")
  }
}
