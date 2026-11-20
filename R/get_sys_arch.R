#' Get operating system and CPU architecture
#'
#' Returns the operating system and the CPU architecture that the running
#' R reports with [base::Sys.info()], as a single string,
#' `"<OS>-<architecture>"`. [install_micromamba()] uses it to choose the
#' micromamba build.
#'
#' @returns A character string such as `"Linux-x86_64"`, `"Linux-aarch64"`,
#'   `"Linux-riscv64"`, `"Darwin-x86_64"` or `"Darwin-arm64"`. On Windows it is
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
  sys_info <- base::Sys.info()
  return(base::paste0(sys_info[["sysname"]], "-", sys_info[["machine"]]))
}

#' Check whether the current platform is Windows
#'
#' Single source of truth for the Windows check. It reads `.Platform`, not
#' `Sys.info()`, which reads the user database on every call: the check
#' runs dozens of times per `run()`. A test that pretends to run on
#' Windows mocks this function; mocking `get_sys_arch()` does not change
#' it (see `sys_arch_is_windows()`).
#'
#' @returns Logical.
#'
#' @keywords internal
#' @noRd
is_windows <- function() {
  return(identical(.Platform$OS.type, "windows"))
}

#' Check whether a system architecture is one of Windows
#'
#' For the choice of a platform (`define_platform()` and the emulation
#' fallbacks), which reads `get_sys_arch()` for macOS too, so that one
#' value decides both and the tests can give it for any OS. Not for code
#' that runs on every call: see `is_windows()`.
#'
#' @param sys_arch Character string in the format returned by
#'   `get_sys_arch()`. Defaults to the current system architecture.
#'
#' @returns Logical.
#'
#' @keywords internal
#' @noRd
sys_arch_is_windows <- function(sys_arch = get_sys_arch()) {
  return(isTRUE(startsWith(sys_arch, "Windows")))
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
