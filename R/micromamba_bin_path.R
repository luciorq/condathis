#' Get the path of the managed micromamba binary
#'
#' Returns the path of the `micromamba` executable that
#' [install_micromamba()] installs, in the condathis data directory (see
#' [get_install_dir()]). It is the third candidate of *micromamba
#' discovery* in [condathis-options], after the `condathis.micromamba_path`
#' option and the `CONDATHIS_MICROMAMBA_PATH` variable.
#'
#' @returns An `fs_path`, the full path of the executable:
#'   `micromamba/bin/micromamba` in the condathis data directory, or
#'   `micromamba/Library/bin/micromamba.exe` on Windows. It does not check
#'   that a file exists there. Like [get_install_dir()], it creates the
#'   condathis data directory when it is missing. Use [fs::file_exists()] on
#'   the result to check that the binary is present, or
#'   [install_micromamba()] to install it.
#'
#' @examples
#' condathis::with_sandbox_dir({
#'   # The path where condathis installs micromamba
#'   print(condathis::micromamba_bin_path())
#' })
#'
#' @family setup
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
