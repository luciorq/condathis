#' Refer to an environment by its path
#'
#' Marks a directory as a Conda environment to run commands from. Use it for
#' an environment that `condathis` did not create, such as one created by
#' another user, or by `conda`, `mamba` or `micromamba` directly. Pass the
#' result as `env_name` to [run()], [run_bin()], [run_pipeline()] or
#' [run_step()].
#'
#' Environments given by path are read-only for `condathis`: only the
#' `run()` family accepts them. [create_env()], [install_packages()],
#' [remove_env()], [validate_env()], [env_exists()], [list_packages()] and
#' [get_env_dir()] reject them with an error of class
#' `condathis_env_path_read_only` (also `condathis_invalid_env_name`), and
#' [list_envs()] does not list them.
#'
#' Commands in an environment given by path run with the environment's own
#' activation. They need a backend that can activate an environment given by
#' its directory. The micromamba backend can. With `method = "auto"`, the
#' first such backend in the order of the option
#' `condathis.backend_priority` runs it, micromamba by default. A `method`
#' that names a backend that cannot aborts with class
#' `condathis_env_path_unsupported_method` (also
#' `condathis_backend_unsupported`).
#'
#' `env_path()` makes `path` absolute against the working directory at the
#' time of the call, so a later [setwd()] does not change which environment
#' it refers to. The function that gets the path checks it when the command
#' runs, and honors its `error` argument. The directory must exist and
#' contain a `conda-meta` directory. Otherwise, `error = "cancel"` aborts
#' with class `condathis_env_path_not_found` or
#' `condathis_env_path_not_conda_env` (both also
#' `condathis_env_not_found`).
#'
#' Prefer environment names in scripts that other people run: a path is
#' specific to one machine.
#'
#' @param path Character string with the path of the environment
#'   directory (the prefix), absolute or relative to the working directory.
#'   `env_path()` expands a leading `~`. A value that is not a single,
#'   non-empty string aborts with class `condathis_env_path_invalid_path`
#'   (also `condathis_invalid_path`).
#'
#' @returns An object of class `condathis_env_path`, holding the absolute
#'   path.
#'
#' @examples
#' condathis::env_path("/opt/conda/envs/shared-tools")
#'
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   # An environment created outside condathis, here with micromamba
#'   # itself, in a directory of our choosing. `--no-rc` and `--no-env`
#'   # make micromamba ignore your own Conda settings, as condathis does.
#'   channel <- system.file(
#'     "extdata", "polyglot-channel",
#'     package = "condathis"
#'   )
#'   prefix <- file.path(tempdir(), "my-prefix-env")
#'   condathis::install_micromamba()
#'   processx::run(
#'     condathis::micromamba_bin_path(),
#'     c(
#'       "create", "-y", "--no-rc", "--no-env",
#'       "-r", file.path(tempdir(), "mamba-root"),
#'       "-p", prefix, "-c", channel, "--override-channels", "polyglot"
#'     )
#'   )
#'
#'   condathis::run("polyglot", env_name = condathis::env_path(prefix))
#'
#'   # `with_sandbox_dir()` does not change `tempdir()`: clean up.
#'   unlink(c(prefix, file.path(tempdir(), "mamba-root")), recursive = TRUE)
#' })
#' }
#'
#' @family environments
#' @seealso [run()], [run_bin()], [run_pipeline()], [run_step()]
#'
#' @export
env_path <- function(path) {
  error_class <- arg_error_class(
    "env_path",
    "path",
    aliases = "condathis_env_path_invalid"
  )
  if (missing(path)) {
    condathis_abort(
      message = c(`x` = "{.arg path} is absent but must be supplied."),
      class = error_class
    )
  }
  if (
    isFALSE(rlang::is_string(path)) ||
      is.na(path) ||
      isFALSE(nzchar(path))
  ) {
    condathis_abort(
      message = c(
        `x` = "{.arg path} must be a single, non-empty character string, not {.obj_type_friendly {path}}."
      ),
      class = error_class
    )
  }
  return(new_env_path(normalize_env_path(path)))
}

#' Construct a `condathis_env_path` object
#'
#' A classed list, not a classed character vector: code that does not know
#' the class then fails its `is.character()` checks instead of using the
#' path as an environment name.
#'
#' @param path Character string. An absolute path.
#'
#' @keywords internal
#' @noRd
new_env_path <- function(path) {
  return(structure(list(path = path), class = "condathis_env_path"))
}

#' Is `x` an environment given by path?
#'
#' @keywords internal
#' @noRd
is_env_path <- function(x) {
  return(inherits(x, "condathis_env_path"))
}

#' Make an environment path absolute and canonical
#'
#' An existing directory is resolved to its real path, so two spellings of
#' the same directory share one activation cache entry.
#'
#' @param path Character string.
#'
#' @returns Character string.
#'
#' @keywords internal
#' @noRd
normalize_env_path <- function(path) {
  path <- fs::path_abs(fs::path_expand(path))
  if (isTRUE(fs::dir_exists(path))) {
    # On Windows, realpath cannot resolve some existing directories (a
    # volume mounted on a folder, some virtual file systems). Keep the
    # absolute spelling then, as `realize_env_paths()` does.
    path <- tryCatch(fs::path_real(path), error = function(e) path)
  }
  return(as.character(fs::path_norm(path)))
}

#' @export
format.condathis_env_path <- function(x, ...) {
  return(paste0("<env_path> ", x$path))
}

#' @export
print.condathis_env_path <- function(x, ...) {
  cat(format(x, ...), "\n", sep = "")
  return(invisible(x))
}

#' Check an environment path before using it
#'
#' A `condathis_env_path` object can be built by hand, so its content is
#' checked again where it is used instead of trusted.
#'
#' @param x A `condathis_env_path` object.
#' @param class Character vector. The calling function's own invalid
#'   `env_name` classes, for example `"condathis_run_invalid_env_name"`, or
#'   `NULL`. The error has the classes `c("condathis_env_path_invalid",
#'   class, "condathis_invalid_env_name", "condathis_invalid_arg",
#'   "condathis_error")`.
#' @param call Calling environment, for the error.
#'
#' @returns The absolute path, as a character string.
#'
#' @keywords internal
#' @noRd
validate_env_path_object <- function(
  x,
  class = NULL,
  call = rlang::caller_env()
) {
  path <- if (rlang::is_list(x)) x[["path"]]
  if (
    isFALSE(rlang::is_string(path)) ||
      is.na(path) ||
      isFALSE(fs::is_absolute_path(path))
  ) {
    condathis_abort(
      message = c(
        `x` = "{.arg env_name} must be an environment name or an object from {.fn env_path}, not a malformed {.cls condathis_env_path} object.",
        `i` = "Create it with {.fn env_path}."
      ),
      class = unique(c(
        "condathis_env_path_invalid",
        class,
        "condathis_invalid_env_name",
        "condathis_invalid_arg"
      )),
      call = call
    )
  }
  return(normalize_env_path(path))
}

#' Resolve an environment given by path for the `run()` family
#'
#' Only a backend whose object has `backend_resolve_run_in_dir()` can run
#' commands in an environment given by path: the default of that function
#' aborts, and `backend_resolve_run()` addresses environments by name. With
#' `method = "auto"`, it is the first such backend in
#' `backend_names_by_priority()` order, after the known backend packages
#' that the option `condathis.backend_priority` names were loaded, as for a
#' new environment. The micromamba backend always has it, so `"auto"`
#' always finds one.
#'
#' @param env_name A `condathis_env_path` object.
#' @param method Character string, as in `run()`.
#' @param class Character vector. The calling function's own invalid
#'   `env_name` classes, passed to `validate_env_path_object()`.
#' @param call Calling environment, for errors.
#'
#' @returns A list with `backend`, `name` (the backend name) and `env_dir`.
#'
#' @keywords internal
#' @noRd
resolve_env_path_target <- function(
  env_name,
  method = "auto",
  class = NULL,
  call = rlang::caller_env()
) {
  env_dir <- validate_env_path_object(env_name, class = class, call = call)
  method <- resolve_method_alias(validate_method_arg(method, call = call))
  candidates <- method
  if (identical(method, "auto")) {
    load_known_backends(priority = TRUE, call = call)
    candidates <- backend_names_by_priority()
  }
  for (candidate in candidates) {
    backend <- get_backend(candidate, call = call)
    if (isTRUE(backend_runs_in_dir(backend))) {
      return(list(backend = backend, name = candidate, env_dir = env_dir))
    }
  }
  runners <- Filter(
    function(nm) backend_runs_in_dir(get_backend(nm, call = call)),
    list_registered_backend_names()
  )
  condathis_abort(
    message = c(
      `x` = "Backend {.field {method}} cannot run commands in an environment given by {.fn env_path}.",
      `i` = "Use {.code method = \"auto\"}, or one of {.val {runners}}."
    ),
    class = c(
      "condathis_env_path_unsupported_method",
      "condathis_backend_unsupported",
      "condathis_invalid_method",
      "condathis_invalid_arg"
    ),
    call = call
  )
}

#' Can a backend run commands in an environment given by path?
#'
#' @param backend A registered backend object.
#'
#' @returns `TRUE` when the object has its own
#'   `backend_resolve_run_in_dir()`, else `FALSE`.
#'
#' @keywords internal
#' @noRd
backend_runs_in_dir <- function(backend) {
  return(isTRUE(
    "backend_resolve_run_in_dir" %in% backend_provided_hooks(backend)
  ))
}

#' Why an environment directory cannot be used, if it cannot
#'
#' @param env_dir Character string. An absolute path.
#'
#' @returns `NULL` when `env_dir` is a Conda environment. Otherwise a list
#'   with `class` (the condition class) and `message` (one line, without a
#'   trailing newline).
#'
#' @keywords internal
#' @noRd
env_path_problem <- function(env_dir) {
  if (isFALSE(fs::dir_exists(env_dir))) {
    return(list(
      class = "condathis_env_path_not_found",
      message = sprintf("Environment directory '%s' does not exist.", env_dir)
    ))
  }
  if (isFALSE(fs::dir_exists(fs::path(env_dir, "conda-meta")))) {
    return(list(
      class = "condathis_env_path_not_conda_env",
      message = sprintf(
        "Directory '%s' is not a Conda environment: it has no 'conda-meta' directory.",
        env_dir
      )
    ))
  }
  return(NULL)
}

#' Check that an environment given by path can be used, per `error`
#'
#' The shared check of `run()`, `run_bin()` and `run_pipeline()`: under
#' `error = "cancel"` an unusable directory aborts, and under
#' `error = "continue"` the caller reports a `status = 127` result with the
#' returned text as its standard error.
#'
#' @param env_dir Character string. An absolute path.
#' @param error_var Logical. `TRUE` for `error = "cancel"`.
#' @param class Character vector. Classes added to the error by the calling
#'   function, as in `abort_env_path_problem()`.
#' @param call Calling environment, for the error.
#'
#' @returns `NULL` when `env_dir` is a Conda environment. Otherwise, under
#'   `error = "continue"`, the standard error text of the result: one line,
#'   with a trailing newline.
#'
#' @keywords internal
#' @noRd
check_env_path_usable <- function(
  env_dir,
  error_var,
  class = NULL,
  call = rlang::caller_env()
) {
  problem <- env_path_problem(env_dir)
  if (is.null(problem)) {
    return(NULL)
  }
  if (isTRUE(error_var)) {
    abort_env_path_problem(problem, class = class, call = call)
  }
  return(paste0(problem$message, "\n"))
}

#' Abort for an environment directory that cannot be used
#'
#' The error has the classes `c(<problem class>, class,
#' "condathis_env_not_found", "condathis_error")`, so every missing
#' environment shares `condathis_env_not_found`.
#'
#' @param problem A list from `env_path_problem()`.
#' @param class Character vector. Classes added by the calling function, so
#'   its existing "environment not found" handlers keep working.
#' @param call Calling environment, for the error.
#'
#' @keywords internal
#' @noRd
abort_env_path_problem <- function(
  problem,
  class = NULL,
  call = rlang::caller_env()
) {
  condathis_abort(
    message = c(`x` = "{problem$message}"),
    class = unique(c(problem$class, class, "condathis_env_not_found")),
    call = call
  )
}

#' Abort for an environment given by path where only names are accepted
#'
#' The error has the classes `c("condathis_env_path_read_only", class,
#' "condathis_invalid_env_name", "condathis_invalid_arg",
#' "condathis_error")`.
#'
#' @param class Character vector. The calling function's own invalid
#'   `env_name` classes.
#' @param call Calling environment, for the error.
#'
#' @keywords internal
#' @noRd
abort_env_path_read_only <- function(class, call = rlang::caller_env()) {
  condathis_abort(
    message = c(
      `x` = "{.arg env_name} must be an environment name, not an environment given by {.fn env_path}.",
      `i` = paste(
        "Environments given by path can only be used to run commands, with",
        "{.fn run}, {.fn run_bin}, {.fn run_pipeline} and {.fn run_step}."
      )
    ),
    class = unique(c(
      "condathis_env_path_read_only",
      class,
      "condathis_invalid_env_name",
      "condathis_invalid_arg"
    )),
    call = call
  )
}
