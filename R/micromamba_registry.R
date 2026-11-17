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
#' so a reader never sees a partial file. libmamba takes no lock on the
#' file either.
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
#'
#' @returns `TRUE` when lines were removed, else `FALSE`, invisibly.
#'
#' @keywords internal
#' @noRd
micromamba_unregister_env <- function(
  env_dirs,
  home = micromamba_user_home()
) {
  result <- tryCatch(
    micromamba_unregister_env_impl(env_dirs = env_dirs, home = home),
    error = function(e) FALSE
  )
  return(invisible(isTRUE(result)))
}

#' @keywords internal
#' @noRd
micromamba_unregister_env_impl <- function(env_dirs, home) {
  env_dirs <- as.character(env_dirs)
  env_dirs <- env_dirs[!is.na(env_dirs) & nzchar(env_dirs)]
  registry <- fs::path(home, ".conda", "environments.txt")
  if (identical(length(env_dirs), 0L) || isFALSE(fs::file_exists(registry))) {
    return(FALSE)
  }
  size <- fs::file_info(registry)$size
  if (isTRUE(is.na(size)) || identical(as.numeric(size), 0)) {
    return(FALSE)
  }
  bytes <- readBin(registry, what = "raw", n = as.numeric(size))
  text <- rawToChar(bytes)
  Encoding(text) <- "UTF-8"
  # Each piece is a line with its own ending, and the last one may have
  # none.
  pieces <- regmatches(text, gregexpr("[^\n]*\n|[^\n]+$", text))[[1L]]
  lines <- sub("\r?\n$", "", pieces)
  drop <- nzchar(lines) &
    registry_line_key(lines) %in% registry_line_key(enc2utf8(env_dirs))
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
  return(isTRUE(file.rename(tmp_file, registry)))
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
