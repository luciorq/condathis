#' Split the output of a command into lines
#'
#' Splits an output stream of a [run()], [run_bin()] or [run_pipeline()]
#' result into lines.
#'
#' Lines end at a line feed, a carriage return and line feed pair, or a
#' carriage return alone, so the result is the same on every operating
#' system. `parse_output()` removes the line ends, and a line end at the end
#' of the output does not start one more, empty line. It keeps the rest of
#' the text as the command wrote it: spaces and tabs at the start and end of
#' lines, and blank lines. Empty output gives `character(0)`.
#'
#' `trim = TRUE` also removes whitespace at the start and end of each line,
#' and blank lines at the start and end of the output. This is useful for
#' a single value, such as a version string. It changes tab-separated
#' output with empty first or last fields, and indented text such as YAML.
#'
#' @param res A [run()], [run_bin()] or [run_pipeline()] result, another
#'   list with `stdout` or `stderr` elements, or a character vector for
#'   `stream = "plain"`. For a pipeline result, `"stdout"` is the output of
#'   the last command, the only one whose standard output is captured.
#'   `"stderr"` joins the captured standard error of every command, in
#'   command order. `parse_output()` cannot split a raw stream, from
#'   `binary = TRUE`, into lines. Use the raw vector itself, for example with
#'   [writeBin()].
#' @param stream Character string selecting the output source:
#'   `"stdout"` (the default), `"stderr"`, `"both"` or `"plain"`.
#'   * `"stdout"` and `"stderr"` abort when that stream was not captured
#'     (redirected to a file or discarded, `NA` in the result).
#'   * `"both"` gives all of the standard output, then all of the standard
#'     error. The order in which the command wrote to the two streams is
#'     lost. `parse_output()` leaves out a stream that was not captured. It
#'     aborts only if neither stream was captured.
#'   * `"plain"` reads `res` itself, a character vector without missing
#'     values. `parse_output()` joins its elements with line ends.
#'
#'   Other values abort with class `condathis_invalid_stream`.
#' @param trim Logical. Whether to remove whitespace at the start and end of
#'   each line, and blank lines at the start and end of the output. Defaults
#'   to `FALSE`. Values other than `TRUE` and `FALSE` abort with class
#'   `condathis_invalid_trim`.
#'
#' @returns A character vector with one line per element, without line
#'   ends. `character(0)` for empty output. A `res` that cannot be read
#'   aborts with class `condathis_parse_output_invalid_res` (also
#'   `condathis_invalid_res`), and a raw stream with
#'   `condathis_parse_output_binary_stream`.
#'
#' @examples
#' # A list with the output fields of a `run()` result
#' res <- list(
#'   stdout = "line1\nline2\nline3\n",
#'   stderr = "error1\nerror2\n"
#' )
#'
#' # Parse the standard output
#' parse_output(res, stream = "stdout")
#'
#' # Parse the standard error
#' parse_output(res, stream = "stderr")
#'
#' # Merge both
#' parse_output(res, stream = "both")
#'
#' # Parse plain text
#' plain_text <- "This is line one.\nThis is line two.\nThis is line three."
#' parse_output(plain_text, stream = "plain")
#'
#' # Whitespace is kept: the empty first field of this tab-separated line
#' # stays in place
#' parse_output("\tchr1\t100\n", stream = "plain")
#'
#' # Remove it when only the text matters
#' parse_output("  2.9.0  \n\n", stream = "plain", trim = TRUE)
#'
#' @family commands
#'
#' @export
parse_output <- function(
  res,
  stream = c("stdout", "stderr", "both", "plain"),
  trim = FALSE
) {
  stream <- arg_match_classed(
    stream,
    values = c("stdout", "stderr", "both", "plain"),
    class = arg_error_class("parse_output", "stream"),
    arg_name = "stream"
  )
  validate_bool_arg(
    trim,
    class = arg_error_class("parse_output", "trim"),
    arg_name = "trim"
  )
  res_class <- arg_error_class("parse_output", "res")

  if (inherits(res, "condathis_pipeline")) {
    res <- pipeline_output_streams(res)
  }

  if (
    isFALSE(rlang::is_character(res)) &&
      isFALSE(
        rlang::is_list(res) &&
          (rlang::has_name(res, "stdout") || rlang::has_name(res, "stderr"))
      )
  ) {
    condathis_abort(
      c(
        `x` = "{.arg res} must be a character vector, or a list with {.field stdout} and {.field stderr} elements, not {.obj_type_friendly {res}}."
      ),
      class = res_class
    )
  }

  if (
    identical(stream, "plain") &&
      isTRUE(rlang::is_character(res)) &&
      isTRUE(anyNA(res))
  ) {
    condathis_abort(
      c(
        `x` = "{.arg res} must not contain missing values with {.code stream = \"plain\"}."
      ),
      class = res_class
    )
  }

  if (rlang::is_list(res)) {
    binary_streams <- Filter(
      x = c("stdout", "stderr"),
      f = function(nm) rlang::has_name(res, nm) && isTRUE(is.raw(res[[nm]]))
    )
    if (
      length(binary_streams) > 0L &&
        (identical(stream, "both") || stream %in% binary_streams)
    ) {
      condathis_abort(
        c(
          `x` = "{.field {binary_streams}}: raw binary data, not text.",
          `i` = "{.fn parse_output} only works on character output. Read the raw vector directly instead (e.g. with {.fn writeBin})."
        ),
        class = c("condathis_parse_output_binary_stream", res_class)
      )
    }
  }

  # Start from `NULL`: an `exists("raw_text")` check also found a
  # same-named variable in the caller's workspace and returned its value.
  raw_text <- NULL
  if (stream %in% c("stdout", "stderr") && rlang::has_name(res, stream)) {
    if (isFALSE(is_uncaptured_stream(res[[stream]]))) {
      raw_text <- res[[stream]]
    }
  } else if (identical(stream, "both") && rlang::is_list(res)) {
    # `[[` and not `$`, which would read a `stdout_file` field as `stdout`.
    parts <- list(res[["stdout"]], res[["stderr"]])
    captured <- !vapply(parts, is_uncaptured_stream, logical(1L))
    if (isTRUE(any(captured))) {
      raw_text <- join_output_parts(parts[captured])
    }
  } else if (identical(stream, "plain") && rlang::is_character(res)) {
    raw_text <- paste0(res, collapse = "\n")
  }

  if (is.null(raw_text)) {
    hint <- if (isTRUE(rlang::is_character(res))) {
      c(`i` = "Use {.code stream = \"plain\"} to read a character vector.")
    } else {
      c(
        `i` = "A stream that was redirected to a file or discarded is not captured."
      )
    }
    condathis_abort(
      c(
        `x` = "{.arg res} does not contain the stream {.field {stream}}.",
        hint
      ),
      class = res_class
    )
  }

  # The line ends `readLines()` recognizes. The alternation tries "\r\n"
  # first, so a Windows line end is one line end, not two.
  lines <- stringr::str_split(
    string = raw_text,
    pattern = stringr::regex(r"(\r\n|\r|\n)"),
    simplify = FALSE
  )[[1L]]
  # A line end at the end of the output ends the last line: it does not
  # start one more. Empty output then has no lines.
  if (identical(lines[[length(lines)]], "")) {
    lines <- lines[-length(lines)]
  }

  if (isTRUE(trim)) {
    lines <- stringr::str_trim(lines)
    text_lines <- which(nzchar(lines))
    lines <- if (length(text_lines) == 0L) {
      character(0L)
    } else {
      lines[seq(text_lines[[1L]], text_lines[[length(text_lines)]])]
    }
  }
  return(lines)
}

#' Whether an output stream was not captured
#'
#' A stream redirected to a file or discarded is `NA` in a result object, or
#' missing from it (`NULL`).
#'
#' @param x A stream from a result object.
#'
#' @returns Logical.
#'
#' @keywords internal
#' @noRd
is_uncaptured_stream <- function(x) {
  return(is.null(x) || (is.character(x) && isTRUE(all(is.na(x)))))
}

#' Collapse a pipeline result into one `stdout` and one `stderr` stream
#'
#' @param res A `condathis_pipeline` object.
#'
#' @returns A list with `stdout` (the last process's captured output) and
#'   `stderr` (every process's captured standard error concatenated in
#'   command order). A stream that was not captured anywhere is left out,
#'   so `parse_output()` reports it as missing. Raw streams stay raw so
#'   `parse_output()` reports them as binary.
#'
#' @keywords internal
#' @noRd
pipeline_output_streams <- function(res) {
  is_captured <- function(x) {
    isTRUE(is.raw(x)) || (rlang::is_string(x) && isFALSE(is.na(x)))
  }
  processes <- res$processes
  last_stdout <- if (isTRUE(length(processes) > 0L)) {
    processes[[length(processes)]]$stdout
  }
  stderr_parts <- Filter(is_captured, lapply(processes, `[[`, "stderr"))
  stderr_out <- if (isTRUE(length(stderr_parts) > 0L)) {
    join_output_parts(stderr_parts)
  }
  streams <- list()
  if (is_captured(last_stdout)) {
    streams$stdout <- last_stdout
  }
  if (isFALSE(is.null(stderr_out))) {
    streams$stderr <- stderr_out
  }
  return(streams)
}

#' Join captured output streams, keeping their last lines apart
#'
#' A part whose last line has no trailing newline would otherwise merge with
#' the first line of the next part (`"warn"` + `"err"` became `"warnerr"`).
#' A newline is added after every non-empty part that does not end in one.
#'
#' @param parts List of character strings, raw vectors, `NULL`s or `NA`s.
#'   `NULL` and `NA` parts (streams that were not captured) are skipped.
#'
#' @returns A character string, or a raw vector when any part is raw.
#'
#' @keywords internal
#' @noRd
join_output_parts <- function(parts) {
  parts <- Filter(function(x) isFALSE(is_uncaptured_stream(x)), parts)
  if (any(vapply(parts, is.raw, logical(1L)))) {
    raw_parts <- lapply(parts, function(x) if (is.raw(x)) x else charToRaw(x))
    raw_parts <- lapply(raw_parts, function(x) {
      if (isTRUE(length(x) > 0L) && !identical(x[[length(x)]], as.raw(10L))) {
        c(x, as.raw(10L))
      } else {
        x
      }
    })
    return(do.call(c, c(list(raw(0L)), raw_parts)))
  }
  text_parts <- vapply(
    parts,
    function(x) {
      x <- paste0(x, collapse = "")
      if (nzchar(x) && !endsWith(x, "\n")) paste0(x, "\n") else x
    },
    character(1L)
  )
  return(paste0(text_parts, collapse = ""))
}
