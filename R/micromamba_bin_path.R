#' Retrieve Path to the `micromamba` Executable
#'
#' This function returns the file path to the `micromamba` executable managed
#' by the `condathis` package. The path is determined based on the system's
#' operating system and architecture.
#'
#' @return A character string representing the full path to the `micromamba` executable.
#'   The path differs depending on the operating system:
#'   \describe{
#'     \item{Windows}{`<install_dir>/micromamba/Library/bin/micromamba.exe`}
#'     \item{Other OS (e.g., Linux, macOS)}{`<install_dir>/micromamba/bin/micromamba`}
#'   }
#'
#' @examples
#' condathis::with_sandbox_dir({
#'   # Retrieve the path to where micromamba executable is searched
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
      output_dir, "micromamba", "Library", "bin", "micromamba.exe"
    )
  } else {
    umamba_bin_path <- fs::path(output_dir, "micromamba", "bin", "micromamba")
  }
  return(umamba_bin_path)
}
