#' Construct the `"micromamba"` backend object
#'
#' `condathis`'s original, and default, backend: shells out to a managed
#' `micromamba` binary via `native_cmd()`. Registered in `.onLoad()`.
#'
#' @returns An object of class `c("condathis_backend_micromamba",
#'   "condathis_backend")`.
#' @keywords internal
#' @noRd
new_backend_micromamba <- function() {
  structure(
    list(
      backend_create_env = micromamba_backend_create_env,
      backend_install = micromamba_backend_install,
      backend_remove_env = micromamba_backend_remove_env,
      backend_list_envs = micromamba_backend_list_envs,
      backend_env_exists = micromamba_backend_env_exists,
      backend_list_packages = micromamba_backend_list_packages,
      backend_get_env_dir = micromamba_backend_get_env_dir,
      backend_get_install_dir = micromamba_backend_get_install_dir,
      backend_resolve_run = micromamba_backend_resolve_run,
      backend_available = micromamba_backend_available
    ),
    class = c("condathis_backend_micromamba", "condathis_backend")
  )
}

#' Cached singleton for the `"micromamba"` backend object
#'
#' The object carries no mutable state (only its class tag), so internal
#' call sites reach for this instead of constructing/re-registering a new
#' one on every call.
#'
#' @keywords internal
#' @noRd
micromamba_backend <- local({
  cached <- NULL
  function() {
    if (is.null(cached)) {
      cached <<- new_backend_micromamba()
    }
    return(cached)
  }
})

#' @keywords internal
#' @noRd
micromamba_backend_get_install_dir <- function(backend) {
  dir_path <- get_condathis_path()
  if (isFALSE(fs::dir_exists(dir_path))) {
    fs::dir_create(dir_path, recurse = TRUE)
  }
  dir_path <- base::normalizePath(dir_path, mustWork = FALSE)
  return(fs::path_real(dir_path))
}

#' @keywords internal
#' @noRd
micromamba_backend_get_env_dir <- function(
  backend,
  env_name = "condathis-env"
) {
  return(fs::path(install_dir_for_backend(backend), "envs", env_name))
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
#'   Defaults to the caller's own frame (`parent.frame()`) — `withr::defer()`'s
#'   own default `envir` is *its* immediate caller (this function's frame),
#'   so without explicitly threading `envir` through here, the cleanup
#'   would fire the instant this helper returns rather than when
#'   `create_env()` itself exits.
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

#' @keywords internal
#' @noRd
micromamba_backend_create_env <- function(
  backend,
  packages = NULL,
  env_file = NULL,
  env_name = "condathis-env",
  channels = c("conda-forge", "bioconda"),
  channel_priority = c("disabled", "strict", "flexible"),
  additional_channels = NULL,
  platform = NULL,
  overwrite = FALSE,
  verbose = c("output", "silent", "cmd", "spinner", "full")
) {
  ensure_libmamba_pkgs_dir_workaround()

  verbose_list <- parse_strategy_verbose(verbose = verbose)
  packages_arg <- resolve_create_env_packages_arg(
    packages = packages,
    env_file = env_file
  )
  channels_arg <- format_channels_args(channels, additional_channels)
  channel_priority_args <- parse_strategy_channel_priority(
    channel_priority = channel_priority
  )
  platform_args <- resolve_create_env_platform_args(
    packages = packages,
    platform = platform,
    channels = channels,
    channel_priority = channel_priority,
    additional_channels = additional_channels
  )

  # Workaround for when directory already exists by other reasons.
  # + When micromamba fail to create an environment with a different platform
  # + than the native one, it leaves the directory there and do not overwrite.
  if (
    isFALSE(backend_has_env(backend, env_name = env_name)) &&
      isTRUE(fs::dir_exists(env_dir_for_backend(backend, env_name)))
  ) {
    fs::dir_delete(env_dir_for_backend(backend, env_name))
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
  return(px_res)
}

#' @keywords internal
#' @noRd
micromamba_backend_install <- function(
  backend,
  packages,
  env_name = "condathis-env",
  channels = c("conda-forge", "bioconda"),
  channel_priority = c("disabled", "strict", "flexible"),
  additional_channels = NULL,
  verbose = c("output", "silent", "cmd", "spinner", "full")
) {
  verbose_list <- parse_strategy_verbose(verbose = verbose)
  channels_arg <- format_channels_args(channels, additional_channels)
  channel_priority_args <- parse_strategy_channel_priority(
    channel_priority = channel_priority
  )

  px_res <- rethrow_error_cmd(
    expr = {
      native_cmd(
        conda_cmd = "install",
        conda_args = c(
          "-n",
          env_name,
          "--yes",
          verbose_list$quiet_flag,
          "--override-channels",
          channel_priority_args,
          channels_arg
        ),
        packages,
        verbose = verbose_list
      )
    }
  )
  return(px_res)
}

#' @keywords internal
#' @noRd
micromamba_backend_remove_env <- function(
  backend,
  env_name = "condathis-env",
  verbose = c("silent", "cmd", "output", "spinner", "full")
) {
  verbose_list <- parse_strategy_verbose(verbose = verbose)

  if (
    isFALSE(backend_has_env(
      backend,
      env_name = env_name,
      verbose = verbose_list$internal_verbose
    )) &&
      isTRUE(fs::dir_exists(env_dir_for_backend(backend, env_name)))
  ) {
    fs::dir_delete(env_dir_for_backend(backend, env_name))
  }
  if (
    isFALSE(backend_has_env(
      backend,
      env_name = env_name,
      verbose = verbose_list$internal_verbose
    ))
  ) {
    cli::cli_abort(
      message = c(
        `x` = "Environment {.field {env_name}} does not exist.",
        `!` = "Check {.code list_envs()} for available environments."
      ),
      class = "condathis_error_env_remove"
    )
  }

  px_res <- rethrow_error_cmd(
    expr = {
      native_cmd(
        conda_cmd = "env",
        conda_args = c(
          "remove",
          "-n",
          env_name,
          "--yes",
          verbose_list$quiet_flag
        ),
        verbose = verbose_list
      )
    }
  )
  return(px_res)
}

#' Keep the env paths that live under the condathis install root, return names
#'
#' Extracted so the filtering can be unit-tested without a live `micromamba`
#' call or real directories.
#'
#' `env_root_dir` is matched as a **literal** substring (`stringr::fixed()`),
#' not a regex. It is a filesystem path (e.g. `~/.local/share/R/condathis`)
#' whose `.` characters would otherwise be treated as "any character" regex
#' metacharacters — matching, for example, `~/Xlocal/share/R/condathis/...`
#' as if it belonged to condathis. The root path itself is excluded by the
#' trailing `basename() != "condathis"` filter, same as before.
#'
#' @param envs_str Character vector of realized environment paths.
#' @param env_root_dir Character string with the condathis install root.
#'
#' @returns A character vector of environment names (basenames).
#'
#' @keywords internal
#' @noRd
condathis_env_names <- function(envs_str, env_root_dir) {
  # `env_root_dir` is an `fs_path`; `stringr::fixed()` wants plain character.
  under_root <- stringr::str_detect(
    as.character(envs_str),
    stringr::fixed(as.character(env_root_dir))
  )
  env_names <- base::basename(envs_str[under_root])
  return(env_names[!env_names %in% "condathis"])
}

#' @keywords internal
#' @noRd
micromamba_backend_list_envs <- function(
  backend,
  verbose = "silent"
) {
  env_root_dir <- install_dir_for_backend(backend)
  px_res <- rethrow_error_cmd(
    expr = {
      native_cmd(
        conda_cmd = "env",
        conda_args = c(
          "list",
          "-q",
          "--json"
        ),
        verbose = verbose
      )
    }
  )
  if (isFALSE(identical(px_res$status, 0L))) {
    cli::cli_abort(
      message = c(
        `x` = "Failed to list environments.",
        `!` = "{.code micromamba env list} exited with status {.val {px_res$status}}."
      ),
      class = "condathis_cmd_status_error"
    )
  }

  envs_list <- jsonlite::fromJSON(px_res$stdout)
  envs_str <- base::normalizePath(envs_list$envs, mustWork = FALSE)
  envs_str <- fs::path_real(envs_str)
  return(condathis_env_names(envs_str, env_root_dir))
}

#' @keywords internal
#' @noRd
micromamba_backend_env_exists <- function(
  backend,
  env_name,
  verbose = "silent"
) {
  available_envs <- backend_list_envs(backend, verbose = verbose)
  return(isTRUE(env_name %in% available_envs))
}

#' @keywords internal
#' @noRd
micromamba_backend_list_packages <- function(
  backend,
  env_name = "condathis-env",
  verbose = "silent"
) {
  verbose_list <- parse_strategy_verbose(verbose = verbose)

  px_res <- rethrow_error_cmd(
    expr = {
      native_cmd(
        conda_cmd = "list",
        conda_args = c(
          "-n",
          env_name,
          verbose_list$quiet_flag,
          "--json"
        ),
        verbose = verbose_list$internal_verbose,
        error = "cancel"
      )
    }
  )
  if (isFALSE(identical(px_res$status, 0L))) {
    cli::cli_abort(
      message = c(
        `x` = "Failed to list packages in environment {.field {env_name}}.",
        `!` = "{.code micromamba list} exited with status {.val {px_res$status}}."
      ),
      class = "condathis_cmd_status_error"
    )
  }

  pkgs_df <- jsonlite::fromJSON(px_res$stdout)
  if (identical(length(pkgs_df), 0L)) {
    pkgs_df <- base::data.frame(
      "base_url" = character(0L),
      "build_number" = integer(0L),
      "build_string" = character(0L),
      "channel" = character(0L),
      "dist_name" = character(0L),
      "name" = character(0L),
      "platform" = character(0L),
      "version" = character(0L)
    )
  }
  pkgs_df <- base::unclass(pkgs_df)
  base::attr(pkgs_df, "class") <- c("tbl_df", "tbl", "data.frame")
  return(pkgs_df)
}

#' @keywords internal
#' @noRd
micromamba_backend_resolve_run <- function(
  backend,
  cmd,
  args = character(0L),
  env_name = "condathis-env",
  verbose = "silent"
) {
  env_dir <- env_dir_for_backend(backend, env_name)
  cmd_path <- resolve_env_bin_path(env_dir, cmd) %||% cmd
  activation_env <- get_micromamba_activation_envvars(env_name = env_name)
  return(list(
    command = as.character(cmd_path),
    args = as.character(args),
    env = activation_env,
    dir = NULL
  ))
}

#' @keywords internal
#' @noRd
micromamba_backend_available <- function(backend) {
  return(TRUE)
}
