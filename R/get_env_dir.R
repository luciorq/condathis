#' Get an environment directory path
#'
#' Returns the absolute path where an environment is expected under its
#' owning backend's installation root. The path is returned even if the
#' environment has not been created yet.
#'
#' @param env_name Character string with the environment name.
#'   Defaults to `"condathis-env"`.
#' @param method Character string naming the backend to use. Defaults to
#'   `"auto"` (resolve automatically: the environment's own owning
#'   backend if it already exists). `"micromamba"` is the only backend
#'   registered today. `"native"` is a deprecated alias for `"micromamba"`
#'   (warns once per session).
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
get_env_dir <- function(env_name = "condathis-env", method = "auto") {
  validate_env_name(env_name, class = "condathis_get_env_dir_invalid_env_name")
  resolved <- resolve_backend(
    env_name = env_name,
    method = method,
    mutating = FALSE
  )
  return(backend_get_env_dir(resolved$backend, env_name = env_name))
}
