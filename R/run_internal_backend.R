#' Run a single command of the run family
#'
#' The one path that starts the command of [run()] and [run_bin()] (see
#' `run_command()`), in both `activate` modes. `run_pipeline()` builds each
#' of its commands with the same helpers (`resolve_child_invocation()`,
#' `compose_child_env()` and `resolve_direct_run_command()`).
#'
#' The child's environment block has three layers:
#'
#' 1. `base_env`, from `build_child_env()`: this session's environment
#'    without the activation of the R session (see `isolate_host_env()`),
#'    then the clean-conda overlay and a per-call `TMPDIR`. The backend
#'    computes its activation against it.
#' 2. The activation (see `resolve_child_invocation()`). With
#'    `activate = TRUE`, the backend describes the invocation as
#'    `list(command, args, env, dir)`, and its `env` goes on top of
#'    `base_env` (see `apply_child_overlay()`). A backend returning `NULL`
#'    or an empty vector means "no activation variables", not "run with an
#'    empty environment". The micromamba backend describes it with the
#'    variables of a real `micromamba run` activation (see
#'    `get_micromamba_activation_envvars()`), so the command is started by
#'    `condathis`, not by `micromamba run`, which on Windows passes the
#'    command through `cmd.exe`. With `activate = FALSE`, no backend
#'    function runs: the fixed activation of `get_activation_envvars()`.
#' 3. With `activate = TRUE`, the binary directories of the environment in
#'    front of a `PATH` that names none of them (see `compose_child_env()`).
#'
#' It hands off to `execute_command()`, so streaming and timeouts behave
#' the same for every backend. A bare command is looked up the same way
#' for every backend, per OS (see `resolve_direct_run_command()`). On Linux
#' and macOS, a command killed by signal `n` has the status `128 + n`, as a
#' shell, and `micromamba run` before, report it (see
#' `signal_exit_status()`), except after a timeout.
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
#' @param activate Logical. Whether the backend activates the environment
#'   (`TRUE`), or `condathis` sets the fixed activation (`FALSE`).
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
  activate = TRUE,
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

  # The child's environment block before activation, like `native_cmd()`:
  # the session's environment without the activation of the R session (see
  # `isolate_host_env()`, which also undoes R's own startup), and the
  # clean-conda overlay, so the caller's own `CONDA_*`/`MAMBA_*` settings,
  # rc files and the variables of R (`R_HOME`, ...) never leak into the
  # child, and a per-call `TMPDIR`, removed when this function returns. The
  # package-cache and envs-path variables come from `backend` (see
  # `child_conda_dirs()`): a child of another backend never gets the
  # micromamba roots. The backend computes its activation against this
  # block, never against the R session's own environment.
  tmp_dir_path <- withr::local_tempdir(pattern = "condathis-tmp")
  run_env_dir <- as.character(
    env_dir %||% env_dir_for_backend(backend, env_name = env_name, call = call)
  )
  env_label <- env_dir %||% env_name

  # With `activate = FALSE`, no backend code runs that could report a
  # missing environment, and `run_command()` lets an `NA` probe through
  # (rule R5). Never fall back to a program on `PATH` then.
  if (isFALSE(activate) && isFALSE(dir.exists(run_env_dir))) {
    if (isTRUE(error_var)) {
      abort_env_not_found(
        env_label,
        class = paste0("condathis_", fn, "_env_not_found"),
        call = call
      )
    }
    return(invisible(list(
      status = 127L,
      stdout = "",
      stderr = sprintf("Conda environment '%s' does not exist.\n", env_label),
      timeout = FALSE
    )))
  }

  base_env <- build_child_env(
    tmp_dir = tmp_dir_path,
    conda_dirs = child_conda_dirs(
      backend,
      env_dir = run_env_dir,
      env_path = isFALSE(is.null(env_dir)),
      root_dir = micromamba_root_of_env_dir(backend, run_env_dir, env_dir)
    )
  )

  # With activation, resolution runs the backend's activation (for
  # micromamba, the `activate.d` hooks via the activation dump) and can
  # fail. Same contract as `run_pipeline()`: under `error = "cancel"`, a
  # backend error becomes the parent of `condathis_<fn>_resolve_failed`,
  # which names the user's call, and a contract error of
  # `validate_resolve_run()` goes on unchanged. Under `"continue"`, both
  # give a failed result with the condition's message. Never fall back to
  # running without activation: that runs the command in a different
  # environment than the caller requested.
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
  invocation <- tryCatch(
    resolve_child_invocation(
      backend,
      cmd = cmd,
      args = args_vector,
      env_name = if (is.null(env_dir)) env_name else NULL,
      env_dir = run_env_dir,
      env_label = env_label,
      activate = activate,
      base_env = base_env,
      verbose = verbose_list$internal_verbose,
      timeout = timeout
    ),
    error = function(cnd) cnd
  )
  if (isTRUE(activate)) {
    if (isTRUE(time_left() <= 0)) {
      return(activation_timeout_result(
        env_label,
        timeout = timeout,
        error_var = error_var
      ))
    }
    if (inherits(invocation, "condition")) {
      if (isTRUE(error_var)) {
        abort_resolve_failure(
          invocation,
          fn = fn,
          cmd_name = cmd,
          env_label = env_label,
          backend_name = backend_name,
          hint = run_family_resolve_hint(),
          call = call
        )
      }
      return(not_resolved(invocation))
    }
    contract_cnd <- tryCatch(
      {
        validate_resolve_run(
          invocation,
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
  } else if (inherits(invocation, "condition")) {
    # No backend code ran: an error here is condathis's own.
    rlang::cnd_signal(invocation)
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

  child_env <- compose_child_env(
    base_env,
    invocation,
    env_dir = run_env_dir,
    activate = activate
  )
  command <- resolve_direct_run_command(
    invocation[["command"]],
    child_env = child_env,
    wd = invocation[["dir"]]
  )
  if (is.null(command)) {
    abort_command_not_found(invocation[["command"]])
  }
  child_env <- r_prefix_command_env(
    command,
    child_env = child_env,
    wd = invocation[["dir"]]
  )

  # The status is checked here, not in `execute_command()`, so that the
  # error of a command killed by a signal has the status of the result.
  px_res <- execute_command(
    command = command,
    # `NULL` means no arguments; `processx` takes only a character vector.
    args = as.character(invocation[["args"]]),
    wd = invocation[["dir"]],
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

#' The invocation of a command of the run family
#'
#' With `activate = TRUE`, the backend describes it: `backend_resolve_run()`
#' for an environment given by name, `backend_resolve_run_in_dir()` for one
#' given by `env_path()`, which has no name. The backend computes its
#' activation against `base_env`. Its error is signaled as it is: the
#' caller turns it into the error of the exported function, or a failed
#' result.
#'
#' With `activate = FALSE`, no backend function runs, so a broken
#' `activate.d` script cannot make the call fail: the command as given,
#' with the fixed activation of `get_activation_envvars()`, composed
#' against the `PATH` of `base_env`, and no working directory.
#'
#' @param backend An already-resolved backend object.
#' @param cmd Character string, the command.
#' @param args Character vector, the arguments of the command.
#' @param env_name Character string, the environment name, or `NULL` for
#'   an environment given by `env_path()`.
#' @param env_dir Character string, the environment directory.
#' @param env_label Character string, the environment name, or the
#'   directory of an `env_path()`: the `CONDA_DEFAULT_ENV` of the fixed
#'   activation.
#' @param activate Logical.
#' @param base_env Named character vector, from `build_child_env()`.
#' @param verbose Character string, the `verbose` of the backend function.
#' @param timeout Numeric seconds the backend function may take, or `Inf`.
#'
#' @returns `list(command, args, env, dir)`, as `backend_resolve_run()`
#'   returns it. Not validated here (see `validate_resolve_run()`).
#'
#' @keywords internal
#' @noRd
resolve_child_invocation <- function(
  backend,
  cmd,
  args,
  env_name,
  env_dir,
  env_label,
  activate,
  base_env,
  verbose = "silent",
  timeout = Inf
) {
  args <- as.character(args)
  if (isFALSE(activate)) {
    return(list(
      command = cmd,
      args = args,
      env = get_activation_envvars(
        env_name = env_label,
        env_dir = env_dir,
        base_path = env_block_path(base_env)
      ),
      dir = NULL
    ))
  }
  if (is.null(env_name)) {
    return(rlang::exec(
      backend_resolve_run_in_dir,
      backend,
      cmd = cmd,
      args = args,
      env_dir = env_dir,
      verbose = verbose,
      base_env = base_env,
      !!!backend_resolve_args(
        backend,
        "backend_resolve_run_in_dir",
        timeout = timeout
      )
    ))
  }
  return(rlang::exec(
    backend_resolve_run,
    backend,
    cmd = cmd,
    args = args,
    env_name = env_name,
    verbose = verbose,
    base_env = base_env,
    !!!backend_resolve_args(
      backend,
      "backend_resolve_run",
      timeout = timeout
    )
  ))
}

#' The complete environment block of a command of the run family
#'
#' `base_env` with the activation of `invocation` on top (see
#' `apply_child_overlay()`). With `activate = TRUE`, when the `PATH` that
#' results names none of the binary directories of the environment, they
#' go in front of it: a backend whose activation sets no `PATH` still runs
#' the programs of the environment. An activation `PATH` that names them
#' is kept as it is, in its order (the directories that `activate.d`
#' scripts add stay where they put them). With `activate = FALSE`, the
#' fixed activation already has them first.
#'
#' In both modes and for every backend, the shell levels and prompt
#' modifiers of `child_activation_level_vars()` go last, over whatever the
#' activation set.
#'
#' @param base_env Named character vector, from `build_child_env()`.
#' @param invocation The value of `resolve_child_invocation()`.
#' @param env_dir Character string, the environment directory.
#' @param activate Logical.
#'
#' @returns A named character vector, passed to `processx` as a full
#'   `env =` replacement.
#'
#' @keywords internal
#' @noRd
compose_child_env <- function(base_env, invocation, env_dir, activate) {
  child_env <- apply_child_overlay(base_env, overlay = invocation[["env"]])
  child_env <- apply_child_overlay(
    child_env,
    overlay = child_activation_level_vars()
  )
  if (isTRUE(activate)) {
    bin_dirs <- as.character(env_bin_search_dirs(env_dir))
    entries <- strsplit(
      env_block_path(child_env),
      .Platform$path.sep,
      fixed = TRUE
    )[[1L]]
    if (isFALSE(any(path_entry_key(bin_dirs) %in% path_entry_key(entries)))) {
      child_env <- apply_child_overlay(child_env, path_prepend = bin_dirs)
    }
  }
  return(child_env)
}

#' The hint of a failed resolution in the run family
#'
#' For the error of `run()`, `run_bin()` and `run_pipeline()` when the
#' backend fails to resolve a command (see `abort_resolve_failure()`).
#'
#' @returns A named character vector, a cli bullet.
#'
#' @keywords internal
#' @noRd
run_family_resolve_hint <- function() {
  return(c(
    `i` = "{.code activate = FALSE} runs the command without the activation of the backend."
  ))
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

#' The executable that the run family starts
#'
#' The one lookup rule of `run()`, `run_bin()` and each command of
#' `run_pipeline()`, in both `activate` modes and for every backend.
#' `backend_resolve_run()` may return a bare command name. It is started
#' the way `micromamba run` started the commands of `run()`:
#'
#' * Linux and macOS: on the `PATH` of the child, after activation, so the
#'   directories that `activate.d` scripts add are searched in their
#'   order. `processx` starts the command with
#'   `execvp()` after it set the child's environment, which does exactly
#'   that, so the name is kept as it is, and the program gets it as its own
#'   name (`argv[0]`).
#' * Windows: as `cmd.exe`, through which `micromamba run` started the
#'   command: in the working directory of the command, then on the `PATH`
#'   of the child, with the extensions of the child's `PATHEXT` (see
#'   `find_command_on_path()`). A name found there becomes its path. The
#'   lookup of `processx` itself (`CreateProcess()`) is never used: it
#'   searches the directory of R's own executable, then the `PATH` of the
#'   R session, so a name that the command's `PATH` lacks ran a program of
#'   R, or of an environment that the R session runs in. A name without an
#'   extension is only found with one of `PATHEXT`: Rtools puts files
#'   without one on the `PATH` of R, such as `cmd`, an MSYS2 shell script
#'   in `C:/rtools45/usr/bin`, ahead of `C:/Windows/System32`.
#'
#' A command with a directory part is kept. A bare command found nowhere is
#' `NULL` on Windows: the caller reports it as a command that could not
#' start, status 127, as `execvp()` does on Linux and macOS (see
#' `abort_command_not_found()`).
#'
#' @param command Character string, the `command` of `backend_resolve_run()`.
#' @param child_env Named character vector, the complete environment block
#'   of the command (see `compose_child_env()`).
#' @param wd Character string, the working directory of the command, or
#'   `NULL` for R's.
#' @param on_windows Logical. Whether to apply the Windows rule.
#'
#' @returns Character string, the command to start, or `NULL`.
#'
#' @keywords internal
#' @noRd
resolve_direct_run_command <- function(
  command,
  child_env,
  wd = NULL,
  on_windows = is_windows()
) {
  command <- as.character(command)
  # As `execvp()` and `CreateProcess()`: a name with a directory part is
  # never searched for.
  if (isFALSE(on_windows) || isTRUE(grepl("[/\\\\:]", command))) {
    return(command)
  }
  pathext_name <- match_env_name(names(child_env), "PATHEXT", on_windows = TRUE)
  pathext <- if (is.na(pathext_name)) "" else child_env[[pathext_name]]
  if (isFALSE(nzchar(pathext))) {
    pathext <- ".COM;.EXE;.BAT;.CMD"
  }
  hit <- find_command_on_path(
    command,
    path = paste(
      c(
        as.character(wd %||% getwd()),
        env_block_path(child_env, on_windows = TRUE)
      ),
      collapse = ";"
    ),
    on_windows = TRUE,
    pathext = pathext
  )
  if (is.null(hit)) {
    return(NULL)
  }
  # Expands 8.3 short paths.
  return(normalizePath(hit, mustWork = FALSE))
}

#' The environment block of a program of R's own Conda prefix
#'
#' On Windows, the binary directories of R's own Conda prefix are not on
#' the `PATH` of a command (see `host_env_prefixes()`). A program of that
#' prefix, such as R's own `Rscript`, then cannot start: Windows has no
#' `rpath`, and the program loads its DLLs from those directories (exit
#' status `-1073741515`, `0xC0000135`). For such a program only, they are
#' appended at the end of its `PATH`, as for the processes that record an
#' activation (see `micromamba_run_path()`): the directories of the
#' environment and of the session still come first. Every other command
#' keeps the `PATH` of `compose_child_env()`.
#'
#' Off Windows, and when R does not run from a Conda prefix, nothing
#' changes: a Conda program finds its libraries through its `rpath`.
#'
#' @param command Character string, the command as
#'   `resolve_direct_run_command()` resolved it.
#' @param child_env Named character vector, the complete environment block
#'   of the command (see `compose_child_env()`).
#' @param wd Character string, the working directory of the command, or
#'   `NULL` for R's. A relative `command` is taken from there.
#' @param on_windows Logical. Whether to apply the Windows rule.
#' @param r_prefix Character string, the Conda prefix that R runs from, or
#'   `NULL` (see `condathis_r_prefix()`).
#'
#' @returns `child_env`, with the `PATH` changed for a program of R's
#'   prefix.
#'
#' @keywords internal
#' @noRd
r_prefix_command_env <- function(
  command,
  child_env,
  wd = NULL,
  on_windows = is_windows(),
  r_prefix = if (isTRUE(on_windows)) condathis_r_prefix()
) {
  if (
    isFALSE(on_windows) ||
      isFALSE(rlang::is_string(r_prefix)) ||
      isFALSE(nzchar(r_prefix)) ||
      isFALSE(rlang::is_string(command))
  ) {
    return(child_env)
  }
  full <- command
  if (isFALSE(fs::is_absolute_path(full))) {
    full <- file.path(wd %||% getwd(), full)
  }
  # Expands 8.3 short paths, so the prefix compares as written.
  full <- normalizePath(full, winslash = "\\", mustWork = FALSE)
  prefix_key <- path_entry_key(
    normalizePath(r_prefix, winslash = "\\", mustWork = FALSE),
    on_windows = TRUE
  )
  if (
    isFALSE(startsWith(
      path_entry_key(full, on_windows = TRUE),
      paste0(sub("\\\\$", "", prefix_key), "\\")
    ))
  ) {
    return(child_env)
  }
  new_path <- micromamba_run_path(
    session_path = env_block_path(child_env, on_windows = TRUE),
    on_windows = TRUE,
    r_prefix = r_prefix
  )
  if (is.null(new_path)) {
    return(child_env)
  }
  return(apply_child_overlay(child_env, overlay = c(PATH = new_path)))
}

#' Signal a command of the run family that could not start
#'
#' For a bare command that `resolve_direct_run_command()` found nowhere.
#' `rethrow_error_run()` takes the condition for a `processx` start
#' failure (see `is_spawn_failure()`), so the call fails, or under
#' `error = "continue"` returns, with status 127 and "command not found",
#' as on Linux and macOS.
#'
#' @param command Character string, the command.
#'
#' @keywords internal
#' @noRd
abort_command_not_found <- function(command) {
  rlang::abort(
    message = sprintf("Command '%s' not found.", command),
    class = "condathis_command_not_found"
  )
}

#' The exit status of a command killed by a signal, as a shell reports it
#'
#' `processx` reports a command that a signal `n` ended as `-n` on Linux
#' and macOS. A shell reports `128 + n`: `137` for `SIGKILL`, `143` for
#' `SIGTERM`, and so did `micromamba run`, through which `run()` started
#' the commands of the micromamba backend there before. `run()`,
#' `run_bin()` and `run_pipeline()` report that for every backend, for each
#' command. Windows has no signals, and its statuses are kept.
#'
#' A timeout is not mapped: the run family reports `-9` for it with every
#' backend, because there `processx` kills the process it started.
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
