#' Get the managed `micromamba` binary path
#'
#' Returns the expected path to the `micromamba` executable managed by
#' `condathis` for the current operating system.
#'
#' @returns A character string with the full executable path.
#'   On Windows this points to `micromamba.exe` under `Library/bin`.
#'   On other platforms this points to `micromamba` under `bin`.
#'
#' @examples
#' condathis::with_sandbox_dir({
#'   # Retrieve the path used by condathis for micromamba
#'   micromamba_path <- condathis::micromamba_bin_path()
#'   print(micromamba_path)
#' })
#'
#' @export
micromamba_bin_path <- function() {
  sys_arch <- get_sys_arch()
  output_dir <- get_install_dir()
  if (isTRUE(stringr::str_detect(sys_arch, "^Windows"))) {
    umamba_bin_path <- fs::path(
      output_dir,
      "micromamba",
      "Library",
      "bin",
      "micromamba.exe"
    )
  } else {
    umamba_bin_path <- fs::path(output_dir, "micromamba", "bin", "micromamba")
  }
  return(fs::path(umamba_bin_path))
}
