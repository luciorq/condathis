#' Return OS and CPU Architecture
#'
#' @return A character vector with one element indicating OS and CPU Architecture.
#' @examples
#' \dontrun{
#' # Create a Conda environment with the CLI fastqc
#' condathis::get_sys_arch()
#' #> [1] "Darwin-x86_64"
#' }
#' @export
get_sys_arch <- function() {
  os <- base::Sys.info()["sysname"]
  cpu_arch <- base::Sys.info()["machine"]
  return(base::paste0(os, "-", cpu_arch))
}
