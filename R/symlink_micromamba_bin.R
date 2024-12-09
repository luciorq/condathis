#' Create a Symlink to the `micromamba` Executable
#'
#' This function checks whether the `micromamba` binary is already available on the
#' system's `PATH`. If not, it creates a symbolic link to the binary managed by `condathis`.
#' Users can specify a custom path to an existing `micromamba` binary or force
#' the creation of a new symlink.
#'
#' @param path A character string specifying the path to the `micromamba` binary
#'   to symlink. If `NULL`, the function attempts to locate a user-installed binary.
#' @param force A logical value indicating whether to overwrite an existing symlink.
#'   Defaults to `FALSE`.
#'
#' @return Invisibly returns the path to the `micromamba` symlink created or verified.
#'
#' @keywords internal
#' @noRd
symlink_micromamba_bin <- function(path = NULL, force = FALSE) {
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
    umamba_version <- parse_output(processx::run(umamba_path, "--version"), stream = "stdout")
    cli::cli_inform(
      message = c(
        `!` = "Micromamba version symlinked: {.field {umamba_version}}"
      )
    )
  }
  return(invisible(umamba_path))
}
