#' Run a process while writing data to its standard input
#'
#' `processx::run()` accepts `stdin = "|"` but never exposes the resulting
#' input connection, so nothing can ever be written to it — the child
#' process blocks forever waiting for input that will never come. This
#' helper drives `processx::process$new()` directly, writing `input` (if
#' any) to the process's stdin pipe and returning a `processx::run()`-shaped
#' result list (`status`, `stdout`, `stderr`, `timeout`, plus `pid`).
#'
#' On non-zero exit with `error_on_status = TRUE`, signals a condition with
#' class `"system_command_status_error"` and `status`/`stderr` fields, the
#' same contract `processx::run()` uses — so `rethrow_error_run()` handles
#' it identically regardless of which of the two ran the process. A missing
#' executable throws directly from `processx::process$new()` (classes
#' `rlib_error_3_0`/`c_error`), also already handled by
#' `rethrow_error_run()`.
#'
#' Unlike `processx::run()`, there is no live streaming of stdout/stderr, no
#' spinner, and no timeout support.
#'
#' Writing `input` and draining stdout/stderr are fully interleaved via
#' `pump_process_io()`, not a write-then-wait-then-read sequence — see that
#' function for the two hazards this avoids (confirmed empirically, not just
#' reasoned about): writing once and closing immediately silently truncates
#' `input` larger than the OS pipe buffer, and draining streams
#' sequentially (or after `wait()`) deadlocks once output exceeds it.
#' `read_output()`/`read_error()` are also mangled into hex-string
#' characters by `processx`'s own `read_all_output()`/`read_all_error()`
#' when `encoding = "binary"`, which `pump_process_io()` avoids too. Binary
#' streams are never echoed to the console.
#'
#' @keywords internal
#' @noRd
run_process_with_input <- function(
  command,
  args = character(),
  input = NULL,
  stdout = "|",
  stderr = "|",
  echo_cmd = FALSE,
  echo = FALSE,
  env = NULL,
  error_on_status = TRUE,
  cleanup_tree = FALSE,
  supervise = FALSE,
  linux_pdeathsig = FALSE,
  encoding = "utf-8"
) {
  proc <- processx::process$new(
    command = command,
    args = args,
    stdin = "|",
    stdout = stdout,
    stderr = stderr,
    env = env,
    echo_cmd = echo_cmd,
    supervise = supervise,
    cleanup_tree = cleanup_tree,
    encoding = encoding,
    linux_pdeathsig = linux_pdeathsig
  )

  is_binary <- identical(encoding, "binary")
  empty_stream <- if (isTRUE(is_binary)) raw(0L) else ""

  streams <- pump_process_io(proc, input = input, binary = is_binary)
  proc$wait()

  p_stdout <- if (is.null(streams$stdout)) empty_stream else streams$stdout
  p_stderr <- if (is.null(streams$stderr)) empty_stream else streams$stderr

  p_status <- proc$get_exit_status()
  if (is.null(p_status)) {
    p_status <- NA_integer_
  }
  p_pid <- proc$get_pid()

  # Binary streams are never echoed to the console, raw bytes have no
  # sensible terminal representation.
  if (isTRUE(echo) && isFALSE(is_binary)) {
    if (nzchar(p_stdout)) {
      cat(p_stdout)
    }
    if (nzchar(p_stderr)) base::message(p_stderr, appendLF = FALSE)
  }

  if (
    isTRUE(error_on_status) &&
      !is.na(p_status) &&
      !identical(p_status, 0L)
  ) {
    rlang::abort(
      message = sprintf("Command failed with status %d", p_status),
      class = "system_command_status_error",
      status = p_status,
      stderr = p_stderr
    )
  }

  return(list(
    status = p_status,
    stdout = p_stdout,
    stderr = p_stderr,
    timeout = FALSE,
    pid = p_pid
  ))
}
