#' Drain every pipeline stage's R-side streams concurrently
#'
#' The pipeline counterpart to `pump_process_io()`, and the fix for a
#' deadlock the sequential per-stage version of this logic could not avoid:
#' draining stage 1's stderr to EOF requires stage 1 to exit, which
#' requires downstream stages to keep consuming its stdout - but a
#' downstream stage only keeps consuming while its *own* R-side pipes
#' (stderr, and for the last stage stdout) are being read. Draining one
#' stage at a time left the last stage's stdout-to-R pipe unread; once the
#' data flowing through the pipeline exceeded the OS pipe buffer, the last
#' stage blocked writing, stopped reading its stdin, and the backpressure
#' froze every stage upstream - a permanent hang, reproduced empirically
#' with `seq 1 500000 | cat`. The only ordering that cannot deadlock is no
#' ordering: poll *all* stages' R-side connections in one loop and read
#' whichever has data, which is what this function does.
#'
#' Also owns writing `input` to the first stage's stdin (interleaved with
#' the draining, for the same single-process reasons documented in
#' `pump_process_io()`), including the EOF-close when there is no input,
#' and treats a write onto an already-exited first stage (broken pipe) as
#' "input undeliverable": the connection is closed and the loop continues,
#' letting that stage's own exit status tell the story instead of an
#' uncaught low-level error escaping `error = "continue"`.
#'
#' On a finite `deadline`, one final zero-timeout poll-and-drain pass runs
#' before returning `timeout = TRUE`, so output stages already produced is
#' captured before the caller kills anything - `kill()` invalidates a
#' process's connections immediately (confirmed empirically), discarding
#' whatever is still unread.
#'
#' @param procs List of `processx::process` objects (or `NULL` for stages
#'   that failed to spawn). Only R-side piped connections are drained: in
#'   practice every stage's stderr (when `"|"`) and the last stage's
#'   stdout; inter-stage stdout-to-stdin wiring is kernel-level and never
#'   touches R.
#' @param input `NULL`, or a character/raw vector to write to the first
#'   stage's stdin (which must have been spawned with `stdin = "|"`).
#' @param binary Logical. Read raw bytes (`TRUE`) or UTF-8 text (`FALSE`).
#' @param deadline Numeric. Absolute `proc.time()[["elapsed"]]` cutoff, or
#'   `Inf`.
#'
#' @returns A list with `stdout` and `stderr` (each a list with one
#'   element per stage: combined text/raw for drained streams, `NULL` for
#'   streams that were not piped to R or stages that never spawned) and
#'   `timeout` (logical).
#'
#' @keywords internal
#' @noRd
pump_pipeline_io <- function(
  procs,
  input = NULL,
  binary = FALSE,
  deadline = Inf
) {
  n <- length(procs)
  live <- !vapply(procs, is.null, logical(1L))
  has_out <- vapply(
    seq_len(n),
    function(i) live[[i]] && isTRUE(procs[[i]]$has_output_connection()),
    logical(1L)
  )
  has_err <- vapply(
    seq_len(n),
    function(i) live[[i]] && isTRUE(procs[[i]]$has_error_connection()),
    logical(1L)
  )
  out_chunks <- rep(list(list()), n)
  err_chunks <- rep(list(list()), n)

  pending_input <- input
  input_done <- is.null(input)
  first_writable <- isTRUE(live[[1L]]) &&
    isTRUE(procs[[1L]]$has_input_connection())
  if (isFALSE(input_done) && isFALSE(first_writable)) {
    # Nothing to write into (the first stage never spawned); its synthetic
    # failure result already reports why.
    input_done <- TRUE
  }
  if (isTRUE(input_done) && isTRUE(first_writable)) {
    close(procs[[1L]]$get_input_connection())
  }

  stream_open <- function(i) {
    (has_out[[i]] && isTRUE(procs[[i]]$is_incomplete_output())) ||
      (has_err[[i]] && isTRUE(procs[[i]]$is_incomplete_error()))
  }

  timed_out <- FALSE
  repeat {
    open_idx <- which(vapply(seq_len(n), stream_open, logical(1L)))
    if (isTRUE(input_done) && identical(length(open_idx), 0L)) {
      break
    }

    deadline_hit <- isTRUE(is.finite(deadline)) &&
      proc.time()[["elapsed"]] >= deadline

    # Bounded poll (200ms) rather than blocking indefinitely: the loop
    # must keep coming back around to retry a pending input write and to
    # check a finite deadline. Once the deadline has been reached, poll
    # non-blockingly for the final drain pass instead of skipping straight
    # to `break` (see the deadline paragraph in the docs above).
    if (identical(length(open_idx), 0L)) {
      # Only input left to write, nothing pollable: pace the retry.
      if (isFALSE(deadline_hit)) {
        Sys.sleep(0.05)
      }
    } else {
      processx::poll(procs[open_idx], if (isTRUE(deadline_hit)) 0L else 200L)
    }

    if (isFALSE(input_done)) {
      write_res <- tryCatch(
        procs[[1L]]$write_input(pending_input),
        error = function(e) e
      )
      if (inherits(write_res, "error")) {
        # Broken pipe: the first stage exited before consuming its input.
        input_done <- TRUE
        try(close(procs[[1L]]$get_input_connection()), silent = TRUE)
      } else {
        pending_input <- write_res
        if (identical(length(pending_input), 0L)) {
          input_done <- TRUE
          close(procs[[1L]]$get_input_connection())
        }
      }
    }

    for (i in open_idx) {
      out_chunks[[i]] <- pump_read_chunk(
        procs[[i]],
        chunks = out_chunks[[i]],
        stream = "output",
        active = has_out[[i]],
        binary = binary
      )
      err_chunks[[i]] <- pump_read_chunk(
        procs[[i]],
        chunks = err_chunks[[i]],
        stream = "error",
        active = has_err[[i]],
        binary = binary
      )
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
  stdout_streams <- lapply(seq_len(n), function(i) {
    if (has_out[[i]]) combine(out_chunks[[i]]) else NULL
  })
  stderr_streams <- lapply(seq_len(n), function(i) {
    if (has_err[[i]]) combine(err_chunks[[i]]) else NULL
  })

  return(list(
    stdout = stdout_streams,
    stderr = stderr_streams,
    timeout = timed_out
  ))
}

#' Read whatever is available from one stream of one process
#'
#' Non-blocking single read, appended to `chunks` when non-empty. The
#' read/append logic mirrors `pump_process_io()`'s exactly, including
#' using the `_bytes` readers in binary mode (`processx`'s own
#' `read_all_*()` helpers mangle raw bytes into hex text).
#'
#' @keywords internal
#' @noRd
pump_read_chunk <- function(proc, chunks, stream, active, binary) {
  if (isFALSE(active)) {
    return(chunks)
  }
  incomplete <- if (identical(stream, "output")) {
    isTRUE(proc$is_incomplete_output())
  } else {
    isTRUE(proc$is_incomplete_error())
  }
  if (isFALSE(incomplete)) {
    return(chunks)
  }
  chunk <- if (identical(stream, "output")) {
    if (isTRUE(binary)) proc$read_output_bytes(-1) else proc$read_output(-1)
  } else {
    if (isTRUE(binary)) proc$read_error_bytes(-1) else proc$read_error(-1)
  }
  if (
    !is.null(chunk) &&
      (if (isTRUE(binary)) length(chunk) > 0L else nzchar(chunk))
  ) {
    chunks[[length(chunks) + 1L]] <- chunk
  }
  return(chunks)
}
