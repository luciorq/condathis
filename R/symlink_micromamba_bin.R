#' Create a symlink to the managed micromamba executable
#'
#' Creates or refreshes a symlink at `micromamba_bin_path()` that points to a
#' discovered or user-specified micromamba binary.
#'
#' @param path Character string with the micromamba binary path to link.
#'   Defaults to `NULL`, which triggers path discovery.
#' @param force Logical value indicating whether an existing symlink should be
#'   replaced. Defaults to `FALSE`.
#'
#' @returns The symlink path, invisibly.
#'
#' @keywords internal
#' @noRd
symlink_micromamba_bin <- function(path = NULL, force = FALSE) {
  if (
    isTRUE(
      rlang::is_null(path) ||
        identical(path, "") ||
        identical(path, fs::path()) ||
        identical(path, fs::path(""))
    )
  ) {
    # Check user overrides before falling back to discovery
    user_opt <- getOption("condathis.micromamba_path", default = NULL)
    user_env <- Sys.getenv("CONDATHIS_MICROMAMBA_PATH", unset = "")
    if (!is.null(user_opt) && nzchar(user_opt)) {
      user_umamba_path <- user_opt
    } else if (nzchar(user_env)) {
      user_umamba_path <- user_env
    } else {
      user_umamba_path <- micromamba_user_installed()
    }
  } else {
    user_umamba_path <- path
  }
  umamba_path <- micromamba_bin_path()
  if (
    isTRUE(force) &&
      isTRUE(fs::file_exists(user_umamba_path)) &&
      isTRUE(fs::file_exists(umamba_path))
  ) {
    fs::file_delete(umamba_path)
  }
  if (isFALSE(fs::file_exists(umamba_path)) || isTRUE(force)) {
    fs::link_create(
      path = user_umamba_path,
      new_path = umamba_path,
      symbolic = TRUE
    )
    # False positive from linter as umamba_version is used on cli message.
    umamba_version <- get_micromamba_version(umamba_path = umamba_path)
    cli::cli_inform(
      message = c(
        `!` = "Micromamba version symlinked: {.field {umamba_version}}"
      )
    )
  }
  return(invisible(fs::path(umamba_path)))
}
