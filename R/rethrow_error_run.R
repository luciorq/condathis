#' Re-throw run errors with condathis classes
#'
#' Turns the `processx` error of a failed or timed-out command into a
#' condathis error (rule R1):
#'
#' * a non-zero exit: `c("condathis_<fn>_status_error",
#'   "condathis_run_status_error", "condathis_status_error",
#'   "condathis_error")`;
#' * a timeout: `c("condathis_<fn>_timeout_error",
#'   "condathis_run_timeout_error", "condathis_timeout_error",
#'   "condathis_error")`.
#'
#' `condathis_run_*` stays on the errors of `run_bin()` as an old class.
#' Both errors carry the fields `status` (integer; `-9` for a timeout, `127`
#' for a command that could not start), `stdout` and `stderr` (`NA` when
#' the stream was not captured) and `timeout` (logical), so a handler does
#' not need to parse the message. The error names `call`, the exported
#' function.
#'
#' @param expr Expression to evaluate.
#' @param env Environment used to evaluate `expr`: the frame of
#'   `run_command()`. It must hold `cmd`, `error_var`, `timeout`, `stdin`,
#'   and the stream targets `stdout` and `stderr`. Defaults to
#'   `parent.frame()`.
#' @param fn Character string, the exported function name, for the classes:
#'   `"run"` or `"run_bin"`.
#' @param call Environment of the exported function the user called, for
#'   the error. Defaults to `env`.
#'
#' @returns The evaluated `expr` result when no captured error is present.
#'   For non-fatal modes, may return a synthesized process-like result list.
#'
#' @keywords internal
#' @noRd
rethrow_error_run <- function(
  expr,
  env = parent.frame(),
  fn = "run",
  call = env
) {
  code <- base::substitute(expr = expr)
  err_cnd <- rlang::catch_cnd(
    expr = {
      px_res <- rlang::eval_bare(expr = code, env = env)
    },
    classes = c(
      "system_command_status_error",
      "system_command_timeout_error",
      "rlib_error_3_0",
      "c_error",
      "condathis_command_not_found"
    )
  )
  is_timeout <- isTRUE(inherits(err_cnd, "system_command_timeout_error"))

  # A caught condition without an exit status is reported as "command not
  # found" (status 127) only when `processx` failed to start the process.
  # Every other one - an interrupt, `setTimeLimit()` firing while polling,
  # an R-level error inside the I/O pump - is re-raised unchanged: it is not
  # a property of the command, and reporting it as one hid the real cause.
  if (
    isFALSE(rlang::is_null(err_cnd)) &&
      isFALSE(is_timeout) &&
      isFALSE("status" %in% names(err_cnd)) &&
      isFALSE(is_spawn_failure(err_cnd))
  ) {
    rlang::cnd_signal(err_cnd)
  }

  # A fallback only: the run family checks `stdin` with its other arguments
  # (`validate_run_args()`), before anything starts.
  if (
    isFALSE(rlang::is_null(env[["stdin"]])) &&
      isFALSE(identical(env[["stdin"]], "|")) &&
      isFALSE(
        fs::is_file(env[["stdin"]]) &&
          fs::file_exists(env[["stdin"]])
      )
  ) {
    condathis_abort(
      message = c(
        `x` = "{.arg stdin} must be {.code NULL}, {.val |}, or the path of a file.",
        `i` = "{.path {stdin}} is not a file."
      ),
      class = arg_error_class(
        fn,
        "stdin",
        aliases = "condathis_run_stdin_error"
      ),
      call = call,
      .envir = env
    )
  }

  if (isFALSE(rlang::is_null(err_cnd)) && !isFALSE(env[["error_var"]])) {
    abort_run_failure(
      err_cnd,
      env = env,
      fn = fn,
      call = call,
      is_timeout = is_timeout
    )
  }

  # `inherits = FALSE` is required: the default lookup walks up through the
  # namespace to the global environment. A workspace object named `px_res`
  # would pass this check and be returned as the process result when the
  # wrapped expression errors before assigning locally.
  if (isFALSE(exists("px_res", inherits = FALSE))) {
    px_res <- run_result_without_process(err_cnd, env, is_timeout)
  }

  # Normalize to a fixed sentinel regardless of how `px_res` was produced.
  # With `error_on_status = FALSE` (`error = "continue"`), `processx::run()`
  # does not throw on timeout. It returns normally with the OS-reported
  # `status` of the killed process (`-9` on Linux/macOS, `2` on Windows for
  # the identical `kill()`). `processx::run()` and `run_process_with_input()`
  # always set `px_res$timeout`, so trust it instead of the raw status.
  if (isTRUE(rlang::is_list(px_res)) && isTRUE(px_res$timeout)) {
    px_res$status <- -9L
  }

  return(px_res)
}

#' Abort for a command that failed or timed out
#'
#' The condathis error of `rethrow_error_run()` for `error = "cancel"`:
#' the classes and fields are described there.
#'
#' @param err_cnd The condition caught from `processx`.
#' @param env,fn,call As in `rethrow_error_run()`.
#' @param is_timeout Logical. Whether the command timed out.
#'
#' @returns Does not return.
#'
#' @keywords internal
#' @noRd
abort_run_failure <- function(err_cnd, env, fn, call, is_timeout) {
  additional_lines <- NULL
  if (isTRUE("stderr" %in% names(err_cnd))) {
    additional_lines <- stream_display_lines(err_cnd[["stderr"]])
  }

  if (isFALSE("status" %in% names(err_cnd))) {
    status_code <- 127L
    additional_lines <- c("{cmd}: command not found", additional_lines)
  } else {
    status_code <- err_cnd[["status"]]
  }
  # The same value as the `status` of a result under `error = "continue"`.
  status_code <- if (isTRUE(is_timeout)) -9L else as.integer(status_code)
  env[["status_code"]] <- status_code

  # A stream that was not captured is `NA`, as in `condathis_result`. A
  # command that never started gets the streams of the result of
  # `error = "continue"` (see below).
  not_started <- isFALSE("status" %in% names(err_cnd))
  error_stream <- function(name, not_started_value) {
    value <- err_cnd[[name]]
    if (isTRUE(not_started)) {
      value <- not_started_value
    }
    if (
      is.null(value) ||
        (exists(name, envir = env, inherits = FALSE) &&
          isFALSE(identical(env[[name]], "|")))
    ) {
      return(NA_character_)
    }
    return(value)
  }
  stdout_field <- error_stream("stdout", "")
  stderr_field <- error_stream(
    "stderr",
    paste("System command", hide_secrets(env[["cmd"]]), "not found")
  )

  if (isTRUE(is_timeout)) {
    condathis_abort(
      message = c(
        `x` = "Command {.code {cmd}} timed out after {timeout} second{?s}.",
        additional_lines
      ),
      class = unique(c(
        paste0("condathis_", fn, "_timeout_error"),
        "condathis_run_timeout_error",
        "condathis_timeout_error"
      )),
      status = status_code,
      stdout = stdout_field,
      stderr = stderr_field,
      timeout = TRUE,
      call = call,
      .envir = env
    )
  }

  condathis_abort(
    message = c(
      `x` = "Command {.code {cmd}} failed with exit status {status_code}.",
      additional_lines
    ),
    class = unique(c(
      paste0("condathis_", fn, "_status_error"),
      "condathis_run_status_error",
      "condathis_status_error"
    )),
    status = status_code,
    stdout = stdout_field,
    stderr = stderr_field,
    timeout = FALSE,
    call = call,
    .envir = env
  )
}

#' The result of a command that has no process result
#'
#' For `error = "continue"` when the evaluated expression failed before it
#' returned a result, as for a command that could not start.
#'
#' @param err_cnd The condition caught from `processx`, or `NULL`.
#' @param env As in `rethrow_error_run()`.
#' @param is_timeout Logical. Whether the command timed out.
#'
#' @returns A list with `status`, `stdout`, `stderr` and `timeout`.
#'
#' @keywords internal
#' @noRd
run_result_without_process <- function(err_cnd, env, is_timeout) {
  if (isTRUE(rlang::is_null(err_cnd[["status"]]))) {
    status_code <- 127L
  } else {
    status_code <- err_cnd[["status"]]
  }

  if (isTRUE(is_timeout)) {
    stderr_msg <- sprintf(
      "Command timed out after %s seconds",
      env[["timeout"]]
    )
  } else if (
    inherits(err_cnd, "condathis_command_not_found") ||
      (isFALSE(rlang::is_null(err_cnd[["message"]])) &&
        isTRUE(stringr::str_detect(err_cnd[["message"]], "Native call to")))
  ) {
    if (isFALSE(rlang::is_null(env[["cmd"]]))) {
      cmd_str <- env[["cmd"]]
    }
    stderr_msg <- paste("System command", hide_secrets(cmd_str), "not found")
  } else {
    stderr_msg <- "Unknown Error"
  }

  return(list(
    status = status_code,
    stdout = "",
    stderr = stderr_msg,
    timeout = is_timeout
  ))
}

#' Did `processx` fail to start the process?
#'
#' @param cnd A condition caught from `processx`.
#'
#' @returns Logical scalar. `TRUE` for the `processx_exec` spawn failure
#'   (for example a missing or non-executable command), on every platform,
#'   and for a bare command that condathis found nowhere on Windows (see
#'   `abort_command_not_found()`).
#'
#' @keywords internal
#' @noRd
is_spawn_failure <- function(cnd) {
  if (inherits(cnd, "condathis_command_not_found")) {
    return(TRUE)
  }
  messages <- character(0L)
  while (isFALSE(rlang::is_null(cnd))) {
    messages <- c(messages, conditionMessage(cnd))
    cnd <- cnd[["parent"]]
  }
  return(any(grepl(
    "processx_exec|cannot start processx process",
    messages
  )))
}
