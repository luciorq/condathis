#' List Conda environments managed by condathis
#'
#' Returns environment names located under the `condathis` installation root.
#' Environments not managed by `condathis` are excluded.
#'
#' @param verbose Character string controlling console output.
#'   Defaults to `"silent"`.
#'
#' @returns A character vector of environment names.
#'
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   # Create environments
#'   condathis::create_env(
#'     packages = "bioconda::fastqc",
#'     env_name = "fastqc-env"
#'   )
#'   condathis::create_env(
#'     packages = "python",
#'     env_name = "python-env"
#'   )
#'
#'   # List environments
#'   condathis::list_envs()
#'   #> [1] "fastqc-env" "python-env"
#' })
#' }
#'
#' @export
list_envs <- function(verbose = "silent") {
  env_root_dir <- get_install_dir()
  px_res <- rethrow_error_cmd(
    expr = {
      native_cmd(
        conda_cmd = "env",
        conda_args = c(
          "list",
          "-q",
          "--json"
        ),
        verbose = verbose
      )
    }
  )
  if (isFALSE(identical(px_res$status, 0L))) {
    # `rethrow_error_cmd()` already aborts with `condathis_cmd_status_error`
    # whenever `native_cmd()` itself throws (the normal failure path, since
    # its default `error = "cancel"` makes the underlying `processx::run()`
    # throw on a non-zero exit rather than return one) — this only
    # triggers if `px_res` is ever returned with a non-zero status without
    # throwing. Raising the same class here, rather than silently
    # returning `px_res$status` (a bare number, not a character vector),
    # keeps this function's return type invariant regardless of how the
    # underlying command failed.
    cli::cli_abort(
      message = c(
        `x` = "Failed to list environments.",
        `!` = "{.code micromamba env list} exited with status {.val {px_res$status}}."
      ),
      class = "condathis_cmd_status_error"
    )
  }

  envs_list <- jsonlite::fromJSON(px_res$stdout)
  envs_str <- base::normalizePath(envs_list$envs, mustWork = FALSE)
  envs_str <- fs::path_real(envs_str)
  return(condathis_env_names(envs_str, env_root_dir))
}

#' Keep the env paths that live under the condathis install root, return names
#'
#' Extracted from `list_envs()` so the filtering can be unit-tested without a
#' live `micromamba` call or real directories.
#'
#' `env_root_dir` is matched as a **literal** substring (`stringr::fixed()`),
#' not a regex. It is a filesystem path (e.g. `~/.local/share/R/condathis`)
#' whose `.` characters would otherwise be treated as "any character" regex
#' metacharacters — matching, for example, `~/Xlocal/share/R/condathis/...`
#' as if it belonged to condathis. The root path itself is excluded by the
#' trailing `basename() != "condathis"` filter, same as before.
#'
#' @param envs_str Character vector of realized environment paths.
#' @param env_root_dir Character string with the condathis install root.
#'
#' @returns A character vector of environment names (basenames).
#'
#' @keywords internal
#' @noRd
condathis_env_names <- function(envs_str, env_root_dir) {
  # `env_root_dir` is an `fs_path`; `stringr::fixed()` wants plain character.
  under_root <- stringr::str_detect(
    as.character(envs_str),
    stringr::fixed(as.character(env_root_dir))
  )
  env_names <- base::basename(envs_str[under_root])
  return(env_names[!env_names %in% "condathis"])
}
