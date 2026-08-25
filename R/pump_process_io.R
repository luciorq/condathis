#' Write input to a process's stdin while draining stdout/stderr, all
#' interleaved, without deadlocking or silently truncating
#'
#' Two distinct hazards, both confirmed empirically (not just reasoned
#' about), both fixed by the same interleaved poll loop:
#'
#' 1. **Truncated writes.** `proc$write_input()`'s underlying write is a
#'    single, non-blocking syscall that can - and does - write less than
#'    asked and silently return the undelivered remainder, which the R
#'    wrapper discards. Calling it once and closing immediately after
#'    truncates any `input` bigger than the OS pipe buffer with no error:
#'    confirmed on macOS, `input` of 200,000 bytes silently delivered only
#'    8,192 to the child, verified independently with `wc -c` on the
#'    receiving end. This retries the write with the returned leftover
#'    instead of discarding it.
#' 2. **Deadlock.** Draining stdout and stderr sequentially - or waiting for
#'    the process to exit before reading either - deadlocks once combined
#'    output exceeds the OS pipe buffer (64KB on Linux, much smaller on
#'    macOS/Windows): the child blocks on `write()` to whichever stream
#'    isn't being read yet, so it never finishes. Retrying a stdin write
#'    without concurrently draining stdout has the same failure mode one
#'    level up - a child that echoes input to output (e.g. `cat`) blocks
#'    writing its own output once *that* pipe fills, which stalls it from
#'    reading more stdin, which stalls the write retry forever. This polls
#'    all three directions together, once per loop iteration, matching how
#'    `processx::run()` avoids the same class of hazard internally.
#'
#' `read_output()`/`read_error()` (text) or `read_output_bytes()`/
#' `read_error_bytes()` (`binary = TRUE`) are used for reads, since
#' `processx`'s own `read_all_output()`/`read_all_error()` additionally
#' mangle raw bytes into hex-string characters when reading in binary mode
#' (they concatenate chunks with `paste0()`, which coerces `raw` to per-byte
#' hex text).
#'
#' Callers must call `proc$wait()` themselves *after* this returns - never
#' before, and never in between.
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
#'   process hasn't finished - e.g. `proc.time()[["elapsed"]] + timeout`.
#'   Defaults to `Inf` (never times out, the original behavior). Does
#'   **not** kill the process itself; the caller is responsible for that
#'   (see the `timeout` element of the return value) and for calling
#'   `proc$wait()` regardless, same as always.
#'
#' @returns A list with `stdout`/`stderr` elements, each a raw vector
#'   (`binary = TRUE`) or a character string (`binary = FALSE`), or `NULL`
#'   when the corresponding stream was not drained (no `want_*`, or no piped
#'   connection); and a `timeout` logical element, `TRUE` if `deadline` was
#'   reached before the process finished.
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

  pending_input <- input
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

    # Short timeout while still writing, so a full pipe doesn't stall the
    # retry indefinitely; once input is fully sent, block until more
    # output/error data (or EOF) is actually ready - unless a finite
    # `deadline` is active, in which case that indefinite wait is replaced
    # with the same short poll used while writing, so the loop keeps
    # coming back around to check the deadline instead of blocking past it.
    # Once the deadline itself has been reached, poll non-blockingly (`0`)
    # instead of skipping straight to `break`: killing a process discards
    # any output still sitting unread in its connection (confirmed
    # empirically - `processx` invalidates the connection on `kill()`), so
    # this last, instant drain is the only chance to recover data the
    # child already produced before the caller kills it.
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
      leftover <- proc$write_input(pending_input)
      if (length(leftover) == 0L) {
        input_done <- TRUE
        if (isTRUE(proc$has_input_connection())) {
          close(proc$get_input_connection())
        }
      }
      pending_input <- leftover
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
