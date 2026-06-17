#' Check whether a compatible micromamba version is available
#'
#' @param umamba_path Character path to the micromamba executable.
#'   Defaults to `NULL`, which uses `micromamba_bin_path()`.
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
