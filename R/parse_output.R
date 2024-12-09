#' Parse the output of a Condathis command
#'
#' This function processes the result of a [condathis::run()] call by parsing
#' the specified output stream (`stdout` or `stderr`) into individual, trimmed lines.
#'
#' @param res A list containing the result of [condathis::run()], typically including
#'   `stdout` and `stderr` as character strings.
#' @param stream A character string specifying the data stream to parse. Must be either
#'   `"stdout"` or `"stderr"`. Defaults to `"stdout"`.
#'
#' @return A character vector where each element is a trimmed line from the specified stream.
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
#' @export
parse_output <- function(res, stream = c("stdout", "stderr")) {
  stream <- rlang::arg_match(stream)
  lines <- stringr::str_split(
    string = stringr::str_trim(res[[stream]]),
    pattern = stringr::regex("\\R"),
    simplify = FALSE
  )[[1]]
  return(stringr::str_trim(lines))
}
