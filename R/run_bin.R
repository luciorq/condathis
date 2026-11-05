#' Run a binary from a Conda environment
#'
#' Runs a program of a Conda environment, found in the binary directories
#' of the environment. With `activate = TRUE` (the default), the program
#' runs with the activation of the environment, as in [run()]. With
#' `activate = FALSE`, `run_bin()` only puts the binary directories in
#' front of `PATH`.
#'
#' The binary directories are `bin` on Linux and macOS. On Windows, they
#' are the environment directory, `Library/mingw-w64/bin`,
#' `Library/usr/bin`, `Library/bin`, `Scripts` and `bin`, searched with the
#' extensions of `PATHEXT`. `run_bin()` looks up a `cmd` that is not there
#' on the `PATH` that the program gets. That `PATH` lists the binary
#' directories first. Then it lists the `PATH` of the activation with
#' `activate = TRUE`, or of the R session with `activate = FALSE`.
#' `run_bin()` uses a `cmd` with a directory part as it is.
#'
#' With `activate = TRUE`, `run_bin()` differs from [run()] in two ways
#' only. It finds `cmd` differently. It reports a different status for a
#' command that a signal ends. [run()] looks up a bare name on the
#' activated `PATH` (on Windows, in the binary directories first).
#' `run_bin()` looks it up in the binary directories first on every
#' platform.
#'
#' When `env_name` is the default `"condathis-env"` and that environment
#' does not exist, `run_bin()` creates it, empty, with the backend that
#' `method` selects. `run_bin()` never creates any other missing
#' environment, and no program from `PATH` runs. The call fails, as `error`
#' describes.
#'
#' The errors of a failed or timed-out command carry the fields `status`,
#' `stdout`, `stderr` and `timeout`. A handler does not need to parse the
#' message.
#'
#' @inheritParams condathis-params
#' @inheritParams run
#' @param ... Arguments of the command, unnamed, as in [run()]. Each
#'   element of a character, numeric or logical vector is one argument.
#'   `run_bin()` drops `NULL` values and writes numbers in full. `NA`, named
#'   arguments, and values that are not atomic vectors abort with class
#'   `condathis_run_bin_invalid_args`.
#' @param activate Logical. Whether to run `cmd` with the activation of the
#'   environment. Defaults to `TRUE`, which activates the environment as
#'   [run()] does. An activation that fails is an error, as `error`
#'   describes. With `FALSE`, `run_bin()` skips the activation. It resolves
#'   `cmd` in the binary directories of the environment (then on the `PATH`
#'   of the R session), puts those directories in front of `PATH`, and
#'   applies no activation variables or `activate.d` scripts. In both modes,
#'   the command gets the variables that `condathis` sets in every process
#'   it starts (see [condathis-options]). Values other than `TRUE` and
#'   `FALSE` abort with class `condathis_invalid_activate`.
#'
#' @returns A `condathis_result` object, invisibly: a classed list with
#'   `status`, `stdout`, `stderr`, `timeout`, `pid`, `cmd` and `env_name`,
#'   which prints as a short summary. `status` is the exit status of the
#'   command. On Linux and macOS, a command that a signal ends has the
#'   negative signal number as status (-15 for `SIGTERM`, where [run()]
#'   reports 143). `stdout` and `stderr` are `NA` when that stream was not
#'   captured (a target other than `"|"`). `pid` is the process ID of the
#'   command with `stdin = "|"`, and `NA` otherwise. `cmd` is your command
#'   line, each part quoted, also when the backend runs it through a
#'   wrapper. It masks the credentials of URLs (see `verbose`). `env_name`
#'   is the environment name, or the directory of an [env_path()].
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
#'   condathis::create_env(
#'     "polyglot",
#'     env_name = "polyglot-env",
#'     channels = channel
#'   )
#'
#'   # Run the 'polyglot' script, on any platform
#'   condathis::run_bin("polyglot", env_name = "polyglot-env")
#'
#'   # Create an environment with 'python' and 'ripgrep', which conda-forge
#'   # builds for Linux, macOS and Windows (it has no Windows builds of GNU
#'   # tools such as `grep`)
#'   condathis::create_env(
#'     c("conda-forge::python", "conda-forge::ripgrep"),
#'     env_name = "my-env"
#'   )
#'
#'   # Run 'python' with a script in 'my-env' environment
#'   condathis::run_bin(
#'     "python", "-c", "import sys; print(sys.version)",
#'     env_name = "my-env"
#'   )
#'
#'   # Run the 'rg' (ripgrep) binary with additional arguments, without
#'   # activation
#'   condathis::run_bin(
#'     "rg", "--version",
#'     env_name = "my-env",
#'     activate = FALSE
#'   )
#' })
#' }
#'
#' @seealso [env_path()] for an environment created outside `condathis`,
#'   and [condathis-conditions] for the condition classes.
#' @family commands
#'
#' @export
run_bin <- function(
  cmd,
  ...,
  env_name = "condathis-env",
  method = "auto",
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
  activate = TRUE,
  timeout = Inf
) {
  # Every argument is checked before the first backend call or other side
  # effect (rule R2).
  validate_cmd_arg(cmd, class = "condathis_run_bin_invalid_cmd")
  # The user's arguments, kept apart from the arguments a backend's
  # activation may wrap them in, so `cmd` of the result shows the user's
  # command line.
  user_args <- cmd_args_as_character(
    list(...),
    class = "condathis_run_bin_invalid_args",
    formal_names = names(formals(run_bin)),
    named_class = dots_named_old_class
  )
  validate_input_with_stdin(
    input,
    stdin = stdin,
    class = arg_error_class(
      "run_bin",
      "input",
      aliases = "condathis_run_invalid_input"
    )
  )
  validate_bool_arg(
    binary,
    class = arg_error_class(
      "run_bin",
      "binary",
      aliases = "condathis_run_invalid_binary_arg"
    ),
    arg_name = "binary"
  )
  env_name_class <- "condathis_run_bin_invalid_env_name"
  if (isTRUE(is_env_path(env_name))) {
    validate_env_path_object(env_name, class = env_name_class)
  } else {
    validate_env_name(env_name, class = env_name_class)
  }
  error <- arg_match_classed(
    error,
    values = c("cancel", "continue"),
    class = "condathis_invalid_error",
    arg_name = "error"
  )
  verbose_list <- parse_verbose_arg(verbose)
  run_args <- validate_run_args(
    fn = "run_bin",
    timeout = timeout,
    supervise = supervise,
    cleanup_tree = cleanup_tree,
    linux_pdeathsig = linux_pdeathsig,
    stdin = stdin,
    stdout = stdout,
    stderr = stderr,
    activate = activate
  )
  # `rethrow_error_run()` reads `timeout` from this frame for its message.
  timeout <- run_args$timeout
  validate_method_arg(method)

  # Read by `rethrow_error_run()` from this frame.
  error_var <- identical(error, "cancel")
  fn_env <- rlang::current_env()

  verbose_output <- verbose_list$output
  if (isFALSE(stderr %in% c("|", ""))) {
    verbose_output <- FALSE
  }
  encoding <- if (isTRUE(binary)) "binary" else "utf-8"
  # Binary streams have no sensible terminal representation, never echo them.
  if (isTRUE(binary)) {
    verbose_output <- FALSE
  }

  cmd_string <- format_cmd_line(c(cmd, user_args))
  # Each early return below reports a command that never started.
  not_started <- function(stderr_text, env_label) {
    return(invisible(new_condathis_result(
      status = 127L,
      stdout = captured_or_na("", target = stdout),
      stderr = captured_or_na(stderr_text, target = stderr),
      timeout = FALSE,
      pid = NA_integer_,
      cmd = cmd_string,
      env_name = env_label
    )))
  }

  # An environment given by `env_path()` is run from its directory, by a
  # backend that can (see `resolve_env_path_target()`), and must be a
  # Conda environment.
  if (isTRUE(is_env_path(env_name))) {
    resolved <- resolve_env_path_target(
      env_name,
      method = method,
      class = env_name_class
    )
    env_dir <- resolved$env_dir
    env_label <- env_dir
    run_env_name <- NULL
    env_path_stderr <- check_env_path_usable(
      env_dir,
      error_var = error_var,
      class = "condathis_run_bin_env_not_found"
    )
    if (isFALSE(is.null(env_path_stderr))) {
      return(not_started(env_path_stderr, env_label))
    }
  } else {
    resolved <- resolve_backend(
      env_name = env_name,
      method = method,
      mutating = FALSE
    )
    env_label <- env_name
    run_env_name <- env_name
    # A probe that fails (NA) proceeds: the backend then reports the real
    # error (rule R5). Only a definite FALSE is a missing environment.
    env_name_exists <- backend_probe_env(
      resolved$backend,
      env_name,
      verbose = "silent"
    )
    if (isFALSE(env_name_exists)) {
      if (identical(env_name, "condathis-env")) {
        # Only the default environment is created (decision D3), with the
        # backend this call resolved.
        create_base_env(
          method = resolved$name,
          verbose = verbose_list$internal_verbose
        )
      } else {
        # Never fall back to a program on `PATH`: a misspelled `env_name`
        # must not run a binary from outside any environment.
        if (isTRUE(error_var)) {
          abort_env_not_found(
            env_name,
            class = "condathis_run_bin_env_not_found"
          )
        }
        return(not_started(
          sprintf("Conda environment '%s' does not exist.\n", env_name),
          env_name
        ))
      }
    }
    env_dir <- as.character(
      env_dir_for_backend(resolved$backend, env_name = env_name)
    )
  }

  # The child's environment block before activation: the session's
  # environment with the clean-conda overlay (the caller's own
  # `CONDA_*`/`MAMBA_*` settings, rc files and `R_HOME` are cleared) and a
  # per-call `TMPDIR`. The package-cache and envs-path variables come from
  # the backend that owns the environment (see `child_conda_dirs()`). It is
  # the `base_env` of `backend_resolve_run()`: the backend computes its
  # activation against it, never against the R session's own environment.
  # The calling session's environment and PATH are never modified.
  tmp_dir_path <- withr::local_tempdir(pattern = "condathis-tmp")
  base_env <- build_child_env(
    tmp_dir = tmp_dir_path,
    conda_dirs = child_conda_dirs(
      resolved$backend,
      env_dir = env_dir,
      env_path = is.null(run_env_name)
    )
  )

  # With `activate = TRUE`, the backend describes the invocation: the
  # executable, the arguments (possibly wrapped), the activation variables
  # and the working directory. An environment given by path has no name,
  # so the backend describes it from its directory. With
  # `activate = FALSE`, no backend function runs at all, so a broken
  # `activate.d` script cannot make the call fail.
  # `timeout` covers the activation and the command together (see
  # `run_internal_backend()`).
  started <- proc.time()[["elapsed"]]
  time_left <- function() {
    return(timeout - (proc.time()[["elapsed"]] - started))
  }
  if (isTRUE(activate)) {
    backend_run <- tryCatch(
      if (is.null(run_env_name)) {
        rlang::exec(
          backend_resolve_run_in_dir,
          resolved$backend,
          cmd = cmd,
          args = user_args,
          env_dir = env_dir,
          verbose = verbose_list$internal_verbose,
          base_env = base_env,
          !!!backend_resolve_args(
            resolved$backend,
            "backend_resolve_run_in_dir",
            timeout = timeout
          )
        )
      } else {
        rlang::exec(
          backend_resolve_run,
          resolved$backend,
          cmd = cmd,
          args = user_args,
          env_name = run_env_name,
          verbose = verbose_list$internal_verbose,
          base_env = base_env,
          !!!backend_resolve_args(
            resolved$backend,
            "backend_resolve_run",
            timeout = timeout
          )
        )
      },
      error = function(cnd) cnd
    )
    if (isTRUE(time_left() <= 0)) {
      px_res <- rethrow_error_run(
        expr = activation_timeout_result(
          env_label,
          timeout = timeout,
          error_var = error_var
        ),
        fn = "run_bin"
      )
      return(invisible(new_condathis_result(
        status = px_res$status,
        stdout = captured_or_na(px_res$stdout, target = stdout),
        stderr = captured_or_na(px_res$stderr, target = stderr),
        timeout = TRUE,
        pid = NA_integer_,
        cmd = cmd_string,
        env_name = env_label
      )))
    }
    # The failure honors `error`: `"cancel"` aborts with the backend's error
    # as the parent of `condathis_run_bin_resolve_failed`, which names the
    # user's call; `"continue"` reports a failed result. Never fall back to
    # running unactivated: that runs the command in a different environment
    # than the caller requested.
    if (inherits(backend_run, "condition")) {
      if (isTRUE(error_var)) {
        abort_resolve_failure(
          backend_run,
          fn = "run_bin",
          cmd_name = cmd,
          env_label = env_label,
          backend_name = resolved$name,
          hint = c(
            `i` = "{.code activate = FALSE} runs the command without the activation of the backend."
          ),
          call = fn_env
        )
      }
      return(not_started(
        resolve_failure_stderr("activation", env_label, backend_run),
        env_label
      ))
    }
    # A contract error goes on unchanged under `"cancel"`: it already names
    # the backend, the environment and the user's call.
    contract_cnd <- tryCatch(
      {
        validate_resolve_run(
          backend_run,
          env_name = env_label,
          backend_name = resolved$name,
          call = fn_env
        )
        NULL
      },
      error = function(cnd) cnd
    )
    if (isFALSE(is.null(contract_cnd))) {
      if (isTRUE(error_var)) {
        rlang::cnd_signal(contract_cnd)
      }
      return(not_started(
        resolve_failure_stderr("activation", env_label, contract_cnd),
        env_label
      ))
    }
  } else {
    backend_run <- list(
      command = resolve_env_bin_path(env_dir, cmd) %||% cmd,
      args = user_args,
      env = NULL,
      dir = NULL
    )
  }

  activation_overlay <- if (isTRUE(length(backend_run[["env"]]) > 0L)) {
    backend_run[["env"]]
  }

  # The child's complete environment block, passed as a full `env =`
  # replacement: the block before activation, the activation overlay, and
  # the env bin dirs prepended to PATH.
  child_env <- apply_child_overlay(
    base_env,
    overlay = activation_overlay,
    path_prepend = env_bin_search_dirs(env_dir)
  )
  # A bare command is looked up on the child's PATH: the environment's
  # directories first, then the PATH of the activation. The session's PATH
  # could pick a same-named program from outside the environment.
  child_path_name <- match_env_name(names(child_env), "PATH")
  cmd_path <- resolve_run_bin_command(
    backend_run[["command"]],
    env_dir,
    path = if (isFALSE(is.na(child_path_name))) {
      unname(child_env[[child_path_name]])
    }
  )
  px_res <- rethrow_error_run(
    expr = {
      execute_command(
        command = cmd_path,
        # `NULL` means no arguments; `processx` takes only a character
        # vector.
        args = as.character(backend_run[["args"]]),
        wd = backend_run[["dir"]],
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
        timeout = if (isTRUE(is.finite(timeout))) {
          max(time_left(), 0.001)
        } else {
          Inf
        }
      )
    },
    fn = "run_bin"
  )

  result <- new_condathis_result(
    status = px_res$status,
    stdout = captured_or_na(px_res$stdout, target = stdout),
    stderr = captured_or_na(px_res$stderr, target = stderr),
    timeout = if (is.null(px_res$timeout)) FALSE else px_res$timeout,
    pid = if (is.null(px_res$pid)) NA_integer_ else px_res$pid,
    cmd = cmd_string,
    env_name = env_label
  )
  return(invisible(result))
}

#' The executable `run_bin()` starts
#'
#' A command that contains a directory part (an absolute or relative path)
#' is kept as it is. A bare command is looked up on `path`, which
#' `run_bin()` takes from the child's environment block: the environment's
#' directories come first, then the `PATH` of the activation
#' (`activate = TRUE`) or of the R session (`activate = FALSE`).
#' `condathis` resolves it itself because the operating system does not do
#' it the same way everywhere: `execvp()` on Linux and macOS searches the
#' child's `PATH`, but `processx` on Windows searches the `PATH` of the R
#' session.
#'
#' A hit is kept as found on Linux and macOS: resolving symbolic links
#' changes `argv[0]`, which multicall binaries (busybox) and tools that
#' dispatch on their own name depend on. On Windows, 8.3 short paths are
#' expanded. A command found nowhere becomes `<env_dir>/bin/<command>`,
#' which does not exist, so the start fails as "command not found"
#' (status 127). With `keep_bare = TRUE`, as for `run()` (see
#' `resolve_direct_run_command()`), it stays as it is instead.
#'
#' @param command Character string, the command to start.
#' @param env_dir Character string, the environment directory.
#' @param path Character string, the `PATH` to search, or `NULL`.
#' @param on_windows Logical. Whether to apply the Windows rule.
#' @param pathext Character string, the value of `PATHEXT`, for the
#'   Windows rule.
#' @param keep_bare Logical. Whether a command found nowhere is returned
#'   unchanged, rather than as a path under `env_dir`.
#'
#' @returns Character string, the path of the executable, or `command`.
#'
#' @keywords internal
#' @noRd
resolve_run_bin_command <- function(
  command,
  env_dir,
  path = Sys.getenv("PATH"),
  on_windows = is_windows(),
  pathext = Sys.getenv("PATHEXT", ".COM;.EXE;.BAT;.CMD"),
  keep_bare = FALSE
) {
  command <- as.character(command)
  # As `execvp()` and `CreateProcess()`: a name with a directory part is
  # never searched for on `PATH`.
  dir_separators <- if (isTRUE(on_windows)) "[/\\\\:]" else "/"
  if (isTRUE(grepl(dir_separators, command))) {
    return(command)
  }
  hit <- find_command_on_path(
    command,
    path = path,
    on_windows = on_windows,
    pathext = pathext
  )
  if (isFALSE(is.null(hit))) {
    if (isTRUE(on_windows)) {
      return(normalizePath(hit, mustWork = FALSE))
    }
    return(hit)
  }
  if (isTRUE(keep_bare)) {
    return(command)
  }
  return(as.character(fs::path(env_dir, "bin", command)))
}
