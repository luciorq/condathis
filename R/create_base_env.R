#' Ensure the default condathis base environment exists
#'
#' Creates the empty default environment `"condathis-env"` when it is
#' missing. Only `run()`, `run_bin()`, `run_pipeline()` and
#' `install_packages()` call it (decision D3).
#'
#' @param method Character string, the backend to create it with. Callers
#'   pass the name they resolved (`resolved$name`), so the environment is
#'   created under the backend the call uses, not the first backend in
#'   priority order.
#' @param verbose Character string, one of the five verbose values.
#'   Defaults to `"silent"`.
#'
#' @returns `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
create_base_env <- function(method = "auto", verbose = "silent") {
  if (
    isFALSE(env_exists(
      env_name = "condathis-env",
      method = method,
      verbose = verbose
    ))
  ) {
    create_env(
      env_name = "condathis-env",
      method = method,
      verbose = verbose,
      overwrite = FALSE
    )
  }
  return(invisible(NULL))
}
