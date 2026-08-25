#' Remove a Conda environment
#'
#' Removes an environment managed by `condathis`.
#'
#' @param env_name Character string with the environment name to remove.
#'   Defaults to `"condathis-env"`.
#' @param method Character string naming the backend to use. Defaults to
#'   `"auto"` (resolve automatically: the environment's own owning backend).
#'   `"micromamba"` is the only backend registered today. `"native"` is a
#'   deprecated alias for `"micromamba"` (warns once per session).
#' @param verbose Character string controlling console output.
#'   Supported values are `"silent"`, `"cmd"`, `"output"`, `"spinner"`,
#'   and `"full"`. Defaults to `"silent"`.
#'
#' @returns A `condathis_result` S3 object (a classed list, still usable as
#'   a plain list) with `status`, `stdout`, `stderr`, `timeout`, `pid`,
#'   `cmd`, and `env_name`.
#'
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   condathis::create_env(
#'     packages = "bioconda::fastqc",
#'     env_name = "fastqc-env"
#'   )
#'   condathis::remove_env(env_name = "fastqc-env")
#' })
#' }
#'
#' @export
remove_env <- function(
  env_name = "condathis-env",
  method = "auto",
  verbose = c(
    "silent",
    "cmd",
    "output",
    "spinner",
    "full"
  )
) {
  validate_env_name(env_name, class = "condathis_remove_env_invalid_env_name")
  verbose_list <- parse_strategy_verbose(verbose = verbose)

  resolved <- resolve_backend(
    env_name = env_name,
    method = method,
    mutating = TRUE
  )

  px_res <- backend_remove_env(
    resolved$backend,
    env_name = env_name,
    verbose = verbose
  )

  if (isTRUE(verbose_list$strategy %in% c("full", "output"))) {
    cli::cli_inform(
      message = c(
        `!` = "Environment {.field {env_name}} succesfully removed."
      )
    )
  }

  result <- new_condathis_result(
    status = if (is.null(px_res$status)) 0L else px_res$status,
    stdout = if (is.null(px_res$stdout)) "" else px_res$stdout,
    stderr = if (is.null(px_res$stderr)) "" else px_res$stderr,
    timeout = if (is.null(px_res$timeout)) FALSE else px_res$timeout,
    pid = if (is.null(px_res$pid)) NA_integer_ else px_res$pid,
    cmd = paste(
      c(resolved$name, "env", "remove", "-n", env_name),
      collapse = " "
    ),
    env_name = env_name
  )
  return(invisible(result))
}
