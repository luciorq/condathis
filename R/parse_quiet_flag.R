#' Parse Quiet Flag From Verbosity Level
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
