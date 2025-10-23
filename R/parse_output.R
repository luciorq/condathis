#' Parse the output of a Condathis command
#'
#' This function processes the result of a [condathis::run()] call by parsing
#' the specified output stream (`"stdout"`, `"stderr"`, or `"both"`) into
#' individual, trimmed lines.
#'
#' @param res A list containing the result of [condathis::run()], typically
#'   including `stdout` and `stderr` as character strings.
#' @param stream A character string specifying the data stream to parse.
#'   Must be either `"stdout"`, `"stderr"`, or `"both"`.
#'   Additionally, "plain" can be used to provide raw text as the `res` input.
#' Defaults to `"stdout"`.
#'
#' @return A character vector where each element is a trimmed line from the
#'   specified stream.
#'
#' @examples
#' # Example result object from condathis::run()
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
#' # # Parse plain text
#' plain_text <- "This is line one.\nThis is line two.\nThis is line three."
#' parse_output(plain_text, stream = "plain")
#'
#' @export
parse_output <- function(res, stream = c("stdout", "stderr", "both", "plain")) {
  stream <- rlang::arg_match(stream)

  if (
    isFALSE(rlang::is_character(res)) &&
      isFALSE(
        rlang::is_list(res) &&
          (rlang::has_name(res, "stdout") || rlang::has_name(res, "stderr"))
      )
  ) {
    cli::cli_abort(
      c(
        `x` = "The `res` argument must be a character string or a list with `stdout` and `stderr` elements."
      ),
      class = "condathis_parse_output_invalid_res"
    )
  }

  if (stream %in% c("stdout", "stderr") && rlang::has_name(res, stream)) {
    raw_text <- res[[stream]]
  } else if (identical(stream, "both")) {
    raw_text <- paste0(
      if (!is.null(res$stdout)) res$stdout else "",
      if (!is.null(res$stderr)) res$stderr else ""
    )
  } else if (identical(stream, "plain") && rlang::is_character(res)) {
    raw_text <- paste0(res, collapse = "\n")
  }

  if (isFALSE(exists("raw_text"))) {
    cli::cli_abort(
      c(
        `x` = "The `res` argument does not contain the specified stream: {.field {stream}}."
      ),
      class = "condathis_parse_output_invalid_res"
    )
  }

  lines <- stringr::str_split(
    string = stringr::str_trim(raw_text),
    pattern = stringr::regex("\\R"),
    simplify = FALSE
  )[[1]]
  return(stringr::str_trim(lines))
}
