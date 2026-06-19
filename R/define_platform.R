#' Resolve platform arguments for environment creation
#'
#' Determines whether `--platform` should be set for `micromamba create`.
#' On Apple Silicon, this helper can fallback to `osx-64` when Rosetta 2 is
#' available and package availability requires it.
#'
#' @param packages Character vector of package MatchSpec strings.
#' @param platform Character string with a user-specified platform.
#'   Defaults to `NULL`.
#' @param channels Character vector with channel names.
#'   Defaults to `c("conda-forge", "bioconda")`.
#' @param channel_priority Character string with channel priority mode.
#'   Supported values are `"disabled"`, `"strict"`, and `"flexible"`.
#'   Defaults to `"disabled"`.
#' @param additional_channels Character vector of additional channels.
#'   Defaults to `NULL`.
#' @param verbose Character string controlling console output.
#'   Defaults to `"silent"`.
#'
#' @returns A character vector with platform CLI arguments, or `NULL` when no
#'   platform override is needed.
#'
#' @keywords internal
#' @noRd
define_platform <- function(
  packages,
  platform = NULL,
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
  verbose = "silent"
) {
  if (rlang::is_null(platform)) {
    platform_args <- NULL
  } else {
    platform_args <- c("--platform", platform)
  }

  sys_arch <- get_sys_arch()

  if (identical(sys_arch, "Darwin-arm64") && rlang::is_null(platform)) {
    native_res <- packages_search_native(
      packages = packages,
      channels = channels,
      channel_priority = channel_priority,
      additional_channels = additional_channels,
      platform = "osx-arm64",
      verbose = verbose
    )
    if (isFALSE(native_res)) {
      px_res <- processx::run(
        command = Sys.which("pgrep"),
        args = "oahd",
        error_on_status = FALSE,
        spinner = FALSE,
        echo = FALSE,
        echo_cmd = FALSE
      )
      if (identical(px_res$status, 0L)) {
        rosetta_res <- packages_search_native(
          packages = packages,
          channels = channels,
          channel_priority = channel_priority,
          additional_channels = additional_channels,
          platform = "osx-64",
          verbose = verbose
        )
      } else {
        cli::cli_inform(c(
          `x` = "{.var packages} are not available for this architecture.",
          `!` = "Additionally, {.field Rosetta 2} is not enabled on Apple Silicon."
        ))
        rosetta_res <- FALSE
      }
      if (isTRUE(rosetta_res)) {
        cli::cli_inform(c(
          `!` = "Using {.field Rosetta 2} emulation."
        ))
        platform_args <- c("--platform", "osx-64")
      }
    }
  }
  return(platform_args)
}
