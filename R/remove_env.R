#' Remove a Conda Environment
#'
#' Remove a Conda environment previously created by `create_env()`.
#'
#' @inheritParams create_env
#'
#' @return An object of class `list` representing the result of the command
#'   execution. Contains information about the standard output, standard error,
#'   and exit status of the command.
#'
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   condathis::create_env(
#'     packages = "fastqc",
#'     env_name = "fastqc-env"
#'   )
#'   condathis::remove_env(env_name = "fastqc-env")
#' })
#' }
#'
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
  quiet_flag <- parse_quiet_flag(verbose = verbose)
  px_res <- rethrow_error_cmd(
    expr = {
      native_cmd(
        conda_cmd = "env",
        conda_args = c(
          "remove",
          "-n",
          env_name,
          "--yes",
          quiet_flag
        ),
        verbose = verbose
      )
    }
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
