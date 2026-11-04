#' Check if a File Exists and is Executable
#'
#' @param path Character string. Path to check.
#'
#' @returns Logical. `TRUE` if the file exists and is executable.
#'
#' @keywords internal
#' @noRd
is_executable <- function(path) {
  if (!nzchar(path)) {
    return(FALSE)
  }
  path <- path.expand(path)
  if (!file.exists(path)) {
    return(FALSE)
  }
  # Check executable bit via file.access (0 = exists, 1 = execute).
  # file.access() names its result after the path, so identical() with a
  # bare 0L was always FALSE, and no TAR path was ever accepted.
  return(identical(unname(file.access(path, mode = 1L)), 0L))
}

#' Find a program on `PATH`
#'
#' A wrapper around `Sys.which()`, so tests can replace the `PATH` lookup.
#' On Windows, `Sys.which()` also searches the system directories before
#' `PATH`, so a test cannot control the result through `PATH` alone.
#'
#' @param name Character string. Program name.
#'
#' @returns Character string with the program path, or `""` when the
#'   program is not found.
#'
#' @keywords internal
#' @noRd
find_program <- function(name) {
  return(unname(Sys.which(name)))
}

#' Resolve the system `tar` program
#'
#' The one rule that `has_system_tar()` and `extract_tar_bz2()` share, so a
#' `tar` that is reported as available is also the one that runs:
#'
#' 1. `TAR`, when it names a program. A value with a path separator is a
#'    path, used when it is executable. Any other value is a program name,
#'    looked up on `PATH`. The value `"internal"` (R's own tar, see
#'    `utils::untar()`) and an empty value name no program and are skipped.
#' 2. `tar` on `PATH`.
#'
#' A `TAR` value that names no usable program is skipped, not used as is:
#' the system tar is only a fallback for when R's internal tar fails, and
#' a broken `TAR` must not disable it.
#'
#' @param tar_env Character string. Value of the `TAR` environment
#'   variable.
#'
#' @returns Character string with the path of the `tar` program, or `NULL`
#'   when no `tar` program is found. A relative path in `TAR` is returned
#'   as an absolute path, because `extract_tar_bz2()` runs `tar` in another
#'   working directory.
#'
#' @keywords internal
#' @noRd
system_tar_program <- function(tar_env = Sys.getenv("TAR", unset = "")) {
  if (
    isTRUE(rlang::is_string(tar_env)) &&
      isTRUE(nzchar(tar_env)) &&
      isFALSE(identical(tar_env, "internal"))
  ) {
    if (isTRUE(grepl("[/\\\\]", tar_env))) {
      if (isTRUE(is_executable(tar_env))) {
        return(as.character(fs::path_abs(path.expand(tar_env))))
      }
    } else {
      tar_path <- find_program(tar_env)
      if (isTRUE(nzchar(tar_path))) {
        return(tar_path)
      }
    }
  }
  path_tar <- find_program("tar")
  if (isTRUE(nzchar(path_tar))) {
    return(path_tar)
  }
  return(NULL)
}

#' Check if System Tar Program is Available
#'
#' Checks whether a system `tar` program is available, with the rule of
#' `system_tar_program()`: `TAR` when it names a usable program, then `tar`
#' on `PATH`.
#'
#' @returns Logical. `TRUE` if `tar` is found, `FALSE` otherwise.
#'
#' @keywords internal
#' @noRd
has_system_tar <- function() {
  return(isFALSE(is.null(system_tar_program())))
}
