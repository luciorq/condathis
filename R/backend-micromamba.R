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
      backend_resolve_run_in_dir = micromamba_backend_resolve_run_in_dir,
      backend_available = micromamba_backend_available,
      backend_clean_cache = micromamba_backend_clean_cache,
      backend_native_platform = micromamba_backend_native_platform,
      backend_can_solve = micromamba_backend_can_solve
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

#' First micromamba release that fixes the `~/.mamba/pkgs` lock error
#'
#' WORKAROUND(luciorq/condathis#13): libmamba 2.0.0 to 2.0.2 lock the default
#' package cache (`~/.mamba/pkgs`, `%APPDATA%/.mamba/pkgs` on Windows) even
#' when the root prefix and `pkgs_dirs` point elsewhere. They log
#' `error libmamba Could not lock non-existing path ...` when it is missing.
#' Remove when the minimum supported micromamba is 2.0.4 or later.
#'
#' libmamba 2.0.4 and later create that directory and stay silent.
#' Verified on 2026-10-02 against 2.0.2 (error) and 2.0.4, 2.0.5, 2.0.8,
#' 2.3.1, 2.8.1, 2.9.0 (no error), and on 2026-10-26 against 2.10.0 (no
#' error). No stable 2.0.3 release exists.
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

#' Does the micromamba in use need `~/.mamba/pkgs` to exist?
#'
#' @param umamba_version Character string. When `NULL`, the version in use
#'   is unknown. If `minimum_version` already has the fix, no micromamba in
#'   use can need the workaround, so the result is `FALSE` with no file
#'   system or process access. Otherwise the version is read from the
#'   binary of `get_best_micromamba_path()`. The result is also `FALSE` when
#'   no micromamba is available yet (the first `create_env()` call installs
#'   the pinned version, which is newer than the fix) or when the version
#'   cannot be read.
#' @param minimum_version Character string, the oldest micromamba version
#'   that discovery and `install_micromamba()` accept. Exposed so tests can
#'   lower it.
#'
#' @returns Logical scalar.
#'
#' @keywords internal
#' @noRd
needs_libmamba_pkgs_dir_workaround <- function(
  umamba_version = NULL,
  minimum_version = micromamba_minimum_version
) {
  if (rlang::is_null(umamba_version)) {
    # `get_best_micromamba_path()` and `install_micromamba()` accept only
    # micromamba >= `minimum_version`. Compare the two constants first: the
    # binary lookup and the extra `micromamba --version` process ran on
    # every `create_env()` call, although their result can only matter if
    # the minimum is lowered below the fixed version.
    floor_compare <- utils::compareVersion(
      minimum_version,
      libmamba_pkgs_dir_workaround_fixed_version
    )
    if (isFALSE(floor_compare < 0L)) {
      return(FALSE)
    }
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
#' directory creation is gated by `needs_libmamba_pkgs_dir_workaround()`:
#' nothing is touched for micromamba >= 2.0.4, or when no micromamba is
#' available yet. The discovery chain accepts only micromamba >=
#' `micromamba_minimum_version` (2.8.1), so this never fires today, and the
#' gate costs no file system or process access. It is kept, gated, in case
#' that floor is lowered.
#'
#' When it runs, it creates the directory if missing and registers a
#' `withr::defer()` cleanup that removes only what it created: the `pkgs`
#' directory, plus the parent `.mamba` directory only if that did not exist
#' beforehand either. A pre-existing `.mamba` with other contents is never
#' removed.
#'
#' @param envir Environment whose exit triggers the deferred cleanup.
#'   Defaults to the caller's frame (`parent.frame()`). `withr::defer()`
#'   defaults to its own caller's frame (this function), so without passing
#'   `envir` the cleanup would fire when this helper returns, not when
#'   `create_env()` exits.
#' @param umamba_version Character string, the micromamba version to gate
#'   on. Resolved automatically when `NULL`. Exposed so tests can pin it.
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
#' @returns `packages` when `env_file` is `NULL`; otherwise
#'   `c("-f", env_file)`. `~` at the start of a package path or of
#'   `env_file` is expanded as micromamba expands it (see
#'   `micromamba_expand_home()`): `micromamba create` can run with another
#'   home (see `micromamba_create_keeps_home()`). Aborts with class
#'   `c("condathis_create_env_missing_env_file",
#'   "condathis_create_missing_env_file", "condathis_invalid_env_file",
#'   "condathis_invalid_arg", "condathis_error")` if `env_file` is given but
#'   does not exist. `create_env()` checks this first; this check only
#'   catches a file removed in between.
#'
#' @keywords internal
#' @noRd
resolve_create_env_packages_arg <- function(packages, env_file) {
  if (isTRUE(rlang::is_null(env_file))) {
    if (isTRUE(rlang::is_null(packages))) {
      return(NULL)
    }
    return(micromamba_expand_home(packages))
  }
  if (isFALSE(fs::file_exists(env_file))) {
    condathis_abort(
      message = c(
        `x` = "{.arg env_file} {.path {env_file}} does not exist."
      ),
      class = c(
        "condathis_create_env_missing_env_file",
        "condathis_create_missing_env_file",
        "condathis_invalid_env_file",
        "condathis_invalid_arg"
      )
    )
  }
  return(c("-f", micromamba_expand_home(as.character(fs::path(env_file)))))
}

#' The `--platform` argument of `micromamba create` and `micromamba install`
#'
#' condathis chooses the platform before it calls the backend (see
#' `resolve_create_platform()` and `resolve_install_platform()`), so the
#' micromamba backend only passes it on.
#'
#' @param platform `NULL`, or a platform (subdir) name.
#'
#' @returns `c("--platform", platform)`, or `NULL` for `NULL`: micromamba
#'   then solves for the platform of its binary.
#'
#' @keywords internal
#' @noRd
micromamba_platform_args <- function(platform) {
  if (rlang::is_null(platform)) {
    return(NULL)
  }
  return(c("--platform", platform))
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
  platform_args <- micromamba_platform_args(platform)

  # condathis calls this only for a missing environment directory (see
  # ?register_backend). `with_env_dir_replacement()` has deleted a stale
  # directory, or moved an existing environment (`overwrite = TRUE`) aside,
  # and runs a micromamba that lives in that environment from its new
  # place (`micromamba_binary_in_env_dir()`). It also moves the old
  # environment back when this create fails, and deletes what a failed
  # create left: micromamba writes `conda-meta/history` before the
  # downloads, and leaves the directory behind when a create for a
  # non-native platform fails.
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
        error = "cancel",
        # micromamba starts processes of its own (the pip of an environment
        # file, link scripts). On Windows an interrupt kills only
        # micromamba, so pip went on after the lock of the environment was
        # released, and kept its files open.
        cleanup_tree = TRUE
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
  platform = NULL,
  verbose = c("output", "silent", "cmd", "spinner", "full")
) {
  verbose_list <- parse_strategy_verbose(verbose = verbose)
  channels_arg <- format_channels_args(channels, additional_channels)
  channel_priority_args <- parse_strategy_channel_priority(
    channel_priority = channel_priority
  )
  abort_unless_micromamba_env(
    backend,
    env_name = env_name,
    class = "condathis_install_packages_env_not_found"
  )
  # condathis passes the platform of the environment, or for one without
  # packages of a platform the emulation fallback of create_env() (see
  # `resolve_install_platform()`). `native_cmd()` passes `--rc-file`, so
  # micromamba does not read the platform from the `.mambarc` of the
  # environment itself.
  platform_args <- micromamba_platform_args(platform)

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
          channels_arg,
          platform_args
        ),
        packages,
        verbose = verbose_list,
        # As for `create` (see `micromamba_backend_create_env()`).
        cleanup_tree = TRUE
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
  verbose = c("output", "silent", "cmd", "spinner", "full")
) {
  verbose_list <- parse_strategy_verbose(verbose = verbose)

  # Use the raw `backend_env_exists()` generic, not `backend_has_env()`, as
  # `with_env_dir_replacement()` does. A failed existence check must abort
  # loudly: the first check gates a directory deletion, and coercing a
  # transient failure to "absent" would delete a real environment and then
  # report it as never having existed. A probe prints nothing (rule R4).
  env_name_exists <- backend_env_exists(
    backend,
    env_name = env_name,
    verbose = "silent"
  )
  if (
    isFALSE(env_name_exists) &&
      isTRUE(fs::dir_exists(env_dir_for_backend(backend, env_name)))
  ) {
    delete_stale_env_dir(backend, env_name)
  }
  # `remove_env()` checks existence before it calls the backend. This
  # safeguard is reached only when that probe failed (rule R5).
  if (isFALSE(env_name_exists)) {
    abort_env_not_found(
      env_name,
      class = c(
        "condathis_remove_env_env_not_found",
        "condathis_error_env_remove"
      ),
      hint = c(`i` = "See {.fn list_envs} for the environments that exist.")
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

#' The path of the micromamba in use, relative to an environment directory
#'
#' `with_env_dir_replacement()` moves an environment aside before the
#' backend creates it again. When the micromamba binary that `native_cmd()`
#' would run is inside that environment, the create must run it from the
#' new place.
#'
#' @returns A relative path, or `NULL` when no binary is found or it is not
#'   inside the directory of `env_name`.
#'
#' @keywords internal
#' @noRd
micromamba_binary_in_env_dir <- function(backend, env_name) {
  binary <- get_best_micromamba_path()
  if (is.null(binary)) {
    return(NULL)
  }
  real_binary <- real_path_or_na(binary)
  real_env_dir <- real_path_or_na(env_dir_for_backend(backend, env_name))
  if (isTRUE(is.na(real_binary)) || isTRUE(is.na(real_env_dir))) {
    return(NULL)
  }
  real_binary <- to_slash_path(real_binary)
  real_env_dir <- to_slash_path(real_env_dir)
  prefix <- paste0(tolower_on_windows(real_env_dir), "/")
  if (isFALSE(startsWith(tolower_on_windows(real_binary), prefix))) {
    return(NULL)
  }
  return(substring(real_binary, nchar(prefix) + 1L))
}

#' Abort when an environment of the micromamba backend does not exist
#'
#' condathis checks that an environment exists before it calls
#' `backend_install()` or `backend_list_packages()`, so this is reached only
#' when that probe failed (rule R5), or when another process removed the
#' environment in between. micromamba itself would fail with "No prefix
#' found"; the contract asks for the class `condathis_env_not_found` (see
#' ?register_backend). A directory without `conda-meta/history` is not an
#' environment, as for `list_conda_prefix_envs()`.
#'
#' @param class Character vector, the function-specific classes.
#'
#' @returns `NULL`, invisibly, when the environment exists.
#'
#' @keywords internal
#' @noRd
abort_unless_micromamba_env <- function(
  backend,
  env_name,
  class,
  call = rlang::caller_env()
) {
  return(abort_unless_conda_prefix(
    env_dir_for_backend(backend, env_name),
    env_name = env_name,
    class = class,
    call = call
  ))
}

#' Run a micromamba listing only when micromamba is already installed
#'
#' The listings of the micromamba backend are queries, and a query never
#' installs micromamba (decision D3). They call this instead of
#' `native_cmd()`, and read the file system when it returns `NULL`.
#'
#' @param ... Arguments passed to `native_cmd()`.
#'
#' @returns The result of `native_cmd()`, or `NULL` when no usable
#'   micromamba binary is found. In that case no process is started.
#'
#' @keywords internal
#' @noRd
native_cmd_if_installed <- function(...) {
  return(tryCatch(
    native_cmd(..., install = FALSE),
    condathis_micromamba_not_installed = function(cnd) NULL
  ))
}

#' @keywords internal
#' @noRd
micromamba_backend_list_envs <- function(
  backend,
  verbose = "silent"
) {
  verbose_list <- parse_strategy_verbose(verbose = verbose)
  # Decision D3: a query on a fresh root starts no process, installs no
  # micromamba and creates no directory. `backend_env_exists()` probes every
  # backend on every call that names an environment, so this also keeps
  # calls with another backend's `method` from running micromamba.
  if (isFALSE(backend_has_env_dirs("micromamba"))) {
    return(character(0L))
  }
  env_root_dir <- install_dir_for_backend(backend)
  # `verbose_list$quiet_flag` makes `native_cmd()` keep the JSON listing off
  # the console for "output"; "cmd" and "full" still echo the command.
  # `native_cmd()` gives the listing a home inside the root, so micromamba
  # does not rewrite the user's `~/.conda/environments.txt` on every probe
  # (see `micromamba_cmd_overlay()`).
  px_res <- rethrow_error_cmd(
    expr = {
      native_cmd_if_installed(
        conda_cmd = "env",
        conda_args = c(
          "list",
          "-q",
          verbose_list$quiet_flag,
          "--json"
        ),
        verbose = verbose_list
      )
    }
  )
  # Environment directories but no micromamba binary, for example after an
  # upgrade raised the minimum micromamba version: answer from the file
  # system instead of installing micromamba (decision D3).
  if (is.null(px_res)) {
    return(list_conda_prefix_envs(env_root_dir))
  }
  if (isFALSE(identical(px_res$status, 0L))) {
    condathis_abort(
      message = c(
        `x` = "Failed to list environments.",
        `i` = "{.code micromamba env list} exited with status {.val {px_res$status}}."
      ),
      class = c(
        "condathis_micromamba_status_error",
        "condathis_cmd_status_error"
      ),
      status = px_res$status,
      stderr = px_res$stderr
    )
  }

  envs_list <- jsonlite::fromJSON(px_res$stdout)
  # micromamba 2.9.0 and later hide every `/t/<word>` of their JSON output
  # as a channel token (see `hide_secrets()`), paths included: under a root
  # with such a part, no listed path names its environment. Read the same
  # environments from the file system then.
  if (isTRUE(any(grepl("/t/*****", envs_list$envs, fixed = TRUE)))) {
    return(list_conda_prefix_envs(env_root_dir))
  }
  envs_str <- base::normalizePath(envs_list$envs, mustWork = FALSE)
  envs_str <- realize_env_paths(envs_str)
  # micromamba can report one environment under two spellings, for example
  # through a registry entry with a symbolic link in its path (on macOS,
  # `/var` is a link to `/private/var`). Both realize to the same path, and
  # the contract requires unique names.
  return(unique(condathis_env_names(envs_str, env_root_dir)))
}

#' @keywords internal
#' @noRd
micromamba_backend_env_exists <- function(
  backend,
  env_name,
  verbose = "silent"
) {
  # The cheap probe (see `backend_has_env_dirs()`): micromamba lists only
  # environments whose directory exists, so a missing directory is a sure
  # "no", without a process, an install or a new directory. When the
  # directory exists, the listing decides: on a case-insensitive file
  # system, `<root>/envs/myenv` also opens `<root>/envs/MyEnv`.
  if (
    isFALSE(fs::dir_exists(fs::path(get_condathis_path(), "envs", env_name)))
  ) {
    return(FALSE)
  }
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
  abort_unless_micromamba_env(
    backend,
    env_name = env_name,
    class = c(
      "condathis_list_packages_env_not_found",
      "condathis_list_packages_missing_env"
    )
  )

  px_res <- rethrow_error_cmd(
    expr = {
      native_cmd_if_installed(
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
  if (is.null(px_res)) {
    # No micromamba binary: read the package records and the PyPI packages,
    # as for the listing of environments (decision D3).
    pkgs_df <- read_env_package_records(
      env_dir = env_dir_for_backend(backend, env_name),
      env_name = env_name
    )
  } else {
    pkgs_df <- micromamba_use_record_channels(
      micromamba_parse_list_json(px_res, env_name),
      env_dir = env_dir_for_backend(backend, env_name)
    )
  }
  # A local channel in a directory with white space was passed to
  # micromamba by another path (see `micromamba_channel_arg()`), which is
  # also in the package URLs.
  if (isTRUE(is.data.frame(pkgs_df))) {
    for (column in intersect(c("channel", "base_url", "url"), names(pkgs_df))) {
      pkgs_df[[column]] <- micromamba_channel_display(pkgs_df[[column]])
    }
  }
  return(as_package_records_tbl(pkgs_df))
}

#' Parse the output of `micromamba list --json`
#'
#' @param px_res The result of `native_cmd()`.
#' @param env_name Character string, for the error message.
#'
#' @returns A data frame, or an empty list for an empty environment. A
#'   non-zero status aborts with `c("condathis_micromamba_status_error",
#'   "condathis_cmd_status_error", "condathis_error")`.
#'
#' @keywords internal
#' @noRd
micromamba_parse_list_json <- function(px_res, env_name) {
  if (isFALSE(identical(px_res$status, 0L))) {
    condathis_abort(
      message = c(
        `x` = "Failed to list packages in environment {.field {env_name}}.",
        `i` = "{.code micromamba list} exited with status {.val {px_res$status}}."
      ),
      class = c(
        "condathis_micromamba_status_error",
        "condathis_cmd_status_error"
      ),
      status = px_res$status,
      stderr = px_res$stderr,
      call = rlang::caller_env()
    )
  }
  pkgs_df <- jsonlite::fromJSON(px_res$stdout)
  # micromamba 2.9.0 changed the `list --json` shape: a bare array of
  # packages before, `{"log_history": [...], "packages": [...]}` since.
  # Parse both: the discovery chain can pick a system-installed 2.9+ over the
  # pinned version, so the shape depends on the user's machine.
  if (isFALSE(is.data.frame(pkgs_df)) && rlang::has_name(pkgs_df, "packages")) {
    pkgs_df <- pkgs_df[["packages"]]
  }
  return(pkgs_df)
}

#' Report the channel of the package records in a `micromamba list` listing
#'
#' `micromamba list --json` derives `channel` from the package URL. Since
#' micromamba 2.10.0, a package downloads from the URL that its channel's
#' repodata gives, which can be outside the channel, and the listing then
#' reports that location as the channel. So a repeated, identical
#' `create_env()` aborted, and the channel differed from the one reported
#' without a micromamba binary and by other backends. The record in
#' `conda-meta/` keeps the channel the package was solved from, as
#' `micromamba list` without `--json` shows. A listed channel that is
#' neither the record's channel (see `conda_record_channel()`) nor its
#' `base_url` is replaced by the record's. Rows without a record, such as
#' PyPI packages, are kept, and so is the whole listing when the records
#' cannot be read.
#'
#' @param pkgs_df The result of `micromamba_parse_list_json()`.
#' @param env_dir Character string with the environment directory.
#'
#' @returns `pkgs_df`, with `channel` taken from the records where they
#'   differ.
#'
#' @keywords internal
#' @noRd
micromamba_use_record_channels <- function(pkgs_df, env_dir) {
  if (
    isFALSE(is.data.frame(pkgs_df)) ||
      identical(nrow(pkgs_df), 0L) ||
      isFALSE(all(c("base_url", "channel", "dist_name") %in% names(pkgs_df)))
  ) {
    return(pkgs_df)
  }
  records_df <- tryCatch(
    read_conda_package_records(
      env_dir = env_dir,
      env_name = fs::path_file(env_dir)
    ),
    condathis_env_not_found = function(cnd) list()
  )
  if (identical(length(records_df), 0L)) {
    return(pkgs_df)
  }
  record_channel <- records_df[["channel"]][
    match(pkgs_df[["dist_name"]], records_df[["dist_name"]])
  ]
  # A missing listed value compares as `NA`, and is replaced too.
  keep <- is.na(record_channel) |
    record_channel == pkgs_df[["channel"]] |
    record_channel == pkgs_df[["base_url"]]
  replace <- !(keep %in% TRUE)
  pkgs_df[["channel"]][replace] <- record_channel[replace]
  return(pkgs_df)
}

#' @keywords internal
#' @noRd
micromamba_backend_resolve_run <- function(
  backend,
  cmd,
  args = character(0L),
  env_name = "condathis-env",
  verbose = "silent",
  base_env = NULL,
  timeout = Inf
) {
  # The activation variables are the ones that micromamba's activation of
  # the environment gives, cached per environment (see
  # `get_micromamba_activation_envvars()`). `base_env` gives the activation
  # the `TMPDIR` and the user cache of the command.
  return(micromamba_resolve_run_in_dir(
    env_dir = env_dir_for_backend(backend, env_name),
    cmd = cmd,
    args = args,
    env_name = env_name,
    base_env = base_env,
    timeout = timeout
  ))
}

#' @keywords internal
#' @noRd
micromamba_backend_resolve_run_in_dir <- function(
  backend,
  cmd,
  args = character(0L),
  env_dir,
  verbose = "silent",
  base_env = NULL,
  timeout = Inf
) {
  # As `micromamba_backend_resolve_run()`: the activation variables are
  # micromamba's own, cached per directory.
  return(micromamba_resolve_run_in_dir(
    env_dir = env_dir,
    cmd = cmd,
    args = args,
    base_env = base_env,
    timeout = timeout
  ))
}

#' Describe a command run in a micromamba environment directory
#'
#' The body of `micromamba_backend_resolve_run()`, which looks the directory
#' up by name, and of `micromamba_backend_resolve_run_in_dir()`, for an
#' environment given by `env_path()`, which has no name.
#'
#' On Linux and macOS, `command` is the bare `cmd`, as `micromamba run`
#' started it: `execvp()` finds it on the activated `PATH`, in the order
#' that `activate.d` scripts give, and the program gets the name as typed
#' (`argv[0]`), which tools print in their messages. On Windows, a command
#' of the environment becomes its path (see `resolve_env_bin_path()`).
#' `run_bin()` looks a bare name up itself, in the environment first.
#'
#' @param env_dir Character string with the environment's directory.
#' @param cmd Character string with the command.
#' @param args Character vector of arguments.
#' @param env_name Character string, or `NULL` for an environment given by
#'   path. Selects how activation addresses the environment.
#' @param base_env Named character vector, the environment of the command
#'   before activation, or `NULL`.
#' @param timeout Numeric, the seconds the activation may take.
#'
#' @returns `list(command, args, env, dir)`, as `backend_resolve_run()`.
#'
#' @keywords internal
#' @noRd
micromamba_resolve_run_in_dir <- function(
  env_dir,
  cmd,
  args = character(0L),
  env_name = NULL,
  base_env = NULL,
  timeout = Inf
) {
  cmd_path <- cmd
  if (isTRUE(is_windows())) {
    cmd_path <- resolve_env_bin_path(env_dir, cmd) %||% cmd
  }
  activation_env <- get_micromamba_activation_envvars(
    env_name = env_name,
    env_dir = env_dir,
    base_env = base_env,
    timeout = timeout
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
