#' Get channels recorded in an environment's history
#'
#' Reads the `conda-meta/history` file of an environment and extracts the
#' channel names embedded in the package URLs, reflecting the channels that
#' packages currently installed in the environment were actually resolved
#' from.
#'
#' @param env_name Character string with the environment name.
#'
#' @returns A character vector with unique channel names, or `character(0)`
#'   when the environment has no history file.
#'
#' @keywords internal
#' @noRd
get_env_history_channels <- function(env_name) {
  history_file <- fs::path(get_env_dir(env_name), "conda-meta", "history")
  if (isFALSE(fs::file_exists(history_file))) {
    return(character(0L))
  }

  history_lines <- readLines(history_file, warn = FALSE)
  pkg_lines <- history_lines[
    stringr::str_detect(history_lines, "^[+-]https?://")
  ]
  if (isTRUE(length(pkg_lines) == 0L)) {
    return(character(0L))
  }

  channel_matches <- stringr::str_match(
    pkg_lines,
    "^[+-]https?://[^/]+/(.+)/[^/]+::"
  )

  channels_vec <- channel_matches[, 2]
  channels <- unique(channels_vec[!is.na(channels_vec)])
  return(as.character(channels))
}
