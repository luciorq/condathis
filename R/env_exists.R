#' Check If Environment Already exists
#'
#' @inheritParams create_env
#' @return Boolean.
#' @examples
#' \dontrun{
#' # Create the environment
#' condathis::create_env(
#'   packages = "fastqc",
#'   env_name = "fastqc-env"
#' )
#' # Check if exists
#' condathis::env_exists("fastqc-env")
#' #> [1] TRUE
#' }
#' @export
env_exists <- function(env_name) {
  rlang::check_required(env_name)
  available_envs <- list_envs()
  condathis_env_path <- env_name
  if (isTRUE(condathis_env_path %in% available_envs)) {
    return(TRUE)
  } else {
    return(FALSE)
  }
}
