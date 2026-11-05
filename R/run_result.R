#' Run result object
#'
#' @description
#' An S3 class representing the result of `run()` or `run_bin()`. It is a
#' plain list. The fields `$status`, `$stdout`, `$stderr`, and `$timeout`
#' are always present and match a `processx::run()` result list. The class
#' adds `print()`/`format()` methods and `pid`/`cmd`/`env_name` metadata,
#' mirroring `condathis_pipeline`'s per-process result shape.
#'
#' @param status Integer exit status.
#' @param stdout Character string or raw vector with stdout, or `NA` if not
#'   captured.
#' @param stderr Character string or raw vector with stderr, or `NA` if not
#'   captured.
#' @param timeout Logical. Whether the process was killed due to timeout.
#' @param pid Integer process ID, or `NA_integer_` when unavailable.
#' @param cmd Character string with the command and arguments.
#' @param env_name Character string with the Conda environment name.
#'
#' @returns An object of class `"condathis_result"`.
#'
#' @keywords internal
#' @noRd
new_condathis_result <- function(
  status,
  stdout,
  stderr,
  timeout = FALSE,
  pid = NA_integer_,
  cmd = NA_character_,
  env_name = NA_character_
) {
  structure(
    list(
      status = status,
      stdout = stdout,
      stderr = stderr,
      timeout = timeout,
      pid = pid,
      cmd = cmd,
      env_name = env_name
    ),
    class = "condathis_result"
  )
}

#' @export
format.condathis_result <- function(x, ...) {
  status_str <- if (is.na(x$status)) "NA" else as.character(x$status)
  status_icon <- if (identical(x$status, 0L)) {
    "OK"
  } else {
    paste("exit:", status_str)
  }

  lines <- c(
    sprintf("<condathis_result> %s (%s)", x$cmd, x$env_name),
    sprintf("  status: %s", status_icon)
  )
  if (!is.null(x$pid) && !is.na(x$pid)) {
    lines <- c(lines, sprintf("  pid: %d", x$pid))
  }
  stdout_preview <- stream_preview_line(x$stdout)
  if (!is.null(stdout_preview)) {
    lines <- c(lines, sprintf("  stdout: %s", stdout_preview))
  }
  stderr_preview <- stream_preview_line(x$stderr)
  if (!is.null(stderr_preview)) {
    lines <- c(lines, sprintf("  stderr: %s", stderr_preview))
  }
  paste0(lines, collapse = "\n")
}

#' @export
print.condathis_result <- function(x, ...) {
  cat(format(x, ...), "\n")
  invisible(x)
}

#' @export
as.list.condathis_result <- function(x, ...) {
  unclass(x)
}

#' Report a stream that was not captured as `NA`
#'
#' A stream redirected to a file or discarded came back as `NULL` from
#' `processx::run()` but as `""` from the writable-stdin path. Both now read
#' `NA`, as documented for `condathis_result`.
#'
#' @param value The stream value from the process result.
#' @param target The `stdout`/`stderr` argument the caller passed.
#'
#' @returns `value` when `target` is `"|"`, otherwise `NA_character_`.
#'
#' @keywords internal
#' @noRd
captured_or_na <- function(value, target) {
  if (identical(target, "|")) {
    return(value)
  }
  return(NA_character_)
}

#' Build the result of a backend mutation
#'
#' Reads what `backend_create_env()`, `backend_install()` or
#' `backend_remove_env()` returned. The contract allows `NULL` or a list:
#' condathis copies the elements `status`, `stdout`, `stderr`, `timeout`,
#' `pid` and `cmd` when present, with exact names (`[[`), and ignores every
#' other element. A value that is not a list counts as `list()`.
#'
#' Defaults and rules per element:
#' * `status`: `0L` when absent. A whole number is made integer. Any other
#'   value aborts with `c("condathis_backend_invalid_return",
#'   "condathis_backend_contract_violation")`. A non-zero status aborts with
#'   `c("condathis_<fn>_failed", "condathis_backend_error")`, because the
#'   contract requires a backend to signal its failures; the error has the
#'   fields `status`, `stdout` and `stderr`.
#' * `stdout`, `stderr`: a single string or a raw vector is kept. Anything
#'   else, `NULL` included, is `NA_character_` ("not reported").
#' * `timeout`: `TRUE` only when the element is `TRUE`.
#' * `pid`: a whole number is made integer, else `NA_integer_`.
#' * `cmd`: a single, non-`NA` string is kept, with the credentials of
#'   URLs hidden (see `hide_secrets()`), else `NA_character_`.
#'
#' @param px_res The value the backend returned.
#' @param fn Character string, the exported function name.
#' @param backend_name Character string, the registered backend name.
#' @param env_name Character string, the environment name.
#' @param call Environment of the function the error is reported for.
#'
#' @returns A `condathis_result` with status `0L`.
#'
#' @keywords internal
#' @noRd
new_backend_result <- function(
  px_res,
  fn,
  backend_name,
  env_name,
  call = rlang::caller_env()
) {
  if (isFALSE(is.list(px_res))) {
    px_res <- list()
  }
  is_whole_number <- function(x) {
    return(
      isTRUE(is.numeric(x)) &&
        identical(length(x), 1L) &&
        isFALSE(is.na(x)) &&
        isTRUE(x == trunc(x)) &&
        isTRUE(abs(x) <= .Machine$integer.max)
    )
  }
  stream_or_na <- function(x) {
    if (isTRUE(rlang::is_string(x)) || isTRUE(is.raw(x))) {
      return(x)
    }
    return(NA_character_)
  }

  status <- px_res[["status"]]
  if (is.null(status)) {
    status <- 0L
  } else if (isTRUE(is_whole_number(status))) {
    status <- as.integer(status)
  } else {
    condathis_abort(
      message = c(
        `x` = "Backend {.field {backend_name}} returned an invalid {.field status} for environment {.field {env_name}}.",
        `i` = "{.field status} must be a single whole number, not {.obj_type_friendly {status}}."
      ),
      class = c(
        "condathis_backend_invalid_return",
        "condathis_backend_contract_violation"
      ),
      call = call
    )
  }
  stdout <- stream_or_na(px_res[["stdout"]])
  stderr <- stream_or_na(px_res[["stderr"]])
  if (isFALSE(identical(status, 0L))) {
    condathis_abort(
      message = c(
        `x` = "Backend {.field {backend_name}} returned exit status {.val {status}} for environment {.field {env_name}}.",
        `i` = "A backend must signal an error when an operation fails."
      ),
      class = c(paste0("condathis_", fn, "_failed"), "condathis_backend_error"),
      status = status,
      stdout = stdout,
      stderr = stderr,
      call = call
    )
  }
  pid <- px_res[["pid"]]
  cmd <- px_res[["cmd"]]
  return(new_condathis_result(
    status = status,
    stdout = stdout,
    stderr = stderr,
    timeout = isTRUE(px_res[["timeout"]]),
    pid = if (isTRUE(is_whole_number(pid))) as.integer(pid) else NA_integer_,
    cmd = if (isTRUE(rlang::is_string(cmd))) {
      hide_secrets(cmd)
    } else {
      NA_character_
    },
    env_name = env_name
  ))
}

#' The `stderr` text of a command that could not be resolved
#'
#' One text for every site where `backend_resolve_run()` or the activation
#' of an environment fails under `error = "continue"`.
#'
#' @param what Character string, `"command"` or `"activation"`.
#' @param env_label Character string, the environment name or directory.
#' @param cnd The error condition.
#'
#' @returns Character string:
#'   `"Failed to resolve <what> for environment '<env_label>': <message>\n"`,
#'   with the ANSI codes of the condition message removed and the
#'   credentials of URLs hidden (see `hide_secrets()`).
#'
#' @keywords internal
#' @noRd
resolve_failure_stderr <- function(what, env_label, cnd) {
  return(hide_secrets(paste0(
    "Failed to resolve ",
    what,
    " for environment '",
    env_label,
    "': ",
    cli::ansi_strip(conditionMessage(cnd)),
    "\n"
  )))
}

#' Abort for a command that the backend could not resolve
#'
#' The one error of `run()`, `run_bin()` and `run_pipeline()` under
#' `error = "cancel"` when `backend_resolve_run()`, or the micromamba
#' activation of an environment given by `env_path()`, fails. The backend's
#' error becomes the parent of a new error that names the backend, the
#' command, the environment and the user's call. The condathis classes of
#' `cnd` stay on the new error, as in `with_backend_errors()`, so a handler
#' for them (for example `condathis_activation_dump_error`) still works.
#' Other classes of `cnd` are found through the parent, with
#' `rlang::cnd_inherits()`.
#'
#' A `backend_resolve_run()` value that breaks the contract is not passed
#' here: `validate_resolve_run()` reports it.
#'
#' @param cnd The backend's error condition.
#' @param fn Character string, the exported function name: `"run"`,
#'   `"run_bin"` or `"run_pipeline"`.
#' @param cmd_name Character string, the command.
#' @param env_label Character string, the environment name, or the
#'   directory of an `env_path()`.
#' @param backend_name Character string, the registered backend name.
#' @param step_index Integer position of the command in a pipeline, or
#'   `NULL` for a single command.
#' @param hint Character vector of extra cli bullets, or `NULL`.
#' @param call Environment of the function the error is reported for.
#'
#' @returns Does not return. The error has the classes
#'   `c("condathis_<fn>_resolve_failed", "condathis_backend_error", <the
#'   condathis classes of cnd>, "condathis_error")`.
#'
#' @keywords internal
#' @noRd
abort_resolve_failure <- function(
  cnd,
  fn,
  cmd_name,
  env_label,
  backend_name,
  step_index = NULL,
  hint = NULL,
  call = rlang::caller_env()
) {
  parent_classes <- setdiff(
    grep("^condathis_", class(cnd), value = TRUE),
    c("condathis_error", "condathis_warning")
  )
  header <- if (is.null(step_index)) {
    "Backend {.field {backend_name}} failed to resolve command {.code {cmd_name}} for environment {.field {env_label}}."
  } else {
    "Backend {.field {backend_name}} failed to resolve command {step_index} ({.code {cmd_name}}) for environment {.field {env_label}}."
  }
  condathis_abort(
    message = c(`x` = header, hint),
    class = c(
      paste0("condathis_", fn, "_resolve_failed"),
      "condathis_backend_error",
      parent_classes
    ),
    parent = cnd,
    call = call
  )
}
