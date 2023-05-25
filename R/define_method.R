# TODO(luciorq): This function should go on `runthis` package.
#' Automatically Find Suitable Infrastrucure to Run CLI Tools
#' @inheritParams create_env
define_method_to_use <- function(packages = NULL,
                                 channels = NULL,
                                 additional_channels = NULL) {

  # TODO(luciorq): Implement step by step approach
  # + First check if native is fully functional, only then check next method.
  singularity_avail <- try({is_singularity_available()}, silent = TRUE)
  docker_avail <- try({dockerthis::is_docker_available()}, silent = TRUE)
  umamba_avail <- try({is_micromamba_available_for_arch()}, silent = TRUE)

  # TODO(luciorq): Check if environment already exists and tool is on PATH
  # + before searching for packages

  # TODO(luciorq): Search packages on container methods

  if (isTRUE(class(umamba_avail) == "character")) {
    umamba_bin_path <- micromamba_bin_path()
    if (isFALSE(fs::file_exists(umamba_bin_path))) {
      install_micromamba(force = TRUE)
    }
    if (isFALSE(is.null(packages)) & isFALSE(is.null(channels))) {
      pkgs_available <- packages_search(
        packages = packages,
        channels = channels,
        additional_channels = additional_channels
      )
    } else {
      pkgs_available <- TRUE
    }
    if (isTRUE(pkgs_available)) {
      method_to_use <- "native"
    }
  } else if (isFALSE(class(singularity_avail) == "try-error")) {
      method_to_use <- "singularity"
  } else if (isFALSE(class(docker_avail) == "try-error")) {
    method_to_use <- "docker"
  } else {
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
packages_search <- function(packages,
                              channels = c("bioconda",
                                           "conda-forge",
                                           "defaults"),
                              method = c("native",
                                         "docker",
                                         "singularity"),
                              additional_channels = NULL) {
  # TODO(luciorq): Implement methods
  umamba_bin_path <- micromamba_bin_path()
  withr::local_envvar(list(CONDA_SHLVL = 0))

  channels_arg <- format_channels_args(channels, additional_channels)

  available_vector <- c()
  for (pkg in packages) {
    px_res <- processx::run(
      command = fs::path_real(umamba_bin_path),
      args = c(
        "search",
        "--yes",
        "--json",
        channels_arg,
        packages
      ),
      spinner = TRUE
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
