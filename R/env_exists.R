#' Check If Environment Names Already exists
#'
#' @inheritParams create_env
#'
#' @export
env_exists <- function(env_name = "condathis-env") {
  available_envs <- list_envs()
  condathis_env_path <- env_name
  if (isTRUE(condathis_env_path %in% available_envs)) {
    return(TRUE)
  } else {
    return(FALSE)
  }
}
