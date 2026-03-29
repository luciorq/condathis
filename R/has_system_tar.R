#' Check if a File Exists and is Executable
#'
#' @param path Character string. Path to check.
#' @returns Logical. `TRUE` if the file exists and is executable.
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
  # Check executable bit via file.access (0 = exists, 1 = execute)
  identical(file.access(path, mode = 1L), 0L)
}

#' Check if System `tar` is Available
#'
#' Checks whether a working `tar` executable is available. First checks the
#' `TAR` environment variable (also used by `utils::untar()`), then falls back
#' to `Sys.which("tar")`.
#'
#' @returns Logical. `TRUE` if `tar` is found, `FALSE` otherwise.
#'
#' @keywords internal
#' @noRd
has_system_tar <- function() {
  # R respects the TAR env var in utils::untar()
  tar_env <- Sys.getenv("TAR", unset = "")
  if (nzchar(tar_env) && is_executable(tar_env)) {
    return(TRUE)
  }
  return(nzchar(Sys.which("tar")))
}

#' Check if System `bzip2` is Available
#'
#' Checks whether a working `bzip2` executable is available. First checks
#' the `R_BZIPCMD` environment variable (used by R internals for bzip2
#' decompression), then falls back to `Sys.which("bzip2")`.
#'
#' @returns Logical. `TRUE` if `bzip2` is found, `FALSE` otherwise.
#'
#' @keywords internal
#' @noRd
has_system_bzip2 <- function() {
  # R uses R_BZIPCMD for bzip2 operations (see ?connections)
  bzip2_env <- Sys.getenv("R_BZIPCMD", unset = "")
  if (nzchar(bzip2_env) && is_executable(bzip2_env)) {
    return(TRUE)
  }
  return(nzchar(Sys.which("bzip2")))
}

#' Check if Compressed Archive Extraction is Possible
#'
#' Checks whether the system has both `tar` and `bzip2` available,
#' which are required to extract `.tar.bz2` archives.
#'
#' @returns Logical. `TRUE` if both `tar` and `bzip2` are available.
#'
#' @keywords internal
#' @noRd
can_extract_tar_bz2 <- function() {
  return(has_system_tar() && has_system_bzip2())
}
