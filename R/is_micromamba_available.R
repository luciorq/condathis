#' Map system architecture to a micromamba platform slug
#'
#' @param sys_arch Character string in the format returned by `get_sys_arch()`.
#'   Defaults to `NULL`, which uses the current system architecture.
#'
#' @returns A character platform slug such as `"linux-64"` or `"osx-arm64"`.
#'   A native ARM64 R on Windows (`"Windows-aarch64"`) gets `"win-arm64"`.
#'   An x64 R on the same machine reports `"Windows-x86-64"` and gets
#'   `"win-64"`, which runs through x64 emulation.
#'   An architecture without a micromamba build aborts with class
#'   `condathis_micromamba_not_available_for_arch` (the old class
#'   `condathis_umamba_not_available_for_arch` is kept until 1.0).
#'
#' @keywords internal
#' @noRd
is_micromamba_available_for_arch <- function(sys_arch = NULL) {
  if (rlang::is_null(sys_arch)) {
    sys_arch <- get_sys_arch()
  }
  if (identical(sys_arch, "Linux-x86_64")) {
    sys_arch_str <- "linux-64"
  } else if (
    identical(sys_arch, "Darwin-x86_64") || identical(sys_arch, "MacOSX-x86_64")
  ) {
    sys_arch_str <- "osx-64"
  } else if (
    identical(sys_arch, "Windows-x86_64") ||
      identical(sys_arch, "Windows-x86-64")
  ) {
    sys_arch_str <- "win-64"
  } else if (isTRUE(is_windows_arm64(sys_arch))) {
    sys_arch_str <- "win-arm64"
  } else if (
    identical(sys_arch, "Darwin-arm64") || identical(sys_arch, "MacOSX-arm64")
  ) {
    sys_arch_str <- "osx-arm64"
  } else if (identical(sys_arch, "Linux-aarch64")) {
    sys_arch_str <- "linux-aarch64"
  } else if (identical(sys_arch, "Linux-ppc64le")) {
    sys_arch_str <- "linux-ppc64le"
  } else {
    condathis_abort(
      message = c(
        `x` = "{.pkg micromamba} is not available for the {.val {sys_arch}} CPU architecture."
      ),
      class = c(
        "condathis_micromamba_not_available_for_arch",
        "condathis_umamba_not_available_for_arch"
      )
    )
  }
  return(sys_arch_str)
}
