#' List Conda environments managed by condathis
#'
#' Returns a data frame of the environments under the data directory of
#' each registered backend. It leaves out environments that `condathis` does
#' not manage.
#'
#' `list_envs()` is a query: it never creates an environment. On a new data
#' directory, with no environment yet, it returns a data frame with no rows.
#' It does not start or install micromamba.
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
#' @returns A data frame (a tibble) with one row per environment and the
#'   columns `backend` (chr), `env_name` (chr) and `path` (chr). The
#'   rows follow the backend order of `method`. When the listing fails for
#'   the backend that `method` names, `list_envs()` aborts with class
#'   `condathis_list_envs_failed` (also `condathis_backend_error`). With
#'   `method = "auto"`, `list_envs()` skips a backend whose listing fails
#'   and warns with class `condathis_backend_query_failed`. It aborts only
#'   when every backend fails.
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
#'   # Create environments
#'   condathis::create_env(
#'     "polyglot",
#'     env_name = "polyglot-env",
#'     channels = channel
#'   )
#'   condathis::create_env(env_name = "empty-env")
#'
#'   # List environments
#'   print(condathis::list_envs()$env_name)
#'   #> [1] "empty-env"    "polyglot-env"
#' })
#' }
#'
#' @export
list_envs <- function(method = "auto", verbose = "silent") {
  # Rule R2: every argument is checked before the first backend call.
  method <- resolve_method_alias(validate_method_arg(method))
  verbose_list <- parse_verbose_arg(verbose)

  # "auto" lists every registered backend, available or not (rule R6):
  # availability only decides where a new environment goes.
  auto <- identical(method, "auto")
  backend_names <- if (isTRUE(auto)) backend_names_by_priority() else method

  # The directories are part of the query, so a backend whose
  # `backend_get_env_dir()` fails is skipped like one whose listing fails.
  # The backend gets the user's level (rule R4), so "cmd" shows the command
  # line, as documented. The micromamba listing adds its quiet arguments,
  # so "output" does not print the JSON listing.
  results <- query_registered_backends(
    backend_names = backend_names,
    query = function(backend) {
      env_names <- backend_list_envs_checked(
        backend,
        verbose = verbose_list$strategy
      )
      paths <- vapply(
        env_names,
        function(env_name) {
          return(as.character(env_dir_for_backend(backend, env_name)))
        },
        character(1L),
        USE.NAMES = FALSE
      )
      return(list(env_name = env_names, path = paths))
    },
    auto = auto,
    fn = "list_envs",
    action = "list its environments"
  )

  rows <- lapply(names(results), function(nm) {
    listing <- results[[nm]]
    return(base::data.frame(
      backend = rep(nm, length(listing$env_name)),
      env_name = listing$env_name,
      path = listing$path,
      stringsAsFactors = FALSE
    ))
  })
  empty_df <- base::data.frame(
    backend = character(0L),
    env_name = character(0L),
    path = character(0L),
    stringsAsFactors = FALSE
  )
  envs_df <- do.call(rbind, c(list(empty_df), rows))
  return(new_tbl(envs_df))
}

#' Make a data frame a plain tibble
#'
#' Sets the class `c("tbl_df", "tbl", "data.frame")` and compact integer
#' row names. `rbind()` and `vapply()` give character row names, which a
#' tibble must not have.
#'
#' @param df A data frame.
#'
#' @returns The data frame, with the tibble class and row names `1:n`.
#'
#' @keywords internal
#' @noRd
new_tbl <- function(df) {
  n_rows <- base::nrow(df)
  df <- base::unclass(df)
  base::attr(df, "row.names") <- base::.set_row_names(n_rows)
  base::attr(df, "class") <- c("tbl_df", "tbl", "data.frame")
  return(df)
}
