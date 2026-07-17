#' Read all of a process's stdout/stderr stream as raw bytes
#'
#' `processx::process`'s `read_all_output()`/`read_all_error()` accumulate
#' chunks with `paste0(result, self$read_output())`. When the process was
#' created with `encoding = "binary"`, `read_output()`/`read_error()` return
#' raw vectors, and `paste0()` coerces each one to per-byte hex-string
#' characters (e.g. `"68" "65" "6c"`) instead of concatenating bytes, so the
#' reassembled result is not the original binary data. This reads the stream
#' in a loop using the byte-level accessors (`read_output_bytes()` /
#' `read_error_bytes()`, which return raw vectors regardless of the
#' process's configured encoding) and concatenates with `c()` instead.
#'
#' @param proc A `processx::process` object.
#' @param stream Character string, `"output"` or `"error"`.
#'
#' @returns A raw vector with the stream's full contents.
#'
#' @keywords internal
#' @noRd
read_all_stream_binary <- function(proc, stream = c("output", "error")) {
  stream <- rlang::arg_match(stream)
  is_incomplete <- if (identical(stream, "output")) {
    proc$is_incomplete_output
  } else {
    proc$is_incomplete_error
  }
  read_fn <- if (identical(stream, "output")) {
    proc$read_output_bytes
  } else {
    proc$read_error_bytes
  }

  result <- raw(0L)
  while (isTRUE(is_incomplete())) {
    proc$poll_io(-1)
    chunk <- read_fn(-1)
    if (length(chunk) > 0L) {
      result <- c(result, chunk)
    }
  }
  return(result)
}
