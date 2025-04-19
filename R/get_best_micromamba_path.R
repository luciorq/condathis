#' Return the path of the best micromamba installation to use
#'
#' @keywords internal
#' @noRd
get_best_micromamba_path <- function() {
  paths_to_check <- c(
    micromamba_bin_path(),
    fs::path(Sys.getenv("CONDA_PREFIX", unset = "fake_path"), "bin", "micromamba"),
    fs::path(Sys.getenv("CONDA_PREFIX", unset = "fake_path"), "Library", "bin", "micromamba.exe"),
    fs::path(get_install_dir(), "envs", "micromamba-env", "bin", "micromamba"),
    fs::path(get_install_dir(), "envs", "micromamba-env", "Library", "bin", "micromamba.exe"),
    Sys.which("micromamba")
  )
  for (path in paths_to_check) {
    if (is_umamba_version_available(path)) {
      return(fs::path(path))
    }
  }
  return(NULL)
}
