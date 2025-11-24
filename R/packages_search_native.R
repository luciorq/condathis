#' Search For Package in Channels
#'
#' Search if Package is available in required Channels
#'
#' @inheritParams create_env
#'
#' @keywords internal
#' @noRd
packages_search_native <- function(
  packages,
  channels = c(
    "bioconda",
    "conda-forge"
  ),
  channel_priority = c(
    "disabled",
    "strict",
    "flexible"
  ),
  additional_channels = NULL,
  platform = NULL,
  verbose = "silent"
) {
  channels_arg <- format_channels_args(
    channels,
    additional_channels
  )

  verbose_list <- parse_strategy_verbose(verbose = verbose)

  if (rlang::is_null(platform)) {
    platform_args <- NULL
  } else {
    platform_args <- c("--platform", platform)
  }

  channel_priority_args <- parse_strategy_channel_priority(
    channel_priority = channel_priority
  )

  available_vector <- c()
  for (pkg_query in packages) {
    px_res <- native_cmd(
      conda_cmd = "search",
      conda_args = c(
        "-n",
        "condathis-env",
        "--yes",
        "--json",
        verbose_list$quiet_flag,
        "--override-channels",
        channel_priority_args,
        channels_arg,
        platform_args
      ),
      pkg_query,
      verbose = verbose_list,
      error = "cancel"
    )
    if (identical(px_res$status, 0L)) {
      json_output <- jsonlite::fromJSON(px_res$stdout)
      if (identical(length(json_output$result$pkgs), 0L)) {
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
