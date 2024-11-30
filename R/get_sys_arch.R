#' Retrieve Operating System and CPU Architecture
#'
#' This function retrieves the operating system (OS) name and the CPU architecture
#' of the current system. The output combines the OS and CPU architecture into
#' a single string in the format `"<OS>-<Architecture>"`.
#'
#' @return A character string indicating the operating system and CPU architecture,
#'   e.g., `"Darwin-x86_64"` or `"Linux-aarch64"`.
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
