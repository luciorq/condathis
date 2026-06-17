#' Build CLI channel arguments
#'
#' @param ... Unnamed character vectors with channel names.
#'
#' @returns A character vector with repeated `-c <channel>` pairs.
#'
#' @keywords internal
#' @noRd
format_channels_args <- function(...) {
  rlang::check_dots_unnamed()
  channels <- c(...)
  if (rlang::is_null(channels)) {
    channels <- c(
      "conda-forge",
      "bioconda"
    )
  }
  channels_arg <- c()
  for (channel in channels) {
    channels_arg <- c(channels_arg, "-c", channel)
  }
  return(channels_arg)
}
