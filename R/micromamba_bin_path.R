#' Retrieve the path to the `condathis` managed installation of `micromamba`.
#' @export
micromamba_bin_path <- function() {
  sys_arch <- get_sys_arch()
  output_dir <- get_install_dir()
  if (isTRUE(stringr::str_detect(sys_arch, "^Windows"))) {
    umamba_bin_path <- fs::path(
      output_dir, "micromamba", "Library", "bin", "micromamba.exe"
    )
  } else {
    umamba_bin_path <- fs::path(output_dir, "micromamba", "bin", "micromamba")
  }
  return(umamba_bin_path)
}
