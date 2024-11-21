#' List Installed Environments
#'
#' @inheritParams run
#' @return Character vector of name of conda environment installed.
#' @examples
#' \dontrun{
#' #'Create the environments
#' condathis::create_env(packages = "fastqc",
#'                       env_name = "fastqc_env"
#'                       )
#' condathis::create_env(packages = "samtool",
#'                       env_name = "samtool_env"
#'                       )
#' # List environments
#' condathis::list_envs()
#' #> [1] "fastqc-env"  "samtools_env"
#' }
#' @export
list_envs <- function(verbose = "silent") {
  env_root_dir <- get_install_dir()
  px_res <- native_cmd(
    conda_cmd = "env",
    conda_args = c(
      "list",
      "-q",
      "--json"
    ),
    verbose = verbose
  )
  if (isTRUE(px_res$status == 0)) {
    envs_list <- jsonlite::fromJSON(px_res$stdout)
    envs_str <- base::normalizePath(envs_list$envs)
    envs_str <- fs::path_real(envs_str)
    envs_str <- envs_str[stringr::str_detect(c(envs_str), env_root_dir)]
    envs_to_return <- base::basename(envs_str)
    envs_to_return <- envs_to_return[!envs_to_return %in% "condathis"]
    return(envs_to_return)
  } else {
    return(px_res$status)
  }
}
