#' Directories where an environment's own binaries can live
#'
#' Linux/macOS Conda environments always put binaries in `<prefix>/bin`.
#' Windows environments instead spread them across several directories
#' (this is the same order real `conda`/`micromamba` activation adds to
#' `PATH` on Windows), and most environments do not have a `<prefix>/bin`
#' at all.
#'
#' @keywords internal
#' @noRd
env_bin_search_dirs <- function(env_dir) {
  if (isFALSE(stringr::str_detect(get_sys_arch(), "^Windows"))) {
    return(fs::path(env_dir, "bin"))
  }
  return(fs::path(
    env_dir,
    c(
      "",
      "Library/mingw-w64/bin",
      "Library/usr/bin",
      "Library/bin",
      "Scripts",
      "bin"
    )
  ))
}

#' Resolve a command to an absolute path inside a Conda environment
#'
#' Searches `env_bin_search_dirs()` for `cmd`, trying every extension in
#' `PATHEXT` on Windows (a bare `fs::file_exists()` check does not do the
#' implicit extension search a shell/`CreateProcess` would). Never falls
#' back to the ambient system `PATH` itself — that is the caller's
#' responsibility, and doing it here would blur the distinction between
#' "found in this environment" and "found somewhere else by coincidence".
#'
#' @param env_dir Character string with the absolute path to the
#'   environment directory.
#' @param cmd Character string with the command name (or path) to resolve.
#'
#' @returns An absolute path (character string) if found inside `env_dir`,
#'   otherwise `NULL`.
#'
#' @keywords internal
#' @noRd
resolve_env_bin_path <- function(env_dir, cmd) {
  is_windows <- isTRUE(stringr::str_detect(get_sys_arch(), "^Windows"))
  candidate_names <- cmd
  if (isTRUE(is_windows)) {
    pathext <- strsplit(
      Sys.getenv("PATHEXT", ".COM;.EXE;.BAT;.CMD"),
      ";",
      fixed = TRUE
    )[[1L]]
    candidate_names <- unique(c(
      cmd,
      paste0(cmd, tolower(pathext)),
      paste0(cmd, pathext)
    ))
  }

  for (dir in env_bin_search_dirs(env_dir)) {
    for (name in candidate_names) {
      candidate <- fs::path(dir, name)
      if (isTRUE(fs::file_exists(candidate))) {
        return(candidate)
      }
    }
  }
  return(NULL)
}
