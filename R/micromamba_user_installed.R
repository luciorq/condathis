#' Retrieve Micromamba Installed Path
#'
#' Checks if user already have `micromamba` binaries available on `PATH`.
#'
#' @keywords internal
micromamba_user_installed <- function() {
  umamba_bin_path <- Sys.which("micromamba")
  if (isTRUE(umamba_bin_path == "")) {
    umamba_bin_path <- Sys.which("micromamba.exe")
  }
  if (isTRUE(umamba_bin_path == "")) {
    return(invisible(umamba_bin_path))
  }
  umamba_bin_path <- normalizePath(umamba_bin_path)
  return(fs::path(umamba_bin_path))
}

#' Retrieve Micromamba Installed Path
#'
#' Checks if user already have `micromamba` binaries available on `PATH`.
#'
#' @keywords internal
symlink_micromamba_bin <- function(path = NULL, force = FALSE) {
  # force <- rlang::arg_match(force)

  if (isTRUE(is.null(path))) {
    user_umamba_path <- micromamba_user_installed()
  } else {
    (
      user_umamba_path <- path
    )
  }

  umamba_path <- micromamba_bin_path()

  if (isTRUE(force) && isTRUE(fs::file_exists(user_umamba_path)) && isTRUE(fs::file_exists(umamba_path))) {
    fs::file_delete(umamba_path)
  }

  if (isFALSE(fs::file_exists(umamba_path)) || isTRUE(force)) {
    fs::link_create(
      path = user_umamba_path,
      new_path = umamba_path,
      symbolic = TRUE
    )
  }

  umamba_version <- parse_output(processx::run(umamba_path, "--version"), stream = "stdout")
  cli::cli_inform(
    message = c(
      `!` = "Micromambma version symlinked: {.field {umamba_version}}"
    )
  )
  return(invisible(umamba_path))
}
