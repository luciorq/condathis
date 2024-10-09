#' Retrieve Path To Environment
#'
#' Retrieve path to where environment should be created.
#'    **Note**: It retrieves the Path even if the environment is **not** created yet.
#'
#' @inheritParams create_env
#'
#' @export
get_env_dir <- function(env_name = "condathis-env") {
  return(fs::path(get_install_dir(), "envs", env_name))
}
