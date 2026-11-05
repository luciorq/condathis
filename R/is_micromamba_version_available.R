#' Check whether a compatible micromamba version is available
#'
#' Any failure while probing the candidate counts as "not available": a
#' missing file, a directory, a file that is not executable, a binary that
#' crashes or prints no version. Only the missing-file error
#' (`condathis_micromamba_bin_path_not_executable`) used to be caught, so
#' one broken candidate (for example a stale
#' `CONDATHIS_MICROMAMBA_PATH`, or a truncated managed binary) aborted
#' discovery in `get_best_micromamba_path()` instead of moving on to the next
#' candidate, and every later command failed with it.
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
  avail_bool <- tryCatch(
    check_micromamba_version(umamba_path),
    error = function(e) FALSE
  )
  return(isTRUE(avail_bool))
}
