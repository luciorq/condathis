#' Create a Conda environment
#'
#' Creates a Conda environment managed by `condathis` and installs dependencies
#' from package specs or from an environment file.
#'
#' @param packages Character vector of package MatchSpec strings.
#'   Examples: `"python=3.13"`, `"bioconda::fastqc==0.12.1"`.
#'   Defaults to `NULL`.
#' @param env_file Character string with the path to an environment YAML file.
#'   Defaults to `NULL`.
#'   When provided, it is passed to `micromamba create -f`.
#' @param env_name Character string with the target environment name.
#'   Defaults to `"condathis-env"`.
#' @param channels Character vector with channel names used for dependency
#'   resolution. Defaults to `c("conda-forge", "bioconda")`.
#' @param channel_priority Character string with channel priority mode.
#'   Supported values are `"disabled"`, `"strict"`, and `"flexible"`.
#'   Defaults to `"disabled"`.
#' @param additional_channels Character vector of additional channels appended
#'   to `channels`. Defaults to `NULL`.
#' @param method Character string with the backend execution strategy.
#'   Supported values are `"native"` and `"auto"`.
#'   Defaults to `"native"`.
#'   This argument is soft-deprecated and currently does not change behavior.
#' @param platform Character string with the platform used for dependency
#'   solving (for example, `"linux-64"`, `"osx-64"`, `"osx-arm64"`,
#'   `"win-64"`, `"noarch"`). Defaults to `NULL`.
#'   On Apple Silicon, `condathis` may fall back to `"osx-64"` when Rosetta 2
#'   is available and packages are not available for `"osx-arm64"`.
#' @inheritParams run
#' @param overwrite Logical value that controls whether an existing environment
#'   should always be recreated. Defaults to `FALSE`.
#'
#' @returns A process result list (from `processx::run()`) with command output,
#'   error output, exit status, and timeout information.
#'
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   # Create a Conda environment and install the CLI `fastqc` in it.
#'   # Explicitly using the channel `bioconda` and version `0.12.1`.
#'   condathis::create_env(
#'     packages = "bioconda::fastqc==0.12.1",
#'     env_name = "fastqc-env",
#'     verbose = "output"
#'   )
#' })
#' }
#' @export
create_env <- function(
  packages = NULL,
  env_file = NULL,
  env_name = "condathis-env",
  channels = c(
    "conda-forge",
    "bioconda"
  ),
  method = c(
    "native",
    "auto"
  ),
  channel_priority = c(
    "disabled",
    "strict",
    "flexible"
  ),
  additional_channels = NULL,
  platform = NULL,
  verbose = c(
    "output",
    "silent",
    "cmd",
    "spinner",
    "full"
  ),
  overwrite = FALSE
) {
  # workaround for a bug in some versions of libmamba where they check for
  # + pkgs_dir in the home directory even when defining it elsewhere.
  pkgs_dir <- fs::path_home(".mamba", "pkgs")
  pkgs_dir_already_exists <- FALSE
  if (isTRUE(stringr::str_detect(get_sys_arch(), "^Windows"))) {
    pkgs_dir <- base::Sys.getenv(
      x = "APPDATA",
      unset = fs::path_home("AppData", "Roaming"),
      names = FALSE
    )
    pkgs_dir <- fs::path(pkgs_dir, ".mamba", "pkgs")
  }
  if (isFALSE(fs::dir_exists(pkgs_dir))) {
    fs::dir_create(pkgs_dir)
  } else {
    pkgs_dir_already_exists <- TRUE
  }
  withr::defer(expr = {
    if (
      isFALSE(pkgs_dir_already_exists) &&
        fs::dir_exists(base::dirname(pkgs_dir))
    ) {
      invisible(rlang::catch_cnd(
        expr = {
          fs::dir_delete(base::dirname(pkgs_dir))
        }
      ))
    }
  })

  if (isFALSE(rlang::is_bool(overwrite))) {
    cli::cli_abort(
      message = c(
        `x` = "Argument {.arg overwrite} needs to be a {.cls logical} value."
      ),
      class = "condathis_create_invalid_overwrite_arg"
    )
  }

  channel_priority_args <- parse_strategy_channel_priority(
    channel_priority = channel_priority
  )
  method <- rlang::arg_match(method)

  verbose_list <- parse_strategy_verbose(verbose = verbose)

  # TODO: @luciorq As of v0.1.3-dev mixing file and packages is allowed,
  # + As this is allowed in conda.
  # + Need to include tests and update docs.
  env_file_path <- NULL
  if (isFALSE(rlang::is_null(env_file))) {
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
    channels,
    additional_channels
  )

  platform_args <- NULL
  if (isFALSE(rlang::is_null(packages))) {
    platform_args <- define_platform(
      packages = packages,
      platform = platform,
      channels = channels,
      channel_priority = channel_priority,
      additional_channels = additional_channels,
      # verbose = verbose_list$internal_verbose
      verbose = "silent"
    )
  } else {
    platform_args <- NULL
  }

  if (isFALSE(rlang::is_null(platform)) && rlang::is_null(platform_args)) {
    platform_args <- c("--platform", platform)
  }

  if (isTRUE(method %in% c("native", "auto"))) {
    # Check if required versions are satisfied even when
    # + `overwrite` is false.
    if (
      isFALSE(overwrite) &&
        # rlang::is_null(env_file) &&
        isTRUE(length(packages) > 0L) &&
        env_exists(env_name = env_name, verbose = "silent")
    ) {
      is_satisfied_vector <- satisfies_dependencies(
        pkg_str_vector = packages,
        env_name = env_name,
        verbose = "silent"
      )
      if (isTRUE(all(is_satisfied_vector))) {
        if (isTRUE(verbose_list$strategy %in% c("full", "output"))) {
          cli::cli_inform(
            message = c(
              `!` = "Environment {.field {env_name}} already exists."
            )
          )
        }
        return(invisible(
          list(status = 0L, stdout = "", stderr = "", timeout = FALSE)
        ))
      }
    }

    # Workaround for when directory already exists by other reasons.
    # + When micromamba fail to create an environment with a different platform
    # + than the native one, it leaves the directory there and do not overwrite.
    if (
      isFALSE(env_exists(env_name)) &&
        isTRUE(fs::dir_exists(get_env_dir(env_name = env_name)))
    ) {
      fs::dir_delete(get_env_dir(env_name = env_name))
    }

    px_res <- rethrow_error_cmd(
      expr = {
        native_cmd(
          conda_cmd = "create",
          conda_args = c(
            "-n",
            env_name,
            "--yes",
            verbose_list$quiet_flag,
            "--override-channels",
            channel_priority_args,
            channels_arg,
            platform_args
          ),
          packages_arg,
          verbose = verbose_list,
          error = "cancel"
        )
      }
    )
  }

  if (isTRUE(verbose_list$strategy %in% c("full", "output"))) {
    cli::cli_inform(
      message = c(
        `!` = "Environment {.field {env_name}} succesfully created."
      )
    )
  }

  return(invisible(px_res))
}
