#' Get the `condathis` data directory
#'
#' Returns the data directory used by each backend, creating it when
#' needed. The base path follows the platform-specific user data directory
#' rules used by `tools::R_user_dir()` (each backend resolves its own root
#' independently - e.g. the `"micromamba"` backend uses `condathis`'s own
#' `tools::R_user_dir("condathis", "data")`).
#'
#' @param method Character string naming which backend(s) to report.
#'   Defaults to `"auto"`: every currently *registered and available*
#'   backend. `"micromamba"` is the only backend registered today.
#'   `"native"` is a deprecated alias for `"micromamba"` (warns once per
#'   session).
#'
#' @details
#' On macOS, `condathis` uses a path without spaces when possible because
#' `micromamba run` can fail on paths that contain spaces.
#'
#' @returns A tibble-classed data frame with one row per backend covered by
#'   `method`, columns `backend` (chr) and `path` (chr) - the normalized,
#'   real path to that backend's own data directory. With a single
#'   registered backend (today's default), this is always the same shape,
#'   just one row.
#'
#' @examples
#' condathis::with_sandbox_dir({
#'   print(condathis::get_install_dir())
#'   #> # A tibble: 1 x 2
#'   #>   backend    path
#'   #>   <chr>      <chr>
#'   #> 1 micromamba /home/username/.local/share/condathis
#' })
#'
#' @export
get_install_dir <- function(method = "auto") {
  method <- resolve_method_alias(validate_method_arg(method))

  registered <- list_registered_backend_names()
  backend_names <- if (identical(method, "auto")) {
    registered[
      vapply(
        registered,
        function(nm) isTRUE(backend_available(get_backend(nm))),
        logical(1L)
      )
    ]
  } else {
    method
  }

  dir_df <- base::data.frame(
    backend = backend_names,
    path = vapply(
      backend_names,
      function(nm) as.character(install_dir_for_backend(get_backend(nm))),
      character(1L)
    ),
    stringsAsFactors = FALSE
  )
  dir_df <- base::unclass(dir_df)
  base::attr(dir_df, "class") <- c("tbl_df", "tbl", "data.frame")
  return(dir_df)
}
