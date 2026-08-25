#' Check whether a Conda environment exists
#'
#' Checks whether an environment name is present in the environments managed
#' by `condathis`.
#'
#' @param env_name Character string with the environment name to check.
#'   Must be a single, non-missing character string.
#' @param method Character string naming which backend(s) to check.
#'   Defaults to `"auto"`: does the environment exist under *any*
#'   registered backend. An explicit backend name checks only that one.
#'   `"micromamba"` is the only backend registered today. `"native"` is a
#'   deprecated alias for `"micromamba"` (warns once per session).
#' @param verbose Character string controlling console output passed to
#'   the backend. Defaults to `"silent"`.
#' @returns `TRUE` when the environment exists and `FALSE` otherwise.
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   # Create the environment
#'   condathis::create_env(
#'     packages = "bioconda::fastqc",
#'     env_name = "fastqc-env"
#'   )
#'
#'   # Check if the environment exists
#'   condathis::env_exists("fastqc-env")
#'   #> [1] TRUE
#'
#'   # Check for a non-existent environment
#'   condathis::env_exists("non-existent-env")
#'   #> [1] FALSE
#' })
#' }
#'
#' @export
env_exists <- function(env_name, method = "auto", verbose = "silent") {
  validate_env_name(env_name, class = "condathis_env_exists_invalid_env_name")
  method <- resolve_method_alias(validate_method_arg(method))

  # Deliberately does NOT call resolve_backend(): resolving a backend for
  # an *existing* environment is itself implemented in terms of this exact
  # per-backend probe (see find_owning_backends()/backend_has_env()) -
  # calling resolve_backend() here would be circular. `method = "auto"`
  # means "does it exist under any registered backend" (reduced with
  # any()); an explicit method checks only that one backend.
  candidate_names <- if (identical(method, "auto")) {
    list_registered_backend_names()
  } else {
    method
  }

  return(any(vapply(
    candidate_names,
    function(nm) backend_has_env(get_backend(nm), env_name, verbose = verbose),
    logical(1L)
  )))
}
