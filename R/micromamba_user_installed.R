#' Retrieve Micromamba Installed Path
#'
#' Checks if user already have `micromamba` binaries available on `PATH`.
#'
#'
micromamba_user_installed <- function() {
  umamba_bin_path <- Sys.which("micromamba")
  if (isTRUE(umamba_bin_path == "")) {
    umamba_bin_path <- Sys.which("micromamba.exe")
  }
  if (isTRUE(umamba_bin_path == "")) {
    return(invisible(umamba_bin_path))
  }
  return(fs::path(umamba_bin_path))
}
