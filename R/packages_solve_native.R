#' Check whether a create request solves for a platform
#'
#' Runs `micromamba create --dry-run --json` with the channel arguments of
#' `micromamba_backend_create_env()`, for the emulation fallbacks of
#' `define_platform()`. It solves the whole request, not each spec on its
#' own, so it also fails when only a dependency has no build for
#' `platform`: a `noarch` spec, such as `r-ggplot2`, is found for every
#' platform, also for one where `r-base` does not exist.
#'
#' @param packages_arg Character vector, the package specs, or
#'   `c("-f", <env_file>)`, as `micromamba create` gets them.
#' @param channels Character vector with channel names.
#'   Defaults to `"conda-forge"`.
#' @param channel_priority Character string with channel priority mode.
#'   Supported values are `"strict"`, `"flexible"`, and `"disabled"`.
#'   Defaults to `"strict"`.
#' @param additional_channels Character vector of additional channels.
#'   Defaults to `NULL`.
#' @param platform Character string with the platform to solve for.
#' @param verbose Character string controlling console output.
#'   Defaults to `"silent"`.
#'
#' @returns `TRUE` when the request solves, `FALSE` when micromamba reports
#'   that it does not, and `NA` for any other failure, such as a missing
#'   channel or no network. Then nothing is known about the platform, and
#'   the create itself reports micromamba's error.
#'
#' @keywords internal
#' @noRd
packages_solve_native <- function(
  packages_arg,
  channels = "conda-forge",
  channel_priority = c("strict", "flexible", "disabled"),
  additional_channels = NULL,
  platform,
  verbose = "silent"
) {
  channels_arg <- format_channels_args(
    channels,
    additional_channels
  )

  verbose_list <- parse_strategy_verbose(verbose = verbose)

  channel_priority_args <- parse_strategy_channel_priority(
    channel_priority = channel_priority
  )

  # A prefix that does not exist, so the dry run cannot touch an
  # environment: `micromamba create` deletes an existing prefix first.
  dry_run_prefix <- fs::path(
    withr::local_tempdir(pattern = "condathis-dry-run"),
    "env"
  )

  px_res <- native_cmd(
    conda_cmd = "create",
    conda_args = c(
      "-p",
      dry_run_prefix,
      "--dry-run",
      "--yes",
      "--json",
      verbose_list$quiet_flag,
      "--override-channels",
      channel_priority_args,
      channels_arg,
      "--platform",
      platform
    ),
    packages_arg,
    verbose = verbose_list,
    error = "continue"
  )
  if (identical(px_res$status, 0L)) {
    return(TRUE)
  }
  # micromamba 2.8 and 2.10 write `solver_problems` only for a request that
  # does not solve. Other failures print no JSON (2.8) or only
  # `log_history` (2.10).
  json_output <- tryCatch(
    jsonlite::fromJSON(px_res$stdout, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (isTRUE(rlang::has_name(json_output, "solver_problems"))) {
    return(FALSE)
  }
  return(NA)
}

#' The `backend_can_solve()` function of the micromamba backend
#'
#' `packages_solve_native()` for the request: `env_file` is solved as
#' `micromamba create -f` gets it. Starts micromamba, which it installs
#' when no binary is found, as the create that follows would.
#'
#' @param backend The micromamba backend object.
#' @param packages Character vector of package specs, or `NULL`.
#' @param env_file `NULL`, or the path of an environment file.
#' @param channels,channel_priority,additional_channels,platform As in
#'   `packages_solve_native()`.
#'
#' @returns `TRUE`, `FALSE` or `NA`, as `packages_solve_native()`.
#'
#' @keywords internal
#' @noRd
micromamba_backend_can_solve <- function(
  backend,
  packages = NULL,
  env_file = NULL,
  channels = "conda-forge",
  channel_priority = c("strict", "flexible", "disabled"),
  additional_channels = NULL,
  platform
) {
  packages_arg <- packages
  if (isFALSE(rlang::is_null(env_file))) {
    packages_arg <- c("-f", fs::path(env_file))
  }
  return(packages_solve_native(
    packages_arg = packages_arg,
    channels = channels,
    channel_priority = channel_priority,
    additional_channels = additional_channels,
    platform = platform,
    verbose = "silent"
  ))
}
