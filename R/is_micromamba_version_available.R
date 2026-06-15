#' Check if Specific Micromamba Version is Available
#'
#' Checks if a compatible version of micromamba is available at the specified
#'   path.
#'
#' @param umamba_path Path to the micromamba executable. If `NULL`, the path
#'  will be determined using `micromamba_bin_path()`.
#'
#' @returns Logical. `TRUE` if a compatible version of micromamba is available,
#'   `FALSE` otherwise.
#'
#' @keywords internal
#' @noRd
is_umamba_version_available <- function(umamba_path = NULL) {
  cnd_res <- rlang::catch_cnd(
    expr = {
      avail_bool <- check_micromamba_version(umamba_path)
    },
    classes = "condathis_umamba_bin_path_not_executable"
  )
  if (isTRUE(rlang::is_condition(cnd_res))) {
    avail_bool <- FALSE
  }
  return(avail_bool)
}
