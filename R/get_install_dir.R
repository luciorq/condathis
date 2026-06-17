#' Get the `condathis` data directory
#'
#' Returns the data directory used by `condathis`, creating it when needed.
#' The base path follows the platform-specific user data directory rules used
#' by `tools::R_user_dir()`.
#'
#' @details
#' On macOS, `condathis` uses a path without spaces when possible because
#' `micromamba run` can fail on paths that contain spaces.
#'
#' @returns A character string with the normalized, real path to the
#'   `condathis` data directory.
#'
#' @examples
#' condathis::with_sandbox_dir({
#'   print(condathis::get_install_dir())
#'   #> /home/username/.local/share/condathis
#' })
#'
#' @export
get_install_dir <- function() {
  dir_path <- get_condathis_path()
  if (isFALSE(fs::dir_exists(dir_path))) {
    fs::dir_create(dir_path, recurse = TRUE)
  }
  dir_path <- base::normalizePath(dir_path, mustWork = FALSE)
  return(fs::path_real(dir_path))
}
