#' Write input to a process's stdin while draining stdout/stderr, all
#' interleaved, without deadlocking or silently truncating
#'
#' Two hazards, both confirmed empirically, share one fix: an interleaved
#' poll loop.
#'
#' 1. **Truncated writes.** `proc$write_input()` makes one non-blocking
#'    write syscall.
#'    It can write less than asked and returns the undelivered remainder,
#'    which the R wrapper discards.
#'    Closing right after one call truncates any `input` larger than the OS
#'    pipe buffer, with no error.
#'    On macOS, `input` of 200,000 bytes delivered only 8,192 bytes to the
#'    child (verified with `wc -c` on the receiving end).
#'    The fix retries the write with the returned remainder.
#' 2. **Deadlock.** Draining stdout and stderr sequentially, or waiting for
#'    exit before reading, deadlocks once combined output exceeds the OS
#'    pipe buffer (64KB on Linux, much smaller on macOS and Windows).
#'    The child blocks on `write()` to the stream not yet read.
#'    Retrying a stdin write without draining stdout fails the same way.
#'    A child that echoes input (e.g. `cat`) blocks when its output pipe
#'    fills, stops reading stdin, and stalls the write retry forever.
#'    The loop polls all three directions once per iteration, as
#'    `processx::run()` does internally.
#'
#' Reads use `read_output()`/`read_error()` (text) or
#' `read_output_bytes()`/`read_error_bytes()` (`binary = TRUE`).
#' `processx`'s `read_all_output()`/`read_all_error()` mangle raw bytes into
#' hex text, because `paste0()` coerces `raw` to per-byte hex strings.
#'
#' Call `proc$wait()` after this function returns, never before or in
#' between.
#'
#' @param proc A `processx::process` object.
#' @param input `NULL`, a character string, or a raw vector to write to
#'   `proc`'s stdin (which must have been created with `stdin = "|"`). The
#'   input connection is always closed once fully written (or immediately,
#'   when `input` is `NULL`), signaling EOF to the child.
#' @param want_stdout,want_stderr Logical. Whether to drain that stream at
#'   all. Actual draining additionally requires the process to have a piped
#'   connection for it (e.g. `run_pipeline()` only pipes stdout for its last
#'   command).
#' @param binary Logical. Read raw bytes (`TRUE`) or UTF-8 text (`FALSE`).
#' @param deadline Numeric. An absolute point in time, comparable to
#'   `proc.time()[["elapsed"]]`, after which draining stops even if the
#'   process hasn't finished, e.g. `proc.time()[["elapsed"]] + timeout`.
#'   Defaults to `Inf` (never times out). Does **not** kill the process.
#'   The caller must kill it (see the `timeout` element of the return value)
#'   and call `proc$wait()` regardless.
#'
#' @returns A list with `stdout`/`stderr` elements, each a raw vector
#'   (`binary = TRUE`) or a character string (`binary = FALSE`), or `NULL`
#'   when the stream was not drained (no `want_*`, or no piped connection).
#'   The `timeout` element is logical: `TRUE` if `deadline` was reached
#'   before the process finished.
#'
#' @keywords internal
#' @noRd
pump_process_io <- function(
  proc,
  input = NULL,
  want_stdout = TRUE,
  want_stderr = TRUE,
  binary = FALSE,
  deadline = Inf
) {
  has_out <- isTRUE(want_stdout) && isTRUE(proc$has_output_connection())
  has_err <- isTRUE(want_stderr) && isTRUE(proc$has_error_connection())

  pending_input <- normalize_stdin_input(input, binary = binary)
  input_done <- is.null(input)
  if (isTRUE(input_done) && isTRUE(proc$has_input_connection())) {
    close(proc$get_input_connection())
  }

  out_chunks <- list()
  err_chunks <- list()
  timed_out <- FALSE

  while (
    isFALSE(input_done) ||
      (has_out && isTRUE(proc$is_incomplete_output())) ||
      (has_err && isTRUE(proc$is_incomplete_error()))
  ) {
    deadline_hit <- isTRUE(is.finite(deadline)) &&
      proc.time()[["elapsed"]] >= deadline

    # Poll for 200 ms while writing, so a full pipe cannot stall the retry.
    # Once input is sent and no finite `deadline` is active, block until
    # data or EOF is ready. With a finite `deadline`, keep the 200 ms poll
    # so the loop checks the deadline. After the deadline, poll with
    # timeout 0: `kill()` invalidates the connection and discards unread
    # output, so this instant drain is the last chance to recover it.
    proc$poll_io(
      if (isTRUE(deadline_hit)) {
        0
      } else if (isTRUE(input_done) && isFALSE(is.finite(deadline))) {
        -1
      } else {
        200
      }
    )

    if (isFALSE(input_done)) {
      # A child that exits before consuming stdin is not an R-level error.
      # The write raises a low-level broken-pipe condition (`c_error`, no
      # `status` field). Uncaught, `rethrow_error_run()` would misreport it
      # as status 127 ("command not found") and mask the real exit status.
      # Treat it as "input undeliverable": stop writing, keep draining, and
      # let the exit status report the failure (mirrors
      # `pump_pipeline_io()`).
      write_res <- tryCatch(
        proc$write_input(pending_input),
        error = function(e) e
      )
      if (inherits(write_res, "error")) {
        input_done <- TRUE
        if (isTRUE(proc$has_input_connection())) {
          try(close(proc$get_input_connection()), silent = TRUE)
        }
      } else {
        if (identical(length(write_res), 0L)) {
          input_done <- TRUE
          if (isTRUE(proc$has_input_connection())) {
            close(proc$get_input_connection())
          }
        }
        pending_input <- write_res
      }
    }

    if (has_out && isTRUE(proc$is_incomplete_output())) {
      chunk <- if (isTRUE(binary)) {
        proc$read_output_bytes(-1)
      } else {
        proc$read_output(-1)
      }
      if (
        !is.null(chunk) &&
          (if (isTRUE(binary)) length(chunk) > 0L else nzchar(chunk))
      ) {
        out_chunks[[length(out_chunks) + 1L]] <- chunk
      }
    }
    if (has_err && isTRUE(proc$is_incomplete_error())) {
      chunk <- if (isTRUE(binary)) {
        proc$read_error_bytes(-1)
      } else {
        proc$read_error(-1)
      }
      if (
        !is.null(chunk) &&
          (if (isTRUE(binary)) length(chunk) > 0L else nzchar(chunk))
      ) {
        err_chunks[[length(err_chunks) + 1L]] <- chunk
      }
    }

    if (isTRUE(deadline_hit)) {
      timed_out <- TRUE
      break
    }
  }

  combine <- function(chunks) {
    if (isTRUE(binary)) {
      return(do.call(c, c(list(raw(0L)), chunks)))
    }
    return(paste0(unlist(chunks), collapse = ""))
  }

  return(list(
    stdout = if (has_out) combine(out_chunks) else NULL,
    stderr = if (has_err) combine(err_chunks) else NULL,
    timeout = timed_out
  ))
}

#' Wait on a process, tolerating an already-finalized handle
#'
#' On Windows, `proc$wait()` can race a concurrent process exit.
#' The OS process handle can be finalized between a liveness check (or a
#' `kill()`) and the wait.
#' `processx` then throws a low-level `c_error` ("failed to wait on process
#' ... The handle is invalid.", system error 6) for a process that is
#' already dead.
#' Windows CI hit this in a pipeline timeout test: the downstream stage
#' exited on EOF after the upstream kill, as the settle logic killed and
#' waited on it.
#' Treat a wait that fails this way as a wait that already returned.
#'
#' @param proc A `processx::process` object.
#' @param timeout `NULL` for an unbounded wait, else milliseconds.
#'
#' @returns `TRUE` if the wait completed normally, `FALSE` if it failed
#'   because the process handle was already finalized (invisibly).
#'
#' @keywords internal
#' @noRd
wait_process_safely <- function(proc, timeout = NULL) {
  return(invisible(tryCatch(
    {
      if (is.null(timeout)) {
        proc$wait()
      } else {
        proc$wait(timeout = timeout)
      }
      TRUE
    },
    error = function(e) FALSE
  )))
}

#' Read a process's exit status, tolerating a finalized handle
#'
#' Companion to `wait_process_safely()`: when the handle was finalized
#' mid-race, `get_exit_status()` may also fail; the caller treats `NA` as
#' "exited, status unknown", which every consumer already handles.
#'
#' @keywords internal
#' @noRd
exit_status_safely <- function(proc) {
  status <- tryCatch(
    proc$get_exit_status(),
    error = function(e) NULL
  )
  if (is.null(status)) {
    return(NA_integer_)
  }
  return(status)
}
