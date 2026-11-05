#' Name of a backend object, for messages
#'
#' @param backend A backend object.
#'
#' @returns Character string: the registered name of the backend's class,
#'   or its first class when no registered backend has that class.
#'
#' @keywords internal
#' @noRd
backend_display_name <- function(backend) {
  backend_class <- class(backend)[[1L]]
  registered <- registered_names_for_class(backend_class)
  if (isTRUE(length(registered) > 0L)) {
    return(registered[[1L]])
  }
  return(backend_class)
}

#' Abort for a value that breaks the backend contract
#'
#' @param generic Character string, the generic that returned the value.
#' @param backend_name Character string.
#' @param rule Character string, the rule the value breaks, as a cli text.
#' @param value The value, described in the message.
#' @param call Environment of the function the error is reported for.
#' @param .envir Environment for the interpolation of `rule`.
#'
#' @returns Does not return.
#'
#' @keywords internal
#' @noRd
abort_backend_invalid_return <- function(
  generic,
  backend_name,
  rule,
  value,
  call,
  .envir = parent.frame()
) {
  message_env <- rlang::env(
    .envir,
    generic = generic,
    backend_name = backend_name,
    value = value
  )
  returned <- if (isTRUE(rlang::is_string(value))) {
    "It returned {.val {value}}."
  } else {
    "It returned {.obj_type_friendly {value}}."
  }
  condathis_abort(
    message = c(
      `x` = "Backend {.field {backend_name}} returned an invalid value from {.fn {generic}}.",
      `i` = rule,
      `i` = returned
    ),
    class = c(
      "condathis_backend_invalid_return",
      "condathis_backend_contract_violation"
    ),
    call = call,
    .envir = message_env
  )
}

#' The columns `backend_list_packages()` must return, with their types
#'
#' @keywords internal
#' @noRd
backend_list_packages_columns <- c(
  name = "character",
  version = "character",
  build_number = "integer",
  build_string = "character",
  channel = "character",
  platform = "character"
)

#' Check the value a backend query generic returned
#'
#' condathis checks what the query generics return at the boundary, so a
#' bad backend fails with one clear error, and not later in unrelated
#' code. The rules, per generic:
#'
#' * `"backend_list_envs"`: a character vector without `NA` or duplicates.
#'   Returns it unnamed and without a class.
#' * `"backend_env_exists"`: a single `TRUE` or `FALSE`. Returns it without
#'   attributes.
#' * `"backend_list_packages"`: a data frame with the columns `name`,
#'   `version`, `build_string`, `channel`, `platform` (character) and
#'   `build_number` (integer). An integer-valued double `build_number` is
#'   made integer. Returns the data frame, with its class.
#' * `"backend_get_env_dir"`: a single, non-`NA`, absolute path. Returns an
#'   `fs_path`.
#' * `"backend_get_install_dir"`: a single, non-`NA`, absolute path of an
#'   existing directory. Returns an `fs_path`.
#' * `"backend_native_platform"`: a single, non-empty string, or a single
#'   `NA`. Returns a character string, `NA_character_` for `NA`.
#' * `"backend_can_solve"`: a single `TRUE`, `FALSE` or `NA`. Returns it
#'   without attributes.
#' * `"backend_quiesce"` and `"backend_available"`: a single `TRUE` or
#'   `FALSE`. Returns it without attributes.
#'
#' A value that breaks its rule aborts with
#' `c("condathis_backend_invalid_return",
#' "condathis_backend_contract_violation", "condathis_error")`, naming the
#' backend and the generic.
#'
#' @param value The returned value.
#' @param generic Character string, one of the generic names above.
#' @param backend_name Character string, the backend name for the message.
#'   It is only evaluated for an invalid value, so
#'   `backend_display_name(backend)` costs nothing on success.
#' @param call Environment of the function the error is reported for.
#'
#' @returns The normalized value.
#'
#' @keywords internal
#' @noRd
validate_backend_return <- function(
  value,
  generic,
  backend_name,
  call = rlang::caller_env()
) {
  invalid <- function(rule, .envir = parent.frame()) {
    abort_backend_invalid_return(
      generic = generic,
      backend_name = backend_name,
      rule = rule,
      value = value,
      call = call,
      .envir = .envir
    )
  }
  if (identical(generic, "backend_list_envs")) {
    if (
      isFALSE(is.character(value)) ||
        isTRUE(anyNA(value)) ||
        isTRUE(anyDuplicated(value) > 0L)
    ) {
      invalid(
        "It must return a character vector of environment names, without {.val {NA}} or duplicates."
      )
    }
    return(unname(as.character(value)))
  }
  if (identical(generic, "backend_env_exists")) {
    if (isFALSE(rlang::is_bool(value))) {
      invalid("It must return {.code TRUE} or {.code FALSE}.")
    }
    return(isTRUE(value))
  }
  if (identical(generic, "backend_list_packages")) {
    return(validate_list_packages_return(value, invalid = invalid))
  }
  if (identical(generic, "backend_native_platform")) {
    if (
      isTRUE(rlang::is_scalar_atomic(value)) &&
        isTRUE(is.na(value)) &&
        (isTRUE(is.logical(value)) || isTRUE(is.character(value)))
    ) {
      return(NA_character_)
    }
    if (isFALSE(rlang::is_string(value)) || isFALSE(nzchar(value))) {
      invalid(
        "It must return one platform name, such as {.val linux-64}, or {.val {NA}}."
      )
    }
    return(as.character(value))
  }
  if (identical(generic, "backend_can_solve")) {
    if (isFALSE(rlang::is_scalar_logical(value))) {
      invalid("It must return {.code TRUE}, {.code FALSE} or {.code NA}.")
    }
    return(as.logical(unname(c(value))))
  }
  if (generic %in% c("backend_quiesce", "backend_available")) {
    if (isFALSE(rlang::is_bool(value))) {
      invalid("It must return {.code TRUE} or {.code FALSE}.")
    }
    return(isTRUE(value))
  }
  if (generic %in% c("backend_get_env_dir", "backend_get_install_dir")) {
    is_path <- isTRUE(rlang::is_string(value)) &&
      isTRUE(fs::is_absolute_path(value))
    if (identical(generic, "backend_get_env_dir")) {
      if (isFALSE(is_path)) {
        invalid("It must return a single, absolute path.")
      }
      return(fs::path(value))
    }
    if (isFALSE(is_path) || isFALSE(isTRUE(fs::dir_exists(value)))) {
      invalid("It must return the absolute path of an existing directory.")
    }
    return(fs::path(value))
  }
  condathis_abort(
    message = "No return rule for {.fn {generic}}.",
    .internal = TRUE
  )
}

#' Check the data frame of `backend_list_packages()`
#'
#' @param value The returned value.
#' @param invalid Function that aborts, from `validate_backend_return()`.
#'
#' @returns The data frame, with an integer `build_number`.
#'
#' @keywords internal
#' @noRd
validate_list_packages_return <- function(value, invalid) {
  if (isFALSE(is.data.frame(value))) {
    invalid(
      "It must return a data frame with the columns {.field {names(backend_list_packages_columns)}}."
    )
  }
  missing_columns <- setdiff(names(backend_list_packages_columns), names(value))
  if (isTRUE(length(missing_columns) > 0L)) {
    invalid("Missing column{?s}: {.field {missing_columns}}.")
  }
  build_number <- value[["build_number"]]
  if (
    isTRUE(is.double(build_number)) &&
      isTRUE(all(is.na(build_number) | build_number == trunc(build_number))) &&
      isTRUE(all(abs(build_number) <= .Machine$integer.max, na.rm = TRUE))
  ) {
    value[["build_number"]] <- as.integer(build_number)
  }
  wrong_type <- vapply(
    names(backend_list_packages_columns),
    function(column) {
      return(
        isFALSE(identical(
          typeof(value[[column]]),
          backend_list_packages_columns[[column]]
        )) ||
          isTRUE(is.object(value[[column]]))
      )
    },
    logical(1L)
  )
  if (isTRUE(any(wrong_type))) {
    bad_columns <- names(backend_list_packages_columns)[wrong_type]
    expected <- paste0(
      bad_columns,
      " (",
      backend_list_packages_columns[wrong_type],
      ")"
    )
    invalid("Column{?s} of the wrong type, expected: {.field {expected}}.")
  }
  return(value)
}

#' `backend_env_exists()`, with its return value checked
#'
#' @param backend An already-resolved backend object.
#' @param env_name Character string with the environment name.
#' @param verbose One of the five verbose strings. Probes pass `"silent"`.
#' @param call Environment of the function an invalid value is reported
#'   for.
#'
#' @returns `TRUE` or `FALSE`. A backend error passes unchanged. Any other
#'   value aborts with `condathis_backend_invalid_return`.
#'
#' @keywords internal
#' @noRd
backend_env_exists_checked <- function(
  backend,
  env_name,
  verbose = "silent",
  call = rlang::caller_env()
) {
  value <- backend_env_exists(backend, env_name = env_name, verbose = verbose)
  return(validate_backend_return(
    value,
    generic = "backend_env_exists",
    backend_name = backend_display_name(backend),
    call = call
  ))
}

#' `backend_list_envs()`, with its return value checked
#'
#' @param backend An already-resolved backend object.
#' @param verbose One of the five verbose strings.
#'
#' @returns An unnamed character vector of environment names.
#'
#' @keywords internal
#' @noRd
backend_list_envs_checked <- function(backend, verbose = "silent") {
  value <- backend_list_envs(backend, verbose = verbose)
  return(validate_backend_return(
    value,
    generic = "backend_list_envs",
    backend_name = backend_display_name(backend)
  ))
}

#' `backend_list_packages()`, with its return value checked
#'
#' @param backend An already-resolved backend object.
#' @param env_name Character string with the environment name.
#' @param verbose One of the five verbose strings.
#'
#' @returns A data frame with at least the six columns of
#'   `backend_list_packages_columns`.
#'
#' @keywords internal
#' @noRd
backend_list_packages_checked <- function(
  backend,
  env_name,
  verbose = "silent"
) {
  value <- backend_list_packages(
    backend,
    env_name = env_name,
    verbose = verbose
  )
  return(validate_backend_return(
    value,
    generic = "backend_list_packages",
    backend_name = backend_display_name(backend)
  ))
}

#' `backend_native_platform()`, with failures read as "cannot tell"
#'
#' An error from the backend counts as `NA`, so a broken probe never stops
#' the creation of an environment: there is then no emulation fallback,
#' and the backend reports its own error. A failed download of micromamba
#' is raised instead (see `probe_or_na()`). A value that breaks the
#' contract aborts.
#'
#' @param backend An already-resolved backend object.
#' @param call Environment of the function an invalid value is reported
#'   for.
#'
#' @returns A platform name, or `NA_character_`.
#'
#' @keywords internal
#' @noRd
backend_native_platform_checked <- function(
  backend,
  call = rlang::caller_env()
) {
  value <- probe_or_na(backend_native_platform(backend), na = NA_character_)
  return(validate_backend_return(
    value,
    generic = "backend_native_platform",
    backend_name = backend_display_name(backend),
    call = call
  ))
}

#' `backend_can_solve()`, with failures read as "cannot tell"
#'
#' As `backend_native_platform_checked()`: an error from the backend counts
#' as `NA`, a failed download of micromamba is raised, and a value that
#' breaks the contract aborts.
#'
#' @param backend An already-resolved backend object.
#' @param ... Passed to `backend_can_solve()` by name: `packages`,
#'   `env_file`, `channels`, `channel_priority`, `additional_channels` and
#'   `platform`.
#' @param call Environment of the function an invalid value is reported
#'   for.
#'
#' @returns `TRUE`, `FALSE` or `NA`.
#'
#' @keywords internal
#' @noRd
backend_can_solve_checked <- function(
  backend,
  ...,
  call = rlang::caller_env()
) {
  value <- probe_or_na(backend_can_solve(backend, ...), na = NA)
  return(validate_backend_return(
    value,
    generic = "backend_can_solve",
    backend_name = backend_display_name(backend),
    call = call
  ))
}

#' Evaluate a platform probe, with its errors read as "cannot tell"
#'
#' A failed download of micromamba (class
#' `condathis_install_micromamba_download_failed`) is not a broken probe:
#' the probes of the micromamba backend install micromamba as the create or
#' install that follows would, so that call would download it again, and
#' wait for every mirror a second time. It is raised.
#'
#' @param expr The probe call.
#' @param na The value for a failed probe.
#'
#' @returns The value of `expr`, or `na`.
#'
#' @keywords internal
#' @noRd
probe_or_na <- function(expr, na) {
  install_failure <- NULL
  value <- tryCatch(
    expr,
    error = function(e) {
      if (isTRUE(inherits(e, "condathis_install_micromamba_download_failed"))) {
        install_failure <<- e
      }
      return(na)
    }
  )
  if (isFALSE(is.null(install_failure))) {
    rlang::cnd_signal(install_failure)
  }
  return(value)
}

#' Wait until no registered backend works in the R process
#'
#' Calls `backend_quiesce()` of every registered backend, in
#' `backend_names_by_priority()` order, before condathis deletes
#' directories that such work may still write to (a sandbox, caches). A
#' failure, or a value that breaks the contract, becomes a warning with
#' class `c("condathis_backend_quiesce_failed", "condathis_warning")`, and
#' the next backend is asked: the caller goes on in every case.
#'
#' @param timeout Positive number, the seconds each backend may wait.
#' @param call Environment of the function that an invalid value is
#'   reported for: `clean_cache()` or `with_sandbox_dir()`.
#'
#' @returns `TRUE`, invisibly, when every backend reported that it is idle,
#'   else `FALSE`.
#'
#' @keywords internal
#' @noRd
quiesce_registered_backends <- function(
  timeout = 30,
  call = rlang::caller_env()
) {
  idle <- TRUE
  for (nm in backend_names_by_priority()) {
    backend <- get_backend(nm)
    answer <- tryCatch(
      validate_backend_return(
        backend_quiesce(backend, timeout = timeout),
        generic = "backend_quiesce",
        backend_name = nm,
        call = call
      ),
      error = function(e) {
        condathis_warn(
          message = c(
            `!` = "Backend {.field {nm}} could not tell whether it still works in this R process; condathis goes on."
          ),
          class = "condathis_backend_quiesce_failed",
          parent = e
        )
        return(FALSE)
      }
    )
    idle <- isTRUE(idle) && isTRUE(answer)
  }
  return(invisible(idle))
}

#' Probe whether a backend has an environment, distinguishing failure
#'
#' Rule R5: when condathis cannot tell whether an environment exists, it
#' never acts as if the environment were missing. This separates "the
#' backend says it is absent" (`FALSE`) from "the backend could not tell"
#' (`NA`): its `backend_env_exists()` failed, or returned a value that is
#' not `TRUE` or `FALSE`.
#'
#' Test the result with `is.na()`, `isTRUE()` and `isFALSE()`, never with
#' `identical()`: the `NA` carries an attribute.
#'
#' @param backend An already-resolved backend object.
#' @param env_name Character string with the environment name.
#' @param verbose One of the five verbose strings.
#'
#' @returns `TRUE`, `FALSE`, or `NA` with `attr(, "condition")`, the caught
#'   error.
#'
#' @keywords internal
#' @noRd
backend_probe_env <- function(backend, env_name, verbose = "silent") {
  return(tryCatch(
    backend_env_exists_checked(backend, env_name = env_name, verbose = verbose),
    error = function(e) structure(NA, condition = e)
  ))
}

#' Check whether a backend has an environment, never erroring
#'
#' `isTRUE(backend_probe_env(...))`: a failed probe reads as `FALSE`. No
#' exported code path decides anything on it (rule R5). It is kept for
#' internal callers that only need a hint.
#'
#' @param backend An already-resolved backend object.
#' @param env_name Character string with the environment name.
#' @param verbose One of the five verbose strings.
#'
#' @returns `TRUE` or `FALSE`.
#'
#' @keywords internal
#' @noRd
backend_has_env <- function(backend, env_name, verbose = "silent") {
  return(isTRUE(backend_probe_env(backend, env_name, verbose = verbose)))
}

#' Abort for an existence probe that failed, before a change
#'
#' Rule R5: condathis does not change an environment whose state it cannot
#' read. As every backend failure (rule R1), the error keeps the condathis
#' classes of the probe's error.
#'
#' @param cnd The probe's error, `attr(probe, "condition")` of a
#'   `backend_probe_env()` result.
#' @param backend_name Character string, the registered backend name.
#' @param env_name Character string with the environment name.
#' @param call Environment of the function the error is reported for.
#'
#' @returns Does not return. The error has the classes
#'   `c("condathis_backend_probe_failed", "condathis_backend_error", <the
#'   condathis_* classes of cnd>, "condathis_error")` and `cnd` as parent.
#'
#' @keywords internal
#' @noRd
abort_env_probe_failed <- function(
  cnd,
  backend_name,
  env_name,
  call = rlang::caller_env()
) {
  condathis_abort(
    message = c(
      `x` = "Backend {.field {backend_name}} could not check whether environment {.field {env_name}} exists.",
      `i` = "condathis does not change an environment whose state it cannot read."
    ),
    class = unique(c(
      "condathis_backend_probe_failed",
      "condathis_backend_error",
      setdiff(
        grep("^condathis_", class(cnd), value = TRUE),
        c("condathis_error", "condathis_warning")
      )
    )),
    parent = cnd,
    call = call
  )
}

#' Find every registered backend that already has a given environment
#'
#' Probes every registered backend, in `backend_names_by_priority()` order,
#' without gating on `backend_available()`: an existing environment under
#' an unavailable backend is still a conflict to report.
#'
#' A known backend that is not registered (see `known_backend_packages`)
#' and has a directory `<backend_root_dir(name)>/envs/<env_name>` aborts a
#' caller that changes the environment, and warns a read-only one (see
#' `check_unregistered_known_owners()`).
#'
#' A backend whose probe fails (`NA`, rule R5):
#' * aborts a caller that changes the environment (`mutating = TRUE`), with
#'   `c("condathis_backend_probe_failed", "condathis_backend_error", <the
#'   condathis_* classes of the probe's error>, "condathis_error")` and the
#'   probe's error as the parent;
#' * warns a read-only caller, with `c("condathis_backend_query_failed",
#'   "condathis_warning")`, and counts as not owning the environment.
#'
#' @param env_name Character string with the environment name.
#' @param mutating Logical. Whether the caller creates, changes or removes
#'   the environment.
#' @param verbose One of the five verbose strings, for the probes.
#' @param call Environment of the function the error is reported for.
#'
#' @returns Character vector of backend names that report `env_name`, in
#'   priority order. Length 0 (new environment), 1 (unambiguous owner), or
#'   more (collision).
#'
#' @keywords internal
#' @noRd
find_owning_backends <- function(
  env_name,
  mutating = FALSE,
  verbose = "silent",
  call = rlang::caller_env()
) {
  owners <- character(0L)
  for (nm in backend_names_by_priority()) {
    probe <- backend_probe_env(
      get_backend(nm, call = call),
      env_name = env_name,
      verbose = verbose
    )
    if (isTRUE(is.na(probe))) {
      cnd <- attr(probe, "condition")
      if (isTRUE(mutating)) {
        abort_env_probe_failed(
          cnd,
          backend_name = nm,
          env_name = env_name,
          call = call
        )
      }
      condathis_warn(
        message = c(
          `!` = "Backend {.field {nm}} could not check whether environment {.field {env_name}} exists; it is skipped."
        ),
        class = "condathis_backend_query_failed",
        parent = cnd
      )
      next
    }
    if (isTRUE(probe)) {
      owners <- c(owners, nm)
    }
  }
  # A known backend whose package is missing can still own the
  # environment: a change must not make a second owner of it.
  check_unregistered_known_owners(
    env_name,
    mutating = mutating,
    call = call
  )
  if (identical(length(owners), 1L)) {
    warn_on_backend_marker_mismatch(
      owners[[1L]],
      env_name = env_name,
      call = call
    )
  }
  return(owners)
}

#' Run one query on several registered backends
#'
#' The shared failure policy of the read-only queries `env_exists()`,
#' `list_envs()` and `get_install_dir()`:
#'
#' * `auto = FALSE` (an explicit `method`): a failing query aborts, as
#'   `with_backend_errors()` does, with
#'   `c("condathis_<fn>_failed", "condathis_backend_error", <the
#'   condathis_* classes of the backend's error>, "condathis_error")` and
#'   the backend's error as the parent.
#' * `auto = TRUE`: a failing backend warns with
#'   `c("condathis_backend_query_failed", "condathis_warning")` and is
#'   skipped. When every backend fails, it aborts as with `auto = FALSE`,
#'   for the first failure, without the warnings.
#'
#' With `auto = TRUE`, a known backend with environments is loaded first
#' (see `load_known_backends()`), and then asked like the others; one that
#' cannot be loaded warns once per session that its environments are
#' skipped (see `warn_unregistered_known_backends()`).
#'
#' `get_backend()` errors (an unregistered name) are not caught.
#'
#' @param backend_names Character vector of registered backend names. With
#'   `auto = TRUE`, it is `backend_names_by_priority()`, computed again
#'   when a known backend was loaded.
#' @param query Function of one argument, the backend object. Its value is
#'   kept as is, so return a value already checked with
#'   `validate_backend_return()` (for example from
#'   `backend_env_exists_checked()` or `backend_list_envs_checked()`).
#' @param auto Logical. `TRUE` for `method = "auto"`.
#' @param fn Character string, the exported function name, for the class.
#' @param action Character string, what the query does, as text to follow
#'   "failed to", for example `"list its environments"`. Not interpolated.
#' @param call Environment of the function the error is reported for.
#'
#' @returns A list of the query results, named by backend, without the
#'   skipped backends.
#'
#' @keywords internal
#' @noRd
query_registered_backends <- function(
  backend_names,
  query,
  auto,
  fn,
  action,
  call = rlang::caller_env()
) {
  if (isTRUE(auto)) {
    # A known backend with environments is loaded, so it is asked too.
    if (isTRUE(length(load_known_backends(call = call)) > 0L)) {
      backend_names <- backend_names_by_priority()
    }
    warn_unregistered_known_backends()
  }
  results <- list()
  failures <- list()
  for (nm in backend_names) {
    backend <- get_backend(nm, call = call)
    if (isFALSE(auto)) {
      results[nm] <- list(with_backend_errors(
        query(backend),
        fn = fn,
        backend_name = nm,
        action = action,
        call = call
      ))
      next
    }
    failure <- NULL
    value <- tryCatch(
      query(backend),
      error = function(e) {
        failure <<- e
        return(NULL)
      }
    )
    if (isFALSE(is.null(failure))) {
      failures[[nm]] <- failure
      next
    }
    results[nm] <- list(value)
  }

  if (
    isTRUE(length(failures) > 0L) &&
      identical(length(failures), length(backend_names))
  ) {
    abort_backend_failure(
      cnd = failures[[1L]],
      fn = fn,
      backend_name = names(failures)[[1L]],
      action = action,
      call = call
    )
  }
  for (nm in names(failures)) {
    condathis_warn(
      message = c(
        `!` = "Backend {.field {nm}} failed to {action}; it is skipped."
      ),
      class = "condathis_backend_query_failed",
      parent = failures[[nm]]
    )
  }
  return(results)
}

#' Abort when the last package spec is an existing environment name
#'
#' Decision D6: `create_env("pkg", "env")` and `install_packages("pkg",
#' "env")` now mean two package specs. When the last of two or more specs
#' is the name of an environment that exists, the user most likely meant
#' the old positional `env_name`. Call this only when `env_name` was not
#' given (`missing(env_name)` in the exported function).
#'
#' It probes every registered backend with `backend_probe_env()`; a failed
#' probe counts as "no". The micromamba backend answers without starting a
#' process. Known backend packages with environments are loaded first, as
#' `resolve_backend()` would load them (see `load_known_backends()`), and an
#' environment directory of a known backend that still is not registered,
#' `<backend_root_dir(name)>/envs/<name>`, counts as an existing
#' environment too: otherwise the check missed the environments of a
#' backend that no call had loaded yet, and the specs went to micromamba.
#'
#' @param specs Character vector from `collect_package_specs()`.
#' @param fn Character string, the exported function name.
#' @param call Environment of the function the error is reported for.
#'
#' @returns `NULL`, invisibly. Aborts with
#'   `c("condathis_<fn>_positional_env_name", "condathis_invalid_packages",
#'   "condathis_invalid_arg", "condathis_error")` and the hint
#'   `env_name = "<name>"`.
#'
#' @keywords internal
#' @noRd
abort_on_positional_env_name <- function(
  specs,
  fn,
  call = rlang::caller_env()
) {
  if (isTRUE(length(specs) < 2L)) {
    return(invisible(NULL))
  }
  candidate <- specs[[length(specs)]]
  if (isFALSE(is_valid_env_name(candidate))) {
    return(invisible(NULL))
  }
  load_known_backends(call = call)
  is_env_name <- any(vapply(
    unregistered_known_backend_names(),
    function(name) {
      return(isTRUE(fs::dir_exists(
        fs::path(backend_root_path(name), "envs", candidate)
      )))
    },
    logical(1L)
  ))
  for (nm in backend_names_by_priority()) {
    if (isTRUE(is_env_name)) {
      break
    }
    is_env_name <- isTRUE(
      backend_probe_env(get_backend(nm, call = call), candidate)
    )
  }
  if (isTRUE(is_env_name)) {
    condathis_abort(
      message = c(
        `x` = "The last package spec, {.val {candidate}}, is the name of an existing environment.",
        `i` = "Name the environment: {.code env_name = \"{candidate}\"}."
      ),
      class = c(
        paste0("condathis_", fn, "_positional_env_name"),
        "condathis_invalid_packages",
        "condathis_invalid_arg"
      ),
      call = call
    )
  }
  return(invisible(NULL))
}

#' Warn if an environment's on-disk backend marker disagrees with its
#' structurally-determined owner
#'
#' Defense-in-depth only (see `read_backend_marker()`). Never changes which
#' backend is used, only reports the inconsistency. The comparison needs a
#' single, structurally-determined owner. Collisions and new environments
#' have nothing to check.
#'
#' @param owner Character string, the backend name `find_owning_backends()`
#'   already determined structurally.
#' @param env_name Character string with the environment name.
#' @param call Environment of the function that an invalid
#'   `backend_get_env_dir()` value is reported for.
#'
#' @keywords internal
#' @noRd
warn_on_backend_marker_mismatch <- function(
  owner,
  env_name,
  call = rlang::caller_env()
) {
  env_dir <- env_dir_for_backend(
    get_backend(owner, call = call),
    env_name = env_name,
    call = call
  )
  marker <- read_backend_marker(env_dir)
  if (isFALSE(is.null(marker)) && isFALSE(identical(marker$backend, owner))) {
    condathis_warn(
      message = c(
        `!` = "Environment {.field {env_name}}'s backend marker says {.field {marker$backend}}, but it was found under backend {.field {owner}}.",
        `i` = "Using {.field {owner}}, the structurally-determined owner."
      ),
      class = "condathis_backend_marker_mismatch"
    )
  }
  return(invisible(NULL))
}

#' Install root of a single, already-resolved backend
#'
#' `backend_get_install_dir()`, with its value checked (see
#' `validate_backend_return()`). Gives internal call sites a bare-path
#' primitive instead of the public, multi-backend `get_install_dir()`,
#' which returns a tibble.
#'
#' @param backend An already-resolved backend object.
#' @param call Environment of the function an invalid value is reported
#'   for.
#'
#' @returns An `fs_path`: an absolute path of an existing directory.
#'
#' @keywords internal
#' @noRd
install_dir_for_backend <- function(backend, call = rlang::caller_env()) {
  return(validate_backend_return(
    backend_get_install_dir(backend),
    generic = "backend_get_install_dir",
    backend_name = backend_display_name(backend),
    call = call
  ))
}

#' Environment directory under a single, already-resolved backend
#'
#' `backend_get_env_dir()`, with its value checked. Same rationale as
#' `install_dir_for_backend()`, for `get_env_dir()`.
#'
#' @param backend An already-resolved backend object.
#' @param env_name Character string with the environment name.
#' @param call Environment of the function an invalid value is reported
#'   for.
#'
#' @returns An `fs_path`: an absolute path. The directory need not exist.
#'
#' @keywords internal
#' @noRd
env_dir_for_backend <- function(
  backend,
  env_name,
  call = rlang::caller_env()
) {
  return(validate_backend_return(
    backend_get_env_dir(backend, env_name = env_name),
    generic = "backend_get_env_dir",
    backend_name = backend_display_name(backend),
    call = call
  ))
}

#' Read an environment's backend marker file, if present
#'
#' Defense-in-depth only, never the discovery mechanism: directory placement
#' under a backend's own root already determines ownership (see
#' `find_owning_backends()`). Used only to cross-check and warn on
#' disagreement, and for the platform of the environment (see
#' `read_backend_marker_platform()`).
#'
#' @returns A list with `backend`, `schema_version` and, for an environment
#'   created for a given or emulated platform, `platform`. `NULL` if the
#'   marker does not exist or cannot be read.
#'
#' @keywords internal
#' @noRd
read_backend_marker <- function(env_dir) {
  marker_path <- fs::path(env_dir, ".condathis", "backend.json")
  if (isFALSE(fs::file_exists(marker_path))) {
    return(NULL)
  }
  return(tryCatch(
    jsonlite::fromJSON(marker_path),
    error = function(e) NULL
  ))
}

#' The platform that an environment's backend marker records
#'
#' @param env_dir Character string, the directory of the environment.
#'
#' @returns The `platform` of the marker when it is one of
#'   `known_platforms`, else `NULL`: no marker, a marker without a platform
#'   (an environment for the native platform, or one of an older
#'   condathis), or a marker that cannot be read.
#'
#' @keywords internal
#' @noRd
read_backend_marker_platform <- function(env_dir) {
  marker <- read_backend_marker(env_dir)
  if (isFALSE(is.list(marker))) {
    return(NULL)
  }
  platform <- marker[["platform"]]
  if (
    isFALSE(rlang::is_string(platform)) ||
      isFALSE(platform %in% known_platforms)
  ) {
    return(NULL)
  }
  return(platform)
}

#' Write an environment's backend marker file
#'
#' Called by the public `create_env()` wrapper after a successful
#' `backend_create_env()` call, never from a `backend_create_env.*` method.
#' This keeps the marker format in one place, written by `condathis` rather
#' than by each backend.
#'
#' @param env_dir Character string, the directory of the environment.
#' @param backend_name Character string, the registered backend name.
#' @param platform `NULL`, or the platform that the environment was created
#'   for: given by the user or chosen by the emulation fallback (see
#'   `resolve_create_platform()`). Recorded only when it is not `NULL`, for
#'   later installs (see `env_platform()`).
#'
#' @keywords internal
#' @noRd
write_backend_marker <- function(env_dir, backend_name, platform = NULL) {
  marker_dir <- fs::path(env_dir, ".condathis")
  if (isFALSE(fs::dir_exists(marker_dir))) {
    fs::dir_create(marker_dir)
  }
  marker <- list(backend = backend_name, schema_version = 1L)
  marker[["platform"]] <- platform
  jsonlite::write_json(
    marker,
    path = fs::path(marker_dir, "backend.json"),
    auto_unbox = TRUE
  )
  return(invisible(NULL))
}
