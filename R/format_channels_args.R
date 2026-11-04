#' Build CLI channel arguments
#'
#' `~` at the start of a channel is expanded as micromamba expands it (see
#' `micromamba_expand_home()`): `micromamba create` can run with another
#' home (see `micromamba_create_keeps_home()`). A local channel in a
#' directory whose path has a space gets a path without one (see
#' `micromamba_channel_arg()`).
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
    channels <- "conda-forge"
  }
  channels <- micromamba_channel_arg(micromamba_expand_home(channels))
  channels_arg <- c()
  for (channel in channels) {
    channels_arg <- c(channels_arg, "-c", channel)
  }
  return(channels_arg)
}

#' A local channel in a form that micromamba can install from
#'
#' micromamba (2.10.0 checked) fails every create and install from a local
#' channel whose path has white space, as a path and as a `file://` URL,
#' percent-encoded or not ("Failed to parse URL ...: Bad path"): it keeps
#' the channel as a decoded URL (`resolve_path_name()` in `channel.cpp`)
#' and parses that again, with curl's parser, for every package of the
#' transaction (`build_fetchers()` in `transaction.cpp`). A dry run works.
#' Other characters, such as `#`, `%` or non-ASCII letters, work. So such a
#' channel gets a path without white space to the same directory:
#'
#' * Windows: its short (8.3) path, when the file system has short names.
#' * Linux and macOS: a symbolic link in `<root>/channels`, named after
#'   the directory and a hash of its path, when the root has no white
#'   space.
#'
#' Otherwise, and for a directory that does not exist, the channel is
#' passed as it is, and micromamba fails as before. A platform filter
#' (`[linux-64]`, or a last path component such as `/linux-64`) is kept.
#' micromamba records the channel with the new path, in `conda-meta/`:
#' `micromamba_channel_display()` turns it back into the URL of the
#' directory for [list_packages()] and `get_env_history_channels()`.
#'
#' @param channels Character vector of channels.
#' @param root_dir Character string, the micromamba root, or `NULL` to
#'   resolve it when a link is needed.
#' @param on_windows Logical. Whether to apply the Windows rule.
#'
#' @returns `channels`, with such local channels replaced by `file://`
#'   URLs.
#'
#' @keywords internal
#' @noRd
micromamba_channel_arg <- function(
  channels,
  root_dir = NULL,
  on_windows = is_windows()
) {
  channels <- as.character(channels)
  for (i in seq_along(channels)) {
    channel <- channels[[i]]
    # `%` for a percent-encoded space in a `file://` URL.
    if (isTRUE(is.na(channel)) || isFALSE(grepl("[[:space:]%]", channel))) {
      next
    }
    local <- split_local_channel(channel)
    if (
      is.null(local) ||
        isFALSE(grepl("[[:space:]]", local$path)) ||
        isFALSE(dir.exists(local$path))
    ) {
      next
    }
    if (isTRUE(on_windows)) {
      short_path_name <- get0(
        "shortPathName",
        envir = asNamespace("utils"),
        inherits = FALSE
      )
      if (is.null(short_path_name)) {
        next
      }
      new_path <- short_path_name(local$path)
    } else {
      root_dir <- root_dir %||%
        as.character(install_dir_for_backend(micromamba_backend()))
      new_path <- micromamba_channel_link(local$path, root_dir)
    }
    if (is.null(new_path) || isTRUE(grepl("[[:space:]]", new_path))) {
      next
    }
    channels[[i]] <- paste0(
      local_file_url(new_path, on_windows = on_windows),
      local$suffix
    )
  }
  return(channels)
}

#' Split a local channel into its directory and its platform filter
#'
#' @param channel Character string, a path or a `file://` URL.
#'
#' @returns `NULL` for a channel that is not local, else a list with
#'   `path`, the absolute path of the channel's directory, and `suffix`,
#'   the platform filter to append to it (`""`, `"/linux-64"` or
#'   `"[linux-64]"`).
#'
#' @keywords internal
#' @noRd
split_local_channel <- function(channel) {
  suffix <- ""
  filter <- regmatches(
    channel,
    regexpr("\\[[^]]*\\]$", channel)
  )
  if (isTRUE(length(filter) > 0L)) {
    suffix <- filter
    channel <- trimws(
      substring(channel, 1L, nchar(channel) - nchar(filter)),
      which = "right"
    )
  }
  if (isTRUE(grepl("^file://", channel, ignore.case = TRUE))) {
    path <- file_url_path(channel)
  } else if (
    isTRUE(grepl("^(/|\\\\\\\\|\\.{1,2}([/\\\\]|$)|[A-Za-z]:[/\\\\])", channel))
  ) {
    path <- channel
  } else {
    return(NULL)
  }
  # As micromamba reads a channel (see `drop_channel_platform()`): a last
  # path component that is a known platform is a filter.
  path <- sub("[/\\\\]+$", "", path)
  last_part <- sub("^.*[/\\\\]", "", path)
  if (
    isTRUE(identical(suffix, "")) &&
      isTRUE(ms_is_known_platform(last_part)) &&
      isTRUE(grepl("[^/\\\\:][/\\\\]+[^/\\\\]+$", path))
  ) {
    suffix <- paste0("/", last_part)
    path <- sub("[/\\\\]+[^/\\\\]+$", "", path)
  }
  return(list(path = as.character(fs::path_abs(path)), suffix = suffix))
}

#' The symbolic link of a local channel in the micromamba root
#'
#' `<root>/channels/<name>-<hash>`: `<name>` is the directory's name with
#' every character other than letters, digits, `.`, `_` and `-` replaced by
#' `-`, and `<hash>` comes from its absolute path, so one directory always
#' gets the same link, and the link of another directory never replaces
#' it. A link that points elsewhere is replaced.
#'
#' @param target Character string, the absolute path of the channel's
#'   directory.
#' @param root_dir Character string, the micromamba root.
#'
#' @returns The path of the link, or `NULL` when the root has white space or
#'   the link cannot be made.
#'
#' @keywords internal
#' @noRd
micromamba_channel_link <- function(target, root_dir) {
  if (isTRUE(grepl("[[:space:]]", root_dir))) {
    return(NULL)
  }
  links_dir <- fs::path(root_dir, "channels")
  name <- paste0(
    gsub("[^A-Za-z0-9._-]", "-", basename(target)),
    "-",
    substr(rlang::hash(as.character(target)), 1L, 16L)
  )
  link <- as.character(fs::path(links_dir, name))
  points_to_target <- function() {
    return(
      isTRUE(fs::is_link(link)) &&
        isTRUE(identical(as.character(fs::link_path(link)), target))
    )
  }
  if (isTRUE(points_to_target())) {
    return(link)
  }
  # Another session can make the same link at the same time.
  tryCatch(
    {
      fs::dir_create(links_dir)
      if (isTRUE(fs::is_link(link))) {
        fs::link_delete(link)
      }
      fs::link_create(target, link)
    },
    error = function(e) NULL
  )
  if (isTRUE(points_to_target())) {
    return(link)
  }
  return(NULL)
}

#' The `file://` URL of a local directory
#'
#' @param path Character string, an absolute path.
#' @param on_windows Logical. Whether `path` has a drive letter.
#' @param encode Logical. Whether to percent-encode the path, as a URL is
#'   written: `%20` for a space.
#'
#' @returns Character string.
#'
#' @keywords internal
#' @noRd
local_file_url <- function(path, on_windows = is_windows(), encode = FALSE) {
  path <- gsub("\\\\", "/", as.character(path))
  if (isTRUE(encode)) {
    path <- utils::URLencode(enc2utf8(path))
  }
  return(paste0("file://", if (isTRUE(on_windows)) "/", path))
}

#' The channels that micromamba recorded, as the user gave them
#'
#' The reverse of `micromamba_channel_arg()`: a `file://` URL of a link in
#' `<root>/channels` becomes the URL of the directory it points to, and on
#' Windows, a `file://` URL with a short (8.3) path becomes the URL of the
#' long path. Both are percent-encoded (`%20` for a space), as rattler
#' records such channels. Any other value is kept.
#'
#' @param x Character vector of channels or URLs, as recorded in
#'   `conda-meta/`.
#' @param root_dir Character string, the micromamba root. Not created.
#' @param on_windows Logical. Whether to apply the Windows rule.
#'
#' @returns Character vector.
#'
#' @keywords internal
#' @noRd
micromamba_channel_display <- function(
  x,
  root_dir = get_condathis_path(),
  on_windows = is_windows()
) {
  x <- as.character(x)
  is_file_url <- !is.na(x) & grepl("^file://", x, ignore.case = TRUE)
  if (isFALSE(any(is_file_url))) {
    return(x)
  }
  links_dir <- to_slash_path(fs::path(
    realize_existing_part(root_dir),
    "channels"
  ))
  for (i in which(is_file_url)) {
    path <- file_url_path(x[[i]])
    if (isTRUE(on_windows)) {
      if (isFALSE(grepl("~", path, fixed = TRUE))) {
        next
      }
      long_path <- normalizePath(path, winslash = "/", mustWork = FALSE)
      if (
        isFALSE(identical(long_path, path)) && isTRUE(file.exists(long_path))
      ) {
        x[[i]] <- local_file_url(long_path, on_windows = TRUE, encode = TRUE)
      }
      next
    }
    if (isFALSE(startsWith(path, paste0(links_dir, "/")))) {
      next
    }
    rest <- substring(path, nchar(links_dir) + 2L)
    name <- sub("/.*$", "", rest)
    link <- fs::path(links_dir, name)
    if (isFALSE(fs::is_link(link))) {
      next
    }
    x[[i]] <- paste0(
      local_file_url(fs::link_path(link), on_windows = FALSE, encode = TRUE),
      substring(rest, nchar(name) + 1L)
    )
  }
  return(x)
}
