#' List Installed Conda Environments
#'
#' This function retrieves a list of Conda environments installed in the Condathis
#' environment directory. The returned value excludes any environments unrelated
#' to Condathis, such as the base Conda environment itself.
#'
#' @param verbose A character string indicating the verbosity level for the command.
#'   Defaults to `"silent"`. Options include `"silent"`, `"minimal"`, and `"verbose"`.
#'   See [condathis::run()] for details.
#'
#' @return A character vector containing the names of installed Conda environments.
#'   If the command fails, the function returns the process exit status as a numeric value.
#'
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   # Create environments
#'   condathis::create_env(
#'     packages = "fastqc",
#'     env_name = "fastqc-env"
#'   )
#'   condathis::create_env(
#'     packages = "python",
#'     env_name = "python-env"
#'   )
#'
#'   # List environments
#'   condathis::list_envs()
#'   #> [1] "fastqc-env" "python-env"
#' })
#' }
#'
#' @export
list_envs <- function(verbose = "silent") {
  env_root_dir <- get_install_dir()
  px_res <- rethrow_error_cmd(
    expr = {
      native_cmd(
        conda_cmd = "env",
        conda_args = c(
          "list",
          "-q",
          "--json"
        ),
        verbose = verbose
      )
    }
  )
  if (isTRUE(px_res$status == 0)) {
    envs_list <- jsonlite::fromJSON(px_res$stdout)
    envs_str <- base::normalizePath(envs_list$envs, mustWork = FALSE)
    envs_str <- fs::path_real(envs_str)
    envs_str <- envs_str[stringr::str_detect(c(envs_str), env_root_dir)]
    envs_to_return <- base::basename(envs_str)
    envs_to_return <- envs_to_return[!envs_to_return %in% "condathis"]
    return(envs_to_return)
  } else {
    return(px_res$status)
  }
}
