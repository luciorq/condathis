#' List Packages Installed in a Conda Environment
#'
#' This function retrieves a list of all packages installed in the specified Conda
#' environment. The result is returned as a tibble with detailed information about
#' each package, including its name, version, and source details.
#'
#' @inheritParams run
#'
#' @return A tibble containing all the packages installed in the specified environment,
#' with the following columns:
#' \describe{
#'   \item{base_url}{The base URL of the package source.}
#'   \item{build_number}{The build number of the package.}
#'   \item{build_string}{The build string describing the package build details.}
#'   \item{channel}{The channel from which the package was installed.}
#'   \item{dist_name}{The distribution name of the package.}
#'   \item{name}{The name of the package.}
#'   \item{platform}{The platform for which the package is built.}
#'   \item{version}{The version of the package.}
#' }
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   # Creates a Conda environment with the CLI `fastqc`
#'   condathis::create_env(
#'     packages = "fastqc",
#'     env_name = "fastqc-env"
#'   )
#'   # Lists the packages in env `fastqc-env`
#'   dat <- condathis::list_packages("fastqc-env")
#'   dim(dat)
#'   #> [1] 34  8
#' })
#' }
#' @export
list_packages <- function(
  env_name = "condathis-env",
  verbose = c(
    "output",
    "silent",
    "cmd",
    "spinner",
    "full"
  )
) {
  verbose_list <- parse_strategy_verbose(verbose = verbose)

  if (isFALSE(env_exists(env_name, verbose = verbose_list$internal_verbose))) {
    cli::cli_abort(
      message = c(
        `x` = "Environment {.field {env_name}} does not exist.",
        `!` = "Check {.code list_envs()} for available environments."
      ),
      class = "condathis_list_packages_missing_env"
    )
  }

  px_res <- rethrow_error_cmd(
    expr = {
      native_cmd(
        conda_cmd = "list",
        conda_args = c(
          "-n",
          env_name,
          verbose_list$quiet_flag,
          "--json"
        ),
        verbose = verbose_list$internal_verbose
      )
    }
  )
  if (isTRUE(px_res$status == 0L)) {
    pkgs_df <- jsonlite::fromJSON(px_res$stdout)
    pkgs_df <- tibble::as_tibble(pkgs_df)
    if (isTRUE(length(pkgs_df) == 0L)) {
      pkgs_df <- tibble::tibble(
        "base_url" = character(0L),
        "build_number" = integer(0L),
        "build_string" = character(0L),
        "channel" = character(0L),
        "dist_name" = character(0L),
        "name" = character(0L),
        "platform" = character(0L),
        "version" = character(0L)
      )
    }
  }

  if (isTRUE(verbose_list$strategy %in% c("full", "output"))) {
    cli::cli_inform(
      message = c(
        `!` = "Retrieved {nrow(pkgs_df)} packages from environment {.field {env_name}}."
      )
    )
    return(pkgs_df)
  } else {
    return(invisible(pkgs_df))
  }
}
