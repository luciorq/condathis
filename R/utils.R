#' Return OS and CPU Architecture
#' @export
get_sys_arch <- function() {
  os <- base::Sys.info()["sysname"]
  cpu_arch <- base::Sys.info()["machine"]
  return(base::paste0(os, "-", cpu_arch))
}

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

# Retrieve `condathis` Cache Directory Path
# get_cache_dir <- function() {
#   sys_arch <- get_sys_arch()
#   # TODO(luciorq): On MacOS micromamba run fail if there is space in the path
#   # + as in ~/Library/Application Support/condathis"
#   # + That is why we are using unix style for macos
#   if (isTRUE(stringr::str_detect(sys_arch, "^Darwin"))) {
#     dir_path <- rappdirs::user_cache_dir(
#       appname = "condathis",
#       appauthor = "luciorq",
#       os = "unix"
#     )
#   } else {
#     dir_path <- rappdirs::user_cache_dir(
#       appname = "condathis",
#       appauthor = "luciorq"
#     )
#   }
#   if (isFALSE(fs::dir_exists(dir_path))) {
#     fs::dir_create(dir_path)
#   }
#   return(fs::path_real(dir_path))
# }

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
      "conda-forge"
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
list_envs <- function(verbose = FALSE) {
  env_root_dir <- get_install_dir()
  px_res <- native_cmd(
    conda_cmd = "env",
    conda_args = c(
      "list",
      "--no-rc",
      "-q",
      "--json"
    ),
    verbose = verbose
  )
  if (isTRUE(px_res$status == 0)) {
    envs_list <- jsonlite::fromJSON(px_res$stdout)
    envs_str <- fs::path_real(envs_list$envs)
    envs_str <- envs_str[stringr::str_detect(c(envs_str), env_root_dir)]
    envs_to_return <- base::basename(envs_str)
    envs_to_return <- envs_to_return[!envs_to_return %in% "condathis"]
    return(envs_to_return)
  } else {
    return(px_res$status)
  }
}

#' List Packages Installed Inside Environment
#' @inheritParams run
#' @export
list_packages <- function(env_name = "condathis-env", verbose = FALSE) {
  px_res <- native_cmd(
    conda_cmd = "list",
    conda_args = c(
      "--no-rc",
      "-n",
      env_name
    ),
    verbose = verbose
  )
  if (isTRUE(px_res$status == 0)) {
    cat(px_res$stdout)
    invisible(px_res)
  } else {
    (
      return(px_res)
    )
  }
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
