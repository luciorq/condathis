#' Create a Conda Environment
#'
#' Create Conda Environment with specific packages installed to be used by `run()`.
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
#'   By default 'c("bioconda", "conda-forge")' are used for solving
#'   dependencies.
#'
#' @param additional_channels Character. Additional Channels to be added to the
#'   default ones.
#'
#' @param method Character. Beckend method to run `micromamba`, the default is
#'   "auto" running "native" with the `micromamba` binaries installed
#'   by `condathis`. Additional methods are supported for using Docker Linux Containers
#'   "docker" and Singularity Containers "singularity" as the beckends,
#'   those are especially useful if running on systems where the Conda
#'   recipes are not available for the OS or CPU architecture in place.
#'   The container-based backends leverage `dockerthis` R package.
#'
#' @param gpu_container Logical. GPU support for Container Beckend `methods`.
#'   This argument is not necessary if running native.
#'   Default to FALSE.
#'
#' @param container_name Character. Name of the Container created by Docker.
#'   Defaults to `"condathis-micromamba-base"`.
#'
#' @param image_name Character. Name of the Docker Image used, it will try
#'   to pull it automatically if internet connection is available.
#'   Defaults to `"luciorq/condathis-micromamba:latest"`.
#'
#' @param container_name Character. Name of the Container created by Docker.
#'   Defaults to `"condathis-micromamba-base"`.
#'
#' @param image_name Character. Name of the Docker Image used, it will try
#'   to pull it automatically if internet connection is available.
#'   Defaults to `"luciorq/condathis-micromamba:latest"`.
#'
#' @param sif_image_path Character. Path to SIF image file.
#'
#' @param platform Character. Platform to search for `packages`.
#'   Defaults to `NULL` which will use the current platform.
#'   E.g. "linux-64", "linux-32", "osx-64", "win-64", "win-32", "noarch".
#'   Note: on Apple Silicon MacOS will use "osx-64" instead of "osx-arm64"
#'     if Rosetta 2 is available.
#'
#' @param verbose Logical. Should command and messages be print to
#'    the console.
#'    defaults to TRUE.
#'
#' @export
create_env <- function(
    packages = NULL,
    env_file = NULL,
    env_name = "condathis-env",
    channels = c(
      "bioconda",
      "conda-forge"
    ),
    method = c(
      "native",
      "auto",
      "docker",
      "singularity"
    ),
    container_name = "condathis-micromamba-base",
    image_name = "luciorq/condathis-micromamba:latest",
    sif_image_path = NULL,
    additional_channels = NULL,
    gpu_container = FALSE,
    platform = NULL,
    verbose = TRUE) {
  env_file_path <- NULL
  if (!is.null(env_file)) {
    if (fs::file_exists(env_file)) {
      env_file_path <- fs::path(env_file)
      packages_arg <- c("-f", env_file_path)
    } else {
      cli::cli_abort(c(
        `x` = "The file {.code \"env_file\"} does not exist."
      ))
    }
  } else {
    packages_arg <- packages
  }
  channels_arg <- format_channels_args(
    additional_channels,
    channels
  )
  method_to_use <- method[1]
  if (isTRUE(method_to_use == "auto")) {
    method_to_use <- define_method_to_use(
      packages = packages,
      channels = channels,
      additional_channels = additional_channels,
      container_name = container_name,
      image_name = image_name,
      sif_image_path = sif_image_path
    )
  }

  if (isFALSE(is.null(packages))) {
    platform_args <- define_platform(
      packages = packages,
      platform = platform,
      channels = channels,
      additional_channels = additional_channels
    )
  } else {
    platform_args <- NULL
  }

  if (isTRUE(method_to_use == "native")) {
    px_res <- native_cmd(
      conda_cmd = "create",
      conda_args = c(
        "-n",
        env_name,
        "--yes",
        "--quiet",
        "--no-channel-priority",
        "--override-channels",
        "--channel-priority=0",
        channels_arg,
        platform_args
      ),
      packages_arg,
      verbose = verbose
    )
  } else if (isTRUE(method_to_use == "docker")) {
    px_res <- create_env_internal_docker(
      packages = packages_arg,
      env_file = env_file,
      env_name = env_name,
      channels = channels,
      container_name = "condathis-micromamba-base",
      image_name = "luciorq/condathis-micromamba:latest",
      additional_channels = additional_channels,
      verbose = verbose
    )
  } else if (isTRUE(method_to_use == "singularity")) {
    # cli::cli_abort(c(
    #   `x` = "Method {.code \"singularity\"} is not implemented yet."
    # ))
    px_res <- create_env_internal_singularity(
      packages = packages_arg,
      env_file = env_file,
      env_name = env_name,
      channels = channels,
      sif_image_path = NULL,
      additional_channels = additional_channels
    )
  }

  # # Write to cache
  # write_cache_env_method(
  #   env_name = env_name,
  #   method_to_use = method_to_use,
  #   cmd = NULL,
  #   overwrite = TRUE
  # )
  return(invisible(px_res))
}

#' Create Environment Using Docker
#'
#' @inheritParams create_env
create_env_internal_docker <- function(
    packages = NULL,
    env_file = NULL,
    env_name = "condathis-env",
    channels = c(
      "bioconda",
      "conda-forge"
    ),
    container_name = "condathis-micromamba-base",
    image_name = "luciorq/condathis-micromamba:latest",
    additional_channels = NULL,
    verbose = TRUE) {
  stop_if_not_installed("dockerthis")
  env_root_dir <- get_install_dir()
  env_root_dir <- fs::path(paste0(env_root_dir, "-docker"))
  if (isFALSE(fs::dir_exists(env_root_dir))) {
    fs::dir_create(env_root_dir)
    fs::dir_create(env_root_dir, "home")
  }
  channels_arg <- format_channels_args(additional_channels, channels)
  env_file_path <- NULL
  if (isFALSE(is.null(env_file))) {
    if (fs::file_exists(env_file)) {
      packages <- c("-f", env_file_path)
    }
  }

  # TODO(luciorq): Fix for case insensitive FS still not working
  # NOTE(luciorq): Fix for case insensitive file systems below
  sys_arch <- get_sys_arch()
  if (isTRUE(stringr::str_detect(sys_arch, "^[Darwin|Windows]"))) {
    prefix_args <- c(
      "-r",
      "/home/dockerthis",
      "-p",
      fs::path(env_root_dir, "envs", env_name)
    )
  } else {
    prefix_args <- c(
      "-r", env_root_dir,
      "-n", env_name
    )
  }
  user_arg <- format_user_arg_string()
  px_res <- dockerthis::docker_run(
    "micromamba",
    "--no-rc",
    "--no-env",
    "create",
    prefix_args,
    "--yes",
    "--experimental",
    "--no-extra-safety-checks",
    "--always-copy",
    # "--no-always-copy",
    # "--no-allow-softlinks",
    "--safety-checks", "0",
    "--no-channel-priority",
    "--override-channels",
    "--channel-priority=0",
    # "--quiet",
    channels_arg,
    packages,
    container_name = container_name,
    image_name = image_name,
    docker_args = c(
      "-e",
      paste0("HOME=", env_root_dir, "/home"),
      "--platform", "linux/amd64",
      user_arg,
      "--rm"
    ),
    mount_paths = c(
      env_root_dir,
      env_file_path
    ),
    verbose = verbose
  )
  return(invisible(px_res))
}

#' Create Environment Using Singularity / Apptainer
#'
#' @inheritParams create_env
create_env_internal_singularity <- function(
    packages = NULL,
    env_file = NULL,
    env_name = "condathis-env",
    channels = c(
      "bioconda",
      "conda-forge"
    ),
    sif_image_path = NULL,
    additional_channels = NULL,
    verbose = TRUE) {
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

  if (isTRUE(sif_image_path == fs::path(sif_dir, "condathis-micromamba", ext = "sif"))) {
    if (isFALSE(fs::file_exists(sif_image_path))) {
      build_container_image_singularity()
    }
  }
  channels_arg <- format_channels_args(additional_channels, channels)
  env_file_path <- NULL
  if (isFALSE(is.null(env_file))) {
    if (fs::file_exists(env_file)) {
      packages <- c("-f", env_file_path)
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
    "--no-rc",
    "--no-env",
    "create",
    "-r",
    env_root_dir,
    "-n",
    env_name,
    "--yes",
    # "--quiet",
    "--no-channel-priority",
    "--override-channels",
    "--channel-priority=0",
    channels_arg,
    packages
  )
  return(invisible(px_res))
}
