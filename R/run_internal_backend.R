#' Run a command through a backend's `backend_resolve_run()` contract
#'
#' Asks the backend to describe the invocation as
#' `list(command, args, env, dir)` and spawns it directly, for every backend
#' on every OS. The micromamba backend describes it with the variables of a
#' real `micromamba run` activation (see
#' `get_micromamba_activation_envvars()`), so the command is started by
#' `condathis`, not by `micromamba run`, which on Windows passes the command
#' through `cmd.exe`. It hands off to `execute_command()`, so streaming,
#' timeouts and process cleanup behave as for `run_bin()`.
#'
#' The child environment is built with `build_child_env()`, like `run_bin()`
#' and `run_pipeline()`: this session's environment, then the clean-conda
#' overlay. That block is the `base_env` that `backend_resolve_run()` gets,
#' the environment to compute the activation against. The backend's `env`
#' variables go on top of it (see `apply_child_overlay()`). A backend
#' returning `NULL` or an empty vector means "no activation variables", not
#' "run with an empty environment".
#'
#' A bare command is looked up the same way for every backend, per OS (see
#' `resolve_direct_run_command()`). On Linux and macOS, a command killed by
#' signal `n` has the status `128 + n`, as a shell, and `micromamba run`
#' before, report it (see `signal_exit_status()`), except after a timeout.
#'
#' A failing `backend_resolve_run()` honors `error`: under `"cancel"` it
#' aborts with `condathis_<fn>_resolve_failed` (see
#' `abort_resolve_failure()`), and under `"continue"` it is reported as a
#' status-127 result.
#'
#' `timeout` covers the activation and the command together: the backend
#' gets the whole time for its activation (see `backend_resolve_run()` in
#' [register_backend()]), and the command what is left of it. When the
#' time runs out before the command starts, the call is a timeout, as if
#' the command had been killed (see `activation_timeout_result()`).
#'
#' @param backend An already-resolved backend object (from
#'   `resolve_backend()$backend`).
#' @param cmd Character string with the command to execute.
#' @param ... Additional unnamed arguments passed to `cmd`.
#' @param env_name Character string with the target environment name.
#' @param env_dir Character string with the directory of an environment
#'   given by `env_path()`, or `NULL`. When set, the command is described
#'   by `backend_resolve_run_in_dir()`, not by `backend_resolve_run()`,
#'   which addresses environments by name.
#' @param verbose A parsed verbosity list from `parse_strategy_verbose()`.
#' @param error `"cancel"` or `"continue"`.
#' @param stdout,stderr,stdin Stream targets, as in `run()`.
#' @param input Character or raw vector written to stdin when `stdin = "|"`.
#' @param binary Logical, whether to capture streams as raw vectors.
#' @param supervise,cleanup_tree,linux_pdeathsig Process-cleanup options.
#' @param timeout Numeric seconds, or `Inf`.
#' @param backend_name Character string, the registered backend name, for
#'   the messages of `validate_resolve_run()`. `NULL` uses the name of
#'   `backend`'s class.
#' @param fn Character string, the exported function name, for the class
#'   of a resolution failure.
#' @param call Environment of the exported function the user called, for
#'   the errors of `validate_resolve_run()` and of a resolution failure.
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
  env_dir = NULL,
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
  timeout = Inf,
  backend_name = NULL,
  fn = "run",
  call = rlang::caller_env()
) {
  verbose_list <- parse_strategy_verbose(verbose = verbose, call = call)
  error <- arg_match_classed(
    error,
    values = c("cancel", "continue"),
    class = "condathis_invalid_error",
    arg_name = "error",
    call = call
  )
  error_var <- identical(error, "cancel")
  backend_name <- backend_name %||% backend_display_name(backend)

  args_vector <- as.character(c(...))
  if (isTRUE(rlang::is_null(args_vector))) {
    args_vector <- character(0L)
  }

  # The child's environment block before activation, like `run_bin()` and
  # `native_cmd()`: the clean-conda overlay, so the caller's own
  # `CONDA_*`/`MAMBA_*` settings, rc files and `R_HOME` never leak into the
  # child, and a per-call `TMPDIR`, removed when this function returns. The
  # package-cache and envs-path variables come from `backend` (see
  # `child_conda_dirs()`): a child of another backend never gets the
  # micromamba roots. The backend computes its activation against this
  # block, never against the R session's own environment.
  tmp_dir_path <- withr::local_tempdir(pattern = "condathis-tmp")
  run_env_dir <- as.character(
    env_dir %||% env_dir_for_backend(backend, env_name = env_name, call = call)
  )
  base_env <- build_child_env(
    tmp_dir = tmp_dir_path,
    conda_dirs = child_conda_dirs(
      backend,
      env_dir = run_env_dir,
      env_path = isFALSE(is.null(env_dir))
    )
  )

  # Resolution runs activation (for micromamba, the `activate.d` hooks via
  # the activation dump) and can fail. Same contract as `run_bin()` and
  # `run_pipeline()`: under `error = "cancel"`, a backend error becomes the
  # parent of `condathis_<fn>_resolve_failed`, which names the user's call,
  # and a contract error of `validate_resolve_run()` goes on unchanged.
  # Under `"continue"`, both give a failed result with the condition's
  # message. Unguarded, `rethrow_error_run()` either let the condition
  # escape `"continue"` or reported it as a failure of `cmd` itself.
  env_label <- env_dir %||% env_name
  started <- proc.time()[["elapsed"]]
  time_left <- function() {
    return(timeout - (proc.time()[["elapsed"]] - started))
  }
  not_resolved <- function(cnd) {
    return(invisible(list(
      status = 127L,
      stdout = "",
      stderr = resolve_failure_stderr("command", env_label, cnd),
      timeout = FALSE
    )))
  }
  resolved_run <- tryCatch(
    if (is.null(env_dir)) {
      rlang::exec(
        backend_resolve_run,
        backend,
        cmd = cmd,
        args = args_vector,
        env_name = env_name,
        verbose = verbose_list$internal_verbose,
        base_env = base_env,
        !!!backend_resolve_args(
          backend,
          "backend_resolve_run",
          timeout = timeout
        )
      )
    } else {
      rlang::exec(
        backend_resolve_run_in_dir,
        backend,
        cmd = cmd,
        args = args_vector,
        env_dir = env_dir,
        verbose = verbose_list$internal_verbose,
        base_env = base_env,
        !!!backend_resolve_args(
          backend,
          "backend_resolve_run_in_dir",
          timeout = timeout
        )
      )
    },
    error = function(cnd) cnd
  )
  if (isTRUE(time_left() <= 0)) {
    return(activation_timeout_result(
      env_label,
      timeout = timeout,
      error_var = error_var
    ))
  }
  if (inherits(resolved_run, "condition")) {
    if (isTRUE(error_var)) {
      abort_resolve_failure(
        resolved_run,
        fn = fn,
        cmd_name = cmd,
        env_label = env_label,
        backend_name = backend_name,
        call = call
      )
    }
    return(not_resolved(resolved_run))
  }
  contract_cnd <- tryCatch(
    {
      validate_resolve_run(
        resolved_run,
        env_name = env_label,
        backend_name = backend_name,
        call = call
      )
      NULL
    },
    error = function(cnd) cnd
  )
  if (isFALSE(is.null(contract_cnd))) {
    if (isTRUE(error_var)) {
      rlang::cnd_signal(contract_cnd)
    }
    return(not_resolved(contract_cnd))
  }

  encoding <- if (isTRUE(binary)) "binary" else "utf-8"

  # Same rules as `native_cmd()`: do not echo when stderr is redirected away
  # from the console, and never echo raw bytes.
  verbose_output <- verbose_list$output
  if (isFALSE(stderr %in% c("|", ""))) {
    verbose_output <- FALSE
  }
  if (identical(encoding, "binary")) {
    verbose_output <- FALSE
  }

  # The backend's activation variables go on top of the block it was given.
  child_env <- apply_child_overlay(base_env, overlay = resolved_run[["env"]])
  command <- resolve_direct_run_command(
    resolved_run[["command"]],
    env_dir = run_env_dir
  )

  # The status is checked here, not in `execute_command()`, so that the
  # error of a command killed by a signal has the status of the result.
  px_res <- execute_command(
    command = command,
    # `NULL` means no arguments; `processx` takes only a character vector.
    args = as.character(resolved_run[["args"]]),
    wd = resolved_run[["dir"]],
    env = child_env,
    spinner = verbose_list$spinner_flag,
    echo_cmd = verbose_list$cmd,
    echo = verbose_output,
    stdout = stdout,
    stderr = stderr,
    stdin = stdin,
    input = input,
    error_on_status = FALSE,
    cleanup_tree = cleanup_tree,
    supervise = supervise,
    linux_pdeathsig = linux_pdeathsig,
    encoding = encoding,
    timeout = if (isTRUE(is.finite(timeout))) max(time_left(), 0.001) else Inf
  )
  if (isFALSE(isTRUE(px_res[["timeout"]]))) {
    px_res[["status"]] <- signal_exit_status(px_res[["status"]])
  }
  if (isTRUE(error_var)) {
    # As in `execute_command()`: on the writable-stdin path, an `NA` status
    # comes from the Windows handle race of `exit_status_safely()`, not
    # from the command.
    signal_process_failure(
      px_res,
      timeout = timeout,
      na_is_failure = isFALSE(identical(stdin, "|"))
    )
  }

  return(invisible(px_res))
}

#' The result of a call whose time ran out before its command started
#'
#' The activation of the environment took the whole `timeout` of `run()`,
#' `run_bin()` or `run_pipeline()` (see `backend_resolve_run()` in
#' [register_backend()]): the result of a command killed by the timeout,
#' status `-9` and `timeout = TRUE`, with a standard error that says why.
#' Under `error = "cancel"` its timeout error is signaled, as for a command
#' that ran out of time.
#'
#' @param env_label Character string, the environment's name or directory.
#' @param timeout Numeric, the `timeout` of the call.
#' @param error_var Logical. `TRUE` for `error = "cancel"`.
#'
#' @returns A `processx::run()`-shaped list.
#'
#' @keywords internal
#' @noRd
activation_timeout_result <- function(env_label, timeout, error_var) {
  px_res <- list(
    status = -9L,
    stdout = "",
    stderr = activation_timeout_stderr(env_label),
    timeout = TRUE
  )
  if (isTRUE(error_var)) {
    signal_process_failure(px_res, timeout = timeout)
  }
  return(invisible(px_res))
}

#' The standard error of a call that timed out during the activation
#'
#' @param env_label Character string, the environment's name or directory.
#'
#' @returns A character string.
#'
#' @keywords internal
#' @noRd
activation_timeout_stderr <- function(env_label) {
  return(sprintf(
    "Timed out while activating environment '%s'.\n",
    as.character(env_label)
  ))
}

#' Apply activation variables to a child's environment block
#'
#' The last layers of `build_child_env()`, on a block that it already
#' built: `overlay` replaces the variables of the same name (on Windows,
#' whatever their case), then `path_prepend` goes in front of the `PATH`
#' that results, without a second copy of its directories, however that
#' `PATH` spells them (see `prepend_path_dirs()`). So the block a backend
#' gets as `base_env` is exactly the child's block without the backend's
#' activation variables.
#'
#' @param base_env Named character vector, from `build_child_env()`.
#' @param overlay Named character vector of activation variables, or
#'   `NULL`.
#' @param path_prepend Character vector of directories to prepend to
#'   `PATH`, or `NULL`.
#'
#' @returns A named character vector: the child's complete environment
#'   block.
#'
#' @keywords internal
#' @noRd
apply_child_overlay <- function(
  base_env,
  overlay = NULL,
  path_prepend = NULL
) {
  env <- as.list(base_env)
  if (isTRUE(length(overlay) > 0L)) {
    env <- apply_env_overrides(env, as.list(overlay))
  }
  if (isTRUE(length(path_prepend) > 0L)) {
    path_name <- match_env_name(names(env), "PATH")
    current_path <- if (is.na(path_name)) "" else env[[path_name]]
    env[[path_name %|na|% "PATH"]] <- prepend_path_dirs(
      path_prepend,
      current_path
    )
  }
  return(unlist(env))
}

#' The executable that `run()` starts for a backend's command
#'
#' `backend_resolve_run()` may return a bare command name. `run()`, and
#' `run_pipeline()` for each stage, then start it the same way for every
#' backend, as `micromamba run` started the commands of `run()`:
#'
#' * Linux and macOS: on the `PATH` of the child, after activation, so the
#'   directories that `activate.d` scripts add are searched in their
#'   order. `processx` starts the command with
#'   `execvp()` after it set the child's environment, which does exactly
#'   that, so the name is kept as it is, and the program gets it as its own
#'   name (`argv[0]`).
#' * Windows: in the binary directories of the environment, with the
#'   extensions of `PATHEXT` (see `resolve_env_bin_path()`), as
#'   micromamba's `backend_resolve_run()` does. A name found there becomes
#'   its path. Any other name stays bare, and `processx` looks it up as it
#'   always did for the micromamba backend: in the working directory of the
#'   command first, then on the `PATH` of the R session, as `<name>.com` or
#'   `<name>.exe`. The `PATH` of the child adds nothing to that but the
#'   directories of `activate.d` scripts: activation puts the binary
#'   directories of the environment in front of the `PATH` of the session.
#'   Searching the child's `PATH` here instead found `cmd`, the MSYS2 shell
#'   script that Rtools puts ahead of `C:/Windows/System32`, ran `.bat`
#'   files of the `PATH`, and skipped the working directory.
#'
#' A command with a directory part is kept, and a command found nowhere
#' stays bare, so that it fails to start as with the micromamba backend.
#'
#' @param command Character string, the `command` of `backend_resolve_run()`.
#' @param env_dir Character string, the environment directory.
#' @param on_windows Logical. Whether to apply the Windows rule.
#' @param pathext Character string, the value of `PATHEXT`.
#'
#' @returns Character string, the command to start.
#'
#' @keywords internal
#' @noRd
resolve_direct_run_command <- function(
  command,
  env_dir,
  on_windows = is_windows(),
  pathext = Sys.getenv("PATHEXT", ".COM;.EXE;.BAT;.CMD")
) {
  command <- as.character(command)
  if (isFALSE(on_windows)) {
    return(command)
  }
  return(resolve_run_bin_command(
    command,
    env_dir,
    path = paste(
      as.character(env_bin_search_dirs(env_dir, on_windows = TRUE)),
      collapse = ";"
    ),
    on_windows = TRUE,
    pathext = pathext,
    keep_bare = TRUE
  ))
}

#' The exit status of a command killed by a signal, as a shell reports it
#'
#' `processx` reports a command that a signal `n` ended as `-n` on Linux
#' and macOS. A shell reports `128 + n`: `137` for `SIGKILL`, `143` for
#' `SIGTERM`, and so did `micromamba run`, through which `run()` started
#' the commands of the micromamba backend there before. `run()` reports
#' that for every backend. Windows has no signals, and its statuses are
#' kept.
#'
#' A timeout is not mapped: `run()` reports `-9` for it with every backend,
#' because there `processx` kills the process it started.
#'
#' @param status The `status` of a `processx` result.
#' @param on_windows Logical. Whether to apply the Windows rule.
#'
#' @returns `status`, with a negative whole number `-n` replaced by the
#'   integer `128 + n` off Windows.
#'
#' @keywords internal
#' @noRd
signal_exit_status <- function(status, on_windows = is_windows()) {
  if (
    isTRUE(on_windows) ||
      isFALSE(rlang::is_scalar_integerish(status)) ||
      isTRUE(is.na(status)) ||
      isFALSE(status < 0)
  ) {
    return(status)
  }
  return(128L - as.integer(status))
}

#' Check a `backend_resolve_run()` return value before spawning anything
#'
#' A backend is third-party code, and a malformed return here would
#' otherwise surface as an opaque `processx` error (or, worse, spawn the
#' wrong thing). Validating at the boundary names the offending backend
#' instead.
#'
#' The rules: `command` is a single, non-`NA` string; `args` is `NULL` or a
#' character vector; `env` is `NULL` or a named character vector; `dir` is
#' `NULL` (keep R's working directory) or a single, non-`NA` string that
#' names an existing directory, the working directory of the command.
#'
#' Every error has the classes `c("condathis_backend_resolve_run_invalid",
#' "condathis_backend_invalid_return",
#' "condathis_backend_contract_violation", "condathis_error")`.
#'
#' @param resolved The value returned by `backend_resolve_run()`.
#' @param env_name Character string, for the error message.
#' @param backend_name Character string, the backend name for the message,
#'   or `NULL`.
#' @param call Environment of the exported function the user called.
#'
#' @returns `resolved`, invisibly.
#'
#' @keywords internal
#' @noRd
validate_resolve_run <- function(
  resolved,
  env_name,
  backend_name = NULL,
  call = rlang::caller_env()
) {
  invalid <- function(problem, .envir = parent.frame()) {
    header <- if (is.null(backend_name)) {
      "{.fn backend_resolve_run} returned an invalid value for environment {.field {env_name}}."
    } else {
      "Backend {.field {backend_name}} returned an invalid value from {.fn backend_resolve_run} for environment {.field {env_name}}."
    }
    message_env <- rlang::env(
      .envir,
      env_name = env_name,
      backend_name = backend_name
    )
    condathis_abort(
      message = c(`x` = header, problem),
      class = c(
        "condathis_backend_resolve_run_invalid",
        "condathis_backend_invalid_return",
        "condathis_backend_contract_violation"
      ),
      call = call,
      .envir = message_env
    )
  }
  if (isFALSE(rlang::is_list(resolved))) {
    invalid(c(
      `i` = "It must return a list, not {.obj_type_friendly {resolved}}."
    ))
  }
  missing_fields <- setdiff(c("command", "args", "env", "dir"), names(resolved))
  if (isTRUE(length(missing_fields) > 0L)) {
    invalid(c(
      `i` = "It must return {.field command}, {.field args}, {.field env} and {.field dir}.",
      `i` = "Missing: {.field {missing_fields}}."
    ))
  }
  if (
    isFALSE(rlang::is_string(resolved[["command"]])) ||
      isTRUE(is.na(resolved[["command"]]))
  ) {
    invalid(c(
      `i` = "{.field command} must be a single, non-missing string."
    ))
  }
  if (
    isFALSE(rlang::is_null(resolved[["args"]])) &&
      isFALSE(rlang::is_character(resolved[["args"]]))
  ) {
    invalid(c(
      `i` = "{.field args} must be a character vector or {.code NULL}."
    ))
  }
  # `processx` requires `env` to be a named character vector and rejects
  # anything else with an opaque `is_env_vector(env) is not TRUE` assertion
  # that names no backend. A named list is the common mistake:
  # `withr::local_envvar()` accepts one, so a backend's own `run()` can work
  # while its contract output is unusable.
  env_value <- resolved[["env"]]
  if (isFALSE(rlang::is_null(env_value))) {
    if (isFALSE(rlang::is_character(env_value))) {
      invalid(c(
        `i` = "{.field env} must be a named character vector or {.code NULL}, not {.obj_type_friendly {env_value}}.",
        `i` = "A named {.cls list} is the common mistake - {.pkg processx} requires a character vector."
      ))
    }
    env_names <- names(env_value)
    if (
      isTRUE(length(env_value) > 0L) &&
        (rlang::is_null(env_names) || isFALSE(all(nzchar(env_names))))
    ) {
      unnamed <- which(!nzchar(env_names %||% rep("", length(env_value))))
      invalid(c(
        `i` = "Every element of {.field env} must be named.",
        `i` = "Unnamed element{?s} at position{?s} {.val {unnamed}}."
      ))
    }
  }
  # Without this check, `processx` failed on a bad `dir` only after the
  # activation was resolved, with an error that names no backend.
  dir_value <- resolved[["dir"]]
  if (isFALSE(rlang::is_null(dir_value))) {
    if (
      isFALSE(rlang::is_string(dir_value)) ||
        isTRUE(is.na(dir_value)) ||
        isFALSE(isTRUE(fs::dir_exists(dir_value)))
    ) {
      invalid(c(
        `i` = "{.field dir} must be {.code NULL} or the path of an existing directory."
      ))
    }
  }
  return(invisible(resolved))
}
