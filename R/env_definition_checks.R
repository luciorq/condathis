# How create_env(), install_packages() and validate_env() use an
# environment definition (`env_definition()`): what the backend makes of
# it, the errors for one it cannot read, and the comparison of an existing
# environment with the records of a lock.

#' Does an environment definition have a `format` or options?
#'
#' @param definition A `condathis_env_definition` object.
#'
#' @returns `TRUE` or `FALSE`.
#'
#' @keywords internal
#' @noRd
definition_has_details <- function(definition) {
  return(
    isFALSE(is.null(definition[["format"]])) ||
      isTRUE(length(definition[["options"]]) > 0L)
  )
}

#' Can a backend function get an environment definition at all?
#'
#' A backend function without a `definition` argument gets only the path,
#' as `env_file`, so it cannot honor a `format` or options. An install
#' function that has neither argument cannot install from a file at all.
#'
#' @param backend A backend object.
#' @param definition A `condathis_env_definition` object.
#' @param generic Character string, the function that will get the file:
#'   `"backend_create_env"` or `"backend_install"`.
#'
#' @returns `NULL`, or one sentence: why the function cannot get it.
#'
#' @keywords internal
#' @noRd
definition_formal_problem <- function(backend, definition, generic) {
  takes_definition <- backend_fn_takes_arg(backend, generic, "definition")
  if (
    identical(generic, "backend_install") &&
      isFALSE(takes_definition) &&
      isFALSE(backend_fn_takes_arg(backend, generic, "env_file"))
  ) {
    return("The backend does not install packages from a file.")
  }
  if (isTRUE(definition_has_details(definition)) && isFALSE(takes_definition)) {
    return(
      "The backend reads only the file of an environment definition, not its format or options."
    )
  }
  return(NULL)
}

#' What a backend makes of an environment definition
#'
#' `backend_describe_definition()`, checked (see
#' `backend_describe_definition_checked()`), after the check of
#' `definition_formal_problem()`: a function that cannot get the definition
#' gives `supported = FALSE` without asking the backend.
#'
#' @param backend An already-resolved backend object.
#' @param definition A valid `condathis_env_definition` object.
#' @param platform `NULL` or the requested platform.
#' @param generic Character string, see `definition_formal_problem()`.
#' @param call Environment of the function an invalid value is reported
#'   for.
#'
#' @returns A list, see `validate_definition_description()`.
#'
#' @keywords internal
#' @noRd
describe_definition <- function(
  backend,
  definition,
  platform = NULL,
  generic = "backend_create_env",
  call = rlang::caller_env()
) {
  problem <- definition_formal_problem(backend, definition, generic)
  if (isFALSE(is.null(problem))) {
    return(definition_description(
      supported = FALSE,
      format = definition[["format"]] %||% NA_character_,
      reason = problem
    ))
  }
  return(backend_describe_definition_checked(
    backend,
    definition = definition,
    platform = platform,
    call = call
  ))
}

#' The hint that names the backends that read the format of a definition
#'
#' From `backend_definition_formats()` of the registered backends (see
#' `registered_definition_formats()`). For messages only.
#'
#' @param definition A `condathis_env_definition` object.
#' @param exclude Character vector of backend names to leave out.
#'
#' @returns A named character vector with one `i` bullet, or
#'   `character(0)` when the definition has no `format` or no other
#'   registered backend lists it. The bullet refers to the variables
#'   `format` and `readers`, so the caller must define them, or format it
#'   with `cli::format_inline()` first, as this function does.
#'
#' @keywords internal
#' @noRd
definition_format_hint <- function(definition, exclude = character(0L)) {
  format <- definition[["format"]]
  if (isFALSE(rlang::is_string(format))) {
    return(character(0L))
  }
  formats <- registered_definition_formats()
  readers <- names(formats)[vapply(
    formats,
    function(x) isTRUE(tolower(format) %in% tolower(x)),
    logical(1L)
  )]
  readers <- setdiff(readers, exclude)
  if (identical(length(readers), 0L)) {
    return(character(0L))
  }
  return(c(
    `i` = cli_escape(cli::format_inline(
      "Format {.val {format}} is read by: {.field {readers}}. Pass one of them as {.arg method}."
    ))
  ))
}

#' Abort for an environment definition that a backend cannot read
#'
#' @param backend_name Character string.
#' @param definition A `condathis_env_definition` object.
#' @param reason `NA` or a character string, the reason of the backend.
#' @param fn Character string, the exported function, for the class.
#' @param call Environment of the function the error is reported for.
#'
#' @returns Does not return. Aborts with
#'   `c("condathis_<fn>_unsupported_definition",
#'   "condathis_backend_unsupported", "condathis_invalid_arg",
#'   "condathis_error")`.
#'
#' @keywords internal
#' @noRd
abort_unsupported_definition <- function(
  backend_name,
  definition,
  reason = NA_character_,
  fn = "create_env",
  call = rlang::caller_env()
) {
  path <- definition$path
  message <- c(
    `x` = "Backend {.field {backend_name}} cannot read environment definition {.path {path}}."
  )
  if (isTRUE(rlang::is_string(reason)) && isFALSE(is.na(reason))) {
    message <- c(message, `i` = "{reason}")
  }
  message <- c(message, definition_format_hint(definition, exclude = backend_name))
  condathis_abort(
    message = message,
    class = c(
      paste0("condathis_", fn, "_unsupported_definition"),
      "condathis_backend_unsupported",
      "condathis_invalid_arg"
    ),
    call = call
  )
}

#' Abort when no available backend reads an environment definition
#'
#' The `on_refused` of `resolve_backend()` for `create_env()` with
#' `method = "auto"`.
#'
#' @param definition A `condathis_env_definition` object.
#' @param refused Named character vector: the reason of each backend that
#'   was tried, named by backend.
#' @param fn Character string, the exported function, for the class.
#' @param call Environment of the function the error is reported for.
#'
#' @returns Does not return. Aborts with the classes of
#'   `abort_unsupported_definition()`.
#'
#' @keywords internal
#' @noRd
abort_no_backend_for_definition <- function(
  definition,
  refused,
  fn = "create_env",
  call = rlang::caller_env()
) {
  path <- definition$path
  tried <- names(refused)
  message <- c(
    `x` = "No available backend can read environment definition {.path {path}}.",
    `i` = "Tried: {.field {tried}}."
  )
  for (i in seq_along(refused)) {
    reason <- refused[[i]]
    if (isTRUE(is.na(reason)) || isFALSE(nzchar(reason))) {
      reason <- "It cannot read it."
    }
    message <- c(
      message,
      `*` = cli_escape(cli::format_inline("{.field {tried[[i]]}}: {reason}"))
    )
  }
  message <- c(message, definition_format_hint(definition, exclude = tried))
  condathis_abort(
    message = message,
    class = c(
      paste0("condathis_", fn, "_unsupported_definition"),
      "condathis_backend_unsupported",
      "condathis_invalid_arg"
    ),
    call = call
  )
}

#' The environment definition in the `...` of `install_packages()` or
#' `validate_env()`
#'
#' At most one, and no package specs with it. The object is checked again
#' and its file must exist.
#'
#' @param definitions List of `condathis_env_definition` objects (see
#'   `split_env_definitions()`).
#' @param packages Character vector, the package specs of the call.
#' @param fn Character string, the exported function, for the classes.
#' @param call Environment of the function the error is reported for.
#'
#' @returns `NULL` when the call has no definition, else a valid
#'   `condathis_env_definition` object whose file exists. Aborts with
#'   class `condathis_<fn>_conflicting_args` (also `condathis_invalid_arg`)
#'   for two definitions, or a definition and package specs.
#'
#' @keywords internal
#' @noRd
resolve_call_definition <- function(
  definitions,
  packages,
  fn,
  call = rlang::caller_env()
) {
  if (identical(length(definitions), 0L)) {
    return(NULL)
  }
  conflicting_class <- c(
    paste0("condathis_", fn, "_conflicting_args"),
    "condathis_invalid_arg"
  )
  if (isTRUE(length(definitions) > 1L)) {
    condathis_abort(
      message = c(
        `x` = "{.fn {fn}} takes at most one {.fn env_definition}, not {length(definitions)}."
      ),
      class = conflicting_class,
      call = call
    )
  }
  if (isTRUE(length(packages) > 0L)) {
    spec <- packages[[length(packages)]]
    condathis_abort(
      message = c(
        `x` = "Use either package specs in {.arg ...} or {.fn env_definition}, not both.",
        `i` = "If {.val {spec}} is an environment name, name its argument: {.code env_name = \"{spec}\"}."
      ),
      class = conflicting_class,
      call = call
    )
  }
  definition <- validate_env_definition_object(definitions[[1L]], call = call)
  return(check_env_definition_exists(definition, fn = fn, call = call))
}

#' Escape the braces of a formatted text for a second cli formatting
#'
#' @param x Character vector, already formatted.
#'
#' @returns `x` with `{` and `}` doubled.
#'
#' @keywords internal
#' @noRd
cli_escape <- function(x) {
  return(gsub("}", "}}", gsub("{", "{{", x, fixed = TRUE), fixed = TRUE))
}

# --- Locks and existing environments ------------------------------------------

#' The records of a lock for one platform
#'
#' @param records A data frame with the character columns `name`,
#'   `version`, `build_string` and `platform`.
#' @param target `NA` (every record) or a platform name: the records for
#'   it, for `noarch`, and those without a platform.
#'
#' @returns A data frame, a subset of `records`.
#'
#' @keywords internal
#' @noRd
lock_records_for <- function(records, target) {
  if (isTRUE(is.na(target))) {
    return(records)
  }
  platform <- as.character(records[["platform"]])
  keep <- is.na(platform) | platform %in% c(target, "noarch")
  return(records[keep, , drop = FALSE])
}

#' The platforms to compare an environment with a lock for
#'
#' @param records The records of the lock.
#' @param target `NA` or a platform name.
#'
#' @returns `target` when it is a platform. Otherwise each platform of the
#'   records (without `noarch`), or `NA` when they name none.
#'
#' @keywords internal
#' @noRd
lock_targets <- function(records, target) {
  if (isFALSE(is.na(target))) {
    return(target)
  }
  platforms <- as.character(records[["platform"]])
  platforms <- unique(setdiff(platforms[!is.na(platforms)], "noarch"))
  if (identical(length(platforms), 0L)) {
    return(NA_character_)
  }
  return(platforms)
}

#' Can an existing environment be compared with an environment definition?
#'
#' Only a lock whose records name every package: `name`, `version` and
#' `build_string`, without `NA`, for each platform it could be compared
#' for. A request depends on the channels and on the day, so it is never
#' compared.
#'
#' @param description A list, see `validate_definition_description()`.
#' @param target `NA` or a platform name.
#'
#' @returns `TRUE` or `FALSE`.
#'
#' @keywords internal
#' @noRd
lock_records_comparable <- function(description, target = NA_character_) {
  records <- description[["records"]]
  if (
    isFALSE(identical(description[["kind"]], "lock")) ||
      is.null(records)
  ) {
    return(FALSE)
  }
  for (one_target in lock_targets(records, target)) {
    selected <- lock_records_for(records, one_target)
    keys <- selected[c("name", "version", "build_string")]
    if (isTRUE(anyNA(keys)) || isFALSE(all(nzchar(as.matrix(keys))))) {
      return(FALSE)
    }
  }
  return(TRUE)
}

#' Package records as `<name>-<version>-<build>` strings
#'
#' The form of conda's package file names, so a record reads the same in
#' every message. Names are compared in lower case, as conda does.
#'
#' @param df A data frame with `name`, `version` and `build_string`.
#'
#' @returns Character vector.
#'
#' @keywords internal
#' @noRd
package_dist_strings <- function(df) {
  if (identical(NROW(df), 0L)) {
    return(character(0L))
  }
  return(paste(
    tolower(as.character(df[["name"]])),
    as.character(df[["version"]]),
    as.character(df[["build_string"]]),
    sep = "-"
  ))
}

#' Compare the packages of an environment with the records of a lock
#'
#' The environment matches when its packages are exactly the records for
#' the platform: the same names, versions and build strings, none missing
#' and none more. Packages that pip installed (channel `pypi`) are left
#' out: the records of a lock list conda packages only. Without a target
#' platform, the environment matches when it matches the records of any
#' platform of the lock.
#'
#' @param installed_pkgs_df Data frame from `list_env_packages_checked()`.
#' @param records The records of the lock (see
#'   `lock_records_comparable()`).
#' @param target `NA` or a platform name.
#'
#' @returns A list with `satisfied` (`TRUE` or `FALSE`), `target` (the
#'   platform compared, or `NA`), `missing` (the records that the
#'   environment does not have) and `unexpected` (the packages of the
#'   environment that the lock does not list), both as
#'   `package_dist_strings()`. For several platforms, the one with the
#'   fewest differences.
#'
#' @keywords internal
#' @noRd
compare_lock_records <- function(installed_pkgs_df, records, target = NA_character_) {
  if (isFALSE(is.null(installed_pkgs_df[["channel"]]))) {
    installed_pkgs_df <- installed_pkgs_df[
      !installed_pkgs_df[["channel"]] %in% "pypi",
      ,
      drop = FALSE
    ]
  }
  installed <- unique(package_dist_strings(installed_pkgs_df))
  best <- NULL
  for (one_target in lock_targets(records, target)) {
    locked <- unique(package_dist_strings(lock_records_for(records, one_target)))
    result <- list(
      satisfied = FALSE,
      target = one_target,
      missing = setdiff(locked, installed),
      unexpected = setdiff(installed, locked)
    )
    result$satisfied <- identical(length(result$missing), 0L) &&
      identical(length(result$unexpected), 0L)
    n_diff <- length(result$missing) + length(result$unexpected)
    if (
      is.null(best) ||
        isTRUE(n_diff < length(best$missing) + length(best$unexpected))
    ) {
      best <- result
    }
    if (isTRUE(result$satisfied)) {
      break
    }
  }
  return(best)
}

#' Message bullets for the differences between an environment and a lock
#'
#' At most five records of each kind, then how many more.
#'
#' @param comparison The list from `compare_lock_records()`.
#'
#' @returns A named character vector of formatted `cli` bullets.
#'
#' @keywords internal
#' @noRd
lock_difference_bullets <- function(comparison) {
  shown <- function(x) {
    head_x <- utils::head(x, 5L)
    more <- length(x) - length(head_x)
    text <- cli::format_inline("{.val {head_x}}")
    if (isTRUE(more > 0L)) {
      text <- paste0(text, cli::format_inline(", and {more} more"))
    }
    return(cli_escape(text))
  }
  bullets <- character(0L)
  if (isTRUE(length(comparison$missing) > 0L)) {
    bullets <- c(
      bullets,
      `x` = paste0(
        "In the lock file, not in the environment: ",
        shown(comparison$missing),
        "."
      )
    )
  }
  if (isTRUE(length(comparison$unexpected) > 0L)) {
    bullets <- c(
      bullets,
      `x` = paste0(
        "In the environment, not in the lock file: ",
        shown(comparison$unexpected),
        "."
      )
    )
  }
  if (isFALSE(is.na(comparison$target))) {
    target <- comparison$target
    bullets <- c(
      bullets,
      `i` = cli_escape(cli::format_inline(
        "Compared with the packages for platform {.val {target}}."
      ))
    )
  }
  return(bullets)
}
