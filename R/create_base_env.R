#' Create Package Base Environment
#' @keywords internal
#' @noRd
create_base_env <- function(verbose = "silent") {
  if (isFALSE(env_exists(env_name = "condathis-env"))) {
    create_env(
      env_name = "condathis-env",
      verbose = verbose,
      overwrite = FALSE
    )
  }
}
