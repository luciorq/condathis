#' Retrieve Path To Environment
#'
#' Retrieve path to where environment should be created.
#'    **Note**: It retrieves the Path even if the environment is **not** created yet.
#'
#' @inheritParams create_env
#' @return A character string indicating the path where environments will be created.

#' @examples
#' condathis::with_sandbox_dir({
#'   # Get the default environment directory
#'   condathis::get_env_dir()
#'   #> "/path/to/condathis/envs/condathis-env"
#'
#'   # Get the directory for a specific environment
#'   condathis::get_env_dir("my-env")
#'   #> "/path/to/condathis/envs/my-env"
#' })
#'
#' @export
get_env_dir <- function(env_name = "condathis-env") {
  return(fs::path(get_install_dir(), "envs", env_name))
}
