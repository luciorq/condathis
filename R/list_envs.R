#' List Installed Environments
#'
#' @inheritParams create_env
#'
#' @export
list_envs <- function(verbose = FALSE) {
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
    envs_str <- fs::path_real(envs_list$envs)
    envs_str <- envs_str[stringr::str_detect(c(envs_str), env_root_dir)]
    envs_to_return <- base::basename(envs_str)
    envs_to_return <- envs_to_return[!envs_to_return %in% "condathis"]
    return(envs_to_return)
  } else {
    return(px_res$status)
  }
}
