#' Map system architecture to a micromamba platform slug
#'
#' @param sys_arch Character string in the format returned by `get_sys_arch()`.
#'   Defaults to `NULL`, which uses the current system architecture.
#' @param micromamba_version `NULL` (the default) or the version `"X.Y.Z"`
#'   that will be downloaded. Some platforms have builds only from a
#'   version on (see `micromamba_platform_first_version`), and an older
#'   version there aborts with the same class as an unknown architecture.
#'
#' @returns A character platform slug such as `"linux-64"` or `"osx-arm64"`.
#'   A native ARM64 R on Windows (`"Windows-aarch64"`) gets `"win-arm64"`.
#'   An x64 R on the same machine reports `"Windows-x86-64"` and gets
#'   `"win-64"`, which runs through x64 emulation.
#'   A RISC-V R on Linux (`"Linux-riscv64"`) gets `"linux-riscv64"`.
#'   An architecture without a micromamba build aborts with class
#'   `condathis_micromamba_not_available_for_arch` (the old class
#'   `condathis_umamba_not_available_for_arch` is kept until 1.0).
#'
#' @keywords internal
#' @noRd
is_micromamba_available_for_arch <- function(
  sys_arch = NULL,
  micromamba_version = NULL
) {
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
  } else if (identical(sys_arch, "Linux-riscv64")) {
    sys_arch_str <- "linux-riscv64"
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
  first_version <- micromamba_platform_first_version[sys_arch_str]
  if (
    isFALSE(is.null(micromamba_version)) &&
      isFALSE(is.na(first_version)) &&
      isTRUE(utils::compareVersion(micromamba_version, first_version) < 0L)
  ) {
    condathis_abort(
      message = c(
        `x` = "{.pkg micromamba} {.val {micromamba_version}} is not available for the {.val {sys_arch}} CPU architecture.",
        `i` = "Its {.val {sys_arch_str}} builds start with version {.val {first_version}}."
      ),
      class = c(
        "condathis_micromamba_not_available_for_arch",
        "condathis_umamba_not_available_for_arch"
      )
    )
  }
  return(sys_arch_str)
}

#' The first micromamba version with a build for a platform
#'
#' Only for the platforms whose builds start after
#' `micromamba_minimum_version`; every other platform has builds of every
#' supported version. conda-forge has `linux-riscv64` builds from 2.9.0 on,
#' so `install_micromamba()` gets them from its conda-forge mirrors. The
#' GitHub releases have them from 2.10.0-0 on (checked on 2026-11-18).
#'
#' @keywords internal
#' @noRd
micromamba_platform_first_version <- c(`linux-riscv64` = "2.9.0")
