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
#'   by `condathis`.
#'   This argument is **soft deprecated** as changing it don't really do anything.
#'
#' @param platform Character. Platform to search for `packages`.
#'   Defaults to `NULL` which will use the current platform.
#'   E.g. "linux-64", "linux-32", "osx-64", "win-64", "win-32", "noarch".
#'   Note: on Apple Silicon MacOS will use "osx-64" instead of "osx-arm64"
#'     if Rosetta 2 is available and any of the `packages` is not available
#'     for "osx-arm64".
#'
#' @inheritParams run
#'
#' @param overwrite Logical. Should environment always be overwritten?
#'     Defaults to `FALSE`.
#'
#' @return An object of class `list` representing the result of the command
#'   execution. Contains information about the standard output, standard error,
#'   and exit status of the command.
#'
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   # Create a Conda environment and install the CLI `fastqc` in it.
#'   condathis::create_env(
#'     packages = "fastqc==0.12.1",
#'     env_name = "fastqc-env",
#'     verbose = "output"
#'   )
#'   #> ! Environment fastqc-env succesfully created.
#' })
#' }
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
      "auto"
    ),
    additional_channels = NULL,
    platform = NULL,
    verbose = "silent",
    overwrite = FALSE) {
  pkgs_dir <- fs::path_home(".mamba", "pkgs")
  pkgs_already_exists <- FALSE
  if (isTRUE(stringr::str_detect(get_sys_arch(), "^Windows"))) {
    pkgs_dir <- Sys.getenv("APPDATA", unset = fs::path_home("AppData", "Roaming"))
    pkgs_dir <- fs::path(pkgs_dir, ".mamba", "pkgs")
  }
  if (isFALSE(fs::dir_exists(pkgs_dir))) {
    fs::dir_create(pkgs_dir)
  } else {
    pkgs_already_exists <- TRUE
  }
  withr::defer(expr = {
    if (isFALSE(pkgs_already_exists) && fs::dir_exists(base::dirname(pkgs_dir))) {
      invisible(rlang::catch_cnd(
        expr = {
          fs::dir_delete(base::dirname(pkgs_dir))
        }
      ))
    }
  })

  method <- rlang::arg_match(method)

  env_file_path <- NULL
  if (isFALSE(is.null(env_file))) {
    if (fs::file_exists(env_file)) {
      env_file_path <- fs::path(env_file)
      packages_arg <- c("-f", env_file_path)
    } else {
      cli::cli_abort(
        message = c(
          `x` = "The file {.code \"env_file\"} does not exist."
        ),
        class = "condathis_create_missing_env_file"
      )
    }
  } else {
    packages_arg <- packages
  }
  channels_arg <- format_channels_args(
    additional_channels,
    channels
  )
  method_to_use <- method[1]
  platform_args <- NULL
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

  if (isFALSE(is.null(platform)) && isTRUE(is.null(platform_args))) {
    platform_args <- c("--platform", platform)
  }

  if (isTRUE(method_to_use %in% c("native", "auto"))) {
    if (env_exists(env_name = env_name) && isFALSE(overwrite)) {
      pkg_list_res <- list_packages(
        env_name = env_name,
        verbose = "silent"
      )
      pkg_present_vector <- vector(mode = "logical", length = length(packages))
      for (i in seq_along(packages)) {
        pkg_name_str <- stringr::str_remove(packages[i], "[=<>~!].*")
        if (pkg_name_str %in% pkg_list_res$name) {
          pkg_present_vector[i] <- TRUE
        } else {
          pkg_present_vector[i] <- FALSE
        }
      }

      if (isTRUE(all(pkg_present_vector))) {
        if (isTRUE(verbose %in% c("full", "output"))) {
          cli::cli_inform(
            message = c(
              `!` = "Environment {.field {env_name}} already exists."
            )
          )
        }
        return(invisible(list(status = 0L, stdout = "", stderr = "", timeout = FALSE)))
      }
    }

    quiet_flag <- parse_quiet_flag(verbose = verbose)

    px_res <- rethrow_error_cmd(
      expr = {
        native_cmd(
          conda_cmd = "create",
          conda_args = c(
            "-n",
            env_name,
            "--yes",
            quiet_flag,
            "--no-channel-priority",
            "--override-channels",
            "--channel-priority=0",
            channels_arg,
            platform_args
          ),
          packages_arg,
          verbose = verbose,
          error = "cancel"
        )
      }
    )
  }
  if (isTRUE(verbose %in% c("full", "output"))) {
    cli::cli_inform(
      message = c(
        `!` = "Environment {.field {env_name}} succesfully created."
      )
    )
  }
  return(invisible(px_res))
}
