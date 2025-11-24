#' Define Platform to be used by `create_env()`.
#'
#' @inheritParams create_env
#'
#' @keywords internal
#' @noRd
define_platform <- function(
  packages,
  platform = NULL,
  channels = c(
    "bioconda",
    "conda-forge"
  ),
  channel_priority = "disabled",
  additional_channels = NULL,
  verbose = "silent"
) {
  if (is.null(platform)) {
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
