#' Retrieve Micromamba Installed Path
#'
#' Checks if user already have `micromamba` binaries available on `PATH`.
#'
#' @keywords internal
#' @noRd
micromamba_user_installed <- function() {
  umamba_bin_path <- Sys.which("micromamba")
  if (isTRUE(umamba_bin_path == "")) {
    umamba_bin_path <- Sys.which("micromamba.exe")
  }
  if (isTRUE(umamba_bin_path == "")) {
    return(invisible(umamba_bin_path))
  }
  umamba_bin_path <- normalizePath(umamba_bin_path, mustWork = FALSE)
  return(fs::path(umamba_bin_path))
}
