#' Check whether a URL endpoint is reachable
#'
#' @param url_to_check Character string with the endpoint URL.
#'
#' @returns `TRUE` when the endpoint can be opened and read, otherwise `FALSE`.
#'
#' @keywords internal
#' @noRd
check_connection <- function(url_to_check) {
  internet_check <- tryCatch(
    {
      url_con <- base::url(
        description = url_to_check,
        open = "rb"
      )
      on.exit(try(base::close(url_con), silent = TRUE), add = TRUE)
      base::readLines(url_con, n = 1L)
      TRUE
    },
    error = function(e) {
      FALSE
    },
    warning = function(w) {
      FALSE
    }
  )
  return(internet_check)
}
