#' Create Package Base Environment
#' @keywords internal
create_base_env <- function() {
  if (isFALSE(env_exists(env_name = "condathis-env"))) {
    create_env(env_name = "condathis-env", verbose = "silent")
  }
}
