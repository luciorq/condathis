#' List packages in a Conda environment
#'
#' Returns the packages installed in a Conda environment, as a data frame.
#'
#' `list_packages()` is a query: it never creates an environment, also not
#' the default `"condathis-env"`. A missing environment aborts. When the
#' environment has no directory, as on a new data directory,
#' `list_packages()` does not start or install micromamba.
#' When no micromamba binary is installed, the micromamba backend reads
#' the `envs` directory of its data directory and the package records in
#' `conda-meta/` instead. It never installs micromamba.
#'
#' @inheritParams condathis-params
#'
#' @returns A data frame (a tibble) with one row per installed package,
#'   returned visibly. Six columns are guaranteed on every backend:
#'   * `name` (chr): the package name.
#'   * `version` (chr): the package version.
#'   * `build_number` (int): the build number.
#'   * `build_string` (chr): the build string.
#'   * `channel` (chr): a channel name or URL.
#'   * `platform` (chr): the platform subdirectory, such as `"linux-64"` or
#'     `"noarch"`.
#'
#'   The list includes the packages that pip or uv installed into the
#'   environment, with every backend. It shows them as micromamba does:
#'   channel `"pypi"`, build string `"pypi_0"`, build number 0, and the
#'   platform as pip reports it, such as `"linux-x86_64"`. Only the
#'   environment's own `site-packages` counts, not the user's site
#'   directory or `PYTHONPATH`.
#'
#'   Other columns vary by backend. Do not rely on them in code that must
#'   work with every backend. The `"micromamba"` backend today also includes
#'   `base_url`, `dist_name`, `md5`, `sha256` and `url`.
#'
#'   `list_packages()` shows the password and the token of a channel URL as
#'   `*****`, as micromamba does (`https://user:*****@host/channel`,
#'   `https://host/t/*****/channel`).
#'
#'   A missing environment aborts with class
#'   `condathis_list_packages_env_not_found` (also
#'   `condathis_env_not_found`). A failed listing aborts with class
#'   `condathis_list_packages_failed` (also `condathis_backend_error`).
#'   A listing without the six columns also has the class
#'   `condathis_backend_invalid_return`.
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
#'   # Creates a Conda environment with `polyglot`
#'   condathis::create_env(
#'     "polyglot",
#'     env_name = "polyglot-env",
#'     channels = channel
#'   )
#'   # Lists the packages in env `polyglot-env`
#'   dat <- condathis::list_packages("polyglot-env")
#'   print(dat[, c("name", "version", "channel")])
#' })
#' }
#'
#' @export
list_packages <- function(
  env_name = "condathis-env",
  method = "auto",
  verbose = "silent"
) {
  # Rule R2: every argument is checked before the first backend call.
  # `resolve_backend()` checks `method` before it probes any backend.
  validate_env_name(
    env_name,
    class = "condathis_list_packages_invalid_env_name"
  )
  verbose_list <- parse_verbose_arg(verbose)

  resolved <- resolve_backend(
    env_name = env_name,
    method = method,
    mutating = FALSE
  )

  # Rule R5: only a definite "absent" (`FALSE`) aborts here. When the probe
  # fails (`NA`), the listing below runs and reports the backend's real
  # error.
  probe <- backend_probe_env(resolved$backend, env_name, verbose = "silent")
  if (isFALSE(probe)) {
    abort_env_not_found(
      env_name,
      class = c(
        "condathis_list_packages_env_not_found",
        "condathis_list_packages_missing_env"
      )
    )
  }

  # The value is checked inside `with_backend_errors()`, as in `list_envs()`
  # and `validate_env()`: an invalid listing also gets
  # `condathis_list_packages_failed` and `condathis_backend_error`, so one
  # handler catches every failed listing.
  pkgs_df <- with_backend_errors(
    backend_list_packages_checked(
      resolved$backend,
      env_name = env_name,
      verbose = verbose_list$strategy
    ),
    fn = "list_packages",
    backend_name = resolved$name,
    action = paste0("list the packages of environment '", env_name, "'")
  )
  pkgs_df <- new_tbl(pkgs_df)
  # micromamba and rattler record a package's URL and channel with the
  # credentials hidden; the records of other tools may keep them.
  for (column in names(pkgs_df)) {
    if (isTRUE(is.character(pkgs_df[[column]]))) {
      pkgs_df[[column]] <- hide_secrets(pkgs_df[[column]])
    }
  }

  if (isTRUE(verbose_list$strategy %in% c("full", "output"))) {
    n_packages <- base::nrow(pkgs_df)
    condathis_inform(
      message = c(
        `i` = "Retrieved {n_packages} package{?s} from environment {.field {env_name}}."
      )
    )
  }
  return(pkgs_df)
}
