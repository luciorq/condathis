#' Remove a Conda environment
#'
#' Removes an environment managed by `condathis`.
#'
#' With the micromamba backend, `remove_env()` does not change
#' `~/.conda/environments.txt`, the registry that conda and mamba share. A
#' line that [create_env()] added to that file stays (see Details in
#' [get_install_dir()]). On Windows, it also leaves the Start Menu
#' shortcuts that `condathis` 0.1.4 and earlier added for packages such as
#' `spyder`. Delete them from the Start Menu.
#'
#' @inheritParams condathis-params
#'
#' @returns A `condathis_result` object, invisibly: a classed list with
#'   `status`, `stdout`, `stderr`, `timeout`, `pid`, `cmd` and `env_name`.
#'   `cmd` is the command line that the backend ran, or `NA` when the
#'   backend reports none. `stdout`, `stderr` and `pid` are `NA` when the
#'   backend reports none, and `pid` always is with micromamba.
#'   An environment that does not exist aborts with class
#'   `condathis_remove_env_env_not_found` (also `condathis_env_not_found`
#'   and the 0.1.4 class `condathis_error_env_remove`). `remove_env()`
#'   deletes nothing then, not even a leftover directory of that name.
#'   A backend failure aborts with class `condathis_remove_env_failed` (also
#'   `condathis_backend_error`), with the backend's error as the parent.
#'   micromamba runs the `pre-unlink` scripts of packages before it removes
#'   them. A backend that does not makes `remove_env()` warn with class
#'   `condathis_remove_env_link_scripts_skipped` (also
#'   `condathis_link_scripts_skipped`). The warning names the packages.
#'
#' @inheritSection create_env Other R sessions
#'
#' @family environments
#' @seealso [condathis-conditions] for every condition class.
#'
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   # A local channel shipped with condathis, with `polyglot`: a
#'   # dependency-free script that runs on Linux, macOS and Windows.
#'   channel <- system.file(
#'     "extdata", "polyglot-channel",
#'     package = "condathis"
#'   )
#'   condathis::create_env(
#'     "polyglot",
#'     env_name = "polyglot-env",
#'     channels = channel
#'   )
#'   condathis::remove_env(env_name = "polyglot-env")
#' })
#' }
#'
#' @export
remove_env <- function(
  env_name = "condathis-env",
  method = "auto",
  verbose = c("output", "silent", "cmd", "spinner", "full")
) {
  # Rule R2: every argument is checked before the first backend call.
  validate_env_name(env_name, class = "condathis_remove_env_invalid_env_name")
  method <- validate_method_arg(method)
  verbose_list <- parse_verbose_arg(verbose)
  method <- resolve_method_alias(method, user_env = rlang::caller_env())

  # One R session at a time changes an environment (see
  # `local_env_lock()`): an install in another session finishes before the
  # environment is removed.
  env_lock <- local_env_lock(env_name, verbose = verbose_list$strategy)

  resolved <- resolve_backend(
    env_name = env_name,
    method = method,
    mutating = TRUE
  )

  # One missing-environment error on every backend, before the backend is
  # called. A name the backend does not list is not removed, so its
  # leftover directory stays: the backend's create replaces that directory
  # (see ?register_backend). A failed probe (`NA`, rule R5) goes on to
  # the backend, which reports its own error.
  env_probe <- backend_probe_env(
    resolved$backend,
    env_name = env_name,
    verbose = "silent"
  )
  if (isFALSE(env_probe)) {
    abort_env_not_found(
      env_name,
      class = c(
        "condathis_remove_env_env_not_found",
        "condathis_error_env_remove"
      )
    )
  }

  env_lock_before_change(env_lock)
  px_res <- with_backend_errors(
    backend_remove_env(
      resolved$backend,
      env_name = env_name,
      verbose = verbose_list$strategy
    ),
    fn = "remove_env",
    backend_name = resolved$name,
    action = paste0("remove environment '", env_name, "'")
  )
  result <- new_backend_result(
    px_res,
    fn = "remove_env",
    backend_name = resolved$name,
    env_name = env_name
  )
  link_scripts <- backend_link_scripts_skipped(
    px_res,
    fn = "remove_env",
    backend_name = resolved$name
  )

  if (isTRUE(verbose_list$strategy %in% c("full", "output"))) {
    condathis_inform(
      message = c(
        `v` = "Environment {.field {env_name}} successfully removed."
      )
    )
  }
  warn_link_scripts_skipped(
    link_scripts,
    fn = "remove_env",
    backend_name = resolved$name,
    env_name = env_name
  )
  return(invisible(result))
}
