#' Create Conda Environment with specific packages
#'
#' @param packages Character vector. Names of the packages, and
#'   version strings if necessary, e.g. 'python=3.11'. The use of the `packages`
#'   argument assumes that env_file is not used.
#'
#' @param env_file Character. Path to the YAML file with Conda Environment
#'   discription. If this argument is used, the `packages` argument should not
#'   be included in the command.
#'
#' @param env_name Character. Name of the Conda environment where the packages
#'   are going to be installed. Defaults to 'condathis-env'.
#'
#' @param channels Character vector. Names of the channels to be included.
#'   By default 'c("bioconda", "conda-forge", "defaults")' are used for solving
#'   dependencies.
#'
#' @param method Character. Beckend method to run `micromamba`, the default is
#'   "auto" running nativelly "native" with the `micromamba` binaries installed
#'   by `condathis`. Additional methods are supported for using Docker Linux Containers
#'   "docker" and Singularity Containers "singularity" as the beckends,
#'   those are especially useful if running on systems where the conda
#'   recipes are not available for the OS or CPU architecture in place.
#'   The container based backends leverage `dockerthis` R package.
#'
#' @export
create_env <- function(packages = NULL,
                       env_file = NULL,
                       env_name = "condathis-env",
                       channels = c("bioconda",
                                    "conda-forge",
                                    "defaults"),
                       method = c("auto",
                                  "native",
                                  "docker",
                                  "singularity")) {
  umamba_bin_path <- micromamba_bin_path()
  env_root_dir <- get_install_dir()

  env_file_path <- NULL
  if (!is.null(env_file)) {
    if (fs::file_exists(env_file)) {
      env_file_path <- fs::path(env_file)
      packages = c("-f", env_file_path)
    }
  }
  channels_arg <- c()
  for (channel in channels) {
    channels_arg <- c(channels_arg, "-c", channel)
  }

  # TODO: Implement auto mode.
  method_to_use <- method[1]
  if (method_to_use == "auto") {
    cli::cli_inform(c(
      `!` = "{.code method = \"auto\"} is not implemented yet.",
      `v` = "Using {.code method = \"native\"} instead."
    ))
    method_to_use <- "native"
  }
  if (isTRUE(method_to_use == "native")) {
    px_res <- processx::run(
      command = fs::path_real(umamba_bin_path),
      args = c(
        "create",
        "-r",
        env_root_dir,
        channels_arg,
        "-n",
        env_name,
        "--yes",
        "--quiet",
       packages
      ),
      spinner = TRUE,
      echo_cmd = TRUE
    )
  } else if (isTRUE(method_to_use == "docker")) {
    px_res <- create_env_docker(
      packages = packages,
      env_file = env_file,
      env_name = env_name,
      channels = channels,
      container_name = "condathis-micromamba-base",
      image_name = "luciorq/condathis-micromamba:latest"
    )
  } else if (isTRUE(method_to_use == "singularity")) {
    cli::cli_abort(c(
      `x` = "Method {.code \"singularity\"} is not implemented yet."
    ))
  }
  return(invisible(px_res))
}

#' @inheritParams create_env
create_env_docker <- function(packages = NULL,
                              env_file = NULL,
                              env_name = "condathis-env",
                              channels = c(
                                "bioconda",
                                "conda-forge",
                                "defaults"
                              ),
                              container_name = "condathis-micromamba-base",
                              image_name = "luciorq/condathis-micromamba:latest"
                              ) {
  stop_if_not_installed("dockerthis")
  env_root_dir <- get_install_dir()
  env_root_dir <- fs::path(paste0(env_root_dir, "-docker"))
  if (isFALSE(fs::dir_exists(env_root_dir))) {
    fs::dir_create(env_root_dir)
  }
  channels_arg <- c()
  for (channel in channels) {
    channels_arg <- c(channels_arg, "-c", channel)
  }
  env_file_path <- NULL
  if (!is.null(env_file)) {
    if (fs::file_exists(env_file)) {
      packages = c("-f", env_file_path)
    }
  }
  user_arg <- "--user=dockerthis"
  if (isTRUE(Sys.info()["sysname"] == "Linux")) {
    user_arg = "--user=$(id -u):$(id -g)"
  }
  px_res <- dockerthis::docker_run(
    "micromamba",
    "create",
    "-r",
    env_root_dir,
    "-n",
    env_name,
    "--yes",
    # "--quiet",
    channels_arg,
    packages,
    container_name = container_name,
    image_name = image_name,
    docker_args = c(
      "--platform=linux/amd64",
      user_arg,
      "--rm"
    ),
    mount_paths = c(
      env_root_dir,
      env_file_path
    )
  )
  return(invisible(px_res))
}
