#' Clean Conda Cache
#'
#' This function cleans the Conda cache by removing all packages and tarballs
#' from the local cache directory. It is useful for freeing up disk space
#' and ensuring that the cache does not contain outdated or unnecessary files.
#'
#' @param verbose A character string indicating the verbosity level of the
#'  output. It can be one of "silent", "cmd", "output", or "full".
#'  The default is "output".
#'
#' @return Invisibly returns the result of the underlying command executed.
#'
#' @details
#' Packages that are still linked with existing environments are not be
#' removed. If you expect to clean the whole cache, consider removing
#' all existing environments first using `list_envs()` and `remove_env()`.
#'
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   clean_cache(verbose = "output")
#' })
#' }
#'
#' @export
clean_cache <- function(
  verbose = c(
    "output",
    "silent",
    "cmd",
    "spinner",
    "full"
  )
) {
  verbose_list <- parse_strategy_verbose(verbose = verbose)
  px_res <- rethrow_error_cmd(
    expr = {
      native_cmd(
        conda_cmd = "clean",
        conda_args = c(
          "--all",
          "--yes",
          verbose_list$quiet_flag
        ),
        verbose = verbose_list,
        error = "cancel"
      )
    }
  )

  if (isTRUE(verbose_list$strategy %in% c("full", "output"))) {
    cli::cli_inform(
      message = c(
        `!` = "Cache succesfully removed."
      )
    )
  }
  return(invisible(px_res))
}
