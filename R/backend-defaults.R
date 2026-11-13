#' Get the root directory of a backend
#'
#' Returns the root (data directory) that condathis assigns to a backend.
#' The root of the built-in `"micromamba"` backend is the condathis data
#' directory (see [get_install_dir()]). The root of every other backend is
#' the directory of its name inside it, for example
#' `<condathis data directory>/rattler`. A backend keeps its environments in
#' `<root>/envs`, and its caches in other directories of its root (see
#' *Roots* in [register_backend()]). The default functions of the backend
#' contract use this directory, and a backend package calls it to find its
#' root.
#'
#' `backend_root_dir()` computes the path on every call, so it follows
#' [with_sandbox_dir()].
#'
#' Part of the **experimental** backend extension API. See the
#' *Lifecycle* section of [register_backend()].
#'
#' @param name Character string, a backend name, registered or not. It
#'   follows the rules of `name` in [register_backend()], except that
#'   `"micromamba"` is allowed.
#'
#' @returns An `fs_path`, the absolute path of the root. When the root
#'   exists, its real path (symbolic links resolved). Otherwise, the real
#'   path of its nearest existing parent directory, followed by the rest of
#'   the path. It creates nothing. Aborts with class
#'   `condathis_backend_invalid_name` for a malformed name, and
#'   `condathis_backend_reserved_name` (also `condathis_backend_invalid_name`)
#'   for a reserved name other than `"micromamba"`.
#'
#' @seealso [get_install_dir()]
#' @family backends
#'
#' @examples
#' condathis::with_sandbox_dir({
#'   condathis::backend_root_dir("rattler")
#'   #> <data dir>/R/condathis/rattler
#' })
#'
#' @export
backend_root_dir <- function(name) {
  validate_backend_name(name, allow_reserved = identical(name, "micromamba"))
  return(realize_existing_part(backend_root_path(name)))
}

#' The root path of a backend, unchecked and not realized
#'
#' The cheap form of `backend_root_dir()`, for probes that only ask whether
#' something exists.
#'
#' @param name Character string, a valid backend name.
#'
#' @returns An `fs_path`.
#'
#' @keywords internal
#' @noRd
backend_root_path <- function(name) {
  if (identical(name, "micromamba")) {
    return(get_condathis_path())
  }
  return(fs::path(get_condathis_path(), name))
}

#' The real form of a path that need not exist
#'
#' The nearest existing directory on the path is realized
#' (`fs::path_real()`), and the rest is appended unchanged. On macOS, a
#' temporary directory under `/var` then reads `/private/var`, before and
#' after the rest of the path is created.
#'
#' @param path Character string, an absolute path.
#'
#' @returns An `fs_path`. `path` unchanged when no part of it can be
#'   realized.
#'
#' @keywords internal
#' @noRd
realize_existing_part <- function(path) {
  path <- fs::path_abs(path)
  current <- path
  rest <- character(0L)
  repeat {
    if (isTRUE(fs::dir_exists(current))) {
      real <- tryCatch(
        as.character(fs::path_real(current)),
        error = function(e) NULL
      )
      if (isFALSE(is.null(real))) {
        return(do.call(fs::path, as.list(c(real, rest))))
      }
    }
    parent <- fs::path_dir(current)
    if (isTRUE(identical(as.character(parent), as.character(current)))) {
      return(path)
    }
    rest <- c(as.character(fs::path_file(current)), rest)
    current <- parent
  }
}

#' The root of a backend object, for the default methods
#'
#' @param backend A backend object.
#'
#' @returns An `fs_path`, from `backend_root_dir()` of the registered name
#'   of the backend's class.
#'
#' @keywords internal
#' @noRd
default_backend_root <- function(backend) {
  return(backend_root_dir(backend_display_name(backend)))
}

# --- Default methods of the optional contract functions -------------------
# Each is used for a backend object that does not have the function (see
# `backend_optional_hooks`). They treat the environments of the backend as
# conda prefixes in `<backend_root_dir(name)>/envs`, as micromamba does.

#' @keywords internal
#' @noRd
#' @exportS3Method
backend_get_install_dir.default <- function(backend) {
  root <- default_backend_root(backend)
  if (isFALSE(fs::dir_exists(root))) {
    fs::dir_create(root, recurse = TRUE)
  }
  return(fs::path_real(root))
}

#' @keywords internal
#' @noRd
#' @exportS3Method
backend_get_env_dir.default <- function(backend, env_name = "condathis-env") {
  # `backend_root_dir()` never creates the root (decision D3).
  return(fs::path(default_backend_root(backend), "envs", env_name))
}

#' @keywords internal
#' @noRd
#' @exportS3Method
backend_list_envs.default <- function(backend, verbose = "silent") {
  return(list_conda_prefix_envs(default_backend_root(backend)))
}

#' @keywords internal
#' @noRd
#' @exportS3Method
backend_env_exists.default <- function(backend, env_name, verbose = "silent") {
  # A missing directory is a sure "no". When it exists, the listing
  # decides: on a file system that ignores case, `<root>/envs/myenv` also
  # opens `<root>/envs/MyEnv`.
  env_dir <- fs::path(default_backend_root(backend), "envs", env_name)
  if (isFALSE(fs::dir_exists(env_dir))) {
    return(FALSE)
  }
  return(isTRUE(env_name %in% backend_list_envs(backend, verbose = verbose)))
}

#' @keywords internal
#' @noRd
#' @exportS3Method
backend_resolve_run_in_dir.default <- function(
  backend,
  cmd,
  args = character(0L),
  env_dir,
  verbose = "silent",
  base_env = NULL,
  timeout = Inf
) {
  # condathis asks only a backend that has this function (see
  # `resolve_env_path_target()`), so this is reached when it is called
  # directly.
  backend_name <- backend_display_name(backend)
  condathis_abort(
    message = c(
      `x` = "Backend {.field {backend_name}} cannot run commands in an environment given by {.fn env_path}."
    ),
    class = "condathis_backend_unsupported"
  )
}

#' @keywords internal
#' @noRd
#' @exportS3Method
backend_list_packages.default <- function(
  backend,
  env_name = "condathis-env",
  verbose = "silent"
) {
  env_dir <- env_dir_for_backend(backend, env_name)
  abort_unless_conda_prefix(
    env_dir,
    env_name = env_name,
    class = c(
      "condathis_list_packages_env_not_found",
      "condathis_list_packages_missing_env"
    )
  )
  return(as_package_records_tbl(read_env_package_records(
    env_dir = env_dir,
    env_name = env_name
  )))
}

#' @keywords internal
#' @noRd
#' @exportS3Method
backend_remove_env.default <- function(
  backend,
  env_name = "condathis-env",
  verbose = c("output", "silent", "cmd", "spinner", "full")
) {
  # The raw generic, as in `micromamba_backend_remove_env()`: a failed
  # existence check must abort, never read as "absent" before a delete.
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
  target <- check_exact_env_dir(
    backend,
    env_name = env_name,
    action = "delete",
    class = "condathis_unsafe_env_dir_delete"
  )
  skipped <- env_pre_unlink_scripts(target)
  # The environment leaves every listing at once, also when the delete
  # below stops half way.
  history <- fs::path(target, "conda-meta", "history")
  if (isTRUE(fs::file_exists(history))) {
    fs::file_delete(history)
  }
  delete_env_dir_via_trash(backend, target)
  return(list(status = 0L, link_scripts_skipped = skipped))
}

#' @keywords internal
#' @noRd
#' @exportS3Method
backend_available.default <- function(backend) {
  return(TRUE)
}

#' @keywords internal
#' @noRd
#' @exportS3Method
backend_clean_cache.default <- function(
  backend,
  verbose = c("output", "silent", "cmd", "spinner", "full")
) {
  return(NULL)
}

#' @keywords internal
#' @noRd
#' @exportS3Method
backend_quiesce.default <- function(backend, timeout = 30) {
  return(invisible(TRUE))
}

#' @keywords internal
#' @noRd
#' @exportS3Method
backend_native_platform.default <- function(backend) {
  return(NA_character_)
}

#' @keywords internal
#' @noRd
#' @exportS3Method
backend_can_solve.default <- function(
  backend,
  packages = NULL,
  env_file = NULL,
  channels = "conda-forge",
  channel_priority = c("strict", "flexible", "disabled"),
  additional_channels = NULL,
  platform
) {
  return(NA)
}

# --- Environments as conda prefixes ----------------------------------------

#' Does a backend root have any environment directory?
#'
#' The cheap probe of the listings: it reads one directory, starts no
#' process and creates nothing. `condathis_env_names()` and
#' `realize_env_paths()` only report existing directories whose real parent
#' is `<root>/envs`, so with no directory there the listing is empty. A
#' symbolic link alone does not count: its real path is outside
#' `<root>/envs`, or it is another directory there.
#'
#' @param name Character string, a backend name (`"micromamba"` for the
#'   condathis data directory itself).
#'
#' @returns `FALSE` when `<root>/envs` is missing or has no subdirectory
#'   other than `env_trash_dir()`. `TRUE` otherwise, also when the
#'   directory cannot be read, so that the real listing decides.
#'
#' @keywords internal
#' @noRd
backend_has_env_dirs <- function(name) {
  envs_dir <- fs::path(backend_root_path(name), "envs")
  if (isFALSE(fs::dir_exists(envs_dir))) {
    return(FALSE)
  }
  env_dirs <- tryCatch(
    fs::dir_ls(envs_dir, type = "directory", all = TRUE),
    error = function(e) NULL
  )
  if (is.null(env_dirs)) {
    return(TRUE)
  }
  # The trash of `create_env(overwrite = TRUE)` is not an environment.
  env_dirs <- env_dirs[base::basename(env_dirs) != env_trash_name()]
  return(isTRUE(length(env_dirs) > 0L))
}

#' Does a backend root have anything besides its environments?
#'
#' Such an entry is a cache that [clean_cache()] has to clean. An empty
#' directory is not one, and neither is a directory that holds only lock
#' files (names that end in `.lock`) or a lone lock file: a backend's clean
#' can leave its cache directories with their lock file behind, which
#' another R session may be holding. Only the entries of the root and one
#' level below them are read.
#'
#' @param name Character string, a backend name other than `"micromamba"`.
#'
#' @returns `TRUE` when the root exists and has such an entry other than
#'   `envs`, also when it cannot be read. No process starts.
#'
#' @keywords internal
#' @noRd
backend_has_cache_entries <- function(name) {
  root <- backend_root_path(name)
  if (isFALSE(fs::dir_exists(root))) {
    return(FALSE)
  }
  entries <- tryCatch(
    fs::dir_ls(root, all = TRUE),
    error = function(e) NULL
  )
  if (is.null(entries)) {
    return(TRUE)
  }
  entries <- entries[base::basename(entries) != "envs"]
  for (entry in entries) {
    if (isTRUE(is_cache_content(entry))) {
      return(TRUE)
    }
  }
  return(FALSE)
}

#' Does an entry of a backend root hold cached data?
#'
#' @param path Character string, an entry of a backend root.
#'
#' @returns `FALSE` for a lock file, an empty directory and a directory
#'   with only lock files in it; `TRUE` otherwise, also when the directory
#'   cannot be read.
#'
#' @keywords internal
#' @noRd
is_cache_content <- function(path) {
  if (isFALSE(isTRUE(unname(fs::is_dir(path))))) {
    return(isFALSE(endsWith(base::basename(path), ".lock")))
  }
  inner <- tryCatch(
    fs::dir_ls(path, all = TRUE),
    error = function(e) NULL
  )
  if (is.null(inner)) {
    return(TRUE)
  }
  is_lock <- endsWith(base::basename(inner), ".lock") &
    !unname(fs::is_dir(inner))
  return(isFALSE(all(is_lock)))
}

#' List the conda prefixes in `<root>/envs`
#'
#' What `micromamba env list` reports for `<root>/envs`: the directories
#' that contain `conda-meta/history` (checked with micromamba 2.9.0 and
#' 2.10.0). A directory without that file is not an environment, so the
#' stale-directory cleanup of `create_env()` and `remove_env()` treats it
#' as micromamba would. Symbolic links are not listed, and neither is
#' `env_trash_dir()`. The default `backend_list_envs()`, and the listing of
#' the micromamba backend when no micromamba binary is found.
#'
#' @param env_root_dir Character string, the real path of the root.
#'
#' @returns A character vector of environment names, without duplicates.
#'   `character(0)` when `<root>/envs` does not exist.
#'
#' @keywords internal
#' @noRd
list_conda_prefix_envs <- function(env_root_dir) {
  env_dirs <- tryCatch(
    as.character(fs::dir_ls(
      fs::path(env_root_dir, "envs"),
      type = "directory",
      all = TRUE
    )),
    error = function(e) character(0L)
  )
  env_dirs <- env_dirs[base::basename(env_dirs) != env_trash_name()]
  env_dirs <- env_dirs[
    fs::file_exists(fs::path(env_dirs, "conda-meta", "history"))
  ]
  envs_str <- realize_env_paths(env_dirs)
  return(unique(condathis_env_names(envs_str, env_root_dir)))
}

#' Keep the env paths that live under the condathis install root, return names
#'
#' A path is kept when its parent directory is exactly `<env_root_dir>/envs`,
#' compared as a literal string, never as a regex or a substring. A regex
#' would treat the `.` characters of the path as "any character" (matching
#' `~/Xlocal/share/R/condathis/...`). A substring match would claim any path
#' that contains the root, for example a backup copy at
#' `/backup/home/user/.local/share/R/condathis/envs/x`. The root itself and
#' nested directories are not direct children of `<root>/envs`, so they are
#' dropped without a filter on the name.
#'
#' @param envs_str Character vector of realized environment paths.
#' @param env_root_dir Character string with the condathis install root.
#'
#' @returns A character vector of environment names (basenames).
#'
#' @keywords internal
#' @noRd
condathis_env_names <- function(envs_str, env_root_dir) {
  # Keep exactly the environments whose parent is `<root>/envs`. Filtering
  # by basename (`!= "condathis"`, meant to drop the root prefix itself)
  # also dropped a real environment named "condathis", which then looked
  # absent and was deleted by the stale-directory cleanup of `create_env()`
  # and `remove_env()`. Backslashes are folded too: on Windows a path that
  # `fs::path_real()` could not realize falls back to the backslash form of
  # `normalizePath()`.
  envs_str <- to_slash_path(envs_str)
  envs_parent <- paste0(to_slash_path(env_root_dir), "/envs")
  in_envs_dir <- tolower_on_windows(dirname(envs_str)) ==
    tolower_on_windows(envs_parent)
  return(base::basename(envs_str[in_envs_dir]))
}

#' Fold backslashes to `/` and drop trailing separators
#'
#' @param x Character vector of paths.
#'
#' @returns Character vector.
#'
#' @keywords internal
#' @noRd
to_slash_path <- function(x) {
  return(sub("/+$", "", gsub("\\\\", "/", as.character(x))))
}

#' Lowercase paths on Windows, where they compare case-insensitively
#'
#' @keywords internal
#' @noRd
tolower_on_windows <- function(x) {
  if (isTRUE(is_windows())) {
    return(tolower(x))
  }
  return(x)
}

#' Resolve environment paths to their real form, tolerating missing ones
#'
#' `micromamba env list` reports every path in its registries, including
#' stale entries for directories that are missing. `native_cmd()` hides the
#' user's `~/.conda/environments.txt` from it, but another process can
#' still remove an environment between the listing subprocess and this
#' call.
#' A vectorized `fs::path_real()` errors with ENOENT on the first such path.
#' That aborts `list_envs()` for every environment, and makes every probe
#' of the micromamba backend fail (rule R5), so no call could tell whether
#' any micromamba environment exists. A stale entry must only affect
#' itself: drop paths that are missing.
#' When realization fails after the existence check, fall back to the
#' normalized path.
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

#' Abort when a directory is not a conda prefix
#'
#' A directory without `conda-meta/history` is not an environment, as for
#' `list_conda_prefix_envs()`. condathis checks that an environment exists
#' before it lists its packages or installs into it, so this is reached
#' only when that probe failed (rule R5), or when another process removed
#' the environment in between. The contract asks for the class
#' `condathis_env_not_found` (see ?register_backend).
#'
#' @param env_dir Character string, the environment directory.
#' @param env_name Character string, for the message.
#' @param class Character vector, the function-specific classes.
#' @param call Environment of the function the error is reported for.
#'
#' @returns `NULL`, invisibly, when the environment exists.
#'
#' @keywords internal
#' @noRd
abort_unless_conda_prefix <- function(
  env_dir,
  env_name,
  class,
  call = rlang::caller_env()
) {
  history <- fs::path(env_dir, "conda-meta", "history")
  if (isFALSE(fs::file_exists(history))) {
    abort_env_not_found(env_name, class = class, call = call)
  }
  return(invisible(NULL))
}

# --- Package records -------------------------------------------------------

#' Read the packages of a conda prefix as `micromamba list --json` lists them
#'
#' The default `backend_list_packages()`, and the listing of the micromamba
#' backend when no micromamba binary is found: the Conda package records
#' (`read_conda_package_records()`) and the PyPI packages that pip or uv
#' installed into the environment (`read_pypi_package_records()`), merged
#' as micromamba 2.10.0 merges them (`PrefixData::all_pkg_mgr_records()`
#' in `libmamba/src/core/prefix_data.cpp`): a PyPI package whose name is
#' the name of a Conda package is left out, and the rows are sorted by
#' name.
#'
#' @param env_dir Character string with the environment directory.
#' @param env_name Character string, for the error message.
#'
#' @returns A data frame sorted by `name`, or an empty list when the
#'   environment has no package. Aborts as `read_conda_package_records()`.
#'
#' @keywords internal
#' @noRd
read_env_package_records <- function(env_dir, env_name) {
  conda_df <- read_conda_package_records(env_dir = env_dir, env_name = env_name)
  pypi_df <- read_pypi_package_records(env_dir = env_dir, conda_df = conda_df)
  if (is.null(pypi_df)) {
    return(conda_df)
  }
  pypi_df <- pypi_df[!pypi_df$name %in% conda_df$name, , drop = FALSE]
  if (identical(nrow(pypi_df), 0L)) {
    return(conda_df)
  }
  pkgs_df <- rbind(conda_df, pypi_df[names(conda_df)])
  pkgs_df <- pkgs_df[order(pkgs_df$name, method = "radix"), , drop = FALSE]
  rownames(pkgs_df) <- NULL
  return(pkgs_df)
}

#' The PyPI packages of a conda prefix, as micromamba 2.10.0 lists them
#'
#' micromamba (`PrefixData::load_site_packages()` in
#' `libmamba/src/core/prefix_data.cpp`) asks the environment's own tools:
#'
#' * With a `pip` Conda package, it runs
#'   `python -q -m pip inspect --local` and keeps the distributions whose
#'   `INSTALLER` file names `pip` or `uv`. pip finds one distribution per
#'   normalized name (the first on `sys.path`), skips `python`, `wsgiref`
#'   and `argparse`, and reports the `Name` and `Version` of its metadata
#'   as written. The platform is `<sys.platform>-<platform.machine()>`,
#'   such as `linux-x86_64`, `darwin-arm64` or `win32-AMD64`. Without a
#'   `python` program in the environment, `micromamba list` fails.
#' * Without pip, with a `uv` Conda package, it runs
#'   `uv pip list --format json`, which reports the normalized names, and
#'   leaves out every distribution whose name is the name of a Conda
#'   package (both with `_` and `.` read as `-`, without case) or of a
#'   `.dist-info` or `.egg-info` entry of `site-packages` whose `INSTALLER`
#'   is not `pip` or `uv`. The platform is micromamba's own, such as
#'   `linux-64`.
#' * With neither, there are no PyPI packages.
#'
#' Each such package is a row with the channel `pypi`, the build string
#' `pypi_0`, the build number 0, the `base_url` `https://pypi.org/`, the
#' `dist_name` `<name>-<version>-pypi_0`, and empty `md5`, `sha256` and
#' `url`.
#'
#' This reads the same distributions from the files of the environment
#' instead, without running a program of it: the `.dist-info` and
#' `.egg-info` entries of the `site-packages` directory of its `python`
#' Conda package (see `python_site_packages_dir()`). Without a `python`
#' package there are no PyPI rows. pip also looks outside the
#' environment, in the user's site directory and in `PYTHONPATH`;
#' condathis runs `micromamba list` without them (see
#' `micromamba_cmd_overlay()`). For the platform of uv's rows, this takes
#' the platform of the `python` package, which is micromamba's own unless
#' the environment is for an emulated platform. The micromamba backend
#' gives its own listing that platform too (see
#' `micromamba_pypi_uv_platform()`). uv also normalizes
#' versions, which this reads as written: package builders write them
#' normalized.
#'
#' @param env_dir Character string with the environment directory.
#' @param conda_df The value of `read_conda_package_records()`.
#'
#' @returns A data frame with the columns of `read_conda_package_records()`,
#'   or `NULL` when there are no PyPI packages.
#'
#' @keywords internal
#' @noRd
read_pypi_package_records <- function(env_dir, conda_df) {
  if (isFALSE(is.data.frame(conda_df))) {
    return(NULL)
  }
  conda_names <- conda_df$name
  tool <- if (isTRUE("pip" %in% conda_names)) {
    "pip"
  } else if (isTRUE("uv" %in% conda_names)) {
    "uv"
  }
  python_row <- match("python", conda_names)
  if (is.null(tool) || isTRUE(is.na(python_row))) {
    return(NULL)
  }
  python <- conda_df[python_row, , drop = FALSE]
  dists <- read_site_package_dists(python_site_packages_dir(env_dir, python))
  if (identical(nrow(dists), 0L)) {
    return(NULL)
  }
  by_installer <- dists$installer %in% c("pip", "uv")
  if (identical(tool, "pip")) {
    canonical <- pypi_canonical_name(dists$name)
    keep <- by_installer &
      !duplicated(canonical) &
      !canonical %in% c("python", "wsgiref", "argparse")
    names <- dists$name[keep]
    platform <- pip_platform_tag(python)
  } else {
    non_pip_names <- c(
      libmamba_pypi_name(conda_names),
      libmamba_pypi_name(dists$entry_name[!by_installer])
    )
    canonical <- pypi_canonical_name(dists$name)
    keep <- !duplicated(canonical) &
      !libmamba_pypi_name(canonical) %in% non_pip_names
    names <- canonical[keep]
    platform <- python$platform
  }
  if (identical(sum(keep), 0L)) {
    return(NULL)
  }
  versions <- dists$version[keep]
  n <- length(names)
  return(base::data.frame(
    base_url = rep("https://pypi.org/", n),
    build_number = rep(0L, n),
    build_string = rep("pypi_0", n),
    channel = rep("pypi", n),
    dist_name = paste(names, versions, "pypi_0", sep = "-"),
    md5 = rep("", n),
    name = names,
    platform = rep(platform, n),
    sha256 = rep("", n),
    url = rep("", n),
    version = versions,
    stringsAsFactors = FALSE
  ))
}

#' The `site-packages` directory of an environment's Python
#'
#' The `python_site_packages_path` of the record of the `python` package,
#' when it has one (CEP 17), else the layout of CPython in a conda prefix,
#' as libmamba computes it (`effective_python_site_packages_path()`):
#' `Lib/site-packages` on Windows, `lib/python<X.Y>/site-packages`
#' elsewhere, and `lib/python<X.Y>t/site-packages` for a free-threading
#' build (its build string has `cp<XY>t`).
#'
#' @param env_dir Character string with the environment directory.
#' @param python A one-row data frame, the `python` row of
#'   `read_conda_package_records()`.
#'
#' @returns An `fs_path`.
#'
#' @keywords internal
#' @noRd
python_site_packages_dir <- function(env_dir, python) {
  record <- tryCatch(
    jsonlite::read_json(
      fs::path(env_dir, "conda-meta", paste0(python$dist_name, ".json"))
    ),
    error = function(e) NULL
  )
  rel_path <- record[["python_site_packages_path"]]
  if (isTRUE(rlang::is_string(rel_path)) && isTRUE(nzchar(rel_path))) {
    return(fs::path(env_dir, rel_path))
  }
  if (isTRUE(startsWith(as.character(python$platform), "win-"))) {
    return(fs::path(env_dir, "Lib", "site-packages"))
  }
  short_version <- sub("^([0-9]+[.][0-9]+).*$", "\\1", python$version)
  free_threading <- grepl(
    paste0("cp", gsub(".", "", short_version, fixed = TRUE), "t"),
    python$build_string,
    fixed = TRUE
  )
  return(fs::path(
    env_dir,
    "lib",
    paste0("python", short_version, if (isTRUE(free_threading)) "t"),
    "site-packages"
  ))
}

#' The distributions in a `site-packages` directory
#'
#' Its `*.dist-info` and `*.egg-info` entries (without case), directories
#' and files, as `importlib.metadata` finds them, sorted by entry name. The
#' metadata is `METADATA`, else `PKG-INFO`, of a directory, or the file
#' itself. An entry without a `Name` in its metadata is skipped, as pip
#' skips it.
#'
#' @param site_dir Character string, the directory.
#'
#' @returns A data frame with the character columns `entry_name` (the part
#'   of the entry name before its first `-`, without the extension),
#'   `name` and `version` (as written in the metadata; `NA` without a
#'   version) and `installer` (the first line of its `INSTALLER` file that
#'   is not empty, trimmed, or `""`), one row per entry.
#'
#' @keywords internal
#' @noRd
read_site_package_dists <- function(site_dir) {
  entries <- tryCatch(
    list.files(site_dir, all.files = TRUE, no.. = TRUE),
    error = function(e) character(0L)
  )
  entries <- sort(
    entries[grepl("[.](dist|egg)-info$", entries, ignore.case = TRUE)],
    method = "radix"
  )
  rows <- lapply(entries, function(entry) {
    path <- file.path(site_dir, entry)
    is_dir <- isTRUE(dir.exists(path))
    metadata_file <- path
    if (isTRUE(is_dir)) {
      metadata_file <- file.path(path, "METADATA")
      if (isFALSE(file.exists(metadata_file))) {
        metadata_file <- file.path(path, "PKG-INFO")
      }
    }
    headers <- read_metadata_headers(metadata_file, c("name", "version"))
    if (is.na(headers[["name"]])) {
      return(NULL)
    }
    installer <- ""
    if (isTRUE(is_dir)) {
      installer <- read_installer_name(file.path(path, "INSTALLER"))
    }
    return(c(
      entry_name = sub("-.*$", "", sub("[.][^.]*$", "", entry)),
      name = headers[["name"]],
      version = headers[["version"]],
      installer = installer
    ))
  })
  rows <- Filter(Negate(is.null), rows)
  if (identical(length(rows), 0L)) {
    return(base::data.frame(
      entry_name = character(0L),
      name = character(0L),
      version = character(0L),
      installer = character(0L),
      stringsAsFactors = FALSE
    ))
  }
  return(base::as.data.frame(
    do.call(rbind, rows),
    stringsAsFactors = FALSE
  ))
}

#' Header values of a core metadata file (`METADATA`, `PKG-INFO`)
#'
#' Read as Python's `email` parser reads them: the headers end at the first
#' empty line, names compare without case, the first header of a name
#' counts, and a value loses the spaces and tabs after the colon and the
#' line end.
#'
#' @param path Character string, the file.
#' @param fields Character vector of header names in lower case.
#'
#' @returns A named character vector, one element per field, `NA` for a
#'   missing header or file.
#'
#' @keywords internal
#' @noRd
read_metadata_headers <- function(path, fields) {
  values <- rlang::set_names(rep(NA_character_, length(fields)), fields)
  lines <- tryCatch(
    readLines(path, warn = FALSE, encoding = "UTF-8"),
    error = function(e) character(0L),
    warning = function(w) character(0L)
  )
  lines <- sub("\r$", "", lines)
  end <- match("", lines)
  if (isFALSE(is.na(end))) {
    lines <- lines[seq_len(end - 1L)]
  }
  header <- regmatches(lines, regexec("^([^:[:space:]][^:]*):(.*)$", lines))
  for (parts in header) {
    if (identical(length(parts), 3L)) {
      key <- tolower(parts[[2L]])
      if (isTRUE(key %in% fields) && isTRUE(is.na(values[[key]]))) {
        values[[key]] <- sub("^[ \t]+", "", parts[[3L]])
      }
    }
  }
  return(values)
}

#' The installer that an `INSTALLER` file names
#'
#' @param path Character string, the file.
#'
#' @returns The first line that is not empty, without surrounding white
#'   space, as pip reads it, or `""`.
#'
#' @keywords internal
#' @noRd
read_installer_name <- function(path) {
  lines <- tryCatch(
    trimws(readLines(path, warn = FALSE, encoding = "UTF-8")),
    error = function(e) character(0L),
    warning = function(w) character(0L)
  )
  lines <- lines[nzchar(lines)]
  if (identical(length(lines), 0L)) {
    return("")
  }
  return(lines[[1L]])
}

#' A PyPI project name normalized as PEP 503 does
#'
#' Lower case, with every run of `-`, `_` and `.` replaced by one `-`: the
#' names that pip compares and that uv reports.
#'
#' @param name Character vector.
#'
#' @returns Character vector.
#'
#' @keywords internal
#' @noRd
pypi_canonical_name <- function(name) {
  return(gsub("[-_.]+", "-", tolower(name)))
}

#' A PyPI project name normalized as libmamba compares it
#'
#' `normalize_pypi_name()` of `prefix_data.cpp`: lower case, with each `_`
#' and `.` replaced by `-` (runs are kept).
#'
#' @param name Character vector.
#'
#' @returns Character vector.
#'
#' @keywords internal
#' @noRd
libmamba_pypi_name <- function(name) {
  return(chartr("_.", "--", tolower(name)))
}

#' The platform that pip reports for an environment's Python
#'
#' `<sys.platform>-<platform.machine()>` of the environment's `python`, as
#' `pip inspect` reports it in `environment` and micromamba lists it, read
#' from the platform of the `python` package instead of from the program:
#'
#' * `sys.platform` is `linux`, `darwin` or `win32`.
#' * `platform.machine()` is the machine of the kernel on Linux
#'   (`Sys.info()[["machine"]]`), the architecture of the program on macOS
#'   (`x86_64` for `osx-64`, also under Rosetta 2, `arm64` for
#'   `osx-arm64`), and on Windows the architecture of the processor:
#'   `AMD64` or `ARM64`. CPython 3.11 and earlier report `AMD64` for an x64
#'   Python on an ARM64 processor, which they read from the environment of
#'   the emulated process.
#'
#' @param python A one-row data frame, the `python` row of
#'   `read_conda_package_records()`.
#'
#' @returns A character string.
#'
#' @keywords internal
#' @noRd
pip_platform_tag <- function(python) {
  subdir <- as.character(python$platform)
  os <- sub("-.*$", "", subdir)
  if (identical(os, "osx")) {
    machine <- if (identical(subdir, "osx-arm64")) "arm64" else "x86_64"
    return(paste0("darwin-", machine))
  }
  if (identical(os, "win")) {
    machine <- windows_native_machine()
    if (identical(subdir, "win-arm64")) {
      machine <- "ARM64"
    } else if (identical(subdir, "win-64")) {
      python_version <- numeric_version(
        sub("^([0-9]+[.][0-9]+).*$", "\\1", python$version),
        strict = FALSE
      )
      if (isTRUE(python_version < "3.12")) {
        machine <- "AMD64"
      }
    }
    return(paste0("win32-", machine))
  }
  return(paste0(os, "-", base::Sys.info()[["machine"]]))
}

#' The architecture of the processor of a Windows machine
#'
#' The machine-wide `PROCESSOR_ARCHITECTURE` of the registry, which an
#' emulated process does not change, as CPython 3.12 reads it through WMI.
#' Without it, the variables of this process.
#'
#' @returns A character string, such as `"AMD64"` or `"ARM64"`.
#'
#' @keywords internal
#' @noRd
windows_native_machine <- function() {
  # `utils::readRegistry()` exists only in R for Windows.
  read_registry <- get0(
    "readRegistry",
    envir = asNamespace("utils"),
    mode = "function"
  )
  native <- NULL
  if (isTRUE(is.function(read_registry))) {
    native <- tryCatch(
      read_registry(
        "SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment",
        hive = "HLM",
        view = "64-bit"
      )[["PROCESSOR_ARCHITECTURE"]],
      error = function(e) NULL
    )
  }
  if (isTRUE(rlang::is_string(native)) && isTRUE(nzchar(native))) {
    return(native)
  }
  for (var in c("PROCESSOR_ARCHITEW6432", "PROCESSOR_ARCHITECTURE")) {
    value <- Sys.getenv(var, unset = "")
    if (isTRUE(nzchar(value))) {
      return(value)
    }
  }
  return("AMD64")
}

#' Read the package records of a conda prefix
#'
#' The default `backend_list_packages()`, and the listing of the micromamba
#' backend when no micromamba binary is found. `micromamba list` reads the
#' same records: one JSON file per installed package in `<env_dir>/conda-meta`.
#' The columns are those of `micromamba list --json` (checked with micromamba
#' 2.9.0 and 2.10.0): `build_string` is the record's `build`, `platform`
#' its `subdir`, `base_url` is from `conda_record_base_url()`, and
#' `dist_name` is `<name>-<version>-<build>`. `channel` is from
#' `conda_record_channel()`, as in `micromamba_use_record_channels()`.
#' Records without a `name` and a `version` are skipped.
#'
#' @param env_dir Character string with the environment directory.
#' @param env_name Character string, for the error message.
#'
#' @returns A data frame sorted by `name`, or an empty list when the
#'   environment has no package. A directory without
#'   `conda-meta/history`, which micromamba does not list as an
#'   environment, aborts with `c("condathis_env_not_found",
#'   "condathis_error")`.
#'
#' @keywords internal
#' @noRd
read_conda_package_records <- function(env_dir, env_name) {
  meta_dir <- fs::path(env_dir, "conda-meta")
  if (isFALSE(fs::file_exists(fs::path(meta_dir, "history")))) {
    abort_env_not_found(
      env_name,
      class = character(0L),
      call = rlang::caller_env()
    )
  }
  record_files <- fs::dir_ls(meta_dir, glob = "*.json", type = "file")
  records <- lapply(record_files, function(record_file) {
    record <- tryCatch(
      jsonlite::read_json(record_file),
      error = function(e) NULL
    )
    if (
      isFALSE(is.list(record)) ||
        isFALSE(rlang::is_string(record[["name"]])) ||
        isFALSE(rlang::is_string(record[["version"]]))
    ) {
      return(NULL)
    }
    return(record)
  })
  records <- Filter(Negate(is.null), records)
  if (identical(length(records), 0L)) {
    return(list())
  }
  field <- function(name) {
    return(vapply(
      records,
      function(record) {
        value <- record[[name]]
        if (isTRUE(rlang::is_scalar_atomic(value))) {
          return(as.character(value))
        }
        return(NA_character_)
      },
      character(1L),
      USE.NAMES = FALSE
    ))
  }
  platform <- field("subdir")
  base_url <- conda_record_base_url(field("url"), platform)
  pkgs_df <- base::data.frame(
    base_url = base_url,
    build_number = suppressWarnings(as.integer(field("build_number"))),
    build_string = field("build"),
    channel = conda_record_channel(field("channel"), platform, base_url),
    dist_name = paste(
      field("name"),
      field("version"),
      field("build"),
      sep = "-"
    ),
    md5 = field("md5"),
    name = field("name"),
    platform = platform,
    sha256 = field("sha256"),
    url = field("url"),
    version = field("version"),
    stringsAsFactors = FALSE
  )
  pkgs_df <- pkgs_df[order(pkgs_df$name, method = "radix"), , drop = FALSE]
  rownames(pkgs_df) <- NULL
  return(pkgs_df)
}

#' The `base_url` of a package, as `micromamba list --json` reports it
#'
#' The package URL without the file name, and then without the platform
#' subdirectory when it ends in one. A package that micromamba 2.10.0 or
#' later downloads from a URL outside its channel does not always sit in a
#' platform subdirectory: dropping the last two parts of the URL in every
#' case gave a `base_url` that `micromamba list --json` does not report.
#' A login in the URL (`user:*****@`, as micromamba writes it into the
#' record) is not part of the `base_url` that micromamba reports; a token
#' (`/t/*****/`) is.
#'
#' @param url Character vector of package URLs.
#' @param platform Character vector of platform subdirectories, such as
#'   `"linux-64"` or `"noarch"`.
#'
#' @returns Character vector, `NA` where `url` is `NA`.
#'
#' @keywords internal
#' @noRd
conda_record_base_url <- function(url, platform) {
  base_url <- strip_platform_dir(sub("/[^/]*$", "", url), platform)
  return(sub("^([A-Za-z][A-Za-z0-9+.-]*://)[^/@]*@", "\\1", base_url))
}

#' The channel of a package record, as micromamba lists it
#'
#' The record's `channel`, without trailing slashes and without the
#' platform subdirectory: micromamba 1.x recorded the channel with it
#' (`https://conda.anaconda.org/conda-forge/linux-64`). An empty or missing
#' channel is replaced by `base_url`, from which `micromamba list --json`
#' derives the channel: micromamba 2.10.0 records an empty channel for the
#' packages of a conda-lock file whose channel is a URL such as
#' `https://repo.prefix.dev/conda-forge`. A channel on
#' `https://conda.anaconda.org`, the default channel alias, which condathis
#' never changes, becomes its name, as micromamba lists it. So do the
#' channels that micromamba names itself (its conda-compatible custom
#' channels, `conda_custom_channels()` in libmamba's `channel_context.cpp`):
#' `https://repo.anaconda.com/pkgs/main`, `pkgs/r` and `pkgs/pro`, and on
#' Windows `pkgs/msys2`, the members of `defaults`.
#'
#' @param channel Character vector of the records' `channel` fields.
#' @param platform Character vector of platform subdirectories.
#' @param base_url Character vector from `conda_record_base_url()`.
#'
#' @returns Character vector.
#'
#' @keywords internal
#' @noRd
conda_record_channel <- function(channel, platform, base_url) {
  channel <- strip_platform_dir(sub("/+$", "", channel), platform)
  missing_channel <- is.na(channel) | !nzchar(channel)
  channel[missing_channel] <- base_url[missing_channel]
  channel <- sub(
    "^https://conda\\.anaconda\\.org/(.+)$",
    "\\1",
    channel,
    ignore.case = TRUE
  )
  named_channels <- c("main", "r", "pro", if (isTRUE(is_windows())) "msys2")
  channel <- sub(
    paste0(
      "^https://repo\\.anaconda\\.com/(pkgs/(",
      paste(named_channels, collapse = "|"),
      "))$"
    ),
    "\\1",
    channel,
    ignore.case = TRUE
  )
  return(channel)
}

#' Drop a trailing platform subdirectory from paths or URLs
#'
#' @param x Character vector.
#' @param platform Character vector of platform subdirectories, recycled
#'   to the length of `x`.
#'
#' @returns `x`, without `/<platform>` at the end where it has it.
#'
#' @keywords internal
#' @noRd
strip_platform_dir <- function(x, platform) {
  suffix <- rep_len(paste0("/", platform), length(x))
  has_platform <- !is.na(x) &
    rep_len(!is.na(platform) & nzchar(platform), length(x)) &
    endsWith(x, suffix)
  x[has_platform] <- substr(
    x[has_platform],
    1L,
    nchar(x[has_platform]) - nchar(suffix[has_platform])
  )
  return(x)
}

#' A package listing as the tibble of `backend_list_packages()`
#'
#' @param pkgs_df A data frame of package records, or an empty list for an
#'   environment without packages.
#'
#' @returns A tibble-classed data frame. For an empty environment, zero
#'   rows with the columns `base_url`, `build_number`, `build_string`,
#'   `channel`, `dist_name`, `name`, `platform` and `version`.
#'
#' @keywords internal
#' @noRd
as_package_records_tbl <- function(pkgs_df) {
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

# --- Removal ----------------------------------------------------------------

#' The packages of an environment that have a pre-unlink script
#'
#' The default `backend_remove_env()` deletes the environment without
#' running these scripts, which micromamba runs before it removes a
#' package. A script is `bin/.<name>-pre-unlink.sh` (`Scripts/` and `.bat`
#' on Windows). The packages are the records whose `files` list a script;
#' a script that no record lists is reported under the name in its file
#' name. Only when a script exists are the records read.
#'
#' @param env_dir Character string, the environment directory.
#'
#' @returns A data frame with the columns `package` and `script` (always
#'   `"pre-unlink"`), one row per package, sorted. Zero rows when there is
#'   no script.
#'
#' @keywords internal
#' @noRd
env_pre_unlink_scripts <- function(env_dir) {
  script_pattern <- "^[.](.+)-pre-unlink[.](sh|bat)$"
  scripts <- unlist(lapply(c("bin", "Scripts"), function(dir_name) {
    found <- tryCatch(
      as.character(fs::dir_ls(
        fs::path(env_dir, dir_name),
        all = TRUE,
        type = c("file", "symlink")
      )),
      error = function(e) character(0L)
    )
    return(found[grepl(script_pattern, base::basename(found))])
  }))
  if (identical(length(scripts), 0L)) {
    return(empty_link_scripts())
  }
  script_files <- paste0(
    ifelse(base::basename(dirname(scripts)) == "bin", "bin/", "Scripts/"),
    base::basename(scripts)
  )
  record_files <- tryCatch(
    fs::dir_ls(fs::path(env_dir, "conda-meta"), glob = "*.json", type = "file"),
    error = function(e) character(0L)
  )
  packages <- character(0L)
  claimed <- character(0L)
  for (record_file in record_files) {
    record <- tryCatch(
      jsonlite::read_json(record_file),
      error = function(e) NULL
    )
    if (
      isFALSE(is.list(record)) || isFALSE(rlang::is_string(record[["name"]]))
    ) {
      next
    }
    files <- to_slash_path(unlist(record[["files"]], use.names = FALSE))
    hits <- intersect(script_files, files)
    if (isTRUE(length(hits) > 0L)) {
      packages <- c(packages, record[["name"]])
      claimed <- c(claimed, hits)
    }
  }
  unclaimed <- setdiff(script_files, claimed)
  packages <- c(
    packages,
    sub(script_pattern, "\\1", base::basename(unclaimed))
  )
  packages <- sort(unique(packages), method = "radix")
  return(base::data.frame(
    package = packages,
    script = rep("pre-unlink", length(packages)),
    stringsAsFactors = FALSE
  ))
}

#' An empty `link_scripts_skipped` data frame
#'
#' @keywords internal
#' @noRd
empty_link_scripts <- function() {
  return(base::data.frame(
    package = character(0L),
    script = character(0L),
    stringsAsFactors = FALSE
  ))
}

#' Delete an environment directory through the trash
#'
#' The directory is renamed into `env_trash_dir()`, then gets a `.discard`
#' marker, and is deleted there by `purge_env_trash_dir()`: one rename, so the
#' environment path is free at once, and a delete that is interrupted or
#' fails leaves the copy for a later purge. On NTFS, a directory with an
#' open file below it usually cannot be renamed; then
#' `delete_env_dir_by_files()` deletes it in place.
#'
#' @param backend A backend object.
#' @param target Character string, the checked environment directory (see
#'   `check_exact_env_dir()`).
#'
#' @returns `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
delete_env_dir_via_trash <- function(backend, target) {
  trash_dir <- env_trash_dir(backend)
  purge_env_trash_dir(trash_dir)
  trash_path <- new_trash_path(backend)
  # The marker comes after the rename: a `purge_env_trash_dir()` of another
  # R session (for another environment of this backend) that ran between a
  # marker and its rename deleted the marker as one whose copy is gone, and
  # the copy then stayed in the trash for good. A copy without a marker
  # is kept, so only a crash between the two steps leaves one.
  reason <- suspendInterrupts({
    renamed <- rename_path(target, trash_path)
    if (is.null(renamed)) {
      try(fs::file_create(paste0(trash_path, ".discard")), silent = TRUE)
    }
    renamed
  })
  if (is.null(reason)) {
    purge_env_trash_dir(trash_dir)
    return(invisible(NULL))
  }
  delete_env_dir_by_files(target, trash_dir = trash_dir)
  return(invisible(NULL))
}

#' Delete an environment directory file by file
#'
#' The fallback of `delete_env_dir_via_trash()`, as micromamba removes an
#' environment: every file that cannot be deleted, such as a program that
#' runs on Windows, is renamed to `<trash_dir>/<random>.discard` (Windows
#' allows renaming a file in use, not deleting it), and a later
#' `purge_env_trash_dir()` deletes it. Then the directories are deleted.
#'
#' @param target Character string, the environment directory.
#' @param trash_dir Character string, `env_trash_dir()` of the backend.
#'
#' @returns `NULL`, invisibly. An error from deleting the directories is
#'   not caught.
#'
#' @keywords internal
#' @noRd
delete_env_dir_by_files <- function(target, trash_dir) {
  entries <- as.character(fs::dir_ls(target, recurse = TRUE, all = TRUE))
  dirs <- as.character(fs::dir_ls(
    target,
    recurse = TRUE,
    all = TRUE,
    type = "directory"
  ))
  for (path in setdiff(entries, dirs)) {
    if (isTRUE(delete_env_file(path))) {
      next
    }
    busy_path <- paste0(
      fs::path(trash_dir, base::basename(base::tempfile(pattern = ""))),
      ".discard"
    )
    rename_path(path, busy_path)
  }
  fs::dir_delete(target)
  return(invisible(NULL))
}

#' Delete one file or link
#'
#' A wrapper, so tests can make a file look in use. A symbolic link is
#' deleted, never followed: `fs::file_delete()` deletes a link to a
#' directory with `fs::dir_delete()`, which deleted every file in the
#' directory it points to, outside the environment, before it failed on
#' the link.
#'
#' @param path Character string.
#'
#' @returns `TRUE` when the file is gone, `FALSE` when it could not be
#'   deleted.
#'
#' @keywords internal
#' @noRd
delete_env_file <- function(path) {
  return(tryCatch(
    {
      if (isTRUE(fs::is_link(path))) {
        fs::link_delete(path)
      } else {
        fs::file_delete(path)
      }
      TRUE
    },
    error = function(e) FALSE
  ))
}
