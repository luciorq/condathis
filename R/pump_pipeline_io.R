#' Drain every pipeline stage's R-side streams concurrently
#'
#' Pipeline counterpart to `pump_process_io()`.
#' Poll all stages' R-side connections in one loop and read whichever has
#' data.
#'
#' Draining one stage at a time deadlocks.
#' Draining stage 1's stderr to EOF requires stage 1 to exit.
#' That requires downstream stages to keep consuming its stdout.
#' A downstream stage consumes only while its own R-side pipes (stderr, and
#' stdout for the last stage) are read.
#' Once the data exceeds the OS pipe buffer, the last stage blocks on write
#' and stops reading its stdin.
#' Backpressure then freezes every upstream stage (reproduced with
#' `seq 1 500000 | cat`).
#'
#' Also write `input` to the first stage's stdin, interleaved with the
#' draining (see `pump_process_io()`).
#' Close the stdin connection immediately when there is no input.
#' A write onto an already-exited first stage (broken pipe) means the input
#' is undeliverable: close the connection and continue the loop.
#' The stage's own exit status then reports the failure, and no low-level
#' error escapes `error = "continue"`.
#'
#' On a finite `deadline`, run one final zero-timeout poll-and-drain pass
#' before returning `timeout = TRUE`.
#' This captures output the stages already produced, because `kill()`
#' invalidates a process's connections immediately and discards unread data.
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
#' @param echo Logical. Whether to print every chunk as it is read, like
#'   `processx::run(echo = TRUE)`: standard output as is, standard error in
#'   red. Text mode only. Defaults to `FALSE`.
#' @param spinner Logical. Whether to show a spinner while the pipeline
#'   runs, drawn like the spinner of `processx::run()`: the cursor returns
#'   to the start of the line, so echoed output overwrites it, and it is
#'   not drawn while an echoed line is unfinished. Defaults to `FALSE`.
#'
#' On Windows, also end stages that write after their reader has exited,
#' as `SIGPIPE` does on Unix (see `reap_windows_broken_pipes()`).
#'
#' @param watch `NULL`, or the orphaned-pipe watch functions passed on to
#'   `reap_windows_broken_pipes()`.
#'
#' @returns A list with `stdout` and `stderr` (each a list with one
#'   element per stage: combined text/raw for drained streams, `NULL` for
#'   streams that were not piped to R or stages that never spawned),
#'   `timeout` (logical) and `broken_pipe` (the
#'   `reap_windows_broken_pipes()` state).
#'
#' @keywords internal
#' @noRd
pump_pipeline_io <- function(
  procs,
  input = NULL,
  binary = FALSE,
  deadline = Inf,
  echo = FALSE,
  spinner = FALSE,
  watch = NULL
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

  pending_input <- normalize_stdin_input(input, binary = binary)
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

  # A stage killed for a broken pipe has invalid connections: never touch
  # them again.
  reaped <- rep(FALSE, n)
  stream_open <- function(i) {
    isFALSE(reaped[[i]]) &&
      ((has_out[[i]] && isTRUE(procs[[i]]$is_incomplete_output())) ||
        (has_err[[i]] && isTRUE(procs[[i]]$is_incomplete_error())))
  }

  echo <- isTRUE(echo) && isFALSE(binary)
  # Whether the echoed output ends at the start of a line, where the
  # spinner can be drawn without hiding part of it.
  at_line_start <- TRUE
  spin_frame <- 0L
  spin <- function() {
    if (isFALSE(spinner) || isFALSE(at_line_start)) {
      return(invisible(NULL))
    }
    frames <- c("-", "\\", "|", "/")
    spin_frame <<- spin_frame %% length(frames) + 1L
    cat("\r", frames[[spin_frame]], "\r", sep = "")
    utils::flush.console()
  }
  if (isTRUE(spinner)) {
    on.exit(if (isTRUE(at_line_start)) cat("\r \r"), add = TRUE)
  }
  echo_chunk <- function(chunk, error_stream) {
    cat(if (isTRUE(error_stream)) cli::col_red(chunk) else chunk, sep = "")
    at_line_start <<- endsWith(chunk, "\n")
  }

  broken_pipe <- new_broken_pipe_state(n)
  drain_stage <- function(i) {
    n_out <- length(out_chunks[[i]])
    n_err <- length(err_chunks[[i]])
    out_chunks[[i]] <<- pump_read_chunk(
      procs[[i]],
      chunks = out_chunks[[i]],
      stream = "output",
      active = has_out[[i]],
      binary = binary
    )
    err_chunks[[i]] <<- pump_read_chunk(
      procs[[i]],
      chunks = err_chunks[[i]],
      stream = "error",
      active = has_err[[i]],
      binary = binary
    )
    if (isTRUE(echo)) {
      if (length(out_chunks[[i]]) > n_out) {
        echo_chunk(out_chunks[[i]][[length(out_chunks[[i]])]], FALSE)
      }
      if (length(err_chunks[[i]]) > n_err) {
        echo_chunk(err_chunks[[i]][[length(err_chunks[[i]])]], TRUE)
      }
    }
  }

  timed_out <- FALSE
  repeat {
    spin()
    broken_pipe <- reap_windows_broken_pipes(
      procs,
      broken_pipe,
      before_kill = function(i) {
        drain_stage(i)
        reaped[[i]] <<- TRUE
      },
      watch = watch
    )
    open_idx <- which(vapply(seq_len(n), stream_open, logical(1L)))
    if (isTRUE(input_done) && identical(length(open_idx), 0L)) {
      break
    }

    deadline_hit <- isTRUE(is.finite(deadline)) &&
      proc.time()[["elapsed"]] >= deadline

    # Poll for at most 200 ms so the loop can retry a pending input write
    # and check a finite deadline. After the deadline, poll with timeout 0
    # for the final drain pass (see the `deadline` paragraph in the docs).
    if (identical(length(open_idx), 0L)) {
      # Only input left to write, nothing pollable: pace the retry.
      if (isFALSE(deadline_hit)) {
        Sys.sleep(0.05)
      }
    } else {
      # Poll the still-open connections, not the processes: polling a
      # process reports a stream that is already at EOF as ready on every
      # call, so a stage that closed one stream while keeping the other
      # open turned this loop into a busy spin.
      open_conns <- unlist(
        lapply(open_idx, function(i) {
          c(
            if (has_out[[i]] && isTRUE(procs[[i]]$is_incomplete_output())) {
              list(procs[[i]]$get_output_connection())
            },
            if (has_err[[i]] && isTRUE(procs[[i]]$is_incomplete_error())) {
              list(procs[[i]]$get_error_connection())
            }
          )
        }),
        recursive = FALSE
      )
      processx::poll(open_conns, if (isTRUE(deadline_hit)) 0L else 200L)
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
      drain_stage(i)
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
    timeout = timed_out,
    broken_pipe = broken_pipe
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
