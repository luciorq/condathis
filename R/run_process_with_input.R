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
#' Unlike `processx::run()`, there is no live streaming of stdout/stderr or
#' spinner. `timeout` mirrors `processx::run()`'s own contract as closely as
#' possible: on expiry the process is killed (`proc$kill()`), `status` is
#' forced to `-9` (a `condathis`-normalized sentinel, not read from the
#' killed process's own exit status — that value is an OS/`processx`
#' implementation detail confirmed to differ across platforms, e.g. `2` on
#' Windows for the identical `kill()` call), `timeout = TRUE` is set, and —
#' gated by `error_on_status` exactly like a regular non-zero exit — a
#' condition of class `"system_command_timeout_error"` is signaled instead
#' of `"system_command_status_error"`, so callers can tell the two apart.
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
  wd = NULL,
  error_on_status = TRUE,
  cleanup_tree = FALSE,
  supervise = FALSE,
  linux_pdeathsig = FALSE,
  encoding = "utf-8",
  timeout = Inf
) {
  deadline <- if (isTRUE(is.finite(timeout))) {
    proc.time()[["elapsed"]] + timeout
  } else {
    Inf
  }

  proc <- processx::process$new(
    command = command,
    args = args,
    stdin = "|",
    stdout = stdout,
    stderr = stderr,
    env = env,
    wd = wd,
    echo_cmd = echo_cmd,
    supervise = supervise,
    cleanup_tree = cleanup_tree,
    encoding = encoding,
    linux_pdeathsig = linux_pdeathsig
  )

  is_binary <- identical(encoding, "binary")
  empty_stream <- if (isTRUE(is_binary)) raw(0L) else ""

  streams <- pump_process_io(
    proc,
    input = input,
    binary = is_binary,
    deadline = deadline
  )

  p_timeout <- isTRUE(streams$timeout)
  if (isTRUE(p_timeout)) {
    proc$kill()
  }
  proc$wait()

  p_stdout <- if (is.null(streams$stdout)) empty_stream else streams$stdout
  p_stderr <- if (is.null(streams$stderr)) empty_stream else streams$stderr

  # Normalized to a fixed sentinel on timeout rather than trusting
  # `get_exit_status()`'s raw value: how a killed process's own exit status
  # is reported is an OS/`processx` implementation detail, not something
  # `condathis` controls — confirmed empirically to differ across
  # platforms (`-9` on Linux/macOS, `2` on Windows, for the identical
  # `proc$kill()` call). `-9` was already the documented cross-platform
  # contract for a timed-out `condathis_result`; this makes it actually
  # true everywhere instead of true only where the OS happens to agree.
  if (isTRUE(p_timeout)) {
    p_status <- -9L
  } else {
    p_status <- proc$get_exit_status()
    if (is.null(p_status)) {
      p_status <- NA_integer_
    }
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
    if (isTRUE(p_timeout)) {
      rlang::abort(
        message = sprintf("Command timed out after %s seconds", timeout),
        class = "system_command_timeout_error",
        status = p_status,
        stderr = p_stderr
      )
    }
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
    timeout = p_timeout,
    pid = p_pid
  ))
}
