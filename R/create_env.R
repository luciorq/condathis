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
#'   Currently does not change behavior — reserved for upcoming pluggable
#'   backend support (e.g. running through `rattler` or a container engine
#'   instead of a managed `micromamba` install). Not deprecated.
#' @param platform Character string with the platform used for dependency
#'   solving (for example, `"linux-64"`, `"osx-64"`, `"osx-arm64"`,
#'   `"win-64"`, `"noarch"`). Defaults to `NULL`.
#'   On Apple Silicon, `condathis` may fall back to `"osx-64"` when Rosetta 2
#'   is available and packages are not available for `"osx-arm64"`.
#' @inheritParams run
#' @param overwrite Logical value that controls whether an existing environment
#'   should always be recreated. Defaults to `FALSE`.
#'
#' @returns A `condathis_result` S3 object (a classed list, still usable as
#'   a plain list) with `status`, `stdout`, `stderr`, `timeout`, `pid`,
#'   `cmd`, and `env_name`.
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
  ensure_libmamba_pkgs_dir_workaround()

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
  packages_arg <- resolve_create_env_packages_arg(
    packages = packages,
    env_file = env_file
  )

  channels_arg <- format_channels_args(
    channels,
    additional_channels
  )

  cmd_string <- paste(
    c("micromamba", "create", "-n", env_name, packages_arg),
    collapse = " "
  )

  platform_args <- resolve_create_env_platform_args(
    packages = packages,
    platform = platform,
    channels = channels,
    channel_priority = channel_priority,
    additional_channels = additional_channels
  )

  if (isTRUE(method %in% c("native", "auto"))) {
    # Check if required versions are satisfied even when `overwrite` is
    # false.
    early_result <- env_already_satisfies_request(
      env_name = env_name,
      packages = packages,
      overwrite = overwrite,
      cmd_string = cmd_string,
      verbose_list = verbose_list
    )
    if (isFALSE(is.null(early_result))) {
      return(invisible(early_result))
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

  result <- new_condathis_result(
    status = px_res$status,
    stdout = px_res$stdout,
    stderr = px_res$stderr,
    timeout = if (is.null(px_res$timeout)) FALSE else px_res$timeout,
    pid = if (is.null(px_res$pid)) NA_integer_ else px_res$pid,
    cmd = cmd_string,
    env_name = env_name
  )
  return(invisible(result))
}

#' Work around a libmamba bug that checks for `~/.mamba/pkgs` unconditionally
#'
#' Some versions of libmamba check for a `pkgs_dir` in the home directory
#' even when the package cache is configured elsewhere. Creates it if
#' missing, and registers a `withr::defer()` cleanup that removes it again
#' once the caller (normally `create_env()`) returns — so a fresh
#' `~/.mamba` isn't left behind on a machine that never had one. No cleanup
#' fires if the directory already existed.
#'
#' @param envir Environment whose exit the deferred cleanup is tied to.
#'   Defaults to the caller's own frame (`parent.frame()`), which is what
#'   makes this correct to call with no arguments from `create_env()`:
#'   `withr::defer()`'s own default `envir` is *its* immediate caller —
#'   this function's frame, not `create_env()`'s — so without explicitly
#'   threading `envir` through here, the cleanup would fire the instant
#'   this helper returns rather than when `create_env()` itself exits. Same
#'   class of scoping hazard as `withr::local_tempfile()`'s `.local_envir`
#'   default, already hit twice elsewhere in this codebase.
#'
#' @keywords internal
#' @noRd
ensure_libmamba_pkgs_dir_workaround <- function(envir = parent.frame()) {
  pkgs_dir <- fs::path_home(".mamba", "pkgs")
  pkgs_dir_already_exists <- FALSE
  if (isTRUE(is_windows())) {
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
  withr::defer(
    expr = {
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
    },
    envir = envir
  )
  return(invisible(NULL))
}

#' Resolve `create_env()`'s `packages`/`env_file` arguments into a
#' `micromamba create` argument
#'
#' @param packages Character vector of package MatchSpec strings, or `NULL`.
#' @param env_file Path to an environment YAML file, or `NULL`.
#'
#' @returns `packages` unchanged when `env_file` is `NULL`; otherwise
#'   `c("-f", env_file)`. Aborts with class
#'   `condathis_create_missing_env_file` if `env_file` is given but doesn't
#'   exist.
#'
#' @keywords internal
#' @noRd
resolve_create_env_packages_arg <- function(packages, env_file) {
  if (isTRUE(rlang::is_null(env_file))) {
    return(packages)
  }
  if (isFALSE(fs::file_exists(env_file))) {
    cli::cli_abort(
      message = c(
        `x` = "The file {.code \"env_file\"} does not exist."
      ),
      class = "condathis_create_missing_env_file"
    )
  }
  return(c("-f", fs::path(env_file)))
}

#' Resolve `create_env()`'s `--platform` argument
#'
#' @returns A character vector of `micromamba create` arguments, or `NULL`
#'   when no platform override applies.
#'
#' @keywords internal
#' @noRd
resolve_create_env_platform_args <- function(
  packages,
  platform,
  channels,
  channel_priority,
  additional_channels
) {
  platform_args <- NULL
  if (isFALSE(rlang::is_null(packages))) {
    platform_args <- define_platform(
      packages = packages,
      platform = platform,
      channels = channels,
      channel_priority = channel_priority,
      additional_channels = additional_channels,
      verbose = "silent"
    )
  }

  if (isFALSE(rlang::is_null(platform)) && rlang::is_null(platform_args)) {
    platform_args <- c("--platform", platform)
  }

  return(platform_args)
}

#' Check if an existing environment already satisfies a `create_env()`
#' request
#'
#' @param cmd_string Pre-built command string, used to fill in the
#'   early-return result's `cmd` field so it matches what a real call would
#'   have reported.
#'
#' @returns A `condathis_result` ready to return immediately if the target
#'   environment already exists and already satisfies every requested
#'   package spec (so nothing needs to run); `NULL` otherwise (the caller
#'   should proceed with the actual `micromamba create` call).
#'
#' @keywords internal
#' @noRd
env_already_satisfies_request <- function(
  env_name,
  packages,
  overwrite,
  cmd_string,
  verbose_list
) {
  if (
    isTRUE(overwrite) ||
      isFALSE(length(packages) > 0L) ||
      isFALSE(env_exists(env_name = env_name, verbose = "silent"))
  ) {
    return(NULL)
  }

  is_satisfied_vector <- satisfies_dependencies(
    pkg_str_vector = packages,
    env_name = env_name,
    verbose = "silent"
  )
  if (isFALSE(all(is_satisfied_vector))) {
    return(NULL)
  }

  if (isTRUE(verbose_list$strategy %in% c("full", "output"))) {
    cli::cli_inform(
      message = c(
        `!` = "Environment {.field {env_name}} already exists."
      )
    )
  }

  return(new_condathis_result(
    status = 0L,
    stdout = "",
    stderr = "",
    timeout = FALSE,
    pid = NA_integer_,
    cmd = cmd_string,
    env_name = env_name
  ))
}
