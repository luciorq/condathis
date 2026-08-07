#' Clean Conda cache
#'
#' Removes cached packages and archives from the `condathis` Conda root.
#' Also removes files from the package cache directory returned by
#' `tools::R_user_dir(package = "condathis", which = "cache")`.
#'
#' @param verbose Character string controlling console output.
#'   Supported values are `"output"`, `"silent"`, `"cmd"`, `"spinner"`,
#'   and `"full"`. Defaults to `"output"`.
#'
#' @returns A `condathis_result` S3 object (a classed list, still usable as
#'   a plain list) with `status`, `stdout`, `stderr`, `timeout`, `pid`,
#'   `cmd`, and `env_name`. `env_name` is always `NA` since cache cleanup is
#'   not tied to a specific environment.
#'
#' @details
#' Package files still referenced by existing environments may not be removed.
#' To maximize cleanup, remove environments first with `list_envs()` and
#' `remove_env()`.
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
          "--force-pkgs-dirs",
          verbose_list$quiet_flag
        ),
        verbose = verbose_list,
        error = "cancel"
      )
    }
  )

  r_user_cache <- fs::path(
    tools::R_user_dir(package = "condathis", which = "cache")
  )

  if (fs::dir_exists(r_user_cache)) {
    for (content_item in fs::dir_ls(r_user_cache)) {
      fs::file_delete(content_item)
    }
  }

  if (isTRUE(verbose_list$strategy %in% c("full", "output"))) {
    cli::cli_inform(
      message = c(
        `!` = "Cache successfully removed."
      )
    )
  }

  result <- new_condathis_result(
    status = px_res$status,
    stdout = px_res$stdout,
    stderr = px_res$stderr,
    timeout = if (is.null(px_res$timeout)) FALSE else px_res$timeout,
    pid = if (is.null(px_res$pid)) NA_integer_ else px_res$pid,
    cmd = paste(c("micromamba", "clean", "--all"), collapse = " "),
    env_name = NA_character_
  )
  return(invisible(result))
}
