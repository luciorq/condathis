#' Search For Package in Channels
#'
#' Search if Package is available in required Channels
#'
#' @inheritParams create_env
#'
#' @keywords internal
#' @noRd
packages_search_native <- function(packages,
                                   channels = c(
                                     "bioconda",
                                     "conda-forge"
                                   ),
                                   platform = NULL,
                                   additional_channels = NULL,
                                   verbose = "silent") {
  channels_arg <- format_channels_args(
    additional_channels,
    channels
  )
  if (is.null(platform)) {
    platform_args <- NULL
  } else {
    platform_args <- c("--platform", platform)
  }
  available_vector <- c()
  for (pkg_query in packages) {
    px_res <- native_cmd(
      conda_cmd = "search",
      conda_args = c(
        "-n", "condathis-env",
        "--yes",
        "--json",
        "--no-channel-priority",
        "--override-channels",
        "--channel-priority=0",
        channels_arg,
        platform_args
      ),
      pkg_query,
      verbose = verbose
    )
    if (isTRUE(px_res$status == 0)) {
      json_output <- jsonlite::fromJSON(px_res$stdout)
      if (length(json_output$result$pkgs) == 0) {
        package_available <- FALSE
      } else {
        package_available <- TRUE
      }
    }
    available_vector <- c(available_vector, package_available)
    all_available <- all(available_vector)
  }
  return(all_available)
}
