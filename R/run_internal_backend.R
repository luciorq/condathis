#' Run a command through a backend's `backend_resolve_run()` contract
#'
#' The non-`"micromamba"` counterpart to `run_internal_native()`. Where the
#' micromamba path spawns `micromamba run -n <env> <cmd> ...` and lets that
#' binary do the activation, this path asks the backend to *describe* the
#' invocation — `list(command, args, env, dir)` — and then spawns it
#' directly. Nothing about streaming, timeouts or process cleanup differs
#' between the two: both hand off to [execute_command()].
#'
#' The `env` element is applied as `c("current", env)`, `processx`'s idiom
#' for "inherit this session's environment, then override these" — the same
#' shape `run_bin()` already uses for micromamba's activation variables. A
#' backend returning `NULL` (or an empty vector) therefore means "inherit
#' unchanged", not "run with an empty environment".
#'
#' @param backend An already-resolved backend object (from
#'   `resolve_backend()$backend`).
#' @param cmd Character string with the command to execute.
#' @param ... Additional unnamed arguments passed to `cmd`.
#' @param env_name Character string with the target environment name.
#' @param verbose A parsed verbosity list from `parse_strategy_verbose()`.
#' @param error `"cancel"` or `"continue"`.
#' @param stdout,stderr,stdin Stream targets, as in `run()`.
#' @param input Character or raw vector written to stdin when `stdin = "|"`.
#' @param binary Logical, whether to capture streams as raw vectors.
#' @param supervise,cleanup_tree,linux_pdeathsig Process-cleanup options.
#' @param timeout Numeric seconds, or `Inf`.
#'
#' @returns A `processx::run()`-shaped list.
#'
#' @keywords internal
#' @noRd
run_internal_backend <- function(
  backend,
  cmd,
  ...,
  env_name = "condathis-env",
  verbose = c(
    "output",
    "silent",
    "cmd",
    "spinner",
    "full"
  ),
  error = c("cancel", "continue"),
  stdout = "|",
  stderr = "|",
  stdin = NULL,
  input = NULL,
  binary = FALSE,
  supervise = FALSE,
  cleanup_tree = FALSE,
  linux_pdeathsig = FALSE,
  timeout = Inf
) {
  verbose_list <- parse_strategy_verbose(verbose = verbose)
  error <- rlang::arg_match(error)
  error_var <- identical(error, "cancel")

  args_vector <- as.character(c(...))
  if (isTRUE(rlang::is_null(args_vector))) {
    args_vector <- character(0L)
  }

  resolved_run <- backend_resolve_run(
    backend,
    cmd = cmd,
    args = args_vector,
    env_name = env_name,
    verbose = verbose_list$internal_verbose
  )
  validate_resolve_run(resolved_run, env_name = env_name)

  encoding <- if (isTRUE(binary)) "binary" else "utf-8"

  # Same three rules `native_cmd()` applies: don't echo when stderr is
  # redirected away from the console, and never echo raw bytes.
  verbose_output <- verbose_list$output
  if (isFALSE(stderr %in% c("|", ""))) {
    verbose_output <- FALSE
  }
  if (identical(encoding, "binary")) {
    verbose_output <- FALSE
  }

  child_env <- NULL
  if (isTRUE(length(resolved_run$env) > 0L)) {
    child_env <- c("current", resolved_run$env)
  }

  px_res <- execute_command(
    command = resolved_run$command,
    args = resolved_run$args,
    wd = resolved_run$dir,
    env = child_env,
    spinner = verbose_list$spinner_flag,
    echo_cmd = verbose_list$cmd,
    echo = verbose_output,
    stdout = stdout,
    stderr = stderr,
    stdin = stdin,
    input = input,
    error_on_status = error_var,
    cleanup_tree = cleanup_tree,
    supervise = supervise,
    linux_pdeathsig = linux_pdeathsig,
    encoding = encoding,
    timeout = timeout
  )

  return(invisible(px_res))
}

#' Check a `backend_resolve_run()` return value before spawning anything
#'
#' A backend is third-party code, and a malformed return here would
#' otherwise surface as an opaque `processx` error (or, worse, spawn the
#' wrong thing). Validating at the boundary names the offending backend
#' instead.
#'
#' `env` and `dir` are allowed to be `NULL` — "inherit the environment" and
#' "inherit the working directory" are both legitimate — but `command` must
#' be a single string and `args` a character vector.
#'
#' @param resolved The value returned by `backend_resolve_run()`.
#' @param env_name Character string, for the error message.
#'
#' @returns `resolved`, invisibly.
#'
#' @keywords internal
#' @noRd
validate_resolve_run <- function(
  resolved,
  env_name,
  call = rlang::caller_env()
) {
  if (isFALSE(rlang::is_list(resolved))) {
    cli::cli_abort(
      message = c(
        `x` = "{.fn backend_resolve_run} must return a list.",
        `!` = "Got {.cls {class(resolved)[[1L]]}} for environment {.field {env_name}}."
      ),
      class = "condathis_backend_resolve_run_invalid",
      call = call
    )
  }
  missing_fields <- setdiff(c("command", "args", "env", "dir"), names(resolved))
  if (isTRUE(length(missing_fields) > 0L)) {
    cli::cli_abort(
      message = c(
        `x` = "{.fn backend_resolve_run} must return {.field command}, {.field args}, {.field env} and {.field dir}.",
        `!` = "Missing: {.field {missing_fields}}."
      ),
      class = "condathis_backend_resolve_run_invalid",
      call = call
    )
  }
  if (
    isFALSE(rlang::is_character(resolved$command)) ||
      isFALSE(identical(length(resolved$command), 1L)) ||
      is.na(resolved$command)
  ) {
    cli::cli_abort(
      message = c(
        `x` = "{.fn backend_resolve_run} must return a single, non-missing {.field command} string."
      ),
      class = "condathis_backend_resolve_run_invalid",
      call = call
    )
  }
  if (
    isFALSE(rlang::is_null(resolved$args)) &&
      isFALSE(rlang::is_character(resolved$args))
  ) {
    cli::cli_abort(
      message = c(
        `x` = "{.fn backend_resolve_run}'s {.field args} must be a character vector or {.code NULL}."
      ),
      class = "condathis_backend_resolve_run_invalid",
      call = call
    )
  }
  # `env` is handed straight to `processx`, which requires a *named
  # character vector* and rejects anything else with an opaque
  # `is_env_vector(env) is not TRUE` assertion naming no backend at all. A
  # named list is the easy mistake to make here (`withr::local_envvar()`
  # accepts one, so a backend's own `run()` can work fine while its
  # contract output is unusable), so it's worth naming explicitly.
  if (isFALSE(rlang::is_null(resolved$env))) {
    if (isFALSE(rlang::is_character(resolved$env))) {
      cli::cli_abort(
        message = c(
          `x` = "{.fn backend_resolve_run}'s {.field env} must be a named character vector or {.code NULL}.",
          `!` = "Got {.cls {class(resolved$env)[[1L]]}} for environment {.field {env_name}}.",
          `i` = "A named {.cls list} is the common mistake — {.fn processx} requires a character vector."
        ),
        class = "condathis_backend_resolve_run_invalid",
        call = call
      )
    }
    env_names <- names(resolved$env)
    if (
      isTRUE(length(resolved$env) > 0L) &&
        (rlang::is_null(env_names) || isTRUE(any(!nzchar(env_names))))
    ) {
      cli::cli_abort(
        message = c(
          `x` = "Every element of {.fn backend_resolve_run}'s {.field env} must be named.",
          `!` = "Unnamed element{?s} at position{?s} {.val {which(!nzchar(env_names %||% ''))}}."
        ),
        class = "condathis_backend_resolve_run_invalid",
        call = call
      )
    }
  }
  return(invisible(resolved))
}
