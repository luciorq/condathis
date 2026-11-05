#' Get channels recorded in an environment's history
#'
#' Reads the `conda-meta/history` file of an environment and extracts the
#' channels embedded in the package URLs: the channels the installed
#' packages were resolved from. A channel on `conda.anaconda.org` is
#' returned by name, the URL path without the platform subdirectory
#' (`conda-forge`, `conda-forge/label/main`), as micromamba names it. Any
#' other channel is returned as its URL without the platform subdirectory
#' (`https://repo.prefix.dev/universe`, `file:///srv/channels/my-channel`),
#' which is also what a user passes in `channels`. A local channel that
#' micromamba installed from by another path, because its own has white
#' space, is the URL of its directory (see `micromamba_channel_display()`).
#' The credentials of channel URLs are hidden (see `hide_secrets()`), and
#' a channel on `conda.anaconda.org` is named without its token.
#'
#' @param env_dir Character string with the directory of the environment.
#'   `install_packages()` passes the directory of the backend it already
#'   resolved, so no backend is resolved again.
#'
#' @returns A character vector with unique channels, or `character(0)`
#'   when the environment has no history file.
#'
#' @keywords internal
#' @noRd
get_env_history_channels <- function(env_dir) {
  history_file <- fs::path(env_dir, "conda-meta", "history")
  if (isFALSE(fs::file_exists(history_file))) {
    return(character(0L))
  }

  history_lines <- readLines(history_file, warn = FALSE)
  # `+<channel URL>/<subdir>::<package>`, for any URL scheme.
  channel_urls <- stringr::str_match(
    history_lines,
    "^[+-]([A-Za-z][A-Za-z0-9+.-]*://.*)/[^/]+::"
  )[, 2L]
  channel_urls <- channel_urls[!is.na(channel_urls)]
  if (isTRUE(length(channel_urls) == 0L)) {
    return(character(0L))
  }
  # A local channel in a directory with white space, which micromamba
  # recorded by another path (see `micromamba_channel_arg()`).
  channel_urls <- micromamba_channel_display(channel_urls)
  # micromamba records the channels of the packages with their credentials
  # hidden; other tools may not.
  channel_urls <- hide_secrets(channel_urls)

  # Only `conda.anaconda.org` channels become names, without a token, as
  # micromamba names them. A name taken from another host (`universe` from
  # `https://repo.prefix.dev/universe`) did not compare equal to the URL the
  # user passed (see `normalize_channel_name()`), and the warning named a
  # channel that the user could not pass as it was shown.
  is_anaconda <- stringr::str_detect(
    channel_urls,
    stringr::regex("^https?://conda\\.anaconda\\.org/", ignore_case = TRUE)
  )
  channels_vec <- channel_urls
  channels_vec[is_anaconda] <- stringr::str_remove(
    channel_urls[is_anaconda],
    "^[A-Za-z]+://[^/]+/(t/[*]+/)?"
  )
  channels <- unique(channels_vec)
  return(as.character(channels))
}
