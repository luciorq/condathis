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
