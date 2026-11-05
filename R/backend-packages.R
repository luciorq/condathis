#' Backend packages that condathis knows by name
#'
#' Names are backend names, values the packages that register them. condathis
#' loads such a package on demand (see `load_known_backends()`), so a user
#' never has to load it. condathis declares none of them in its
#' `DESCRIPTION`: the name is only read here, at run time.
#'
#' @keywords internal
#' @noRd
known_backend_packages <- c(rattler = "rattlerthis")

#' Session state of the on-demand loading of known backend packages
#'
#' `loading` is `TRUE` while a package loads, so a backend's `.onLoad()`
#' that calls a condathis function taking `method` does not load again.
#' `failures` holds, per backend name, the failure of a package that could
#' not be loaded or did not register its backend: it is tried once per
#' session.
#'
#' @keywords internal
#' @noRd
known_backend_state <- new.env(parent = emptyenv())
known_backend_state$loading <- FALSE
known_backend_state$failures <- list()

#' Forget the failures of known backend packages
#'
#' For tests.
#'
#' @returns `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
reset_known_backend_state <- function() {
  known_backend_state$loading <- FALSE
  known_backend_state$failures <- list()
  return(invisible(NULL))
}

#' Load a backend package
#'
#' A wrapper of `loadNamespace()` that keeps the error, so tests can mock
#' it. `tests/testthat/setup.R` mocks it for the whole suite: an installed
#' backend package is never loaded into a test process.
#'
#' @param pkg Character string, the package name.
#'
#' @returns `TRUE` when the namespace is loaded. Otherwise `FALSE`, with the
#'   error of `loadNamespace()` as `attr(, "condition")`: of class
#'   `packageNotFoundError` when the package is not installed.
#'
#' @keywords internal
#' @noRd
load_backend_namespace <- function(pkg) {
  failure <- NULL
  loaded <- tryCatch(
    {
      loadNamespace(pkg)
      TRUE
    },
    error = function(e) {
      failure <<- e
      return(FALSE)
    }
  )
  if (isTRUE(loaded)) {
    return(TRUE)
  }
  return(structure(FALSE, condition = failure))
}

#' Is the namespace of a backend package loaded?
#'
#' A wrapper of `isNamespaceLoaded()`, so tests can mock it.
#'
#' @param pkg Character string, the package name.
#'
#' @returns `TRUE` or `FALSE`.
#'
#' @keywords internal
#' @noRd
backend_namespace_loaded <- function(pkg) {
  return(isTRUE(isNamespaceLoaded(pkg)))
}

#' Is a backend package installed?
#'
#' A wrapper, so tests can mock it. It reads the library, and loads
#' nothing.
#'
#' @param pkg Character string, the package name.
#'
#' @returns `TRUE` or `FALSE`.
#'
#' @keywords internal
#' @noRd
backend_package_installed <- function(pkg) {
  return(isTRUE(nzchar(system.file(package = pkg))))
}

#' Known backends that are installed but not registered yet
#'
#' For the message of an invalid `method`: these are valid values too,
#' loaded on first use. A package that already failed to load or to
#' register its backend in this session is left out: it is not tried
#' again, so its name would fail.
#'
#' @returns Character vector of backend names.
#'
#' @keywords internal
#' @noRd
installed_known_backend_names <- function() {
  candidates <- unregistered_known_backend_names()
  installed <- vapply(
    candidates,
    function(name) {
      return(
        is.null(known_backend_state$failures[[name]]) &&
          isFALSE(backend_namespace_loaded(known_backend_packages[[name]])) &&
          isTRUE(backend_package_installed(known_backend_packages[[name]]))
      )
    },
    logical(1L),
    USE.NAMES = FALSE
  )
  return(candidates[installed])
}

#' Known backends that are not registered
#'
#' @returns Character vector of backend names.
#'
#' @keywords internal
#' @noRd
unregistered_known_backend_names <- function() {
  return(setdiff(
    names(known_backend_packages),
    list_registered_backend_names()
  ))
}

#' Load the known backend packages that a call needs
#'
#' A known backend (see `known_backend_packages`) that is not registered is
#' loaded:
#'
#' * when `method` names it: then a failure aborts, with the classes of an
#'   invalid `method` and `condathis_backend_not_installed` (the package is
#'   not installed) or `condathis_backend_load_failed` (it failed to load,
#'   did not register its backend, or is loaded but its backend was
#'   unregistered in this session);
#' * when its backend has environments (`backend_has_env_dirs()`), with
#'   `caches = TRUE` also when its root has any other entry, and with
#'   `priority = TRUE` also when the option `condathis.backend_priority`
#'   names its backend: then a package that is not installed is skipped
#'   silently, and a package that fails warns with
#'   `c("condathis_backend_load_failed", "condathis_warning")`, once per
#'   session and backend (see `known_backend_warn_id()`).
#'
#' The bare existence of a backend's root loads nothing: `get_install_dir()`
#' creates the root of every registered backend. A package that failed is
#' not tried again in the session. While a package loads, the calls of its
#' `.onLoad()` load nothing.
#'
#' @param method `NULL`, or the `method` value of the call.
#' @param caches Logical. `TRUE` for `clean_cache()`.
#' @param priority Logical. `TRUE` when `method = "auto"` chooses the
#'   backend of a new environment (see `resolve_backend_by_priority()`):
#'   the option then decides, whatever was loaded earlier in the session.
#' @param call Environment of the function the error is reported for.
#'
#' @returns Character vector, the backend names that were loaded and
#'   registered, invisibly.
#'
#' @keywords internal
#' @noRd
load_known_backends <- function(
  method = NULL,
  caches = FALSE,
  priority = FALSE,
  call = rlang::caller_env()
) {
  loaded <- character(0L)
  if (isTRUE(known_backend_state$loading)) {
    return(invisible(loaded))
  }
  prioritized <- character(0L)
  if (isTRUE(priority)) {
    option <- getOption("condathis.backend_priority")
    if (isTRUE(is.character(option)) && isFALSE(anyNA(option))) {
      prioritized <- option
    }
  }
  for (name in unregistered_known_backend_names()) {
    named <- isTRUE(identical(method, name))
    in_priority <- isTRUE(name %in% prioritized)
    if (
      isFALSE(named) &&
        isFALSE(in_priority) &&
        isFALSE(backend_has_env_dirs(name)) &&
        isFALSE(isTRUE(caches) && isTRUE(backend_has_cache_entries(name)))
    ) {
      next
    }
    status <- load_known_backend(name)
    if (isTRUE(status$ok)) {
      loaded <- c(loaded, name)
      next
    }
    if (isTRUE(named)) {
      abort_known_backend_unloaded(name, status = status, call = call)
    }
    if (isTRUE(status$reason %in% c("load_failed", "not_registered"))) {
      warn_known_backend_load_failed(
        name,
        status = status,
        why = if (isTRUE(in_priority)) "priority" else "data"
      )
    }
  }
  return(invisible(loaded))
}

#' Load the package of one known backend
#'
#' @param name Character string, a name of `known_backend_packages`.
#'
#' @returns A list: `ok` (`TRUE` when the backend is registered now),
#'   `reason` (`NULL`, or `"not_installed"`, `"load_failed"`,
#'   `"not_registered"` or `"unregistered"`) and `cnd` (the load error, or
#'   `NULL`).
#'
#' @keywords internal
#' @noRd
load_known_backend <- function(name) {
  failure <- known_backend_state$failures[[name]]
  if (isFALSE(is.null(failure))) {
    return(failure)
  }
  pkg <- known_backend_packages[[name]]
  # Loaded, but not registered: its backend was unregistered in this
  # session. Unloading and loading the package again is not safe for a
  # package with a compiled library that runs threads.
  if (isTRUE(backend_namespace_loaded(pkg))) {
    return(list(ok = FALSE, reason = "unregistered", cnd = NULL))
  }
  was_loading <- known_backend_state$loading
  known_backend_state$loading <- TRUE
  on.exit(known_backend_state$loading <- was_loading, add = TRUE)
  res <- load_backend_namespace(pkg)
  known_backend_state$loading <- was_loading
  if (isTRUE(res)) {
    if (isTRUE(name %in% list_registered_backend_names())) {
      return(list(ok = TRUE, reason = NULL, cnd = NULL))
    }
    status <- list(ok = FALSE, reason = "not_registered", cnd = NULL)
    known_backend_state$failures[[name]] <- status
    return(status)
  }
  cnd <- attr(res, "condition")
  if (is.null(cnd) || isTRUE(inherits(cnd, "packageNotFoundError"))) {
    # Not recorded: the package can be installed later in the session.
    return(list(ok = FALSE, reason = "not_installed", cnd = cnd))
  }
  status <- list(ok = FALSE, reason = "load_failed", cnd = cnd)
  known_backend_state$failures[[name]] <- status
  return(status)
}

#' Why a known backend is not registered
#'
#' @param name Character string, a name of `known_backend_packages`.
#'
#' @returns A list as from `load_known_backend()`, without loading
#'   anything: the recorded failure, `"unregistered"` for a loaded
#'   package, else `"not_installed"`.
#'
#' @keywords internal
#' @noRd
known_backend_unloaded_status <- function(name) {
  failure <- known_backend_state$failures[[name]]
  if (isFALSE(is.null(failure))) {
    return(failure)
  }
  if (isTRUE(backend_namespace_loaded(known_backend_packages[[name]]))) {
    return(list(ok = FALSE, reason = "unregistered", cnd = NULL))
  }
  return(list(ok = FALSE, reason = "not_installed", cnd = NULL))
}

#' Why a known backend is not registered, as a clause of a message
#'
#' @param reason The `reason` of a status from `load_known_backend()`:
#'   `"not_installed"`, `"load_failed"`, `"not_registered"` or
#'   `"unregistered"`.
#' @param form `"whose"` for a clause after the backend name ("backend x,
#'   whose package ..."), `"its"` for a clause of its own ("its package
#'   ...").
#'
#' @returns A cli template that uses the variable `pkg`, the package.
#'
#' @keywords internal
#' @noRd
known_backend_cause <- function(reason, form = c("whose", "its")) {
  form <- rlang::arg_match(form)
  if (identical(reason, "unregistered")) {
    return(paste(
      if (identical(form, "whose")) "which" else "it",
      "was unregistered in this session"
    ))
  }
  package <- paste(form, "package {.pkg {pkg}}")
  return(paste(
    package,
    switch(
      reason,
      not_installed = "is not installed",
      not_registered = "loaded without registering it",
      "could not be loaded"
    )
  ))
}

#' What a user can do about an environment of a known backend that is not
#' registered
#'
#' @param reason As in `known_backend_cause()`.
#'
#' @returns A cli template that uses the variables `pkg` and `env_dir`.
#'
#' @keywords internal
#' @noRd
known_backend_remedy <- function(reason) {
  return(switch(
    reason,
    not_installed = "Install {.pkg {pkg}}, or delete {.path {env_dir}}.",
    unregistered = "Restart R to use it, or delete {.path {env_dir}}.",
    not_registered = "Update {.pkg {pkg}}, or delete {.path {env_dir}}.",
    "Repair {.pkg {pkg}}, or delete {.path {env_dir}}."
  ))
}

#' The known backend that owns the directory of an environment
#'
#' The owner search cannot ask a known backend that is not registered
#' (see `check_unregistered_known_owners()`). This finds the one whose
#' root has `<root>/envs/<env_name>` as a directory, so that an error for
#' a missing environment can say why it is missing.
#'
#' @param env_name Character string, an environment name, or the directory
#'   of an environment given by `env_path()`, which no backend root holds.
#'
#' @returns `NULL`, or a list: `name` (the backend), `pkg`, `env_dir` and
#'   `status` (from `known_backend_unloaded_status()`).
#'
#' @keywords internal
#' @noRd
unregistered_known_owner <- function(env_name) {
  if (
    isTRUE(known_backend_state$loading) ||
      isFALSE(isTRUE(is_valid_env_name(env_name)))
  ) {
    return(NULL)
  }
  for (name in unregistered_known_backend_names()) {
    env_dir <- fs::path(backend_root_path(name), "envs", env_name)
    if (isTRUE(fs::dir_exists(env_dir))) {
      return(list(
        name = name,
        pkg = known_backend_packages[[name]],
        env_dir = env_dir,
        status = known_backend_unloaded_status(name)
      ))
    }
  }
  return(NULL)
}

#' Abort for a `method` that names a known backend that cannot be loaded
#'
#' @param name Character string, the backend name.
#' @param status A failed status from `load_known_backend()`.
#' @param call Environment of the function the error is reported for.
#'
#' @returns Does not return. The error has the classes of an invalid
#'   `method` after `condathis_backend_not_installed` or
#'   `condathis_backend_load_failed`, and the load error as its parent.
#'
#' @keywords internal
#' @noRd
abort_known_backend_unloaded <- function(name, status, call) {
  pkg <- known_backend_packages[[name]]
  method_class <- c(
    "condathis_invalid_method",
    "condathis_invalid_method_arg",
    "condathis_invalid_arg"
  )
  message <- switch(
    status$reason,
    not_installed = c(
      `x` = "Backend {.field {name}} needs the {.pkg {pkg}} package.",
      `i` = "Install it."
    ),
    load_failed = c(
      `x` = "Backend {.field {name}} is not available: its package {.pkg {pkg}} could not be loaded."
    ),
    not_registered = c(
      `x` = "Backend {.field {name}} is not available: its package {.pkg {pkg}} was loaded, but it did not register the backend."
    ),
    c(
      `x` = "{.pkg {pkg}} is loaded but backend {.field {name}} is not registered; it was unregistered in this session.",
      `i` = "Restart R to use it."
    )
  )
  first_class <- if (identical(status$reason, "not_installed")) {
    "condathis_backend_not_installed"
  } else {
    "condathis_backend_load_failed"
  }
  condathis_abort(
    message = message,
    class = c(first_class, method_class),
    parent = status$cnd,
    call = call
  )
}

#' The id of the once-per-session warning about a known backend
#'
#' One id per backend for every warning that a known backend is skipped:
#' its package failed to load (`warn_known_backend_load_failed()`), an
#' environment of it was skipped (`check_unregistered_known_owners()`), or
#' a query skipped its environments (`warn_unregistered_known_backends()`).
#' So a session gets at most one of them per backend.
#'
#' @param name Character string, the backend name.
#'
#' @returns Character string.
#'
#' @keywords internal
#' @noRd
known_backend_warn_id <- function(name) {
  return(paste0("known_backend_unavailable_", name))
}

#' Warn once that a known backend could not be loaded
#'
#' @param name Character string, the backend name.
#' @param status A failed status from `load_known_backend()`.
#' @param why `"data"` when the backend has environments or caches,
#'   `"priority"` when the option `condathis.backend_priority` names it.
#'
#' @returns `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
warn_known_backend_load_failed <- function(
  name,
  status,
  why = c("data", "priority")
) {
  why <- rlang::arg_match(why)
  pkg <- known_backend_packages[[name]]
  root <- backend_root_path(name)
  cause <- known_backend_cause(status$reason, form = "its")
  message <- if (identical(why, "priority")) {
    c(
      `!` = paste0(
        "Option {.code condathis.backend_priority} names backend {.field {name}}, but ",
        cause,
        "."
      ),
      `i` = "condathis uses the next backend in this session."
    )
  } else {
    c(
      `!` = paste0(
        "Backend {.field {name}} has environments or caches in {.path {root}}, but ",
        cause,
        "."
      ),
      `i` = "condathis skips them in this session."
    )
  }
  condathis_warn_once(
    id = known_backend_warn_id(name),
    message = message,
    class = "condathis_backend_load_failed",
    parent = status$cnd
  )
  return(invisible(NULL))
}

#' Check the environments of known backends that are not registered
#'
#' The owner search of `find_owning_backends()` cannot ask a backend whose
#' package is missing. Without this check, `create_env("x")` with another
#' backend would make a second owner of `x`, and once the package is back,
#' every call on `x` would abort as ambiguous. So a known backend that is
#' not registered owns `env_name` when `<backend_root_dir(name)>/envs/<env_name>`
#' is a directory: one file system check, no package needed.
#'
#' @param env_name Character string with the environment name.
#' @param mutating Logical. `TRUE` for a call that changes the environment.
#' @param call Environment of the function the error is reported for.
#'
#' @returns `NULL`, invisibly. A change aborts with
#'   `c("condathis_backend_not_installed", "condathis_backend_mismatch",
#'   "condathis_error")` (`condathis_backend_load_failed` instead of the
#'   first class when the package is installed but could not be used). A
#'   query warns once per session and backend, with
#'   `c("condathis_backend_not_installed", "condathis_warning")` (or
#'   `condathis_backend_load_failed`).
#'
#' @keywords internal
#' @noRd
check_unregistered_known_owners <- function(
  env_name,
  mutating,
  call = rlang::caller_env()
) {
  # The `.onLoad()` of a backend package runs before its backend is
  # registered.
  if (isTRUE(known_backend_state$loading)) {
    return(invisible(NULL))
  }
  for (name in unregistered_known_backend_names()) {
    env_dir <- fs::path(backend_root_path(name), "envs", env_name)
    if (isFALSE(fs::dir_exists(env_dir))) {
      next
    }
    pkg <- known_backend_packages[[name]]
    status <- known_backend_unloaded_status(name)
    first_class <- known_backend_condition_class(status)
    cause <- known_backend_cause(status$reason, form = "whose")
    remedy <- known_backend_remedy(status$reason)
    if (isTRUE(mutating)) {
      condathis_abort(
        message = c(
          `x` = paste0(
            "Environment {.field {env_name}} belongs to backend {.field {name}}, ",
            cause,
            "."
          ),
          `i` = remedy
        ),
        class = c(first_class, "condathis_backend_mismatch"),
        parent = status$cnd,
        call = call
      )
    }
    condathis_warn_once(
      id = known_backend_warn_id(name),
      message = c(
        `!` = paste0(
          "Environment {.field {env_name}} belongs to backend {.field {name}}, ",
          cause,
          "; it is skipped."
        ),
        `i` = remedy
      ),
      class = first_class,
      parent = status$cnd
    )
  }
  return(invisible(NULL))
}

#' Warn once about known backends whose environments a query skips
#'
#' For the queries of `method = "auto"` (`list_envs()`, `env_exists()`,
#' `get_install_dir()`): a known backend that is not registered after
#' `load_known_backends()` but has environments is not listed.
#'
#' @returns `NULL`, invisibly. Warns once per session and backend, with
#'   `c("condathis_backend_not_installed", "condathis_warning")`, or
#'   `condathis_backend_load_failed` instead of the first class.
#'
#' @keywords internal
#' @noRd
warn_unregistered_known_backends <- function() {
  if (isTRUE(known_backend_state$loading)) {
    return(invisible(NULL))
  }
  for (name in unregistered_known_backend_names()) {
    if (isFALSE(backend_has_env_dirs(name))) {
      next
    }
    pkg <- known_backend_packages[[name]]
    root <- backend_root_path(name)
    status <- known_backend_unloaded_status(name)
    cause <- known_backend_cause(status$reason, form = "its")
    condathis_warn_once(
      id = known_backend_warn_id(name),
      message = c(
        `!` = paste0(
          "Backend {.field {name}} has environments in {.path {root}}, but ",
          cause,
          "; they are skipped."
        )
      ),
      class = known_backend_condition_class(status),
      parent = status$cnd
    )
  }
  return(invisible(NULL))
}

#' The first class of a condition about a known backend that is not
#' registered
#'
#' @param status A failed status from `load_known_backend()`.
#'
#' @returns `"condathis_backend_not_installed"` when the package is not
#'   installed, else `"condathis_backend_load_failed"`.
#'
#' @keywords internal
#' @noRd
known_backend_condition_class <- function(status) {
  if (identical(status$reason, "not_installed")) {
    return("condathis_backend_not_installed")
  }
  return("condathis_backend_load_failed")
}
