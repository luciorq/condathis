#' Get the managed `micromamba` binary path
#'
#' Returns the expected path to the `micromamba` executable managed by
#' `condathis` for the current operating system.
#'
#' @returns A character string with the full executable path.
#'   On Windows this points to `micromamba.exe` under `Library/bin`.
#'   On other platforms this points to `micromamba` under `bin`.
#'   This is purely a computed, expected path - it does not check whether a
#'   file actually exists there yet (unlike `get_install_dir()`, which
#'   creates its directory before returning). Use `fs::file_exists()` on
#'   the result, or `install_micromamba()`, if you need the binary to
#'   actually be present.
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
  output_dir <- install_dir_for_backend(micromamba_backend())
  if (isTRUE(is_windows())) {
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
