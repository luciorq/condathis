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
remove_env <- function(
  env_name = "condathis-env",
  verbose = c(
    "silent",
    "cmd",
    "output",
    "spinner",
    "full"
  )
) {
  verbose_list <- parse_strategy_verbose(verbose = verbose)

  if (
    isFALSE(env_exists(env_name, verbose = verbose_list$internal_verbose)) &&
      isTRUE(fs::dir_exists(get_env_dir(env_name = env_name)))
  ) {
    fs::dir_delete(get_env_dir(env_name = env_name))
  }
  if (isFALSE(env_exists(env_name, verbose = verbose_list$internal_verbose))) {
    cli::cli_abort(
      message = c(
        `x` = "Environment {.field {env_name}} does not exist.",
        `!` = "Check {.code list_envs()} for available environments."
      ),
      class = "condathis_error_env_remove"
    )
  }

  px_res <- rethrow_error_cmd(
    expr = {
      native_cmd(
        conda_cmd = "env",
        conda_args = c(
          "remove",
          "-n",
          env_name,
          "--yes",
          verbose_list$quiet_flag
        ),
        verbose = verbose_list
      )
    }
  )
  if (isTRUE(verbose_list$strategy %in% c("full", "output"))) {
    cli::cli_inform(
      message = c(
        `!` = "Environment {.field {env_name}} succesfully removed."
      )
    )
  }
  return(invisible(px_res))
}
