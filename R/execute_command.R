#' Spawn a process, with or without writable stdin
#'
#' The single place `condathis` starts a child process. Both execution paths
#' converge here, so `timeout`, `supervise`, `cleanup_tree`,
#' `linux_pdeathsig`, `encoding` and echo/spinner behavior are wired
#' identically for every backend. micromamba's own commands run via
#' `native_cmd()`. The commands of `run()` run via `run_internal_backend()`,
#' for every backend, which spawns the resolved command directly.
#'
#' The split follows `processx`: `processx::run()` accepts `stdin = "|"` but
#' never exposes the resulting connection. Writing to a child's stdin needs
#' `processx::process$new()` driven by hand. See `run_process_with_input()`
#' for that path and the hazards it avoids.
#'
#' @param command Character string with the executable to spawn.
#' @param args Character vector of arguments.
#' @param wd Working directory for the child process, or `NULL` to inherit.
#' @param env Environment variables for the child. `NULL` inherits the
#'   current environment unchanged. `c("current", NAME = "value", ...)` is
#'   the `processx` idiom for "inherit, then override these".
#' @param spinner Logical, whether to show a spinner while waiting. Ignored
#'   on the writable-stdin path, which has no live streaming.
#' @param echo_cmd Logical, whether to print the command before running it,
#'   as `processx` prints it, with the credentials of URLs hidden (see
#'   `echo_command_line()`). The process still gets them.
#' @param echo Logical, whether to echo the child's stdout/stderr.
#' @param stdout,stderr,stdin Stream targets, as in `processx::run()`.
#' @param input Character or raw vector written to stdin when `stdin = "|"`.
#' @param error_on_status Logical, whether a non-zero exit signals.
#' @param cleanup_tree,supervise Process-cleanup options, passed through
#'   unchanged.
#' @param linux_pdeathsig Process-cleanup option, passed through on Linux
#'   only (see `processx_linux_pdeathsig()`).
#' @param encoding `"utf-8"` or `"binary"`.
#' @param timeout Numeric seconds, or `Inf`.
#'
#' With `error_on_status = TRUE`, a non-zero exit signals an error of class
#' `"system_command_status_error"`, and a timeout one of class
#' `"system_command_timeout_error"`, the classes `processx::run()` uses.
#' Unlike the `processx::run()` errors, both carry the fields `status`,
#' `stdout` and `stderr`, so `rethrow_error_run()` can report the output of
#' the failed command. They do not have the class `"system_command_error"`:
#' the `format()` and `print()` methods of `processx` for that class expect
#' a `processx` error object and fail on these. A command that cannot start
#' still fails with the error of `processx`.
#'
#' @returns A `processx::run()`-shaped list: `status`, `stdout`, `stderr`,
#'   `timeout`, and (on the writable-stdin path) `pid`.
#'
#' @keywords internal
#' @noRd
execute_command <- function(
  command,
  args = character(0L),
  wd = NULL,
  env = NULL,
  spinner = FALSE,
  echo_cmd = FALSE,
  echo = FALSE,
  stdout = "|",
  stderr = "|",
  stdin = NULL,
  input = NULL,
  error_on_status = TRUE,
  cleanup_tree = FALSE,
  supervise = FALSE,
  linux_pdeathsig = FALSE,
  encoding = "utf-8",
  timeout = Inf
) {
  # Printed here, not by `processx`, which prints the credentials of
  # channel URLs.
  if (isTRUE(echo_cmd)) {
    echo_command_line(command, args)
  }
  if (identical(stdin, "|")) {
    return(run_process_with_input(
      command = command,
      args = args,
      input = input,
      stdout = stdout,
      stderr = stderr,
      echo_cmd = FALSE,
      echo = echo,
      env = env,
      wd = wd,
      error_on_status = error_on_status,
      cleanup_tree = cleanup_tree,
      supervise = supervise,
      linux_pdeathsig = linux_pdeathsig,
      encoding = encoding,
      timeout = timeout
    ))
  }
  # `error_on_status = FALSE`: the error of `processx::run()` has no
  # `stdout` field, so the error is signaled here instead, with the whole
  # result.
  px_res <- processx::run(
    command = command,
    args = args,
    wd = wd,
    env = env,
    spinner = spinner,
    echo_cmd = FALSE,
    echo = echo,
    stdout = stdout,
    stdout_line_callback = NULL,
    stderr = stderr,
    stderr_line_callback = NULL,
    stdin = stdin,
    error_on_status = FALSE,
    cleanup_tree = cleanup_tree,
    encoding = encoding,
    linux_pdeathsig = processx_linux_pdeathsig(linux_pdeathsig),
    supervise = supervise,
    timeout = timeout
  )
  if (isTRUE(error_on_status)) {
    signal_process_failure(px_res, timeout = timeout)
  }
  return(px_res)
}

#' Signal the error of a process that failed or timed out
#'
#' The errors that `execute_command()` and `run_process_with_input()` give
#' with `error_on_status = TRUE`. They have the specific classes of the
#' `processx::run()` errors, so `rethrow_error_run()` and
#' `rethrow_error_cmd()` handle every path the same way. They do not have
#' `"system_command_error"`, whose `processx` methods fail on them (see
#' `execute_command()`).
#'
#' @param px_res A `processx::run()`-shaped list.
#' @param timeout Numeric, the timeout in seconds, for the message.
#' @param na_is_failure Logical. Whether an `NA` status is a failure, as in
#'   `processx::run()`. `run_process_with_input()` passes `FALSE`: there an
#'   `NA` status comes from the Windows handle race of
#'   `exit_status_safely()`, not from the command.
#'
#' @returns `NULL`, invisibly, when the process exited with status 0.
#'   Otherwise an error of class `"system_command_timeout_error"` for a
#'   timeout, or `"system_command_status_error"`, with the fields `status`,
#'   `stdout` and `stderr`.
#'
#' @keywords internal
#' @noRd
signal_process_failure <- function(
  px_res,
  timeout = Inf,
  na_is_failure = TRUE
) {
  status <- px_res[["status"]]
  # A stream that was not captured is `NULL` in the result. It is left out,
  # as `processx` does, because `rlang::abort()` would keep a `NULL` field.
  fields <- list(
    status = status,
    stdout = px_res[["stdout"]],
    stderr = px_res[["stderr"]]
  )
  fields <- Filter(Negate(is.null), fields)
  if (isTRUE(px_res[["timeout"]])) {
    rlang::exec(
      rlang::abort,
      message = sprintf("Command timed out after %s seconds", timeout),
      class = "system_command_timeout_error",
      !!!fields
    )
  }
  failed <- if (isTRUE(is.na(status))) {
    isTRUE(na_is_failure)
  } else {
    isFALSE(identical(as.integer(status), 0L))
  }
  if (isTRUE(failed)) {
    rlang::exec(
      rlang::abort,
      message = sprintf("Command failed with status %s", status),
      class = "system_command_status_error",
      !!!fields
    )
  }
  return(invisible(NULL))
}
