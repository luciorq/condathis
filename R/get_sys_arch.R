#' Get operating system and CPU architecture
#'
#' Returns the current operating system and CPU architecture as a single
#' string in the format `"<OS>-<Architecture>"`.
#'
#' @returns A character string such as `"Darwin-x86_64"` or
#'   `"Linux-aarch64"`.
#'
#' @examples
#' # Retrieve the system architecture
#' condathis::get_sys_arch()
#' #> [1] "Darwin-x86_64"
#'
#' @export
get_sys_arch <- function() {
  os <- base::Sys.info()["sysname"]
  cpu_arch <- base::Sys.info()["machine"]
  return(base::paste0(os, "-", cpu_arch))
}

#' Check whether the current platform is Windows
#'
#' Single source of truth for the "is this Windows?" check, previously
#' duplicated across the package via three different idioms
#' (`stringr::str_detect(get_sys_arch(), "^Windows")`,
#' `identical(Sys.info()["sysname"], c(sysname = "Windows"))`, and
#' `identical(.Platform$OS.type, "windows")`).
#'
#' @returns Logical.
#'
#' @keywords internal
#' @noRd
is_windows <- function() {
  return(isTRUE(stringr::str_detect(get_sys_arch(), "^Windows")))
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
