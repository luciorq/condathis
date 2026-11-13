#' Create an environment from a file
#'
#' Marks a file as the definition of a Conda environment, such as an
#' environment YAML file or a lock file. Pass the result in the `...` of
#' [create_env()], in place of package specs:
#' `create_env(env_definition("environment.yml"), env_name = "tools")`.
#' [install_packages()] and [validate_env()] take it too (see *Other
#' functions*).
#'
#' `condathis` does not read the file. The backend reads it and tells
#' `condathis` two things: which format the file has, and whether it is a
#' request or a lock.
#' * A request, such as an environment YAML file or a list of package
#'   specs, is solved when the environment is created. The result depends
#'   on the channels and on the day.
#' * A lock, such as an `@EXPLICIT` file or a conda-lock file, lists exact
#'   packages. It is installed as it is, without a solve, and only for a
#'   platform it lists.
#'
#' `env_definition()` makes `path` absolute against the working directory
#' at the time of the call, so a later [setwd()] does not change which file
#' it refers to. It does not resolve symbolic links, so paths in the file
#' that are relative to the file, such as `-r requirements.txt` in a `pip:`
#' section, still resolve. [create_env()] checks that the file exists when
#' it runs.
#'
#' @section Formats:
#' Leave `format` as `NULL` and the backend detects the format. Give it
#' when the file name does not tell, for example for a lock file named
#' `ci.lock`. `condathis` passes `format` to the backend and never reads
#' it. These names are a convention: conda uses them for its `--format`
#' option. Backends should accept them:
#' * `"environment-yaml"` (also `"cep-24"`): an environment YAML file, with
#'   `channels:` and `dependencies:`. A request.
#' * `"requirements"`: a text file with one package spec per line. A
#'   request.
#' * `"explicit"`: an `@EXPLICIT` file, with one package URL per line. A
#'   lock.
#' * `"conda-lock-v1"`: a conda-lock file, version 1. A lock.
#' * `"rattler-lock-v6"` and `"rattler-lock-v7"` (also `"pixi"`): a
#'   `pixi.lock` file. A lock.
#' * `"mambajs-lock-v1"`: a lock file of mambajs, in JSON. A lock.
#'
#' The micromamba backend reads environment YAML, requirements, `@EXPLICIT`,
#' conda-lock version 1 and mambajs files. It detects the format from the
#' contents of the file, so the file can have any name, with one exception:
#' an environment YAML file must have a name that ends in `.yml` or
#' `.yaml`, and not in `-lock.yml` or `-lock.yaml`. It does not read
#' `pixi.lock` files or directories. For a conda-lock file, it accepts one
#' option, `categories`: the package categories to install, `"main"` by
#' default, as in `categories = c("main", "dev")`. A backend aborts for an
#' option it does not know.
#'
#' @section Locks:
#' For a lock, [create_env()] picks the platform from the platforms that
#' the file lists: `platform` when it is given, else the native platform of
#' the backend, else an emulated one (see `platform` in [create_env()]).
#' When the file lists none of these, `create_env()` aborts with class
#' `condathis_create_env_platform_not_locked` (also
#' `condathis_create_env_platform_mismatch`) before anything runs.
#' A lock of `noarch` packages lists no platform, and installs on any
#' platform. For an `@EXPLICIT` or mambajs file, micromamba takes the
#' platform of each package from its subdir, such as `noarch` or
#' `linux-64`, not from the `platform` header of the file.
#' `channels`, `additional_channels` and `channel_priority` cannot be given
#' with a lock: a lock names its packages by URL. They abort with class
#' `condathis_create_env_conflicting_args`. The deprecated `env_file`
#' argument of [create_env()] ignores them, as in 0.1.4. A lock that lists packages but
#' gives an empty environment aborts with class
#' `condathis_create_env_failed`.
#'
#' When the backend reports the packages of a lock, as micromamba does for
#' `@EXPLICIT`, conda-lock and mambajs files, an existing environment is
#' compared with them: the same names, versions and build strings, none
#' missing and none more, for the platform of the lock. Packages that pip
#' installed are left out. `create_env(overwrite = FALSE)` then keeps an
#' environment that has exactly those packages, and
#' `validate_env(env_definition(<lock>), env_name = ...)` returns `TRUE`.
#'
#' @section Other functions:
#' * [install_packages()] installs the packages of a request into an
#'   existing environment, as `micromamba install -f <file>` does. It
#'   aborts for a lock, with class
#'   `condathis_install_packages_unsupported_definition`: create the
#'   environment again with `create_env(..., overwrite = TRUE)`.
#' * [validate_env()] compares an environment with a lock (see *Locks*).
#'   It aborts for a request, with class
#'   `condathis_validate_env_unsupported_definition`: a request depends on
#'   the channels and on the day.
#' * With `method = "auto"`, [create_env()] creates a new environment with
#'   the first available backend in `condathis.backend_priority` order that
#'   does not say it cannot read the file. An explicit `method`, or an
#'   existing environment, keeps its backend.
#'
#' @param path Character string with the path of the file, absolute or
#'   relative to the working directory. `env_definition()` expands a
#'   leading `~`. A backend may also accept a directory. URLs are not
#'   supported: download the file first. A value that is not a single,
#'   non-empty string, or a URL, aborts with class
#'   `condathis_env_definition_invalid_path` (also `condathis_invalid_path`).
#' @param format `NULL` (the default), so that the backend detects the
#'   format, or a single, non-empty string that names it (see *Formats*).
#'   Other values abort with class
#'   `condathis_env_definition_invalid_format`.
#' @param ... Named options for the backend, such as `categories` for a
#'   conda-lock file. `condathis` passes them on and never reads them. An
#'   unnamed or repeated option aborts with class
#'   `condathis_env_definition_invalid_options`.
#'
#' @returns An object of class `condathis_env_definition`: a list with
#'   `path` (the absolute path), `format` (`NULL` or a string) and
#'   `options` (a named list).
#'
#' @examples
#' condathis::env_definition("environment.yml")
#' condathis::env_definition("ci.lock", format = "conda-lock-v1")
#' condathis::env_definition("conda-lock.yml", categories = c("main", "dev"))
#'
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   # An environment YAML file shipped with condathis.
#'   env_file <- system.file("extdata", "stat-env.yml", package = "condathis")
#'   condathis::create_env(
#'     condathis::env_definition(env_file),
#'     env_name = "stat-env"
#'   )
#' })
#' }
#'
#' @family environments
#' @seealso [create_env()]
#'
#' @export
env_definition <- function(path, format = NULL, ...) {
  path_class <- arg_error_class("env_definition", "path")
  if (missing(path)) {
    condathis_abort(
      message = c(`x` = "{.arg path} is absent but must be supplied."),
      class = path_class
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
      class = path_class
    )
  }
  if (isTRUE(is_url_path(path))) {
    condathis_abort(
      message = c(
        `x` = "{.arg path} must be the path of a local file, not a URL.",
        `i` = "Download the file first, and pass its path."
      ),
      class = path_class
    )
  }
  if (
    isFALSE(is.null(format)) &&
      (isFALSE(rlang::is_string(format)) ||
        is.na(format) ||
        isFALSE(nzchar(format)))
  ) {
    condathis_abort(
      message = c(
        `x` = "{.arg format} must be {.code NULL} or a single, non-empty character string, not {.obj_type_friendly {format}}."
      ),
      class = arg_error_class("env_definition", "format")
    )
  }
  options <- rlang::list2(...)
  check_definition_options(options)
  return(new_env_definition(
    path = normalize_definition_path(path),
    format = format,
    options = options
  ))
}

#' Construct a `condathis_env_definition` object
#'
#' A classed list, as `new_env_path()`: code that does not know the class
#' fails its `is.character()` checks instead of using the path as a package
#' spec.
#'
#' @param path Character string. An absolute path.
#' @param format `NULL` or a character string.
#' @param options A named list.
#'
#' @keywords internal
#' @noRd
new_env_definition <- function(path, format = NULL, options = list()) {
  return(structure(
    list(path = path, format = format, options = options),
    class = "condathis_env_definition"
  ))
}

#' Is `x` an environment definition?
#'
#' @keywords internal
#' @noRd
is_env_definition <- function(x) {
  return(inherits(x, "condathis_env_definition"))
}

#' Is a path a URL?
#'
#' @param path Character string.
#'
#' @returns `TRUE` for a string that starts with a URL scheme and `://`,
#'   such as `https://` or `file://`. A Windows path such as `C:\x` or `C:/x`
#'   is not one.
#'
#' @keywords internal
#' @noRd
is_url_path <- function(path) {
  return(isTRUE(grepl("^[A-Za-z][A-Za-z0-9+.-]*://", path)))
}

#' Make the path of an environment definition absolute
#'
#' Not `fs::path_real()`: a pip `-r` path in an environment YAML file is
#' relative to the file as the user named it.
#'
#' @param path Character string.
#'
#' @returns Character string.
#'
#' @keywords internal
#' @noRd
normalize_definition_path <- function(path) {
  return(as.character(fs::path_norm(fs::path_abs(fs::path_expand(path)))))
}

#' Check the backend options of an environment definition
#'
#' @param options A list, the `...` of `env_definition()`.
#' @param class Character vector, the classes of the error.
#' @param call Environment of the function the error is reported for.
#'
#' @returns `options`, invisibly. Aborts for a list with an unnamed or a
#'   repeated element.
#'
#' @keywords internal
#' @noRd
check_definition_options <- function(
  options,
  class = c(
    "condathis_env_definition_invalid_options",
    "condathis_invalid_arg"
  ),
  call = rlang::caller_env()
) {
  option_names <- rlang::names2(options)
  if (isTRUE(any(!nzchar(option_names)))) {
    condathis_abort(
      message = c(
        `x` = "The options in {.arg ...} must be named.",
        `i` = "For example: {.code env_definition(\"conda-lock.yml\", categories = \"main\")}."
      ),
      class = class,
      call = call
    )
  }
  repeated <- unique(option_names[duplicated(option_names)])
  if (isTRUE(length(repeated) > 0L)) {
    condathis_abort(
      message = c(
        `x` = "Each option in {.arg ...} must be given only once.",
        `i` = "Given more than once: {.val {repeated}}."
      ),
      class = class,
      call = call
    )
  }
  return(invisible(options))
}

#' @export
format.condathis_env_definition <- function(x, ...) {
  path <- x[["path"]]
  path <- if (isTRUE(rlang::is_string(path))) path else "<invalid path>"
  extras <- character(0L)
  if (isTRUE(rlang::is_string(x[["format"]]))) {
    extras <- c(extras, paste0("format: ", x[["format"]]))
  }
  option_names <- rlang::names2(x[["options"]])
  if (isTRUE(length(option_names) > 0L)) {
    extras <- c(extras, paste0("options: ", paste(option_names, collapse = ", ")))
  }
  out <- paste0("<env_definition> ", path)
  if (isTRUE(length(extras) > 0L)) {
    out <- paste0(out, " (", paste(extras, collapse = "; "), ")")
  }
  return(out)
}

#' @export
print.condathis_env_definition <- function(x, ...) {
  cat(format(x, ...), "\n", sep = "")
  return(invisible(x))
}

#' Check an environment definition before using it
#'
#' A `condathis_env_definition` object can be built or changed by hand, so
#' its content is checked again where it is used instead of trusted. The
#' existence of the file is checked by `check_env_definition_exists()`.
#'
#' @param x A `condathis_env_definition` object.
#' @param call Environment of the function the error is reported for.
#'
#' @returns The object, with its path made absolute again. Aborts with
#'   `c("condathis_env_definition_invalid", "condathis_invalid_arg",
#'   "condathis_error")`.
#'
#' @keywords internal
#' @noRd
validate_env_definition_object <- function(x, call = rlang::caller_env()) {
  invalid <- function(problem) {
    condathis_abort(
      message = c(
        `x` = "An environment definition must be an object from {.fn env_definition}, not a malformed {.cls condathis_env_definition} object.",
        `x` = problem,
        `i` = "Create it with {.fn env_definition}."
      ),
      class = c("condathis_env_definition_invalid", "condathis_invalid_arg"),
      call = call
    )
  }
  if (isFALSE(rlang::is_list(x))) {
    invalid("It is not a list.")
  }
  path <- x[["path"]]
  if (
    isFALSE(rlang::is_string(path)) ||
      is.na(path) ||
      isFALSE(nzchar(path)) ||
      isTRUE(is_url_path(path)) ||
      isFALSE(fs::is_absolute_path(path))
  ) {
    invalid("Its {.field path} is not an absolute path.")
  }
  format <- x[["format"]]
  if (
    isFALSE(is.null(format)) &&
      (isFALSE(rlang::is_string(format)) ||
        is.na(format) ||
        isFALSE(nzchar(format)))
  ) {
    invalid("Its {.field format} is not {.code NULL} or a non-empty string.")
  }
  options <- x[["options"]]
  if (is.null(options)) {
    options <- list()
  }
  option_names <- rlang::names2(options)
  if (
    isFALSE(is.list(options)) ||
      isTRUE(any(!nzchar(option_names))) ||
      isTRUE(anyDuplicated(option_names) > 0L)
  ) {
    invalid("Its {.field options} is not a list of named options.")
  }
  return(new_env_definition(
    path = normalize_definition_path(path),
    format = format,
    options = options
  ))
}

#' Abort when the file of an environment definition does not exist
#'
#' The check runs in `create_env()`, not only in the backend: the
#' already-satisfied shortcut does not call the backend, and must not let a
#' mistyped path pass.
#'
#' @param definition A valid `condathis_env_definition` object.
#' @param arg Character string, the argument the path came from, for the
#'   message: `"env_file"` for the deprecated argument, `NULL` for an
#'   object in `...`.
#' @param fn Character string, the exported function, for the classes.
#' @param call Environment of the function the error is reported for.
#'
#' @returns `definition`, invisibly. Aborts with
#'   `c("condathis_<fn>_missing_env_file", "condathis_invalid_env_file",
#'   "condathis_invalid_arg", "condathis_error")`, and for `create_env()`
#'   also `"condathis_create_missing_env_file"` after the first class.
#'
#' @keywords internal
#' @noRd
check_env_definition_exists <- function(
  definition,
  arg = NULL,
  fn = "create_env",
  call = rlang::caller_env()
) {
  path <- definition[["path"]]
  if (isTRUE(fs::file_exists(path))) {
    return(invisible(definition))
  }
  message <- if (is.null(arg)) {
    c(`x` = "Environment definition {.path {path}} does not exist.")
  } else {
    c(`x` = "{.arg {arg}} {.path {path}} does not exist.")
  }
  class <- c(
    paste0("condathis_", fn, "_missing_env_file"),
    if (identical(fn, "create_env")) "condathis_create_missing_env_file",
    "condathis_invalid_env_file",
    "condathis_invalid_arg"
  )
  condathis_abort(message = message, class = class, call = call)
}

#' Take the environment definitions out of the `...` of `create_env()`
#'
#' Only unnamed elements count. A named one, such as
#' `packages = env_definition("a.yml")`, stays, and the checks of the
#' package specs reject it.
#'
#' @param dots A list, `rlang::list2(...)`.
#'
#' @returns A list with `dots` (the other elements, with their names) and
#'   `definitions` (a list of `condathis_env_definition` objects, possibly
#'   empty).
#'
#' @keywords internal
#' @noRd
split_env_definitions <- function(dots) {
  if (identical(length(dots), 0L)) {
    return(list(dots = dots, definitions = list()))
  }
  is_definition <- !nzchar(rlang::names2(dots)) &
    vapply(dots, is_env_definition, logical(1L))
  return(list(
    dots = dots[!is_definition],
    definitions = unname(dots[is_definition])
  ))
}

#' A description of an environment definition
#'
#' The value of `backend_describe_definition()` (see ?register_backend).
#'
#' @param supported `TRUE`, `FALSE` or `NA`.
#' @param format `NA` or a character string.
#' @param kind `"request"`, `"lock"` or `NA`.
#' @param platforms `NULL` or a character vector.
#' @param reason `NA` or a character string.
#' @param records `NULL` or a data frame.
#'
#' @returns A list with these elements.
#'
#' @keywords internal
#' @noRd
definition_description <- function(
  supported = NA,
  format = NA_character_,
  kind = NA_character_,
  platforms = NULL,
  reason = NA_character_,
  records = NULL
) {
  return(list(
    supported = supported,
    format = format,
    kind = kind,
    platforms = platforms,
    reason = reason,
    records = records
  ))
}
