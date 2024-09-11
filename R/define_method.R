# TODO(luciorq): This function should go on `runthis` package.
#' Automatically Find Suitable Infrastrucure to Run CLI Tools
#' @inheritParams create_env
define_method_to_use <- function(packages = NULL,
                                 channels = c(
                                   "bioconda",
                                   "conda-forge"
                                 ),
                                 additional_channels = NULL,
                                 container_name = "condathis-micromamba-base",
                                 image_name = "luciorq/condathis-micromamba:latest",
                                 sif_image_path = NULL) {
  # TODO(luciorq): Implement step by step approach
  # + First check if native is fully functional, only then check next method.
  singularity_avail <- try(
    {
      is_singularity_available()
    },
    silent = TRUE
  )
  docker_avail <- try(
    {
      dockerthis::is_docker_available()
    },
    silent = TRUE
  )
  # TODO(luciorq): Add podman wrapper
  umamba_avail <- try(
    {
      is_micromamba_available_for_arch()
    },
    silent = TRUE
  )

  # TODO(luciorq): Check if environment already exists and tool is on PATH
  # + before searching for packages

  # TODO(luciorq): Search packages on container methods
  method_to_use <- NULL
  if (isTRUE(class(umamba_avail) == "character")) {
    umamba_bin_path <- micromamba_bin_path()
    if (isFALSE(fs::file_exists(umamba_bin_path))) {
      install_micromamba(force = TRUE)
    }
    if (isFALSE(is.null(packages)) & isFALSE(is.null(channels))) {
      pkgs_available <- packages_search_native(
        packages = packages,
        channels = channels,
        additional_channels = additional_channels
      )
    } else {
      pkgs_available <- FALSE
    }
    if (isTRUE(pkgs_available)) {
      method_to_use <- "native"
    }
  }

  if (isFALSE("try-error" %in% class(singularity_avail))) {
    pkgs_available <- packages_search_singularity(
      packages = packages,
      channels = channels,
      additional_channels = additional_channels,
      sif_image_path = sif_image_path
    )
    if (isTRUE(pkgs_available)) {
      method_to_use <- "singularity"
    }
  } else if (isFALSE("try-error" %in% class(docker_avail))) {
    pkgs_available <- packages_search_docker(
      packages = packages,
      channels = channels,
      additional_channels = additional_channels,
      container_name = container_name,
      image_name = image_name
    )
    if (isTRUE(pkgs_available)) {
      method_to_use <- "docker"
    }
  }

  if (is.null(method_to_use)) {
    cli::cli_abort(c(
      `x` = "No method available!",
      `!` = "{.code method = \"auto\"} could not detect a possible {.field method}.",
      `!` = "Try manually defining a method if it should be one."
    ))
  }
  return(method_to_use)
}

#' Search For Package in Channels
#'
#' Search if Package is available in required Channels
#'
#' @inheritParams create_env
packages_search_native <- function(packages,
                                   channels = c(
                                     "bioconda",
                                     "conda-forge"
                                   ),
                                   method = c(
                                     "native",
                                     "docker",
                                     "singularity"
                                   ),
                                   platform = NULL,
                                   additional_channels = NULL) {
  # TODO(luciorq): Implement support to other methods
  # + beyond "native".
  channels_arg <- format_channels_args(
    additional_channels,
    channels
  )
  if (is.null(platform)) {
    platform_args <- NULL
  } else {
    platform_args <- c("--platform", platform)
  }
  available_vector <- c()
  for (pkg_query in packages) {
    px_res <- native_cmd(
      conda_cmd = "search",
      conda_args = c(
        "--no-rc",
        "--no-channel-priority",
        "--override-channels",
        "--channel-priority=0",
        "--yes",
        "--json",
        channels_arg,
        platform_args
      ),
      pkg_query,
      verbose = FALSE
    )
    if (isTRUE(px_res$status == 0)) {
      json_output <- jsonlite::fromJSON(px_res$stdout)
      if (length(json_output$result$pkgs) == 0) {
        package_available <- FALSE
      } else {
        package_available <- TRUE
      }
    }
    available_vector <- c(available_vector, package_available)
    all_available <- all(available_vector)
  }
  return(all_available)
}

#' Search for Packages in Channels using Docker
#' @inheritParams create_env
packages_search_docker <- function(packages,
                                   channels = c(
                                     "bioconda",
                                     "conda-forge"
                                   ),
                                   additional_channels = NULL,
                                   container_name = "condathis-micromamba-base",
                                   image_name = "luciorq/condathis-micromamba:latest") {
  stop_if_not_installed("dockerthis")
  env_root_dir <- get_install_dir()
  env_root_dir <- fs::path(paste0(env_root_dir, "-docker"))
  # user_arg <- format_user_arg_string()
  channels_arg <- format_channels_args(additional_channels, channels)
  available_vector <- c()
  for (pkg in packages) {
    px_res <- dockerthis::docker_run(
      "micromamba",
      "search",
      "--no-rc",
      "--no-channel-priority",
      "--override-channels",
      "--channel-priority=0",
      "--yes",
      "--json",
      channels_arg,
      packages,
      container_name = container_name,
      image_name = image_name,
      docker_args = c(
        "-e",
        paste0("HOME=", env_root_dir, "/home"),
        paste0("--workdir=", fs::path_wd()),
        "--platform=linux/amd64",
        # user_arg,
        "--rm"
      ),
      mount_paths = c(
        env_root_dir,
        fs::path_wd()
      ),
      verbose = FALSE
    )
    if (isTRUE(px_res$status == 0)) {
      json_output <- jsonlite::fromJSON(px_res$stdout)
      if (length(json_output$result$pkgs) == 0) {
        package_available <- FALSE
      } else {
        package_available <- TRUE
      }
    }
    available_vector <- c(available_vector, package_available)
    all_available <- all(available_vector)
  }
  return(all_available)
}

#' Search for packages in Channels using Singularity
#' @inheritParams create_env
packages_search_singularity <- function(packages,
                                        channels = c(
                                          "bioconda",
                                          "conda-forge"
                                        ),
                                        additional_channels = NULL,
                                        sif_image_path = NULL) {
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
  if (isFALSE(fs::file_exists(sif_image_path))) {
    build_container_image_singularity()
  }
  channels_arg <- format_channels_args(additional_channels, channels)
  available_vector <- c()
  for (pkg in packages) {
    px_res <- singularity_cmd(
      "exec",
      "-e",
      "-H",
      paste0(env_root_dir, "/home"),
      "-W",
      fs::path_wd(),
      sif_image_path,
      "micromamba",
      "search",
      "--yes",
      "--no-rc",
      "--no-channel-priority",
      "--override-channels",
      "--channel-priority=0",
      "--json",
      channels_arg,
      packages
    )
    if (isTRUE(px_res$status == 0)) {
      json_output <- jsonlite::fromJSON(px_res$stdout)
      if (length(json_output$result$pkgs) == 0) {
        package_available <- FALSE
      } else {
        package_available <- TRUE
      }
    }
    available_vector <- c(available_vector, package_available)
    all_available <- all(available_vector)
  }
  return(all_available)
}
