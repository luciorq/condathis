#' Single-line, raw-safe preview of a captured stdout/stderr stream
#'
#' Used by `format.condathis_result()` and `format.condathis_pipeline()`.
#' `binary = TRUE` on `run()`/`run_bin()`/`run_pipeline()` can make *either*
#' stdout or stderr a raw vector (`processx` shares one `encoding` between
#' both streams of a process), so both call sites must check for `raw` before
#' running character-only operations like `nzchar()`/`strsplit()` on it.
#'
#' @param x A character string, a raw vector, or `NA`/`NULL`.
#' @param max_chars Maximum length of the returned preview.
#'
#' @returns A single-line character string, or `NULL` when there is nothing
#'   to preview.
#'
#' @keywords internal
#' @noRd
stream_preview_line <- function(x, max_chars = 60L) {
  if (is.null(x)) {
    return(NULL)
  }
  if (isTRUE(is.raw(x))) {
    if (length(x) == 0L) {
      return(NULL)
    }
    return(sprintf("<binary data, %d bytes>", length(x)))
  }
  if (is.na(x) || !nzchar(x)) {
    return(NULL)
  }
  first_line <- strsplit(x, "\n")[[1]][1]
  if (nchar(first_line) > max_chars) {
    first_line <- paste0(substr(first_line, 1L, max_chars - 3L), "...")
  }
  return(first_line)
}

#' Multi-line, raw-safe stream text for `cli_abort()` messages
#'
#' Used when re-throwing failed-command errors (`rethrow_error_run()`,
#' `run_pipeline()`'s failure message), where the full (brace-escaped)
#' stderr text is split into lines. Falls back to a single placeholder line
#' when the stream is raw, instead of running `stringr` text operations on
#' it.
#'
#' @param x A character string or a raw vector.
#'
#' @returns A character vector of lines, possibly empty.
#'
#' @keywords internal
#' @noRd
stream_display_lines <- function(x) {
  if (isTRUE(is.raw(x))) {
    if (length(x) == 0L) {
      return(character())
    }
    return(sprintf("<binary data, %d bytes>", length(x)))
  }
  escaped <- escape_cli_braces(x)
  lines <- stringr::str_split(
    string = stringr::str_trim(escaped),
    pattern = stringr::regex("\\R"),
    simplify = FALSE
  )[[1]]
  return(lines)
}
