#' Get operating system and CPU architecture
#'
#' Returns the operating system and the CPU architecture that the running
#' R reports with [base::Sys.info()], as a single string,
#' `"<OS>-<architecture>"`. [install_micromamba()] uses it to choose the
#' micromamba build.
#'
#' @returns A character string such as `"Linux-x86_64"`, `"Linux-aarch64"`,
#'   `"Darwin-x86_64"` or `"Darwin-arm64"`. On Windows it is
#'   `"Windows-aarch64"` for a native ARM64 build of R. It is
#'   `"Windows-x86-64"` for an x64 build, also when that build runs through
#'   x64 emulation on an ARM64 PC.
#'
#' @examples
#' condathis::get_sys_arch()
#'
#' @family setup
#'
#' @export
get_sys_arch <- function() {
  os <- base::Sys.info()["sysname"]
  cpu_arch <- base::Sys.info()["machine"]
  return(base::paste0(os, "-", cpu_arch))
}

#' Check whether the current platform is Windows
#'
#' Single source of truth for the Windows check.
#'
#' @returns Logical.
#'
#' @keywords internal
#' @noRd
is_windows <- function() {
  return(isTRUE(stringr::str_detect(get_sys_arch(), "^Windows")))
}

#' Check whether R runs natively on Windows on ARM64
#'
#' R reports `"aarch64"` there; `"arm64"`, the name Windows itself uses, is
#' accepted too. An x64 R on the same machine reports `"x86-64"` and runs
#' through x64 emulation, so it is not counted.
#'
#' @param sys_arch Character string in the format returned by
#'   `get_sys_arch()`. Defaults to the current system architecture.
#'
#' @returns Logical.
#'
#' @keywords internal
#' @noRd
is_windows_arm64 <- function(sys_arch = get_sys_arch()) {
  return(isTRUE(sys_arch %in% c("Windows-aarch64", "Windows-arm64")))
}

#' Check whether the current platform is macOS
#'
#' @returns Logical.
#'
#' @keywords internal
#' @noRd
is_macos <- function() {
  return(isTRUE(stringr::str_detect(get_sys_arch(), "^Darwin")))
}

#' Check whether the current platform is Linux
#'
#' @returns Logical.
#'
#' @keywords internal
#' @noRd
is_linux <- function() {
  return(isTRUE(stringr::str_detect(get_sys_arch(), "^Linux")))
}

#' The `linux_pdeathsig` value that `processx` gets
#'
#' `linux_pdeathsig` is an option of Linux only. On other platforms,
#' `processx` ignores any value but `FALSE` with a warning, so every
#' `processx` call of `condathis` that starts a command passes its value
#' through this function, and the option is ignored there silently. The
#' value is checked as a flag on every platform (see `validate_run_args()`).
#'
#' @param linux_pdeathsig The `linux_pdeathsig` argument.
#' @param on_linux Logical. Whether R runs on Linux. Defaults to
#'   `is_linux()`.
#'
#' @returns `linux_pdeathsig` on Linux, `FALSE` on other platforms.
#'
#' @keywords internal
#' @noRd
processx_linux_pdeathsig <- function(linux_pdeathsig, on_linux = is_linux()) {
  if (isTRUE(on_linux)) {
    return(linux_pdeathsig)
  }
  return(FALSE)
}
