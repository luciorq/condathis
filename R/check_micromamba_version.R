#' Check micromamba version against a target
#'
#' Validates that the micromamba binary at `umamba_path` satisfies the version
#' requirement.
#'
#' By default, `target_version` is considered the minimum boundary and
#' accepts the target version **or newer** (minimum version check).
#' For exact version matching, set `minimum = FALSE`.
#'
#' @param umamba_path Character string. Path to the micromamba binary.
#'   If `NULL`, uses the default from `micromamba_bin_path()`.
#' @param target_version Character string. The version to compare against.
#'   Defaults to `"2.8.1"`.
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
  target_version = "2.8.1",
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
