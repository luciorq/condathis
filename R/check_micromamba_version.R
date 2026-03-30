#' Check Micromamba Version Against a Target
#'
#' Validates that the micromamba binary at `umamba_path` meets the version
#' requirement. By default, accepts the target version **or newer** (minimum
#' version check). Set `minimum = FALSE` for exact version matching.
#'
#' @param umamba_path Character string. Path to the micromamba binary.
#'   If `NULL`, uses the default from `micromamba_bin_path()`.
#' @param target_version Character string. The version to compare against.
#'   Defaults to `"2.5.0"`.
#' @param minimum Logical. If `TRUE` (default), accepts versions >= target.
#'   If `FALSE`, requires an exact match.
#'
#' @returns Logical. `TRUE` if the version requirement is met, `FALSE`
#'   otherwise.
#'
#' @keywords internal
#' @noRd
check_micromamba_version <- function(
  umamba_path = NULL,
  target_version = "2.5.0",
  minimum = TRUE
) {
  version_string <- get_micromamba_version(umamba_path)
  compare_res <- utils::compareVersion(version_string, target_version)

  if (isTRUE(minimum)) {
    # Accept target version or newer (compare_res >= 0)
    return(isTRUE(compare_res >= 0L))
  }
  # Exact match only
  return(isTRUE(identical(compare_res, 0L)))
}
