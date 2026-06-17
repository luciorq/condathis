#' Parse quiet flag from a verbosity value
#'
#' Deprecated internal helper.
#'
#' @param verbose Character or logical verbosity value.
#'
#' @returns `"--quiet"` or `NULL` based on the verbosity mode.
#'
#' @keywords internal
#' @noRd
parse_quiet_flag <- function(verbose) {
  if (isTRUE(verbose)) {
    verbose <- "full"
  }
  if (isTRUE(verbose %in% c("full"))) {
    quiet_flag <- NULL
  } else {
    quiet_flag <- "--quiet"
  }
  return(quiet_flag)
}
