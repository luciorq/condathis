#' Check If Environment Already exists
#'
#' This function checks whether a specified Conda environment already exists
#' in the available environments. It returns `TRUE` if the environment exists
#' and `FALSE` otherwise.
#'
#' @inheritParams create_env
#' @return Boolean. `TRUE` if the environment exists and `FALSE` otherwise.
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   # Create the environment
#'   condathis::create_env(
#'     packages = "fastqc",
#'     env_name = "fastqc-env"
#'   )
#'
#'   # Check if the environment exists
#'   condathis::env_exists("fastqc-env")
#'   #> [1] TRUE
#'
#'   # Check for a non-existent environment
#'   condathis::env_exists("non-existent-env")
#'   #> [1] FALSE
#' })
#' }
#'
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
