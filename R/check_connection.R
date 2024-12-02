#' @keywords internal
#' @noRd
check_connection <- function(url_to_check) {
  internet_check <- tryCatch(
    {
      url_con <- base::url(
        description = url_to_check,
        open = "rb"
      )
      base::readLines(url_con, n = 1)
      base::close(url_con)
      TRUE
    },
    error = function(e) {
      FALSE
    }
  )
  return(internet_check)
}
