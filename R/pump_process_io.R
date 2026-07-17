#' Drain a process's stdout/stderr without deadlocking
#'
#' Draining stdout and stderr sequentially — read one fully to EOF, then the
#' other — deadlocks once combined output exceeds the OS pipe buffer (64KB
#' on Linux, much smaller on macOS/Windows): the child blocks on `write()`
#' to whichever stream isn't being read yet, so it never reaches EOF on the
#' stream we *are* reading either. Calling `proc$wait()` before reading
#' anything is the same bug with one stream. This polls both connections
#' together, once per loop iteration, so neither stream's OS buffer can ever
#' fill up while the other is being drained — the same approach
#' `processx::run()` uses internally. Verified empirically: sequential
#' draining reproducibly hangs with >64KB on both streams; this loop drains
#' 200KB on each in well under a second.
#'
#' `read_output()`/`read_error()` (text) or `read_output_bytes()`/
#' `read_error_bytes()` (`binary = TRUE`) are used depending on `binary`,
#' since `processx`'s own `read_all_output()`/`read_all_error()` additionally
#' mangle raw bytes into hex-string characters when reading in binary mode
#' (they concatenate chunks with `paste0()`, which coerces `raw` to per-byte
#' hex text).
#'
#' Callers must call `proc$wait()` themselves *after* this returns — never
#' before, and never in between draining the two streams.
#'
#' @param proc A `processx::process` object.
#' @param want_stdout,want_stderr Logical. Whether to drain that stream at
#'   all. Actual draining additionally requires the process to have a piped
#'   connection for it (e.g. `run_pipeline()` only pipes stdout for its last
#'   command).
#' @param binary Logical. Read raw bytes (`TRUE`) or UTF-8 text (`FALSE`).
#'
#' @returns A list with `stdout`/`stderr` elements, each a raw vector
#'   (`binary = TRUE`) or a character string (`binary = FALSE`), or `NULL`
#'   when the corresponding stream was not drained (no `want_*`, or no piped
#'   connection).
#'
#' @keywords internal
#' @noRd
read_all_streams <- function(
  proc,
  want_stdout = TRUE,
  want_stderr = TRUE,
  binary = FALSE
) {
  has_out <- isTRUE(want_stdout) && isTRUE(proc$has_output_connection())
  has_err <- isTRUE(want_stderr) && isTRUE(proc$has_error_connection())

  out_chunks <- list()
  err_chunks <- list()

  while (
    (has_out && isTRUE(proc$is_incomplete_output())) ||
      (has_err && isTRUE(proc$is_incomplete_error()))
  ) {
    proc$poll_io(-1)
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
  }

  combine <- function(chunks) {
    if (isTRUE(binary)) {
      return(do.call(c, c(list(raw(0L)), chunks)))
    }
    return(paste0(unlist(chunks), collapse = ""))
  }

  return(list(
    stdout = if (has_out) combine(out_chunks) else NULL,
    stderr = if (has_err) combine(err_chunks) else NULL
  ))
}
