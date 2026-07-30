#' List packages in a Conda environment
#'
#' Returns package metadata for a Conda environment as a tibble.
#'
#' @param env_name Character string with the target environment name.
#'   Defaults to `"condathis-env"`.
#' @param method Character string naming the backend to use. Defaults to
#'   `"auto"` (resolve automatically: the environment's own owning
#'   backend). `"micromamba"` is the only backend registered today.
#'   `"native"` is a deprecated alias for `"micromamba"` (warns once per
#'   session).
#' @param verbose Character string controlling console output.
#'   Supported values are `"output"`, `"silent"`, `"cmd"`, `"spinner"`,
#'   and `"full"`. Defaults to `"output"`.
#'
#' @returns A data frame (`tibble`) with installed packages. Only four
#'   columns are guaranteed present regardless of backend: **name**,
#'   **version**, **build_number**, and **channel**. Additional columns
#'   vary by backend and shouldn't be relied on in cross-backend code — the
#'   `"micromamba"` backend today also includes `base_url`,
#'   `build_string`, `dist_name`, `platform`, `md5`, `sha256`, and `url`.
#'
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   # Creates a Conda environment with the CLI `fastqc`
#'   condathis::create_env(
#'     packages = "bioconda::fastqc",
#'     env_name = "fastqc-env"
#'   )
#'   # Lists the packages in env `fastqc-env`
#'   dat <- condathis::list_packages("fastqc-env")
#'   dim(dat)
#'   #> [1] 66 11
#' })
#' }
#'
#' @export
list_packages <- function(
  env_name = "condathis-env",
  method = "auto",
  verbose = c(
    "output",
    "silent",
    "cmd",
    "spinner",
    "full"
  )
) {
  validate_env_name(
    env_name,
    class = "condathis_list_packages_invalid_env_name"
  )
  verbose_list <- parse_strategy_verbose(verbose = verbose)

  if (identical(env_name, "condathis-env")) {
    create_base_env(verbose = verbose_list$internal_verbose)
  }

  resolved <- resolve_backend(
    env_name = env_name,
    method = method,
    mutating = FALSE
  )

  if (
    isFALSE(backend_has_env(
      resolved$backend,
      env_name,
      verbose = verbose_list$internal_verbose
    ))
  ) {
    cli::cli_abort(
      message = c(
        `x` = "Environment {.field {env_name}} does not exist.",
        `!` = "Check {.code list_envs()} for available environments."
      ),
      class = "condathis_list_packages_missing_env"
    )
  }

  pkgs_df <- backend_list_packages(
    resolved$backend,
    env_name = env_name,
    verbose = verbose
  )

  if (isTRUE(verbose_list$strategy %in% c("full", "output"))) {
    cli::cli_inform(
      message = c(
        `!` = "Retrieved {nrow(pkgs_df)} packages from environment {.field {env_name}}."
      )
    )
    return(pkgs_df)
  }
  return(invisible(pkgs_df))
}
