#' Abort with the condathis root class
#'
#' Every error that condathis raises goes through this function, so every
#' error has the class `condathis_error` (rule R1). It is
#' `cli::cli_abort()` with `"condathis_error"` appended to `class`, and with
#' the credentials of URLs hidden in the interpolated message (see
#' `hide_secrets()`).
#'
#' Rules for callers:
#' * An argument error uses `class = arg_error_class(fn, arg)`, for example
#'   `c("condathis_create_env_invalid_overwrite",
#'   "condathis_invalid_overwrite", "condathis_invalid_arg")`.
#' * Keep a renamed class as an extra class after the new name until 1.0.
#' * Messages follow rule R3: `{.arg x}` for argument names, `{.field}` for
#'   list fields and environment names, `{.val}` for values, `{.path}` for
#'   paths. Argument errors read `"{.arg x} must be <...>."`. Bullets: `x`
#'   for the problem, `i` for hints, `v` for success, `!` only in warnings.
#'
#' @param message Character vector, a cli message. Names are bullet types.
#'   It is interpolated in `.envir`.
#' @param class Character vector of condition classes, the most specific
#'   first, or `NULL`. `"condathis_error"` is appended. Duplicates are
#'   dropped.
#' @param ... Passed to `cli::cli_abort()`, and so to `rlang::abort()`:
#'   condition fields (for example `status = 1L`) and `parent`.
#' @param call Environment of the function that the error is reported for.
#'   The default is the function that calls `condathis_abort()`. An internal
#'   helper takes `call = rlang::caller_env()` and passes it on, so the
#'   error names the exported function the user called.
#' @param .envir Environment for the interpolation of `message`. The default
#'   is the environment that calls `condathis_abort()`.
#'
#' An error with the class `condathis_backend_error` also gets the field
#' `condathis_backend_rethrown = TRUE`. `with_backend_errors()` passes on
#' only such errors unchanged (see `is_condathis_backend_error()`).
#'
#' @returns Does not return.
#'
#' @keywords internal
#' @noRd
condathis_abort <- function(
  message,
  class = NULL,
  ...,
  call = rlang::caller_env(),
  .envir = parent.frame()
) {
  class <- unique(c(class, "condathis_error"))
  # What `cli::cli_abort()` does, with the credentials hidden after the
  # interpolation.
  message[] <- hide_secrets(vapply(
    message,
    cli::format_inline,
    character(1L),
    .envir = .envir,
    USE.NAMES = FALSE
  ))
  if (isTRUE("condathis_backend_error" %in% class)) {
    # Marks a backend failure that condathis itself raised, so a backend
    # error that only has the class is still wrapped.
    rlang::abort(
      message = message,
      class = class,
      condathis_backend_rethrown = TRUE,
      ...,
      call = call,
      use_cli_format = TRUE,
      .frame = .envir
    )
  }
  rlang::abort(
    message = message,
    class = class,
    ...,
    call = call,
    use_cli_format = TRUE,
    .frame = .envir
  )
}

#' Is this a backend failure that condathis already raised?
#'
#' A backend's own error may have the class `condathis_backend_error` too,
#' although `?register_backend` says not to use it. Only the field that
#' `condathis_abort()` sets tells the two apart.
#'
#' @param cnd A condition.
#'
#' @returns `TRUE` or `FALSE`.
#'
#' @keywords internal
#' @noRd
is_condathis_backend_error <- function(cnd) {
  return(
    isTRUE(inherits(cnd, "condathis_backend_error")) &&
      isTRUE(cnd[["condathis_backend_rethrown"]])
  )
}

#' Warn with the condathis root class
#'
#' Every warning that condathis raises goes through this function, so every
#' warning has the class `condathis_warning` (rule R1). It is
#' `cli::cli_warn()` with `"condathis_warning"` appended to `class`, and
#' with the credentials of URLs hidden in the formatted message (see
#' `hide_secrets()`). Use the `!` bullet for the problem.
#'
#' @param message Character vector, a cli message. It is interpolated in
#'   `.envir`.
#' @param class Character vector of condition classes, the most specific
#'   first, or `NULL`. `"condathis_warning"` is appended.
#' @param ... Passed to `rlang::warn()`: condition fields and `parent`.
#' @param .envir Environment for the interpolation of `message`.
#'
#' @returns `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
condathis_warn <- function(
  message,
  class = NULL,
  ...,
  .envir = parent.frame()
) {
  rlang::warn(
    message = hide_secrets(cli::format_warning(message, .envir = .envir)),
    class = unique(c(class, "condathis_warning")),
    ...
  )
  return(invisible(NULL))
}

#' Show a message, with the credentials of URLs hidden
#'
#' `cli::cli_inform()`, with the credentials of URLs hidden in the
#' formatted message (see `hide_secrets()`). Every message that condathis
#' shows goes through this function.
#'
#' @param message Character vector, a cli message. It is interpolated in
#'   `.envir`.
#' @param ... Passed to `rlang::inform()`: condition fields and `class`.
#' @param .envir Environment for the interpolation of `message`.
#'
#' @returns `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
condathis_inform <- function(message, ..., .envir = parent.frame()) {
  rlang::inform(
    message = hide_secrets(cli::format_message(message, .envir = .envir)),
    ...
  )
  return(invisible(NULL))
}

#' Which once-per-session warnings were already given
#'
#' A package-level environment: one logical entry per warning id.
#' `condathis_warn_once()` writes it, and `reset_warn_once()` clears it.
#'
#' @keywords internal
#' @noRd
condathis_warn_once_state <- new.env(parent = emptyenv())

#' Warn once per R session
#'
#' Gives the warning the first time it is called with `id`, and does
#' nothing on later calls with the same `id`. Use it for deprecations, so a
#' loop does not print the same warning many times. The warning counts as
#' given before it is signaled, so a handler that catches it does not make
#' it come back.
#'
#' Tests that check the warning call `reset_warn_once(id)` first, and again
#' with `withr::defer()`.
#'
#' @param id Character string that names the warning, for example
#'   `"deprecated_packages_arg_create_env"`.
#' @param message,class,...,.envir As in `condathis_warn()`.
#'
#' @returns `TRUE`, invisibly, when the warning was given; `FALSE` when it
#'   was given before in this session.
#'
#' @keywords internal
#' @noRd
condathis_warn_once <- function(
  id,
  message,
  class = NULL,
  ...,
  .envir = parent.frame()
) {
  if (isTRUE(condathis_warn_once_state[[id]])) {
    return(invisible(FALSE))
  }
  condathis_warn_once_state[[id]] <- TRUE
  condathis_warn(message = message, class = class, ..., .envir = .envir)
  return(invisible(TRUE))
}

#' Is a deprecated feature used directly by the person who can change it?
#'
#' The soft deprecation rule of condathis, in base R. It follows
#' `lifecycle::deprecate_soft()`: a deprecated argument warns when the call
#' comes from the global environment (the console, a script, a vignette),
#' or from the tests of the package that makes the call. A call made inside
#' another package does not warn: its users cannot change that code.
#'
#' The option `lifecycle_verbosity` is respected: `"warning"` and `"error"`
#' make every call direct, and `"quiet"` makes none direct. The warning
#' stays a warning, and once per session, with every value.
#'
#' @param user_env The environment the exported function was called from:
#'   `rlang::caller_env()` evaluated in the exported function itself, never
#'   in a helper. `NULL` counts as direct.
#'
#' @returns `TRUE` or `FALSE`.
#'
#' @keywords internal
#' @noRd
is_direct_use <- function(user_env) {
  verbosity <- getOption("lifecycle_verbosity")
  if (
    isTRUE(rlang::is_string(verbosity)) &&
      isTRUE(verbosity %in% c("warning", "error"))
  ) {
    return(TRUE)
  }
  if (isTRUE(identical(verbosity, "quiet"))) {
    return(FALSE)
  }
  if (is.null(user_env)) {
    return(TRUE)
  }
  top <- topenv(user_env)
  if (isTRUE(identical(top, globalenv()))) {
    return(TRUE)
  }
  # testthat sets TESTTHAT_PKG to the package under test: its own tests see
  # the warning, so its maintainer does.
  testing_pkg <- Sys.getenv("TESTTHAT_PKG")
  return(
    isTRUE(nzchar(testing_pkg)) &&
      isTRUE(isNamespace(top)) &&
      isTRUE(identical(unname(getNamespaceName(top)), testing_pkg))
  )
}

#' Warn once per session about a deprecation, only for direct use
#'
#' `condathis_warn_once()` when `is_direct_use(user_env)` is `TRUE`. An
#' indirect call neither warns nor marks `id` as given, so a later direct
#' call still warns.
#'
#' @param id,message,class,.envir As in `condathis_warn_once()`.
#' @param user_env As in `is_direct_use()`.
#'
#' @returns `TRUE`, invisibly, when the warning was given; `FALSE` otherwise.
#'
#' @keywords internal
#' @noRd
condathis_deprecate_soft <- function(
  id,
  message,
  class,
  user_env = NULL,
  .envir = parent.frame()
) {
  if (isFALSE(is_direct_use(user_env))) {
    return(invisible(FALSE))
  }
  return(condathis_warn_once(
    id = id,
    message = message,
    class = class,
    .envir = .envir
  ))
}

#' Forget once-per-session warnings
#'
#' @param id Character vector of warning ids, or `NULL` for every id.
#'
#' @returns `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
reset_warn_once <- function(id = NULL) {
  ids <- id
  if (is.null(ids)) {
    ids <- ls(envir = condathis_warn_once_state, all.names = TRUE)
  }
  ids <- intersect(ids, ls(envir = condathis_warn_once_state, all.names = TRUE))
  rm(list = ids, envir = condathis_warn_once_state)
  return(invisible(NULL))
}

#' Condition classes of an argument error (rule R1)
#'
#' @param fn Character string, the full name of the exported function, for
#'   example `"create_env"`. `NULL` for a check that a parser shared by every
#'   exported function makes (verbose, method, error): those raise only the
#'   shared classes.
#' @param arg Character string, the exact argument name, without an
#'   `_arg` suffix.
#' @param aliases Character vector of old class names to keep, or `NULL`.
#'   They come after the new function class.
#'
#' @returns Character vector:
#'   `c("condathis_<fn>_invalid_<arg>", aliases, "condathis_invalid_<arg>",
#'   "condathis_invalid_arg")`. `condathis_abort()` adds
#'   `"condathis_error"`. For example, `arg_error_class("create_env",
#'   "overwrite", "condathis_create_invalid_overwrite_arg")`.
#'
#' @keywords internal
#' @noRd
arg_error_class <- function(fn, arg, aliases = NULL) {
  fn_class <- if (is.null(fn)) {
    NULL
  } else {
    paste0("condathis_", fn, "_invalid_", arg)
  }
  return(unique(c(
    fn_class,
    aliases,
    paste0("condathis_invalid_", arg),
    "condathis_invalid_arg"
  )))
}

#' Closest names to a misspelled name
#'
#' First the choices that start with `x` (an abbreviation), else the choices
#' with the smallest edit distance, when that distance is at most 2, or at
#' most a third of the length of `x`.
#'
#' @param x Character string.
#' @param choices Character vector.
#'
#' @returns Character vector, possibly empty.
#'
#' @keywords internal
#' @noRd
closest_names <- function(x, choices) {
  if (
    isFALSE(rlang::is_string(x)) ||
      isFALSE(nzchar(x)) ||
      identical(length(choices), 0L)
  ) {
    return(character(0L))
  }
  prefixed <- choices[startsWith(choices, x)]
  if (isTRUE(length(prefixed) > 0L)) {
    return(prefixed)
  }
  distances <- as.vector(utils::adist(x, choices, ignore.case = TRUE))
  max_distance <- base::max(2L, base::floor(nchar(x) / 3L))
  best <- base::min(distances)
  if (isTRUE(best > max_distance)) {
    return(character(0L))
  }
  return(choices[distances == best])
}

#' Match a choice argument, with classed errors
#'
#' `rlang::arg_match()` with condathis classes. Every choice argument uses
#' it (verbose, error, channel_priority, stream, ...).
#'
#' @param arg The value of the argument.
#' @param values Character vector of the valid values.
#' @param class Character vector of classes for the error, the most specific
#'   first, for example `"condathis_invalid_verbose"` or
#'   `arg_error_class("create_env", "channel_priority")`.
#'   `"condathis_invalid_arg"` is appended.
#' @param arg_name Character string with the argument name for the message.
#'   The default is the expression passed as `arg`.
#' @param call Environment of the function the error is reported for.
#'
#' @returns A single string from `values`. When `arg` holds every value of
#'   `values`, as an unchanged default does, the first element of `arg`
#'   (`values[[1L]]` for an unchanged default). Otherwise aborts with
#'   `"{.arg <arg_name>} must be one of ..."`.
#'
#' @keywords internal
#' @noRd
arg_match_classed <- function(
  arg,
  values,
  class,
  arg_name = rlang::caller_arg(arg),
  call = rlang::caller_env()
) {
  # An unchanged default is the vector of choices. A default in another
  # order (a permutation) gives its own first element, as rlang::arg_match()
  # does.
  if (
    isTRUE(is.character(arg)) &&
      isTRUE(length(arg) > 1L) &&
      identical(length(arg), length(values)) &&
      isTRUE(setequal(arg, values)) &&
      identical(anyDuplicated(arg), 0L)
  ) {
    return(arg[[1L]])
  }
  if (isTRUE(rlang::is_string(arg)) && isTRUE(arg %in% values)) {
    return(arg)
  }
  message <- if (isTRUE(rlang::is_string(arg))) {
    c(
      `x` = "{.arg {arg_name}} must be one of {.or {.val {values}}}, not {.val {arg}}."
    )
  } else {
    c(
      `x` = "{.arg {arg_name}} must be one of {.or {.val {values}}}, not {.obj_type_friendly {arg}}."
    )
  }
  suggestion <- if (isTRUE(rlang::is_string(arg))) {
    closest_names(arg, values)
  } else {
    character(0L)
  }
  if (isTRUE(length(suggestion) > 0L)) {
    message <- c(message, `i` = "Did you mean {.val {suggestion}}?")
  }
  condathis_abort(
    message = message,
    class = c(class, "condathis_invalid_arg"),
    call = call
  )
}

#' Abort for an environment that does not exist
#'
#' The one missing-environment error. Its class always ends with
#' `c("condathis_env_not_found", "condathis_error")`. When the directory
#' of the environment is in the root of a known backend that is not
#' registered (see `unregistered_known_owner()`), the message says so
#' instead of the hint: "Environment x belongs to backend rattler, whose
#' package rattlerthis is not installed." Otherwise it contradicted the
#' error of a change to that environment, and the warning of the owner
#' search is given once per session only.
#'
#' @param env_label Character string, the environment name, or the
#'   directory of an environment given by `env_path()`.
#' @param class Character vector, the function's own classes, the most
#'   specific first, for example
#'   `c("condathis_list_packages_env_not_found",
#'   "condathis_list_packages_missing_env")`.
#' @param hint Character vector of extra cli bullets, after the `x` bullet
#'   `"Environment {.field <env_label>} does not exist."`. They are
#'   interpolated in `.envir`, which also holds `env_label`.
#' @param ... Condition fields, passed to `condathis_abort()`.
#' @param call Environment of the function the error is reported for.
#' @param .envir Environment for the interpolation of `hint`.
#'
#' @returns Does not return.
#'
#' @keywords internal
#' @noRd
abort_env_not_found <- function(
  env_label,
  class,
  hint = c(`i` = "Create it with {.fn create_env}, or see {.fn list_envs}."),
  ...,
  call = rlang::caller_env(),
  .envir = parent.frame()
) {
  # A child environment, so `hint` can use the caller's variables and the
  # first bullet can use `env_label`.
  message_env <- rlang::env(.envir, env_label = env_label)
  message <- c(`x` = "Environment {.field {env_label}} does not exist.", hint)
  owner <- unregistered_known_owner(env_label)
  if (isFALSE(is.null(owner))) {
    message_env <- rlang::env(
      message_env,
      name = owner$name,
      pkg = owner$pkg,
      env_dir = owner$env_dir
    )
    message <- c(
      `x` = paste0(
        "Environment {.field {env_label}} belongs to backend {.field {name}}, ",
        known_backend_cause(owner$status$reason, form = "whose"),
        "."
      ),
      `i` = known_backend_remedy(owner$status$reason)
    )
  }
  condathis_abort(
    message = message,
    class = c(class, "condathis_env_not_found"),
    ...,
    call = call,
    .envir = message_env
  )
}

#' Classes of a wrapped backend failure
#'
#' @param fn Character string, the exported function name.
#' @param cnd The backend's error condition.
#'
#' @returns `c("condathis_<fn>_failed", "condathis_backend_error",
#'   <the condathis_* classes of cnd>)`, without `"condathis_error"`, which
#'   `condathis_abort()` adds last.
#'
#' @keywords internal
#' @noRd
backend_failure_class <- function(fn, cnd) {
  parent_classes <- grep("^condathis_", class(cnd), value = TRUE)
  return(unique(c(
    paste0("condathis_", fn, "_failed"),
    "condathis_backend_error",
    setdiff(parent_classes, c("condathis_error", "condathis_warning"))
  )))
}

#' Re-raise a backend failure with the classes of rule R1
#'
#' A backend failure that condathis already raised (see
#' `is_condathis_backend_error()`) is signaled again unchanged. Any other
#' error becomes the parent of a new error with `backend_failure_class()`.
#' The new error also has the `condathis_*` classes of `cnd`, so with
#' `condathis_micromamba_status_error` it also gets the fields `status` and
#' `stderr` of `cnd`.
#'
#' @param cnd The backend's error condition.
#' @param fn Character string, the exported function name.
#' @param backend_name Character string, the registered backend name.
#' @param action Character string, what failed, for the message
#'   `"Backend <name> failed to <action>."`, for example
#'   `"create environment 'x'"`. Plain text: it is not interpolated.
#' @param call Environment of the function the error is reported for.
#'
#' @returns Does not return.
#'
#' @keywords internal
#' @noRd
abort_backend_failure <- function(cnd, fn, backend_name, action, call) {
  if (isTRUE(is_condathis_backend_error(cnd))) {
    rlang::cnd_signal(cnd)
  }
  # The fields of the classes that the error copies from `cnd`: a handler
  # for `condathis_micromamba_status_error` reads `status` and `stderr`.
  status_fields <- list()
  if (isTRUE(inherits(cnd, "condathis_micromamba_status_error"))) {
    status_fields <- list(status = cnd$status, stderr = cnd$stderr)
  }
  rlang::exec(
    condathis_abort,
    message = c(`x` = "Backend {.field {backend_name}} failed to {action}."),
    class = backend_failure_class(fn, cnd),
    parent = cnd,
    # Where an environment that a failed replacement could not move back is
    # kept (class `condathis_env_not_restored`), see ?register_backend.
    kept_env_dir = cnd$kept_env_dir,
    !!!status_fields,
    call = call
  )
}

#' Evaluate a backend call, and re-raise its errors with condathis classes
#'
#' Wrap each mutation and listing generic that an exported function calls:
#' `with_backend_errors(backend_install(...), fn = "install_packages",
#' backend_name = resolved$name, action = "install packages in
#' environment 'x'")`. Argument checks and env-not-found errors happen
#' before the call and stay outside the wrapper.
#'
#' A backend failure from `expr` that condathis already raised (see
#' `is_condathis_backend_error()`) passes unchanged. Any other error `cnd`,
#' also a backend's own error with the class `condathis_backend_error`,
#' becomes an error with the classes
#' `c("condathis_<fn>_failed", "condathis_backend_error", <the condathis_*
#' classes of cnd>, "condathis_error")`, the message
#' `"Backend <backend_name> failed to <action>."`, and `parent = cnd`, so
#' `rlang::cnd_inherits()` and `testthat::expect_error(class =, inherit =
#' TRUE)` still find the backend's own classes. Warnings and messages pass
#' unchanged.
#'
#' @param expr The backend call.
#' @param fn Character string, the exported function name.
#' @param backend_name Character string, the registered backend name.
#' @param action Character string, what the call does, as text to follow
#'   "failed to". It is not interpolated.
#' @param call Environment of the function the error is reported for.
#'
#' @returns The value of `expr`.
#'
#' @keywords internal
#' @noRd
with_backend_errors <- function(
  expr,
  fn,
  backend_name,
  action,
  call = rlang::caller_env()
) {
  # A calling handler, not tryCatch(): the backtrace of the backend's error
  # stays complete.
  return(withCallingHandlers(
    expr,
    error = function(cnd) {
      if (isTRUE(is_condathis_backend_error(cnd))) {
        # Returning declines: the error goes on unchanged.
        return(invisible(NULL))
      }
      abort_backend_failure(
        cnd = cnd,
        fn = fn,
        backend_name = backend_name,
        action = action,
        call = call
      )
    }
  ))
}

#' The kinds of link scripts that a backend can report as not run
#'
#' micromamba runs `pre-link` scripts from the extracted package, and
#' `post-link` and `pre-unlink` scripts in the prefix (see
#' ?register_backend, *Results*).
#'
#' @keywords internal
#' @noRd
link_script_kinds <- c("pre-link", "post-link", "pre-unlink")

#' The link scripts that a backend did not run
#'
#' Reads the element `link_scripts_skipped` of the list that
#' `backend_create_env()`, `backend_install()` or `backend_remove_env()`
#' returned (see *Results* in ?register_backend). `new_backend_result()`
#' ignores it, so the result of every backend has the same fields: the
#' scripts are reported only by `warn_link_scripts_skipped()`.
#'
#' @param px_res The value the backend returned.
#' @param fn Character string, the exported function name: `"create_env"`,
#'   `"install_packages"` or `"remove_env"`.
#' @param backend_name Character string, the registered backend name.
#' @param call Environment of the function the error is reported for.
#'
#' @returns `NULL` when the element is absent or `NULL`. Otherwise a data
#'   frame with the character columns `package` and `script`, without
#'   duplicated rows, possibly with zero rows. A value that is not such a
#'   data frame, with `script` one of `link_script_kinds` and no `NA` or
#'   `""`, aborts with `c("condathis_backend_invalid_return",
#'   "condathis_backend_contract_violation", "condathis_error")`.
#'
#' @keywords internal
#' @noRd
backend_link_scripts_skipped <- function(
  px_res,
  fn,
  backend_name,
  call = rlang::caller_env()
) {
  if (isFALSE(is.list(px_res))) {
    return(NULL)
  }
  value <- px_res[["link_scripts_skipped"]]
  if (is.null(value)) {
    return(NULL)
  }
  is_text_column <- function(x) {
    return(
      isTRUE(is.character(x)) &&
        isFALSE(is.object(x)) &&
        isFALSE(anyNA(x)) &&
        isTRUE(all(nzchar(x)))
    )
  }
  if (
    isFALSE(is.data.frame(value)) ||
      isFALSE(is_text_column(value[["package"]])) ||
      isFALSE(is_text_column(value[["script"]])) ||
      isFALSE(all(value[["script"]] %in% link_script_kinds))
  ) {
    generic <- switch(
      fn,
      create_env = "backend_create_env",
      install_packages = "backend_install",
      remove_env = "backend_remove_env",
      fn
    )
    abort_backend_invalid_return(
      generic = generic,
      backend_name = backend_name,
      rule = "Its element {.field link_scripts_skipped} must be {.code NULL} or a data frame with the character columns {.field package} and {.field script}, without {.val {NA}} or {.val {\"\"}}, where {.field script} is {.or {.val {link_script_kinds}}}.",
      value = value,
      call = call
    )
  }
  skipped <- unique(base::data.frame(
    package = as.character(value[["package"]]),
    script = as.character(value[["script"]]),
    stringsAsFactors = FALSE
  ))
  rownames(skipped) <- NULL
  return(skipped)
}

#' Warn that a backend did not run the link scripts of packages
#'
#' Called by `create_env()`, `install_packages()` and `remove_env()` after
#' the backend succeeded, at every verbose level: a warning is a condition,
#' not output. micromamba runs these scripts; a backend that does not
#' reports them (see `backend_link_scripts_skipped()`).
#'
#' @param skipped The value of `backend_link_scripts_skipped()`.
#' @param fn Character string, the exported function name.
#' @param backend_name Character string, the registered backend name.
#' @param env_name Character string with the environment name.
#'
#' @returns `NULL`, invisibly. When `skipped` has rows, warns with class
#'   `c("condathis_<fn>_link_scripts_skipped",
#'   "condathis_link_scripts_skipped", "condathis_warning")` and the fields
#'   `backend` (the backend name), `env_name`, `packages` (the names of the
#'   packages, sorted) and `scripts` (`skipped`: one row per package and
#'   script kind).
#'
#' @keywords internal
#' @noRd
warn_link_scripts_skipped <- function(skipped, fn, backend_name, env_name) {
  if (is.null(skipped) || identical(nrow(skipped), 0L)) {
    return(invisible(NULL))
  }
  packages_of <- function(kind) {
    return(sort(
      unique(skipped$package[skipped$script == kind]),
      method = "radix"
    ))
  }
  pre_link <- packages_of("pre-link")
  post_link <- packages_of("post-link")
  pre_unlink <- packages_of("pre-unlink")
  installs <- isTRUE(length(pre_link) + length(post_link) > 0L)
  message <- c(
    `!` = if (isTRUE(length(pre_link) > 0L)) {
      "Backend {.field {backend_name}} did not run the pre-link scripts of {.field {pre_link}}."
    },
    `!` = if (isTRUE(length(post_link) > 0L)) {
      "Backend {.field {backend_name}} did not run the post-link scripts of {.field {post_link}}."
    },
    `!` = if (isTRUE(length(pre_unlink) > 0L)) {
      "Backend {.field {backend_name}} did not run the pre-unlink scripts of {.field {pre_unlink}} before it removed them."
    },
    `i` = if (isTRUE(installs)) {
      "Some packages finish their installation in these scripts, so they may not work."
    },
    `i` = if (isTRUE(length(pre_unlink) > 0L)) {
      "Some packages undo changes outside the environment in these scripts."
    },
    `i` = if (
      isTRUE(installs) && isFALSE(identical(backend_name, "micromamba"))
    ) {
      "The {.field micromamba} backend runs them: create the environment with {.code method = \"micromamba\"}."
    }
  )
  condathis_warn(
    message = message,
    class = c(
      paste0("condathis_", fn, "_link_scripts_skipped"),
      "condathis_link_scripts_skipped"
    ),
    backend = backend_name,
    env_name = env_name,
    packages = sort(unique(skipped$package), method = "radix"),
    scripts = skipped
  )
  return(invisible(NULL))
}
