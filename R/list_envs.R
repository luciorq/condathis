#' List Conda environments managed by condathis
#'
#' Returns environment names located under each registered backend's own
#' installation root. Environments not managed by `condathis` are excluded.
#'
#' @param method Character string naming which backend(s) to list.
#'   Defaults to `"auto"`: every currently *registered and available*
#'   backend. `"micromamba"` is the only backend registered today.
#'   `"native"` is a deprecated alias for `"micromamba"` (warns once per
#'   session).
#' @param verbose Character string controlling console output.
#'   Defaults to `"silent"`.
#'
#' @returns A tibble-classed data frame with one row per environment,
#'   columns `backend` (chr), `env_name` (chr), and `path` (chr) - one row
#'   per environment across every backend covered by `method`. With a
#'   single registered backend (today's default), this is always the same
#'   shape, just one `backend` value throughout.
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
#'   condathis::list_envs()$env_name
#'   #> [1] "fastqc-env" "python-env"
#' })
#' }
#'
#' @export
list_envs <- function(method = "auto", verbose = "silent") {
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

  empty_row <- base::data.frame(
    backend = character(0L),
    env_name = character(0L),
    path = character(0L),
    stringsAsFactors = FALSE
  )
  rows <- lapply(backend_names, function(nm) {
    backend <- get_backend(nm)
    envs <- backend_list_envs(backend, verbose = verbose)
    if (identical(length(envs), 0L)) {
      return(empty_row)
    }
    base::data.frame(
      backend = nm,
      env_name = envs,
      path = vapply(
        envs,
        function(e) as.character(env_dir_for_backend(backend, e)),
        character(1L)
      ),
      stringsAsFactors = FALSE
    )
  })

  envs_df <- if (isTRUE(length(rows) == 0L)) {
    empty_row
  } else {
    do.call(rbind, rows)
  }
  envs_df <- base::unclass(envs_df)
  base::attr(envs_df, "class") <- c("tbl_df", "tbl", "data.frame")
  return(envs_df)
}
