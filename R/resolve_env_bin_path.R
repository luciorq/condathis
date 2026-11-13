#' Directories where an environment's own binaries can live
#'
#' Linux and macOS Conda environments put binaries in `<prefix>/bin`.
#' Windows environments spread them across several directories, in the order
#' `conda` and `micromamba` activation adds them to `PATH`.
#' Most Windows environments have no `<prefix>/bin`.
#'
#' @param env_dir Character string, the environment directory.
#' @param on_windows Logical. Whether to apply the Windows rule.
#'
#' @keywords internal
#' @noRd
env_bin_search_dirs <- function(env_dir, on_windows = is_windows()) {
  if (isFALSE(on_windows)) {
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
#' Searches `env_bin_search_dirs()` for `cmd`.
#' On Windows, tries every extension in `PATHEXT`, because a bare
#' `fs::file_exists()` check skips the implicit extension search of a shell
#' or `CreateProcess`.
#' Never falls back to the ambient system `PATH`. That is the caller's job,
#' and doing it here would blur "found in this environment" with "found
#' elsewhere by coincidence".
#'
#' @param env_dir Character string with the absolute path to the
#'   environment directory.
#' @param cmd Character string with the command name (or path) to resolve.
#'
#' @returns An absolute path (character string) if found inside `env_dir`,
#'   otherwise `NULL`. An absolute `cmd` is returned in the form of
#'   `native_command_path()`.
#'
#' @keywords internal
#' @noRd
resolve_env_bin_path <- function(env_dir, cmd) {
  candidate_names <- command_candidate_names(cmd)
  # An absolute path is not looked up in the environment: joining it to
  # `env_dir` names no file there, and on Windows the joined path can exceed
  # `PATH_MAX` (260), which makes `fs::path()` abort. Only the extensions of
  # `PATHEXT` are tried.
  if (isTRUE(fs::is_absolute_path(cmd))) {
    for (candidate in candidate_names) {
      if (isTRUE(fs::file_exists(candidate))) {
        return(native_command_path(candidate))
      }
    }
    return(NULL)
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

#' The path of an executable, as the operating system writes it
#'
#' On Windows, every `/` becomes `\\`. A program sees the path it was
#' started as in its own command line, and some programs read it there:
#' `cmd.exe` started as `C:/Windows/System32/cmd.exe` fails with "The
#' syntax of the command is incorrect." Nothing else changes: links and
#' 8.3 short names are not resolved. On Linux and macOS, the path is
#' returned as `fs::path()` gives it.
#'
#' @param path Character string, the path of an existing file.
#' @param on_windows Logical. Whether to apply the Windows rule.
#'
#' @returns A character string on Windows, an `fs_path` elsewhere.
#'
#' @keywords internal
#' @noRd
native_command_path <- function(path, on_windows = is_windows()) {
  if (isFALSE(on_windows)) {
    return(fs::path(path))
  }
  return(gsub("/", "\\", as.character(path), fixed = TRUE))
}

#' File names a command can have on disk
#'
#' On Linux and macOS, only `cmd` itself. On Windows, `cmd` with each
#' extension of `PATHEXT` appended, in lower case first: the implicit
#' extension search of a shell or `CreateProcess` is skipped by a plain
#' file check. `cmd` itself comes first only when its name has an
#' extension (see `command_has_extension()`): `processx`, as
#' `CreateProcess()`, starts a name without one only as `<name>.com` or
#' `<name>.exe`, never as a file without an extension. Rtools puts such
#' files on the `PATH` of R, for example `cmd`, an MSYS2 shell script in
#' `C:/rtools45/usr/bin`, ahead of `C:/Windows/System32`, so taking them
#' made `run("cmd", ...)` fail with status 127.
#'
#' @param cmd Character string, the command.
#' @param on_windows Logical. Whether to apply the Windows rule.
#' @param pathext Character string, the value of `PATHEXT`.
#'
#' @returns Character vector of file names, without duplicates.
#'
#' @keywords internal
#' @noRd
command_candidate_names <- function(
  cmd,
  on_windows = is_windows(),
  pathext = Sys.getenv("PATHEXT", ".COM;.EXE;.BAT;.CMD")
) {
  if (isFALSE(on_windows)) {
    return(cmd)
  }
  extensions <- strsplit(pathext, ";", fixed = TRUE)[[1L]]
  extensions <- extensions[nzchar(extensions)]
  with_extensions <- c(
    paste0(cmd, tolower(extensions)),
    paste0(cmd, extensions)
  )
  if (isFALSE(command_has_extension(cmd))) {
    return(unique(with_extensions))
  }
  return(unique(c(cmd, with_extensions)))
}

#' Does the file name of a command have an extension?
#'
#' The rule of `processx` on Windows: the file name, after the last `/`,
#' `\\` or `:`, has a `.` that is not its last character. Only then does
#' `processx` try the name as it is.
#'
#' @param cmd Character string, the command.
#'
#' @returns `TRUE` or `FALSE`.
#'
#' @keywords internal
#' @noRd
command_has_extension <- function(cmd) {
  file_name <- sub("^.*[/\\\\:]", "", cmd)
  dot <- regexpr(".", file_name, fixed = TRUE)
  return(isTRUE(dot > 0L) && isTRUE(dot < nchar(file_name)))
}

#' Find a command on a `PATH` value
#'
#' Searches the directories of `path` in order, the way the operating
#' system searches the `PATH` of a new process. `run_bin()` gives the
#' `PATH` of the child's environment block, so a command resolves as it
#' would in the child, not in the R session.
#'
#' On Linux and macOS, a candidate must be a file with execute permission,
#' as for `execvp()`. On Windows, any file with one of the names of
#' `command_candidate_names()` counts: the extensions of `PATHEXT` are
#' tried, and a file without an extension never counts for a name without
#' one. Empty entries are skipped. On Windows, double quotes around an
#' entry are removed.
#'
#' @param cmd Character string, a bare command name.
#' @param path Character string, a `PATH` value, or `NULL`.
#' @param on_windows Logical. Whether to apply the Windows rule.
#' @param pathext Character string, the value of `PATHEXT`.
#'
#' @returns The path of the first match, as found (symbolic links are not
#'   resolved), or `NULL`.
#'
#' @keywords internal
#' @noRd
find_command_on_path <- function(
  cmd,
  path,
  on_windows = is_windows(),
  pathext = Sys.getenv("PATHEXT", ".COM;.EXE;.BAT;.CMD")
) {
  if (isFALSE(rlang::is_string(path)) || isTRUE(is.na(path))) {
    return(NULL)
  }
  path_sep <- if (isTRUE(on_windows)) ";" else ":"
  dirs <- strsplit(path, path_sep, fixed = TRUE)[[1L]]
  if (isTRUE(on_windows)) {
    dirs <- gsub("^\"|\"$", "", dirs)
  }
  dirs <- dirs[nzchar(dirs)]
  candidate_names <- command_candidate_names(
    cmd,
    on_windows = on_windows,
    pathext = pathext
  )
  for (dir in dirs) {
    for (name in candidate_names) {
      candidate <- as.character(fs::path(dir, name))
      if (isFALSE(file.exists(candidate)) || isTRUE(dir.exists(candidate))) {
        next
      }
      if (
        isTRUE(on_windows) ||
          isTRUE(identical(unname(file.access(candidate, 1L)), 0L))
      ) {
        return(candidate)
      }
    }
  }
  return(NULL)
}
