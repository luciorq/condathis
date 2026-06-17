#' Ensure the default condathis base environment exists
#'
#' @param verbose Character string controlling console output.
#'   Defaults to `"silent"`.
#'
#' @returns `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
create_base_env <- function(verbose = "silent") {
  if (isFALSE(env_exists(env_name = "condathis-env", verbose = verbose))) {
    create_env(
      env_name = "condathis-env",
      verbose = verbose,
      overwrite = FALSE
    )
  }
}
