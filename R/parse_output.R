#' Parse the output of [condathis::run()]
#'
#' @param res Result from [condathis::run()].
#'
#' @param stream Data stream to parse.
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
