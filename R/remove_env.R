#' Remove a Conda Environment
#'
#' Remove a Conda environment previously created by `create_env()`.
#'
#' @inheritParams create_env
#' @return No value is returned; this function is used for its side effect of removing a conda environment.
#' @examples
#' \dontrun{
#' condathis::create_env(
#'   # `     packages = "fastqc",
#'   env_name = "fastqc_env"
#' )
#' condathis::remove_env(env_name = "fastqc_env")
#' }
#' @export
remove_env <- function(env_name = "condathis-env",
                       verbose = "silent") {
  if (isFALSE(env_exists(env_name))) {
    cli::cli_abort(
      message = c(
        `x` = "Environment {.field {env_name}} do not exist.",
        `!` = "Check {.code list_envs()} for available environments."
      ),
      class = "condathis_error_env_remove"
    )
  }
  px_res <- native_cmd(
    conda_cmd = "env",
    conda_args = c(
      "remove",
      "-n",
      env_name,
      "--yes",
      "--quiet"
    ),
    verbose = verbose
  )
  if (isTRUE(verbose %in% c("full", "output"))) {
    cli::cli_inform(
      message = c(
        `!` = "Environment {.field {env_name}} succesfully removed."
      )
    )
  }
  return(invisible(px_res))
}
