#' Build clean Conda and Mamba environment variables
#'
#' Returns a named list of Conda and Mamba environment variables configured for
#' isolation from external Conda installations.
#'
#' Key isolation decisions:
#' - `R_HOME = ""` prevents conda-installed R from conflicting with the
#'   host R session.
#' - `CONDA_SHLVL`/`MAMBA_SHLVL` reset to `"0"` to prevent shell-level
#'   confusion.
#' - All prefix/path/rc variables cleared to avoid interference from
#'   the user's conda configuration.
#' - `CONDA_ENVS_PATH`, `CONDA_PKGS_DIRS` and `MAMBA_PKGS_DIRS` come from
#'   `conda_dirs`, the directories of the backend that owns the environment
#'   the child runs in (see `child_conda_dirs()`). With an empty
#'   `CONDA_PKGS_DIRS`, micromamba falls back to a list that also includes
#'   the user's global `~/.mamba/pkgs`, so `clean_cache()` deleted that
#'   shared cache and every install read from and wrote to it. A missing
#'   directory is set to `""`, like the other cleared variables. The
#'   user's own values never reach the child.
#'
#' This function does no file system access. The caller resolves the
#' directories first, so a child of another backend never creates or reads
#' the micromamba data directory.
#'
#' @param tmp_dir Character string path used for `TMPDIR`.
#' @param conda_dirs A list from `child_conda_dirs()` or
#'   `micromamba_conda_dirs()`, with `envs_dir` (for `CONDA_ENVS_PATH`) and
#'   `pkgs_dir` (for `CONDA_PKGS_DIRS` and `MAMBA_PKGS_DIRS`). A `NULL`
#'   element, or `conda_dirs = NULL` (the default), sets the variables to
#'   `""`.
#'
#' @returns A named list of overrides for `build_child_env()`. A `NULL`
#'   entry (`CONDA_ENVS_DIRS`) removes the variable from the child's
#'   environment block. Every other entry is set as-is. Never applied to the
#'   calling session itself.
#'
#' @keywords internal
#' @noRd
get_clean_conda_envvars <- function(tmp_dir, conda_dirs = NULL) {
  envs_dir <- as.character(conda_dirs$envs_dir %||% "")
  pkgs_dir <- as.character(conda_dirs$pkgs_dir %||% "")
  envvar_list <- list(
    `TMPDIR` = tmp_dir,
    `CONDA_SHLVL` = "0",
    `MAMBA_SHLVL` = "0",
    `CONDA_ENVS_PATH` = envs_dir,
    `CONDA_ENVS_DIRS` = NULL,
    `CONDA_ROOT_PREFIX` = "",
    `CONDA_PREFIX` = "",
    `MAMBA_ENVS_PATH` = "",
    `MAMBA_ENVS_DIRS` = "",
    `MAMBA_ROOT_PREFIX` = "",
    `MAMBA_PREFIX` = "",
    `CONDARC` = "",
    `MAMBARC` = "",
    `CONDA_PROMPT_MODIFIER` = "",
    `MAMBA_PROMPT_MODIFIER` = "",
    `CONDA_DEFAULT_ENV` = "",
    `MAMBA_DEFAULT_ENV` = "",
    `CONDA_PKGS_DIRS` = pkgs_dir,
    `MAMBA_PKGS_DIRS` = pkgs_dir,
    `R_HOME` = ""
  )
  return(envvar_list)
}

#' Conda directories of the micromamba root
#'
#' @param root_dir Character string with the already-resolved root of the
#'   micromamba backend.
#'
#' @returns A list with `envs_dir` (`<root>/envs`) and `pkgs_dir`
#'   (`<root>/pkgs`), for the `conda_dirs` argument of `build_child_env()`.
#'   Does no file system access.
#'
#' @keywords internal
#' @noRd
micromamba_conda_dirs <- function(root_dir) {
  return(list(
    envs_dir = as.character(fs::path(root_dir, "envs")),
    pkgs_dir = as.character(fs::path(root_dir, "pkgs"))
  ))
}

#' Conda directories for a child process of a backend's environment
#'
#' The child's `CONDA_ENVS_PATH`, `CONDA_PKGS_DIRS` and `MAMBA_PKGS_DIRS`
#' come from the backend that owns the environment it runs in. Each backend
#' has its own `envs/` and package caches (see `register_backend()`), so
#' the micromamba `envs/` and `pkgs/` never reach a child of another
#' backend.
#'
#' * The micromamba backend: the `envs/` and `pkgs/` directories of its
#'   root. This includes every environment given by `env_path()` that the
#'   micromamba backend runs: the parent of such an environment is not a
#'   directory `condathis` manages.
#' * Any other backend: `CONDA_ENVS_PATH` is the parent directory of
#'   `env_dir`, so a Conda tool run in the environment creates named
#'   environments next to it, under the same backend's root. When `env_dir`
#'   is `<root>/envs/<env_name>` of the backend's root (see
#'   `backend_conda_pkgs_dir()`), `pkgs_dir` is `<root>/conda-pkgs`, a
#'   directory that `condathis` owns in every backend root and that
#'   [clean_cache()] empties: a Conda tool run in the environment then
#'   keeps its package cache in that root, never in `~/.conda/pkgs` and
#'   never in the cache of another backend. Otherwise `pkgs_dir` is `NULL`
#'   and both package-cache variables are `""`. [run()], [run_bin()] and
#'   [run_pipeline()] use these values with and without activation. With
#'   activation, the backend can set any of the three in the `env` element
#'   of its `backend_resolve_run()` result (see `?register_backend`).
#' * An environment given by `env_path()` (`env_path = TRUE`) that a
#'   backend other than micromamba runs: the directories of that backend's
#'   own environments, those of its default environment `"condathis-env"`,
#'   as for micromamba. The parent of such an environment is not a
#'   directory `condathis` manages, and a `conda-pkgs` next to its `envs`
#'   directory would be a cache in another installation's root (such as
#'   micromamba's own root).
#'
#' `CONDA_ENVS_PATH` is also how `with_sandbox_dir()` recognizes a child of
#' an environment inside the sandbox when nothing else about the process
#' names the sandbox (see `process_uses_sandbox()`).
#'
#' @param backend An already-resolved backend object.
#' @param env_dir Character string with the directory of the environment
#'   the child runs in. It is evaluated only for a backend other than
#'   micromamba, so a caller can pass a `backend_get_env_dir()` call that
#'   runs only when needed.
#' @param env_path Logical scalar. `TRUE` when `env_dir` is an environment
#'   given by `env_path()`. Defaults to `FALSE`.
#'
#' @returns A list with `envs_dir` and `pkgs_dir` (character strings or
#'   `NULL`), for the `conda_dirs` argument of `build_child_env()`. Only for
#'   the micromamba backend, and for a backend with its own
#'   `backend_get_env_dir()`, does this resolve a root directory. For a
#'   backend with the default `backend_get_env_dir()`, both come from
#'   `env_dir` alone, without file system access.
#'
#' @keywords internal
#' @noRd
child_conda_dirs <- function(backend, env_dir, env_path = FALSE) {
  if (isTRUE(inherits(backend, "condathis_backend_micromamba"))) {
    return(micromamba_conda_dirs(install_dir_for_backend(backend)))
  }
  if (isTRUE(env_path)) {
    # A backend whose `backend_get_env_dir()` fails gets no directories
    # (`""`), as for an environment outside its root.
    env_dir <- tryCatch(
      as.character(env_dir_for_backend(backend, env_name = "condathis-env")),
      error = function(e) NULL
    )
  }
  envs_dir <- NULL
  pkgs_dir <- NULL
  if (isFALSE(is.null(env_dir))) {
    envs_dir <- as.character(fs::path_dir(env_dir))
    pkgs_dir <- backend_conda_pkgs_dir(backend, env_dir)
  }
  return(list(envs_dir = envs_dir, pkgs_dir = pkgs_dir))
}

#' The package cache of Conda tools run in a backend's environments
#'
#' `<root>/conda-pkgs` for an environment directory `<root>/envs/<name>`
#' in the root of a backend other than micromamba (see
#' `child_conda_dirs()`). The name `envs` is compared without case on
#' Windows, whose file systems ignore it.
#'
#' The root is the one of the backend: for the default
#' `backend_get_env_dir()`, `<backend_root_dir(name)>/envs/<name>` by
#' construction, so nothing is read. A backend with its own
#' `backend_get_env_dir()` can put its environments anywhere: then the
#' `envs` directory must be in its root, `backend_get_install_dir()` for a
#' backend that has its own, else `backend_root_dir(name)`. Otherwise
#' [clean_cache()] would delete a `conda-pkgs` directory next to an `envs`
#' directory of anybody (another tool's cache).
#'
#' @param backend An already-resolved backend object, not micromamba.
#' @param env_dir Character string, the environment directory.
#'
#' @returns Character string, or `NULL`.
#'
#' @keywords internal
#' @noRd
backend_conda_pkgs_dir <- function(backend, env_dir) {
  envs_dir <- fs::path_dir(env_dir)
  envs_name <- as.character(fs::path_file(envs_dir))
  if (isFALSE(identical(tolower_on_windows(envs_name), "envs"))) {
    return(NULL)
  }
  root <- fs::path_dir(envs_dir)
  pkgs_dir <- as.character(fs::path(root, "conda-pkgs"))
  if (is.null(backend[["backend_get_env_dir"]])) {
    return(pkgs_dir)
  }
  backend_root <- tryCatch(
    if (is.null(backend[["backend_get_install_dir"]])) {
      backend_root_dir(backend_display_name(backend))
    } else {
      install_dir_for_backend(backend)
    },
    error = function(e) NULL
  )
  if (is.null(backend_root)) {
    return(NULL)
  }
  same_root <- identical(
    tolower_on_windows(as.character(realize_existing_part(root))),
    tolower_on_windows(as.character(realize_existing_part(backend_root)))
  )
  if (isFALSE(same_root)) {
    return(NULL)
  }
  return(pkgs_dir)
}
