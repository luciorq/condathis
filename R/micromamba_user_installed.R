#' Retrieve Micromamba Installed Path
#'
#' Checks if user already have `micromamba` binaries available on `PATH`.
#'
#' @keywords internal
#' @noRd
micromamba_user_installed <- function() {
  umamba_bin_path <- get_best_micromamba_path()
  if (rlang::is_null(umamba_bin_path)) {
    umamba_bin_path <- ""
  }
  if (isTRUE(umamba_bin_path == "")) {
    return(invisible(umamba_bin_path))
  }
  umamba_bin_path <- normalizePath(umamba_bin_path, mustWork = FALSE)
  return(fs::path(umamba_bin_path))
}
