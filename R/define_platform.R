#' Define Platform to be used by `create_env()`.
#'
#' @inheritParams create_env
#'
#' @keywords internal
#' @noRd
define_platform <- function(packages,
                            platform = NULL,
                            channels = c(
                              "bioconda",
                              "conda-forge"
                            ),
                            additional_channels = NULL) {
  if (is.null(platform)) {
    platform_args <- NULL
  } else {
    platform_args <- c("--platform", platform)
  }

  sys_arch <- get_sys_arch()

  if (isTRUE(sys_arch == "Darwin-arm64") && is.null(platform)) {
    native_res <- packages_search_native(
      packages = packages,
      channels = channels,
      # method = "native",
      platform = "osx-arm64",
      additional_channels = additional_channels
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
      if (isTRUE(px_res$status == 0)) {
        rosetta_res <- packages_search_native(
          packages = packages,
          channels = channels,
          # method = "native",
          platform = "osx-64",
          additional_channels = additional_channels
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
