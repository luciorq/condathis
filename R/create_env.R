# TODO(luciorq): Add unique identifier to `container_name` to reduce potential
# + locks on all docker exec

#' Create Conda Environment with specific packages
#'
#' @param packages Character vector. Names of the packages, and
#'   version strings if necessary, e.g. 'python=3.11'. The use of the `packages`
#'   argument assumes that env_file is not used.
#'
#' @param env_file Character. Path to the YAML file with Conda Environment
#'   description. If this argument is used, the `packages` argument should not
#'   be included in the command.
#'
#' @param env_name Character. Name of the Conda environment where the packages
#'   are going to be installed. Defaults to 'condathis-env'.
#'
#' @param channels Character vector. Names of the channels to be included.
#'   By default 'c("bioconda", "conda-forge", "defaults")' are used for solving
#'   dependencies.
#'
#' @param additional_channels Character. Additional Channels to be added to the
#'   default ones.
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
                                  "singularity"),
                       container_name = "condathis-micromamba-base",
                       image_name = "luciorq/condathis-micromamba:latest",
                       sif_image_path = NULL,
                       additional_channels = NULL) {
  umamba_bin_path <- micromamba_bin_path()
  env_root_dir <- get_install_dir()

  env_file_path <- NULL
  if (!is.null(env_file)) {
    if (fs::file_exists(env_file)) {
      env_file_path <- fs::path(env_file)
      packages = c("-f", env_file_path)
    }
  }
  channels_arg <- format_channels_args(channels, additional_channels)
  # TODO: Implement auto mode.
  method_to_use <- method[1]
  if (isTRUE(method_to_use == "auto")) {
    method_to_use <- define_method_to_use(
      packages = packages_to_search,
      channels = channels,
      additional_channels = additional_channels,
      container_name = container_name,
      image_name = image_name,
      sif_image_path = sif_image_path
    )
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
    px_res <- create_env_internal_docker(
      packages = packages,
      env_file = env_file,
      env_name = env_name,
      channels = channels,
      container_name = "condathis-micromamba-base",
      image_name = "luciorq/condathis-micromamba:latest",
      additional_channels = additional_channels
    )
  } else if (isTRUE(method_to_use == "singularity")) {
    # cli::cli_abort(c(
    #   `x` = "Method {.code \"singularity\"} is not implemented yet."
    # ))
    px_res <- create_env_internal_singularity(
      packages = packages,
      env_file = env_file,
      env_name = env_name,
      channels = channels,
      sif_image_path = NULL,
      additional_channels = additional_channels
    )
  }
  return(invisible(px_res))
}

#' Create Environment Using Docker
#'
#' @param container_name Character. Name of the Container created by Docker.
#'   Defaults to `"condathis-micromamba-base"`.
#'
#' @param image_name Character. Name of the Docker Image used, it will try
#'   to pull it automatically if internet connection is available.
#'   Defaults to `"luciorq/condathis-micromamba:latest"`.
#'
#' @inheritParams create_env
create_env_internal_docker <- function(packages = NULL,
                              env_file = NULL,
                              env_name = "condathis-env",
                              channels = c(
                                "bioconda",
                                "conda-forge",
                                "defaults"
                              ),
                              container_name = "condathis-micromamba-base",
                              image_name = "luciorq/condathis-micromamba:latest",
                              additional_channels = NULL) {
  stop_if_not_installed("dockerthis")
  env_root_dir <- get_install_dir()
  env_root_dir <- fs::path(paste0(env_root_dir, "-docker"))
  if (isFALSE(fs::dir_exists(env_root_dir))) {
    fs::dir_create(env_root_dir)
    fs::dir_create(env_root_dir, "home")
  }
  channels_arg <- format_channels_args(channels, additional_channels)
  env_file_path <- NULL
  if (isFALSE(is.null(env_file))) {
    if (fs::file_exists(env_file)) {
      packages = c("-f", env_file_path)
    }
  }
  user_arg <- format_user_arg_string()
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
      "-e",
      paste0("HOME=", env_root_dir, "/home"),
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

#' Create Environment Using Singularity / Apptainer
#' @param sif_image_path Character. Path to SIF image file.
#' @inheritParams create_env
create_env_internal_singularity <- function(packages = NULL,
                                            env_file = NULL,
                                            env_name = "condathis-env",
                                            channels = c(
                                              "bioconda",
                                              "conda-forge",
                                              "defaults"
                                            ),
                                            sif_image_path = NULL,
                                            additional_channels = NULL) {
  invisible(is_singularity_available())
  env_root_dir <- get_install_dir()
  env_root_dir <- fs::path(paste0(env_root_dir, "-docker"))
  if (isFALSE(fs::dir_exists(env_root_dir))) {
    fs::dir_create(env_root_dir)
    fs::dir_create(env_root_dir, "home")
  }
  sif_dir <- fs::path(env_root_dir, "sif")
  if (isFALSE(fs::dir_exists(sif_dir))) {
    fs::dir_create(sif_dir)
  }
  if (is.null(sif_image_path)) {
    sif_image_path <- fs::path(sif_dir, "condathis-micromamba", ext = "sif")
  }
  channels_arg <- format_channels_args(channels, additional_channels)
    env_file_path <- NULL
  if (isFALSE(is.null(env_file))) {
    if (fs::file_exists(env_file)) {
      packages = c("-f", env_file_path)
    }
  }
  px_res <- singularity_cmd(
    "exec",
    "-e",
    "-H",
    paste0(env_root_dir, "/home"),
    "-W",
    fs::path_wd(),
    sif_image_path,
    "micromamba",
    "create",
    "-r",
    env_root_dir,
    "-n",
    env_name,
    "--yes",
    # "--quiet",
    channels_arg,
    packages
  )
  return(invisible(px_res))
}
