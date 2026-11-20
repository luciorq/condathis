#' Remove the line of a removed environment from the user's registry
#'
#' `micromamba create` adds an environment to `~/.conda/environments.txt`
#' (in `%USERPROFILE%` on Windows) when it runs with the user's home (see
#' `micromamba_create_keeps_home()`), and earlier versions of `condathis`
#' added every environment. `micromamba env remove` runs with the home
#' `<root>/home` (see `micromamba_cmd_overlay()`), because libmamba's
#' `clean_environments_txt()` rewrites the whole file: it drops every line
#' that is not an environment at that moment and sorts the others.
#'
#' This removes only the lines of the given directories, after the
#' environment is gone. Each other line keeps its bytes and its line ending
#' (libmamba writes `\r\n` on Windows). A line matches as libmamba writes
#' it (`EnvironmentsManager::register_env()`: the absolute path, without a
#' trailing separator), compared with `/` for `\` and, on Windows, without
#' case. When no line matches, the file is not touched. The new content
#' goes to a file in the same directory, which then replaces the registry,
#' so a reader never sees a partial file.
#'
#' No process takes a lock on the file: libmamba appends to it
#' (`register_env()`) and rewrites it (`clean_environments_txt()`) without
#' one, and conda and mamba do the same. So, right before the new file
#' replaces the registry, the registry is read again; when it changed since
#' the first read (a line appended by `micromamba create`, or another
#' `remove_env()`), the work starts over, up to `attempts` times, and then
#' gives up. A write that lands between that last read and the rename can
#' still be lost; the window is a few system calls long.
#'
#' Removing the line is best effort: conda and mamba drop the line of a
#' missing environment the next time they list environments. Any failure
#' leaves the registry as it was, and is not reported.
#'
#' @param env_dirs Character vector, the directories of the removed
#'   environment as `condathis` and micromamba name them (for example the
#'   path under the root and its real path). `NA` values are ignored.
#' @param home Character string, the user's home (see
#'   `micromamba_user_home()`).
#' @param attempts Integer, how many times to start over when the registry
#'   changes during the update.
#'
#' @returns `TRUE` when lines were removed, else `FALSE`, invisibly.
#'
#' @keywords internal
#' @noRd
micromamba_unregister_env <- function(
  env_dirs,
  home = micromamba_user_home(),
  attempts = 3L
) {
  result <- tryCatch(
    micromamba_unregister_env_impl(
      env_dirs = env_dirs,
      home = home,
      attempts = attempts
    ),
    error = function(e) FALSE
  )
  return(invisible(isTRUE(result)))
}

#' @keywords internal
#' @noRd
micromamba_unregister_env_impl <- function(env_dirs, home, attempts = 3L) {
  env_dirs <- as.character(env_dirs)
  env_dirs <- env_dirs[!is.na(env_dirs) & nzchar(env_dirs)]
  registry <- fs::path(home, ".conda", "environments.txt")
  if (identical(length(env_dirs), 0L)) {
    return(FALSE)
  }
  keys <- registry_line_key(enc2utf8(env_dirs))
  for (attempt in seq_len(attempts)) {
    bytes <- read_registry_bytes(registry)
    if (identical(length(bytes), 0L)) {
      return(FALSE)
    }
    text <- rawToChar(bytes)
    Encoding(text) <- "UTF-8"
    # Each piece is a line with its own ending, and the last one may have
    # none.
    pieces <- regmatches(text, gregexpr("[^\n]*\n|[^\n]+$", text))[[1L]]
    lines <- sub("\r?\n$", "", pieces)
    drop <- nzchar(lines) & registry_line_key(lines) %in% keys
    if (isFALSE(any(drop))) {
      return(FALSE)
    }
    tmp_file <- tempfile(
      pattern = "environments-",
      tmpdir = as.character(fs::path_dir(registry)),
      fileext = ".txt"
    )
    on.exit(unlink(tmp_file), add = TRUE)
    new_text <- paste0(pieces[!drop], collapse = "")
    writeBin(charToRaw(enc2utf8(new_text)), tmp_file)
    if (isFALSE(is_windows())) {
      fs::file_chmod(tmp_file, fs::file_info(registry)$permissions)
    }
    # Another process changed the registry meanwhile: start over.
    if (isFALSE(identical(read_registry_bytes(registry), bytes))) {
      unlink(tmp_file)
      next
    }
    return(isTRUE(file.rename(tmp_file, registry)))
  }
  return(FALSE)
}

#' Read the registry as raw bytes
#'
#' @param registry Character string, the path of `environments.txt`.
#'
#' @returns A raw vector, empty when the file is missing or empty.
#'
#' @keywords internal
#' @noRd
read_registry_bytes <- function(registry) {
  if (isFALSE(fs::file_exists(registry))) {
    return(raw(0L))
  }
  size <- fs::file_info(registry)$size
  if (isTRUE(is.na(size)) || identical(as.numeric(size), 0)) {
    return(raw(0L))
  }
  return(readBin(registry, what = "raw", n = as.numeric(size)))
}

#' The key of a registry line or an environment directory
#'
#' `/` for `\`, no trailing separator, and on Windows lower case.
#'
#' @param x Character vector.
#'
#' @returns Character vector.
#'
#' @keywords internal
#' @noRd
registry_line_key <- function(x) {
  return(tolower_on_windows(to_slash_path(x)))
}
