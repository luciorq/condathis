#' Parse Quiet Flag From Verbosity Level
#'
#' DEPRECATED: As of version 0.1.3, this function is deprecated. Please use the updated verbosity handling functions.
#'
#' @param verbose Character string specifying the verbosity level.
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
