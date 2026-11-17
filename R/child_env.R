#' Build the complete environment for a condathis child process
#'
#' The single place a child process's environment block is assembled.
#' Layers, in order:
#'
#' 1. A snapshot of the calling session's environment (`Sys.getenv()`) -
#'    read, never written.
#' 2. The activation of the R session undone (`isolate_host_env()`): when
#'    R runs in an activated Conda or pixi environment, or in several
#'    nested ones, their binary directories leave `PATH` and their marker
#'    variables leave the block.
#' 3. The clean-conda overlay from `get_clean_conda_envvars()`, where a
#'    `NULL` entry is a true *removal* from the child's block (something
#'    `processx`'s `env = c("current", ...)` idiom cannot express).
#' 4. `overlay`: activation variables, replacing any same-named inherited
#'    value.
#' 5. `path_prepend`: directories prepended to whatever `PATH` the child
#'    would otherwise get (from `overlay` if it set one, else the `PATH`
#'    after the layers above), composed at call time from the *live*
#'    session.
#'
#' Layers 1 to 3 are the isolation of every child, with and without
#' activation. A backend computes its activation against them (the
#' `base_env` of `backend_resolve_run()`), and `micromamba` itself gets
#' them too (see `native_cmd()`).
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
  env <- isolate_host_env(env)
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
    env[[path_name %|na|% "PATH"]] <- prepend_path_dirs(
      path_prepend,
      current_path
    )
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
#' @param existing_names Character vector of names.
#' @param name Character string, the name to find.
#' @param on_windows Logical. Whether to apply the Windows rule.
#'
#' @returns The matching existing name, or `NA_character_`.
#'
#' @keywords internal
#' @noRd
match_env_name <- function(existing_names, name, on_windows = is_windows()) {
  if (isTRUE(name %in% existing_names)) {
    return(name)
  }
  if (isTRUE(on_windows)) {
    hit <- existing_names[toupper(existing_names) == toupper(name)]
    if (isTRUE(length(hit) > 0L)) {
      return(hit[[1L]])
    }
  }
  return(NA_character_)
}

#' The `PATH` of an environment block
#'
#' @param env Named character vector or named list, an environment block
#'   such as the result of `build_child_env()`.
#' @param on_windows Logical. On Windows, the name compares without case
#'   (`Path`).
#'
#' @returns A character string, `""` when the block has no `PATH`.
#'
#' @keywords internal
#' @noRd
env_block_path <- function(env, on_windows = is_windows()) {
  path_name <- match_env_name(names(env), "PATH", on_windows = on_windows)
  if (isTRUE(is.na(path_name))) {
    return("")
  }
  return(unname(as.character(env[[path_name]])))
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

#' The key under which two `PATH` entries name the same directory
#'
#' Off Windows, an entry is its own key: entries compare as written. On
#' Windows, entries compare as Windows compares directories: without case,
#' with `/` the same as `\\`, and without trailing separators (`C:\\x\\`
#' is `C:\\x`). A drive root keeps its separator: `C:\\` is not `C:`,
#' which names the current directory of drive `C:`.
#'
#' @param x Character vector of `PATH` entries.
#' @param on_windows Logical. Whether to apply the Windows rule.
#'
#' @returns A character vector of the same length as `x`.
#'
#' @keywords internal
#' @noRd
path_entry_key <- function(x, on_windows = is_windows()) {
  if (isTRUE(on_windows)) {
    key <- tolower(gsub("/", "\\", x, fixed = TRUE))
    trimmed <- sub("\\\\+$", "", key)
    is_root <- grepl("^[a-z]:$", trimmed) | !nzchar(trimmed)
    key[!is_root] <- trimmed[!is_root]
    key[is_root] <- sub("\\\\+$", "\\\\", key[is_root])
    return(key)
  }
  return(x)
}

#' Prepend directories to a `PATH` string, one entry per directory
#'
#' As `compose_path()`, but an entry of `base_path` that names one of the
#' directories of `prepend` is dropped also when it is spelled differently
#' (see `path_entry_key()`). On Windows, the activation of micromamba
#' spells the environment's directories with `\\`, and
#' `env_bin_search_dirs()` with `/`: the run family put both copies of each
#' directory on the command's `PATH`. The first copy and its spelling are
#' kept. Off Windows, the result is that of `compose_path()`.
#'
#' Only the entries of `base_path` that repeat a directory of `prepend`
#' are dropped: the other entries of `base_path` stay as they are, as with
#' `compose_path()`.
#'
#' @param prepend Character vector of directories.
#' @param base_path Character string, the existing `PATH` value (may be
#'   empty).
#' @param on_windows Logical. Whether to apply the Windows rule.
#'
#' @returns A character string.
#'
#' @keywords internal
#' @noRd
prepend_path_dirs <- function(prepend, base_path, on_windows = is_windows()) {
  sep <- .Platform$path.sep
  prepend <- as.character(prepend)
  prepend <- prepend[nzchar(prepend)]
  prepend_keys <- path_entry_key(prepend, on_windows = on_windows)
  prepend <- prepend[!duplicated(prepend_keys)]
  base_parts <- strsplit(base_path %||% "", sep, fixed = TRUE)[[1L]]
  base_parts <- base_parts[
    !(path_entry_key(base_parts, on_windows = on_windows) %in% prepend_keys)
  ]
  return(compose_path(prepend, paste(base_parts, collapse = sep)))
}

#' `%|na|%`: fall back when the left-hand side is `NA`
#'
#' @keywords internal
#' @noRd
`%|na|%` <- function(x, y) {
  if (isTRUE(is.na(x))) y else x
}
