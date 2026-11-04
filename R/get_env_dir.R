#' Get an environment directory path
#'
#' Returns the absolute path where an environment is expected under the data
#' directory of its backend. It returns the path even if the environment
#' does not exist yet.
#'
#' Looks up which registered backend owns `env_name`, and creates the
#' backend's data directory when needed. It creates no environment. When
#' `env_name` has no directory yet, it does not start or install
#' micromamba.
#'
#' @inheritParams condathis-params
#'
#' @returns An `fs_path`: the absolute path of the environment directory.
#'
#' @family environments
#'
#' @examples
#' condathis::with_sandbox_dir({
#'   # Get the default environment directory
#'   print(condathis::get_env_dir())
#'   #> <data dir>/R/condathis/envs/condathis-env
#'
#'   # Get the directory for a specific environment
#'   condathis::get_env_dir("my-env")
#'   #> <data dir>/R/condathis/envs/my-env
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
  # Checked at the boundary: always an absolute `fs_path`. The check is
  # called here, not through `env_dir_for_backend()`, so that its error
  # names the user's `get_env_dir()` call.
  return(validate_backend_return(
    backend_get_env_dir(resolved$backend, env_name = env_name),
    generic = "backend_get_env_dir",
    backend_name = resolved$name
  ))
}
