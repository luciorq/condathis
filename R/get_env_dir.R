#' Get an environment directory path
#'
#' Returns the absolute path where an environment is expected under the
#' `condathis` installation root. The path is returned even if the
#' environment has not been created yet.
#'
#' @param env_name Character string with the environment name.
#'   Defaults to `"condathis-env"`.
#' @returns A character string with the expected environment directory path.

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
  validate_env_name(env_name, class = "condathis_get_env_dir_invalid_env_name")
  return(fs::path(get_install_dir(), "envs", env_name))
}
