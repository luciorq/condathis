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

#' First micromamba release that no longer needs the `~/.mamba/pkgs` workaround
#'
#' libmamba 2.0.0 through 2.0.2 tried to lock the *default* package cache
#' (`~/.mamba/pkgs`, `%APPDATA%/.mamba/pkgs` on Windows) even when the root
#' prefix and `pkgs_dirs` were configured elsewhere, logging
#' `error libmamba Could not lock non-existing path ...` when it was missing
#' (luciorq/condathis#13). From 2.0.4 on libmamba creates that directory
#' itself and stays silent. Verified empirically on 2026-10-02 against
#' 2.0.2 (error) and 2.0.4, 2.0.5, 2.0.8, 2.3.1, 2.8.1, 2.9.0 (no error);
#' there was no stable 2.0.3 release.
#'
#' @keywords internal
#' @noRd
libmamba_pkgs_dir_workaround_fixed_version <- "2.0.4"

#' Default libmamba package-cache directory in the user's home
#'
#' @returns `fs::path` to `~/.mamba/pkgs` (`%APPDATA%/.mamba/pkgs` on
#'   Windows).
#'
#' @keywords internal
#' @noRd
libmamba_default_pkgs_dir <- function() {
  if (isTRUE(is_windows())) {
    base_dir <- base::Sys.getenv(
      x = "APPDATA",
      unset = fs::path_home("AppData", "Roaming"),
      names = FALSE
    )
    return(fs::path(base_dir, ".mamba", "pkgs"))
  }
  return(fs::path_home(".mamba", "pkgs"))
}

#' Does the micromamba in use still need the `~/.mamba/pkgs` workaround?
#'
#' @param umamba_version Character string. Resolved from
#'   `get_best_micromamba_path()` when `NULL`. Returns `FALSE` when no
#'   micromamba is available yet (the first `create_env()` call installs
#'   the pinned version, which is newer than the fix) or when the version
#'   cannot be read.
#'
#' @returns Logical scalar.
#'
#' @keywords internal
#' @noRd
needs_libmamba_pkgs_dir_workaround <- function(umamba_version = NULL) {
  if (rlang::is_null(umamba_version)) {
    umamba_path <- get_best_micromamba_path()
    if (rlang::is_null(umamba_path)) {
      return(FALSE)
    }
    cnd <- rlang::catch_cnd(
      expr = {
        umamba_version <- get_micromamba_version(umamba_path)
      }
    )
    if (isTRUE(rlang::is_condition(cnd))) {
      return(FALSE)
    }
  }
  compare_res <- utils::compareVersion(
    umamba_version,
    libmamba_pkgs_dir_workaround_fixed_version
  )
  return(isTRUE(compare_res < 0L))
}

#' Work around libmamba 2.0.0-2.0.2 requiring `~/.mamba/pkgs` to exist
#'
#' See `libmamba_pkgs_dir_workaround_fixed_version` for the bug. The
#' workaround is version-gated via `needs_libmamba_pkgs_dir_workaround()`:
#' nothing is touched for micromamba >= 2.0.4, or when no micromamba is
#' available yet. (Today the discovery chain only accepts >= 2.8.1, so in
#' practice this never fires; it is kept, gated, for the case where that
#' floor is lowered.)
#'
#' When it does run, it creates the directory if missing and registers a
#' `withr::defer()` cleanup that removes *only what it created*: the `pkgs`
#' directory, plus the parent `.mamba` directory only if that did not exist
#' beforehand either. A pre-existing `.mamba` with other contents is never
#' removed. (Before 0.2.0 the cleanup deleted the whole parent whenever
#' `pkgs` was missing, which could wipe a user's unrelated `.mamba` files.)
#'
#' @param envir Environment whose exit the deferred cleanup is tied to.
#'   Defaults to the caller's own frame (`parent.frame()`) - `withr::defer()`'s
#'   own default `envir` is *its* immediate caller (this function's frame),
#'   so without explicitly threading `envir` through here, the cleanup
#'   would fire the instant this helper returns rather than when
#'   `create_env()` itself exits.
#' @param umamba_version Character string, the micromamba version to gate
#'   on. Resolved automatically when `NULL`; exposed so tests can pin it.
#'
#' @keywords internal
#' @noRd
ensure_libmamba_pkgs_dir_workaround <- function(
  envir = parent.frame(),
  umamba_version = NULL
) {
  if (isFALSE(needs_libmamba_pkgs_dir_workaround(umamba_version))) {
    return(invisible(NULL))
  }
  pkgs_dir <- libmamba_default_pkgs_dir()
  mamba_dir <- fs::path_dir(pkgs_dir)
  if (isTRUE(fs::dir_exists(pkgs_dir))) {
    return(invisible(NULL))
  }
  mamba_dir_already_exists <- isTRUE(fs::dir_exists(mamba_dir))
  fs::dir_create(pkgs_dir)
  withr::defer(
    expr = {
      invisible(rlang::catch_cnd(
        expr = {
          if (isTRUE(fs::dir_exists(pkgs_dir))) {
            fs::dir_delete(pkgs_dir)
          }
          if (
            isFALSE(mamba_dir_already_exists) &&
              isTRUE(fs::dir_exists(mamba_dir))
          ) {
            fs::dir_delete(mamba_dir)
          }
        }
      ))
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
  channels = "conda-forge",
  channel_priority = c("strict", "flexible", "disabled"),
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
  # Uses the raw `backend_env_exists()` generic here, not `backend_has_env()`
  # - this decision is about to delete a directory, so a failed existence
  # check (e.g. a transient `micromamba env list` failure) must abort loudly
  # instead of being coerced to "definitely absent, safe to delete".
  if (
    isFALSE(backend_env_exists(backend, env_name = env_name)) &&
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
  channels = "conda-forge",
  channel_priority = c("strict", "flexible", "disabled"),
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

  # As in `micromamba_backend_create_env()`, use the raw `backend_env_exists()`
  # generic (not `backend_has_env()`) for both checks below: a failed
  # existence check must abort loudly here, not be coerced to "definitely
  # absent" - the first check gates a directory deletion, and treating a
  # transient check failure as "absent" would delete a real environment and
  # then still report it as never having existed.
  env_name_exists <- backend_env_exists(
    backend,
    env_name = env_name,
    verbose = verbose_list$internal_verbose
  )
  if (
    isFALSE(env_name_exists) &&
      isTRUE(fs::dir_exists(env_dir_for_backend(backend, env_name)))
  ) {
    fs::dir_delete(env_dir_for_backend(backend, env_name))
  }
  if (isFALSE(env_name_exists)) {
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
#' `env_root_dir` is matched as an **anchored literal prefix**
#' (`startsWith()` with a trailing separator appended), never a regex or a
#' bare substring: a regex would treat the path's `.` characters as "any
#' character" (matching `~/Xlocal/share/R/condathis/...`), and an
#' unanchored substring match claimed any path merely *containing* the
#' root somewhere inside it (e.g. a backup copy at
#' `/backup/home/user/.local/share/R/condathis/envs/x`) as
#' condathis-owned. The root path itself is excluded by the trailing
#' `basename() != "condathis"` filter, same as before.
#'
#' @param envs_str Character vector of realized environment paths.
#' @param env_root_dir Character string with the condathis install root.
#'
#' @returns A character vector of environment names (basenames).
#'
#' @keywords internal
#' @noRd
condathis_env_names <- function(envs_str, env_root_dir) {
  # Both sides are realized/normalized to forward-slash form upstream
  # (`fs::path_real()`), so "/" is the separator on every platform here.
  root_prefix <- paste0(sub("/+$", "", as.character(env_root_dir)), "/")
  under_root <- startsWith(as.character(envs_str), root_prefix)
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
  envs_str <- realize_env_paths(envs_str)
  return(condathis_env_names(envs_str, env_root_dir))
}

#' Resolve environment paths to their real form, tolerating missing ones
#'
#' `micromamba env list` reports whatever its registries (e.g.
#' `~/.conda/environments.txt`) contain, including stale entries for
#' directories that no longer exist - and an environment can also be
#' removed by another process between the listing subprocess and this
#' call. A vectorized `fs::path_real()` errors with ENOENT on the *first*
#' such path, which used to abort `list_envs()` for every environment at
#' once and, worse, flow through `backend_has_env()`'s never-errors
#' contract as `FALSE` - making `env_exists()` report existing
#' environments as absent and `resolve_backend()` treat them as brand-new.
#' A stale entry must only affect itself: paths that no longer exist are
#' dropped, and a path whose realization fails anyway (removed in the
#' window after the existence check) falls back to its normalized form.
#'
#' @param envs_str Character vector of normalized environment paths.
#'
#' @returns Character vector: existing paths realized (symlinks resolved),
#'   vanished paths removed.
#'
#' @keywords internal
#' @noRd
realize_env_paths <- function(envs_str) {
  envs_str <- envs_str[fs::dir_exists(envs_str)]
  return(vapply(
    envs_str,
    FUN = function(path) {
      tryCatch(
        as.character(fs::path_real(path)),
        error = function(e) path
      )
    },
    FUN.VALUE = character(1L),
    USE.NAMES = FALSE
  ))
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
  # micromamba changed `list --json`'s output shape in 2.9.0: a bare array
  # of packages before, `{"log_history": [...], "packages": [...]}` since.
  # Both shapes must parse - which binary answers depends on the
  # discovery chain (a system-installed 2.9+ can legitimately win over the
  # pinned internal version), so this is a runtime property of the user's
  # machine, not of the version condathis pins.
  if (isFALSE(is.data.frame(pkgs_df)) && rlang::has_name(pkgs_df, "packages")) {
    pkgs_df <- pkgs_df[["packages"]]
  }
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
  activation_env <- get_micromamba_activation_envvars(
    env_name = env_name,
    env_dir = env_dir
  )
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
