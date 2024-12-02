#' Format Channels Arguments
#' @param ... Character. Channels to be used by `micromamba`.
#' @keywords internal
#' @noRd
format_channels_args <- function(...) {
  channels <- c(...)
  if (is.null(channels)) {
    channels <- c(
      "bioconda",
      "conda-forge"
    )
  }
  channels_arg <- c()
  for (channel in channels) {
    channels_arg <- c(channels_arg, "-c", channel)
  }
  return(channels_arg)
}
