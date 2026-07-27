#' Check whether a Conda environment exists
#'
#' Checks whether an environment name is present in the environments managed by
#' `condathis`.
#'
#' @param env_name Character string with the environment name to check.
#'   Must be a single, non-missing character string.
#' @param verbose Character string controlling console output passed to
#'   `list_envs()`. Defaults to `"silent"`.
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
env_exists <- function(env_name, verbose = "silent") {
  rlang::check_required(env_name)
  if (
    isFALSE(rlang::is_character(env_name)) ||
      isFALSE(identical(length(env_name), 1L)) ||
      is.na(env_name)
  ) {
    cli::cli_abort(
      message = c(
        `x` = "{.arg env_name} must be a single, non-missing character string."
      ),
      class = "condathis_env_exists_invalid_env_name"
    )
  }
  available_envs <- list_envs(verbose = verbose)
  condathis_env_path <- env_name
  if (isTRUE(condathis_env_path %in% available_envs)) {
    return(TRUE)
  } else {
    return(FALSE)
  }
}
