#' Check whether a Conda environment exists
#'
#' Checks whether an environment name is present in the environments managed
#' by `condathis`.
#'
#' `env_exists()` is a query: it never creates an environment. When
#' `env_name` has no directory under a backend's data directory, as on a new
#' data directory, `env_exists()` returns `FALSE`. It does not start or
#' install micromamba.
#' When no micromamba binary is installed, the micromamba backend reads
#' the `envs` directory of its data directory and the package records in
#' `conda-meta/` instead. It never installs micromamba.
#'
#' @inheritParams condathis-params
#' @param method Character string naming the backend to query. `"auto"` (the
#'   default) covers every registered backend, in
#'   `getOption("condathis.backend_priority")` order, also a backend that
#'   reports itself unavailable. Any name from
#'   [list_registered_backend_names()] queries only that backend.
#'   `"micromamba"` is built in. The name of a backend whose package
#'   condathis knows, such as `"rattler"` of the `rattlerthis` package,
#'   also queries only that backend. condathis loads that package. When it
#'   is not installed, the call aborts with class
#'   `condathis_backend_not_installed`. `"native"` is a deprecated alias for
#'   `"micromamba"` (warns once per session). Invalid values abort with
#'   class `condathis_invalid_method`.
#'
#' @returns `TRUE` when a queried backend reports the environment. `FALSE`
#'   when every queried backend reports it absent. When the query fails for
#'   the backend that `method` names, `env_exists()` aborts with class
#'   `condathis_env_exists_failed` (also `condathis_backend_error`). With
#'   `method = "auto"`, `env_exists()` skips a backend whose query fails and
#'   warns with class `condathis_backend_query_failed`. It aborts only when
#'   every backend fails.
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
#'
#'   # Create the environment
#'   condathis::create_env(
#'     "polyglot",
#'     env_name = "polyglot-env",
#'     channels = channel
#'   )
#'
#'   # Check if the environment exists
#'   print(condathis::env_exists("polyglot-env"))
#'   #> [1] TRUE
#'
#'   # Check for a non-existent environment
#'   condathis::env_exists("non-existent-env")
#'   #> [1] FALSE
#' })
#' }
#'
#' @export
env_exists <- function(
  env_name = "condathis-env",
  method = "auto",
  verbose = "silent"
) {
  # Rule R2: every argument is checked before the first backend call.
  validate_env_name(env_name, class = "condathis_env_exists_invalid_env_name")
  method <- resolve_method_alias(validate_method_arg(method))
  verbose_list <- parse_verbose_arg(verbose)

  # Do not call `resolve_backend()` here: it finds the owner of an existing
  # environment with this same per-backend probe (see
  # `find_owning_backends()`), so the call would be circular. "auto" asks
  # every registered backend, available or not (rule R6), because an
  # environment of an unavailable backend still exists.
  auto <- identical(method, "auto")
  backend_names <- if (isTRUE(auto)) backend_names_by_priority() else method

  # `backend_env_exists_checked()` keeps "absent" (`FALSE`) apart from
  # "failed" (an error), so a failed query is never read as `FALSE`
  # (rule R5). The backend gets the user's level (rule R4), so "cmd" shows
  # the command line, as documented. The micromamba listing adds its quiet
  # arguments, so "output" does not print the JSON listing.
  results <- query_registered_backends(
    backend_names = backend_names,
    query = function(backend) {
      return(backend_env_exists_checked(
        backend,
        env_name = env_name,
        verbose = verbose_list$strategy
      ))
    },
    auto = auto,
    fn = "env_exists",
    action = paste0("check whether environment '", env_name, "' exists")
  )
  return(isTRUE(any(unlist(results, use.names = FALSE))))
}
