#' Validate an `env_name` argument
#'
#' Shared type-check for `env_name` arguments: a single, non-missing,
#' non-`NA` character string. Used by every exported function that accepts
#' `env_name`, so the same input is rejected the same way everywhere,
#' instead of `fs::path()`/`list_envs()` call sites each surfacing a
#' different (or no) error for the same bad input. Does **not** check
#' whether the environment actually exists - see `env_exists()` for that.
#'
#' @param env_name The value to validate.
#' @param class Character string. Condition class for the abort, so each
#'   call site can keep its own distinct, already-documented error class.
#' @param call Calling environment, passed to `cli::cli_abort()` so the
#'   error is attributed to the public-facing caller, not this helper.
#'
#' @returns `env_name`, invisibly, when valid. Aborts otherwise.
#'
#' @keywords internal
#' @noRd
validate_env_name <- function(env_name, class, call = rlang::caller_env()) {
  rlang::check_required(env_name, call = call)
  if (
    isFALSE(rlang::is_character(env_name)) ||
      isFALSE(identical(length(env_name), 1L)) ||
      is.na(env_name)
  ) {
    cli::cli_abort(
      message = c(
        `x` = "{.arg env_name} must be a single, non-missing character string."
      ),
      class = class,
      call = call
    )
  }
  return(invisible(env_name))
}
