#' Install packages in a Conda environment
#'
#' Installs packages into an existing `condathis` environment.
#' If the target environment does not exist, it is created first.
#'
#' @param packages Character vector of package MatchSpec strings to install.
#'   Required; must not be `NULL` (use `create_env()` to create an empty
#'   environment instead).
#' @param env_name Character string with the target environment name.
#'   Defaults to `"condathis-env"`.
#' @param method Character string naming the backend to use. Defaults to
#'   `"auto"` (resolve automatically: the environment's own owning backend
#'   if it already exists). `"micromamba"` is the only backend registered
#'   today. `"native"` is a deprecated alias for `"micromamba"` (warns once
#'   per session).
#' @param channels Character vector with channel names used for dependency
#'   resolution. Defaults to `c("conda-forge", "bioconda")`.
#' @param channel_priority Character string with channel priority mode.
#'   Supported values are `"disabled"`, `"strict"`, and `"flexible"`.
#'   Defaults to `"disabled"`.
#' @param additional_channels Character vector of additional channels appended
#'   to `channels`. Defaults to `NULL`.
#' @param verbose Character string controlling console output.
#'   Supported values are `"output"`, `"silent"`, `"cmd"`, `"spinner"`,
#'   and `"full"`. Defaults to `"output"`.
#'
#' @returns A `condathis_result` S3 object (a classed list, still usable as
#'   a plain list) with `status`, `stdout`, `stderr`, `timeout`, `pid`,
#'   `cmd`, and `env_name`.
#'
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   condathis::create_env(
#'     packages = "bioconda::fastqc",
#'     env_name = "fastqc-env"
#'   )
#'   # Install the package `python` in the `fastqc-env` environment.
#'   # NOTE: It is not recommended to install multiple packages in the same
#'   # environment, as it defeats the purpose of isolation provided by
#'   # separate environments.
#'   condathis::install_packages(packages = "python", env_name = "fastqc-env")
#' })
#' }
#'
#' @export
install_packages <- function(
  packages,
  env_name = "condathis-env",
  method = "auto",
  channels = c(
    "conda-forge",
    "bioconda"
  ),
  channel_priority = c(
    "disabled",
    "strict",
    "flexible"
  ),
  additional_channels = NULL,
  verbose = c(
    "output",
    "silent",
    "cmd",
    "spinner",
    "full"
  )
) {
  if (missing(packages) || rlang::is_null(packages)) {
    cli::cli_abort(
      message = c(
        `x` = "{.arg packages} must be a character vector of package names."
      ),
      class = "condathis_install_packages_missing_packages"
    )
  }
  validate_env_name(
    env_name,
    class = "condathis_install_packages_invalid_env_name"
  )

  verbose_list <- parse_strategy_verbose(verbose = verbose)

  resolved <- resolve_backend(
    env_name = env_name,
    method = method,
    mutating = TRUE
  )

  if (isFALSE(backend_has_env(resolved$backend, env_name))) {
    create_env(
      packages = NULL,
      env_name = env_name,
      method = resolved$name,
      verbose = verbose_list$internal_verbose
    )
  }

  # Channel-history-mismatch warning is a micromamba-specific convenience
  # (reads `conda-meta/history`, a micromamba/conda prefix-layout detail) —
  # not part of the generic backend contract; other backends simply don't
  # get this warning yet.
  if (identical(resolved$name, "micromamba")) {
    previous_channels <- get_env_history_channels(env_name = env_name)
    missing_channels <- setdiff(
      previous_channels,
      c(channels, additional_channels)
    )
    if (isTRUE(length(missing_channels) > 0L)) {
      cli::cli_warn(
        message = c(
          "!" = "Environment {.field {env_name}} was previously installed using channel{?s} {.field {missing_channels}}, not included in this call.",
          "i" = "Dependency resolution may differ from previous installs. Consider adding {.field {missing_channels}} to {.arg channels} or {.arg additional_channels}."
        ),
        class = "condathis_install_missing_previous_channels"
      )
    }
  }

  px_res <- backend_install(
    resolved$backend,
    packages = packages,
    env_name = env_name,
    channels = channels,
    channel_priority = channel_priority,
    additional_channels = additional_channels,
    verbose = verbose
  )

  if (
    isTRUE(verbose_list$strategy %in% c("full", "output")) &&
      isTRUE(length(packages) > 0L)
  ) {
    cli::cli_inform(
      message = c(
        `!` = "{cli::qty(packages)}Package{?s} {.field {packages}} succesfully installed in environment {.field {env_name}}."
      )
    )
  }

  result <- new_condathis_result(
    status = if (is.null(px_res$status)) 0L else px_res$status,
    stdout = if (is.null(px_res$stdout)) "" else px_res$stdout,
    stderr = if (is.null(px_res$stderr)) "" else px_res$stderr,
    timeout = if (is.null(px_res$timeout)) FALSE else px_res$timeout,
    pid = if (is.null(px_res$pid)) NA_integer_ else px_res$pid,
    cmd = paste(
      c(resolved$name, "install", "-n", env_name, packages),
      collapse = " "
    ),
    env_name = env_name
  )
  return(invisible(result))
}
