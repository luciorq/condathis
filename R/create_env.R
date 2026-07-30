#' Create a Conda environment
#'
#' Creates a Conda environment managed by `condathis` and installs dependencies
#' from package specs or from an environment file.
#'
#' @param packages Character vector of package MatchSpec strings.
#'   Examples: `"python=3.13"`, `"bioconda::fastqc==0.12.1"`.
#'   Defaults to `NULL`.
#' @param env_file Character string with the path to an environment YAML file.
#'   Defaults to `NULL`.
#'   When provided, it is passed to `micromamba create -f`.
#' @param env_name Character string with the target environment name.
#'   Defaults to `"condathis-env"`.
#' @param channels Character vector with channel names used for dependency
#'   resolution. Defaults to `c("conda-forge", "bioconda")`.
#' @param channel_priority Character string with channel priority mode.
#'   Supported values are `"disabled"`, `"strict"`, and `"flexible"`.
#'   Defaults to `"disabled"`.
#' @param additional_channels Character vector of additional channels appended
#'   to `channels`. Defaults to `NULL`.
#' @param method Character string naming the backend to use. Defaults to
#'   `"auto"` (resolve automatically: the environment's own owning backend
#'   if it already exists, otherwise `getOption("condathis.backend_priority")`
#'   order). `"micromamba"` is the only backend registered today.
#'   `"native"` is a deprecated alias for `"micromamba"` (warns once per
#'   session).
#' @param platform Character string with the platform used for dependency
#'   solving (for example, `"linux-64"`, `"osx-64"`, `"osx-arm64"`,
#'   `"win-64"`, `"noarch"`). Defaults to `NULL`.
#'   On Apple Silicon, `condathis` may fall back to `"osx-64"` when Rosetta 2
#'   is available and packages are not available for `"osx-arm64"`.
#' @inheritParams run
#' @param overwrite Logical value that controls whether an existing environment
#'   should always be recreated. Defaults to `FALSE`.
#'
#' @returns A `condathis_result` S3 object (a classed list, still usable as
#'   a plain list) with `status`, `stdout`, `stderr`, `timeout`, `pid`,
#'   `cmd`, and `env_name`.
#'
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   # Create a Conda environment and install the CLI `fastqc` in it.
#'   # Explicitly using the channel `bioconda` and version `0.12.1`.
#'   condathis::create_env(
#'     packages = "bioconda::fastqc==0.12.1",
#'     env_name = "fastqc-env",
#'     verbose = "output"
#'   )
#' })
#' }
#' @export
create_env <- function(
  packages = NULL,
  env_file = NULL,
  env_name = "condathis-env",
  channels = c(
    "conda-forge",
    "bioconda"
  ),
  method = "auto",
  channel_priority = c(
    "disabled",
    "strict",
    "flexible"
  ),
  additional_channels = NULL,
  platform = NULL,
  verbose = c(
    "output",
    "silent",
    "cmd",
    "spinner",
    "full"
  ),
  overwrite = FALSE
) {
  validate_env_name(env_name, class = "condathis_create_invalid_env_name")

  if (isFALSE(rlang::is_bool(overwrite))) {
    cli::cli_abort(
      message = c(
        `x` = "Argument {.arg overwrite} needs to be a {.cls logical} value."
      ),
      class = "condathis_create_invalid_overwrite_arg"
    )
  }

  resolved <- resolve_backend(
    env_name = env_name,
    method = method,
    mutating = TRUE
  )

  verbose_list <- parse_strategy_verbose(verbose = verbose)

  # TODO: @luciorq As of v0.1.3-dev mixing file and packages is allowed,
  # + As this is allowed in conda.
  # + Need to include tests and update docs.
  cmd_string <- paste(
    c(
      resolved$name,
      "create",
      "-n",
      env_name,
      packages,
      if (isFALSE(rlang::is_null(env_file))) env_file
    ),
    collapse = " "
  )

  early_result <- env_already_satisfies_request(
    backend = resolved$backend,
    env_name = env_name,
    packages = packages,
    overwrite = overwrite,
    cmd_string = cmd_string,
    verbose_list = verbose_list
  )
  if (isFALSE(is.null(early_result))) {
    return(invisible(early_result))
  }

  px_res <- backend_create_env(
    resolved$backend,
    packages = packages,
    env_file = env_file,
    env_name = env_name,
    channels = channels,
    channel_priority = channel_priority,
    additional_channels = additional_channels,
    platform = platform,
    overwrite = overwrite,
    verbose = verbose
  )

  write_backend_marker(
    env_dir_for_backend(resolved$backend, env_name),
    resolved$name
  )

  if (isTRUE(verbose_list$strategy %in% c("full", "output"))) {
    cli::cli_inform(
      message = c(
        `!` = "Environment {.field {env_name}} succesfully created."
      )
    )
  }

  result <- new_condathis_result(
    status = if (is.null(px_res$status)) 0L else px_res$status,
    stdout = if (is.null(px_res$stdout)) "" else px_res$stdout,
    stderr = if (is.null(px_res$stderr)) "" else px_res$stderr,
    timeout = if (is.null(px_res$timeout)) FALSE else px_res$timeout,
    pid = if (is.null(px_res$pid)) NA_integer_ else px_res$pid,
    cmd = cmd_string,
    env_name = env_name
  )
  return(invisible(result))
}

#' Check if an existing environment already satisfies a `create_env()`
#' request
#'
#' Backend-agnostic: only calls the generic `backend_has_env()`/
#' `satisfies_dependencies()` against an already-resolved backend, so every
#' backend benefits from this shortcut without re-implementing it.
#'
#' @param backend An already-resolved backend object (from
#'   `resolve_backend()`), so this never triggers a second, independent
#'   backend resolution.
#' @param cmd_string Pre-built command string, used to fill in the
#'   early-return result's `cmd` field so it matches what a real call would
#'   have reported.
#'
#' @returns A `condathis_result` ready to return immediately if the target
#'   environment already exists and already satisfies every requested
#'   package spec (so nothing needs to run); `NULL` otherwise (the caller
#'   should proceed with the actual creation call).
#'
#' @keywords internal
#' @noRd
env_already_satisfies_request <- function(
  backend,
  env_name,
  packages,
  overwrite,
  cmd_string,
  verbose_list
) {
  if (
    isTRUE(overwrite) ||
      isFALSE(length(packages) > 0L) ||
      isFALSE(backend_has_env(backend, env_name = env_name, verbose = FALSE))
  ) {
    return(NULL)
  }

  is_satisfied_vector <- satisfies_dependencies(
    pkg_str_vector = packages,
    env_name = env_name,
    verbose = "silent",
    backend = backend
  )
  if (isFALSE(all(is_satisfied_vector))) {
    return(NULL)
  }

  if (isTRUE(verbose_list$strategy %in% c("full", "output"))) {
    cli::cli_inform(
      message = c(
        `!` = "Environment {.field {env_name}} already exists."
      )
    )
  }

  return(new_condathis_result(
    status = 0L,
    stdout = "",
    stderr = "",
    timeout = FALSE,
    pid = NA_integer_,
    cmd = cmd_string,
    env_name = env_name
  ))
}
