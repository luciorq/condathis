#' Clean Conda Cache
#' @keywords internal
#' @noRd
clean_cache <- function(
    verbose = "output") {
  quiet_flag <- parse_quiet_flag(verbose = verbose)
  px_res <- rethrow_error_cmd(
    expr = {
      native_cmd(
        conda_cmd = "clean",
        conda_args = c(
          "--all",
          "--yes",
          quiet_flag
        ),
        verbose = verbose
      )
    }
  )

  # fs::dir_ls(fs::path(get_condathis_path(), "pkgs"))
  # fs::dir_delete()

  if (isTRUE(verbose %in% c("full", "output"))) {
    cli::cli_inform(
      message = c(
        `!` = "Cache succesfully removed."
      )
    )
  }
  return(invisible(px_res))
}
