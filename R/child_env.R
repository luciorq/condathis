#' Build the complete environment for a condathis child process
#'
#' The single place a child process's environment block is assembled.
#' Layers, in order:
#'
#' 1. A snapshot of the calling session's environment (`Sys.getenv()`) -
#'    read, never written.
#' 2. The clean-conda overlay from `get_clean_conda_envvars()`, where a
#'    `NULL` entry is a true *removal* from the child's block (something
#'    `processx`'s `env = c("current", ...)` idiom cannot express).
#' 3. `overlay`: activation variables, replacing any same-named inherited
#'    value.
#' 4. `path_prepend`: directories prepended to whatever `PATH` the child
#'    would otherwise get (from `overlay` if it set one, else inherited),
#'    composed at call time so it always reflects the *live* session
#'    `PATH`.
#'
#' The result is passed as a full `env =` replacement to `processx`,
#' deliberately not `c("current", ...)`. Mutating the calling session's
#' environment (`withr::local_envvar()`) would let parent-side code that runs
#' during child execution (spinner callbacks, condition handlers, interrupt
#' paths) observe corrupted session state. The main hazard is `R_HOME = ""`
#' breaking `R.home()` (see `condathis-package.R`). Building the child block
#' explicitly confines every override to the child.
#'
#' On Windows, environment variable names are case-insensitive: overrides
#' and removals match existing names case-insensitively (replacing e.g. an
#' inherited `Path` with the override's `PATH`) so the child's block never
#' ends up with case-variant duplicates.
#'
#' @param tmp_dir Character string used for the child's `TMPDIR`.
#' @param conda_dirs A list with `envs_dir` and `pkgs_dir`, from
#'   `child_conda_dirs()` for a child of an environment, or from
#'   `micromamba_conda_dirs()` for micromamba itself. Passed through to
#'   `get_clean_conda_envvars()`. `NULL` (the default) sets the
#'   package-cache and envs-path variables to `""`. This function does no
#'   file system access.
#' @param overlay Named character vector of activation variables, or
#'   `NULL`.
#' @param path_prepend Character vector of directories to prepend to the
#'   child's `PATH`, or `NULL`.
#'
#' @returns A named character vector: the child's complete environment
#'   block.
#'
#' @keywords internal
#' @noRd
build_child_env <- function(
  tmp_dir,
  conda_dirs = NULL,
  overlay = NULL,
  path_prepend = NULL
) {
  env <- as.list(Sys.getenv())
  env <- apply_env_overrides(
    env,
    get_clean_conda_envvars(tmp_dir = tmp_dir, conda_dirs = conda_dirs)
  )
  if (isTRUE(length(overlay) > 0L)) {
    env <- apply_env_overrides(env, as.list(overlay))
  }
  if (isTRUE(length(path_prepend) > 0L)) {
    path_name <- match_env_name(names(env), "PATH")
    current_path <- if (is.na(path_name)) "" else env[[path_name]]
    env[[path_name %|na|% "PATH"]] <- compose_path(path_prepend, current_path)
  }
  return(unlist(env))
}

#' Apply a list of environment overrides onto an environment snapshot
#'
#' `NULL`-valued and `NA` entries remove the variable; everything else sets
#' it. An `NA` is how an activation overlay says that the activation unsets
#' a variable (see `resolve_micromamba_activation_envvars()` and
#' `backend_resolve_run()` in [register_backend()]).
#' Matching is case-insensitive on Windows (see `build_child_env()`):
#' an override replaces any case-variant of its name already present,
#' under the override's own spelling.
#'
#' @param env Named list, the environment block being built.
#' @param overrides Named list. Values are coerced with `as.character()`.
#'   `NULL` and `NA` remove.
#'
#' @keywords internal
#' @noRd
apply_env_overrides <- function(env, overrides) {
  for (nm in names(overrides)) {
    existing <- match_env_name(names(env), nm)
    if (!is.na(existing) && !identical(existing, nm)) {
      env[[existing]] <- NULL
    }
    value <- overrides[[nm]]
    if (is.null(value) || isTRUE(is.na(value))) {
      env[[nm]] <- NULL
    } else {
      env[[nm]] <- as.character(overrides[[nm]])
    }
  }
  return(env)
}

#' Find the existing spelling of an environment variable name
#'
#' Matches exactly everywhere. On Windows, matching is also case-insensitive
#' because the OS treats environment variable names case-insensitively.
#'
#' @returns The matching existing name, or `NA_character_`.
#'
#' @keywords internal
#' @noRd
match_env_name <- function(existing_names, name) {
  if (isTRUE(name %in% existing_names)) {
    return(name)
  }
  if (isTRUE(is_windows())) {
    hit <- existing_names[toupper(existing_names) == toupper(name)]
    if (isTRUE(length(hit) > 0L)) {
      return(hit[[1L]])
    }
  }
  return(NA_character_)
}

#' Prepend directories to a `PATH` string, deduplicated, order-preserving
#'
#' @param prepend Character vector of directories.
#' @param base_path Character string, the existing `PATH` value (may be
#'   empty).
#' @param append Character vector of directories to append. Defaults to
#'   none.
#'
#' @keywords internal
#' @noRd
compose_path <- function(prepend, base_path, append = character(0L)) {
  sep <- .Platform$path.sep
  parts <- c(
    as.character(prepend),
    strsplit(base_path %||% "", sep, fixed = TRUE)[[1L]],
    as.character(append)
  )
  parts <- parts[nzchar(parts)]
  return(paste(unique(parts), collapse = sep))
}

#' `%|na|%`: fall back when the left-hand side is `NA`
#'
#' @keywords internal
#' @noRd
`%|na|%` <- function(x, y) {
  if (isTRUE(is.na(x))) y else x
}
