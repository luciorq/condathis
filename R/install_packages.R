#' Install packages in a Conda environment
#'
#' Installs packages into an existing `condathis` environment.
#' If the target environment does not exist, it is created first.
#'
#' @param packages Character vector of package MatchSpec strings to install.
#' @param env_name Character string with the target environment name.
#'   Defaults to `"condathis-env"`.
#' @param channels Character vector with channel names used for dependency
#'   resolution. Defaults to `c("conda-forge", "bioconda")`.
#' @param channel_priority Character string with channel priority mode.
#'   Supported values are `"disabled"`, `"strict"`, and `"flexible"`.
#'   Defaults to `"disabled"`.
#' @param additional_channels Character vector of additional channels appended
#'   to `channels`. Defaults to `NULL`.
#' @param verbose Character string controlling console output.
#'   Supported values are `"output"`, `"silent"`, `"cmd"`, `"spinner"`,
#'   and `"full"`. Defaults to `"output"`.
#'
#' @returns A process result list (from `processx::run()`) with command output,
#'   error output, exit status, and timeout information.
#'
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   condathis::create_env(
#'     packages = "bioconda::fastqc",
#'     env_name = "fastqc-env"
#'   )
#'   # Install the package `python` in the `fastqc-env` environment.
#'   # NOTE: It is not recommended to install multiple packages in the same
#'   # environment, as it defeats the purpose of isolation provided by
#'   # separate environments.
#'   condathis::install_packages(packages = "python", env_name = "fastqc-env")
#' })
#' }
#'
#' @export
install_packages <- function(
  packages,
  env_name = "condathis-env",
  channels = c(
    "conda-forge",
    "bioconda"
  ),
  channel_priority = c(
    "disabled",
    "strict",
    "flexible"
  ),
  additional_channels = NULL,
  verbose = c(
    "output",
    "silent",
    "cmd",
    "spinner",
    "full"
  )
) {
  verbose_list <- parse_strategy_verbose(verbose = verbose)
  channel_priority_args <- parse_strategy_channel_priority(
    channel_priority = channel_priority
  )

  if (
    isFALSE(any(
      list_envs(verbose = verbose_list$internal_verbose) %in% env_name
    ))
  ) {
    create_env(
      packages = NULL,
      env_name = env_name,
      verbose = verbose_list$internal_verbose
    )
  }

  channels_arg <- format_channels_args(
    channels,
    additional_channels
  )

  px_res <- rethrow_error_cmd(
    expr = {
      native_cmd(
        conda_cmd = "install",
        conda_args = c(
          "-n",
          env_name,
          "--yes",
          verbose_list$quiet_flag,
          "--override-channels",
          channel_priority_args,
          channels_arg
        ),
        packages,
        verbose = verbose_list
      )
    }
  )

  if (
    isTRUE(verbose_list$strategy %in% c("full", "output")) &&
      isTRUE(length(packages) > 0L)
  ) {
    cli::cli_inform(
      message = c(
        `!` = "{cli::qty(packages)}Package{?s} {.field {packages}} succesfully installed in environment {.field {env_name}}."
      )
    )
  }
  return(invisible(px_res))
}
