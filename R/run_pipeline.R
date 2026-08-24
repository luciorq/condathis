#' Run a pipeline of commands connected with pipes
#'
#' @description
#' Executes a sequence of commands where each command's standard output is
#' piped as standard input to the next command (like a Unix shell pipeline).
#' Data flows directly between child processes via kernel-level pipes, the
#' parent R process only sees the output of the final command.
#'
#' Each command in the pipeline can run in a **different** Conda environment.
#' Commands that do not specify an environment use the default `env_name`.
#'
#' @param cmds A list of command specifications. Each element is either:
#'   \itemize{
#'     \item A character vector: `c("cmd", "arg1", ...)`. Runs in the
#'       default `env_name`.
#'     \item A named list with `cmd` (character vector) and, optionally,
#'       `env_name` (character string) to specify a per-command environment,
#'       `method` (character string) to specify a per-command backend
#'       (see `method` below — only the `"micromamba"` backend can
#'       actually execute a command today, regardless of which backend
#'       owns its environment), `stderr` to override the top-level
#'       `stderr` target for this command, and `stdout` to override the
#'       top-level `stdout` target, only allowed on the **last** command,
#'       since every other command's standard output is always piped to
#'       the next command.
#'   }
#' @param stdout Standard output target for the **last** process.
#'   `"|"` (default) captures output in the result. Use a file path to
#'   redirect to a file, or `NULL` to discard. Can be overridden per-command
#'   for the last command only (see `cmds`).
#' @param stderr Standard error target for **all** processes.
#'   `"|"` (default) captures stderr per-process. Use a file path to
#'   redirect all stderr to a file, or `NULL` to discard. Can be overridden
#'   per-command (see `cmds`).
#' @param stdin Standard input source for the **first** process.
#'   `NULL` (default) discards input. Provide a file path to redirect file
#'   contents as stdin, or `"|"` to write `input` to the first process.
#' @param input Character or raw vector written to the first process's
#'   standard input when `stdin = "|"`. Defaults to `NULL`. Ignored (and
#'   must not be set) when `stdin` is not `"|"`.
#' @param binary Logical. Whether to capture every process's stderr, and the
#'   last process's stdout, as raw vectors instead of decoding them as UTF-8
#'   text. Defaults to `FALSE`. Applies to the whole pipeline; there is no
#'   per-command override.
#' @param error Character string controlling error behavior.
#'   Supported values are `"cancel"` and `"continue"`.
#'   Defaults to `"cancel"`.
#' @param env_name Character string with the default Conda environment name
#'   for commands that do not specify their own.
#'   Defaults to `"condathis-env"`.
#' @param method Character string naming the default backend for commands
#'   that do not specify their own `method` (see `cmds`). Defaults to
#'   `"auto"` (resolve automatically: each command's environment's own
#'   owning backend). `"micromamba"` is the only backend registered
#'   today — and the only one that can actually execute a command so far.
#'   `"native"` is a deprecated alias for `"micromamba"` (warns once per
#'   session).
#' @param supervise Logical. Whether each process should be supervised by
#'   the `processx` supervisor for crash-safe cleanup. Defaults to `TRUE`
#'   (unlike `run()`/`run_bin()`, which default to `FALSE`) since a pipeline
#'   manages multiple concurrently connected processes.
#' @param cleanup_tree Logical. Whether to clean up each process's child
#'   tree on crash/interrupt. Defaults to `TRUE`.
#' @param linux_pdeathsig Logical. On Linux, whether to send `SIGKILL` to
#'   each child process if the parent R process dies. Has no effect on
#'   other platforms. Defaults to `FALSE`.
#' @param timeout Numeric. Maximum number of seconds to let the whole
#'   pipeline run before every process in it is killed. Defaults to `Inf`
#'   (no limit, the previous behavior). Applies to the pipeline as a whole
#'   (a single shared deadline across every command), not per-command. On
#'   expiry, every still-running process is killed (`status = -9`, matching
#'   `processx::run()`'s own convention) and, gated by `error` exactly like
#'   a non-zero exit status, `error = "cancel"` aborts with class
#'   `condathis_pipeline_timeout_error` while `error = "continue"` returns
#'   normally with `result$timeout` (and each killed process's own
#'   `timeout`) set to `TRUE`.
#' @param activate Logical. Whether to resolve each command's environment
#'   through a real `micromamba run` activation (including package
#'   `activate.d` hook scripts), cached per
#'   `env_name`. Defaults to `TRUE`. Set to `FALSE` to use the original,
#'   faster hand-rolled activation (a fixed set of `CONDA_*`/`MAMBA_*`
#'   variables, no `activate.d` execution). The
#'   first pipeline call touching a given `env_name` with `activate = TRUE`
#'   pays for two extra subprocess spawns to resolve it; repeat calls for
#'   the same, unchanged environment hit the cache.
#'
#' @returns A `condathis_pipeline` S3 object with per-process results:
#'   \item{statuses}{Integer vector of exit statuses, one per command.}
#'   \item{processes}{List of per-process `condathis_result` objects (the
#'     same class `run()`/`run_bin()` return), each with `cmd`, `env_name`,
#'     `status`, `stdout` (`NA` for non-last processes), `stderr`, `pid`,
#'     and `timeout` (`TRUE` for whichever process(es) were still running
#'     when the pipeline's `timeout` expired, `FALSE` otherwise).
#'     `format()`/`print()` work directly on an individual `processes[[i]]`,
#'     not just on the whole pipeline result.}
#'   \item{timeout}{Logical. Whether the pipeline timed out.}
#'
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   # `ripgrep` (the `rg` binary) is used here instead of GNU `grep`: a
#'   # single package name that installs and runs the same way on every
#'   # platform `condathis` supports, unlike `grep`, which on Windows only
#'   # exists under the "m2-" (MSYS2) prefix on conda-forge.
#'   #
#'   # `samtools` (bioconda) has no Windows build on any channel, so this
#'   # specific example only runs on Linux/macOS regardless — there's no
#'   # portable substitute that still demonstrates a real bioinformatics
#'   # CLI operating on the packaged BAM file below.
#'   create_env("bioconda::samtools", env_name = "samtools-env")
#'   create_env("conda-forge::ripgrep", env_name = "ripgrep-env")
#'
#'   # Pipeline with per-command environments
#'   res <- run_pipeline(
#'     list(
#'       list(
#'         cmd = c(
#'           "samtools", "view", "-H",
#'           fs::path_package("condathis", "extdata", "example.bam")
#'         ),
#'         env_name = "samtools-env"
#'       ),
#'       list(
#'         cmd = c("rg", "@SQ"),
#'         env_name = "ripgrep-env"
#'       )
#'     )
#'   )
#'   print(res)
#' })
#' }
#'
#' @seealso
#' \code{\link{run}} for single-command execution,
#' \code{\link{run_bin}} for direct binary execution.
#'
#' @export
run_pipeline <- function(
  cmds,
  stdout = "|",
  stderr = "|",
  stdin = NULL,
  input = NULL,
  binary = FALSE,
  error = c("cancel", "continue"),
  env_name = "condathis-env",
  method = "auto",
  supervise = TRUE,
  cleanup_tree = TRUE,
  linux_pdeathsig = FALSE,
  activate = TRUE,
  timeout = Inf
) {
  error <- rlang::arg_match(error)
  error_var <- isTRUE(identical(error, "cancel"))

  validate_pipeline_args(input = input, stdin = stdin, binary = binary)
  pipeline_encoding <- if (isTRUE(binary)) "binary" else "utf-8"

  pipeline_deadline <- if (isTRUE(is.finite(timeout))) {
    proc.time()[["elapsed"]] + timeout
  } else {
    Inf
  }

  tmp_dir_path <- withr::local_tempdir(pattern = "condathis-tmp")
  withr::local_envvar(
    .new = get_clean_conda_envvars(tmp_dir = tmp_dir_path)
  )

  parsed <- parse_cmds_spec(
    cmds,
    default_env_name = env_name,
    default_method = method
  )
  n_cmds <- length(parsed)

  if (n_cmds < 2L) {
    cli::cli_abort(
      message = c(
        `x` = "{.field cmds} must contain at least 2 commands for a pipeline."
      ),
      class = "condathis_pipeline_too_few_commands"
    )
  }

  check_stdout_overrides(parsed, n_cmds = n_cmds)
  precreate_result <- precreate_envs(
    parsed,
    tmp_dir_path = tmp_dir_path,
    error_var = error_var
  )
  missing_envs <- precreate_result$missing_envs
  resolved_backends <- precreate_result$resolved_backends

  # `supervise = TRUE` (the default) hangs `run_pipeline()` indefinitely on
  # native Windows for any 2+ command pipeline — confirmed via a clean A/B
  # test on a real Windows machine: overriding to `FALSE` fixes it
  # instantly (well under 1s), switching back to `TRUE` reproduces the hang,
  # in the same R session. `processx::pipeline`'s own reference
  # implementation never enables `supervise` at all (every process gets
  # `process$new()`'s own `FALSE` default) and does not hang. A
  # `supervisor.exe` helper process was observed (via `tasklist`) to
  # outlive the piped child on Windows; it likely holds its own handle to
  # the piped stdout, which would explain the reader never seeing EOF even
  # after the writer process has already exited. Rather than dropping the
  # crash-safety guarantee `run_pipeline()` intentionally adds on every
  # platform (its whole reason for defaulting to `TRUE`, unlike `run()`/
  # `run_bin()`), only Windows is forced to `FALSE` here.
  effective_supervise <- if (isTRUE(is_windows())) {
    FALSE
  } else {
    supervise
  }

  spawned_all <- run_pipeline_spawn_all(
    n_cmds = n_cmds,
    parsed = parsed,
    missing_envs = missing_envs,
    resolved_backends = resolved_backends,
    stdin = stdin,
    stdout = stdout,
    stderr = stderr,
    activate = activate,
    tmp_dir_path = tmp_dir_path,
    effective_supervise = effective_supervise,
    cleanup_tree = cleanup_tree,
    linux_pdeathsig = linux_pdeathsig,
    pipeline_encoding = pipeline_encoding
  )
  procs <- spawned_all$procs
  spawn_failures <- spawned_all$spawn_failures

  # Write `input` to the first process's stdin while draining *its* stderr
  # (never its stdout — that's piped straight into the second command, not
  # captured by R) concurrently, via pump_process_io(). Writing once and
  # closing immediately, as this used to do, silently truncates `input`
  # larger than the OS pipe buffer — confirmed empirically, not just
  # reasoned about (see pump_process_io()) — and not draining stderr while
  # writing risks the same deadlock class pump_process_io() is built to
  # avoid, one level up. This fully drains the first process's stderr to
  # EOF as a side effect, so the main loop below reuses this result for
  # process 1 instead of draining it a second time.
  first_proc_streams <- NULL
  if (identical(stdin, "|") && !is.null(procs[[1L]])) {
    first_proc_streams <- pump_process_io(
      procs[[1L]],
      input = input,
      want_stdout = FALSE,
      want_stderr = TRUE,
      binary = binary,
      deadline = pipeline_deadline
    )
  }

  drained_all <- run_pipeline_drain_all(
    n_cmds = n_cmds,
    parsed = parsed,
    procs = procs,
    spawn_failures = spawn_failures,
    first_proc_streams = first_proc_streams,
    binary = binary,
    pipeline_deadline = pipeline_deadline
  )
  processes <- drained_all$processes
  all_statuses <- drained_all$all_statuses
  timeout_flag <- drained_all$timeout_flag
  any_failed <- drained_all$any_failed

  if (isTRUE(error_var) && isTRUE(timeout_flag)) {
    abort_pipeline_timeout(processes, timeout)
  }

  if (isTRUE(error_var) && isTRUE(any_failed)) {
    abort_pipeline_status_error(all_statuses, processes, procs)
  }

  result <- new_condathis_pipeline(
    statuses = all_statuses,
    processes = processes,
    timeout = timeout_flag
  )

  return(invisible(result))
}

#' Validate `run_pipeline()`'s top-level `input`/`binary` arguments
#'
#' @keywords internal
#' @noRd
validate_pipeline_args <- function(input, stdin, binary) {
  if (!is.null(input) && !identical(stdin, "|")) {
    cli::cli_abort(
      message = c(
        `x` = "{.field input} can only be used when {.field stdin} is {.val {\"|\"}}."
      ),
      class = "condathis_pipeline_invalid_input"
    )
  }
  if (isFALSE(rlang::is_bool(binary))) {
    cli::cli_abort(
      message = c(
        `x` = "{.field binary} needs to be a single {.cls logical} value."
      ),
      class = "condathis_pipeline_invalid_binary_arg"
    )
  }
  return(invisible(NULL))
}

#' Resolve one pipeline stage's stdin/stdout wiring
#'
#' `conn_create_proc_pipepair()`, not `conn_create_pipepair()`, is the
#' constructor documented for wiring two child processes together
#' (`?processx::processx_connections`): its ends are synchronous/
#' blocking, which is "required for child-process stdin/stdout on
#' Windows". `conn_create_pipepair()`'s ends are non-blocking, meant for
#' R-side reading/writing (e.g. this package's own `pump_process_io()`,
#' used for `run()`/`run_bin()`'s `stdin = "|"` handling) — using it here
#' instead is what caused `run_pipeline()` to hang indefinitely on
#' Windows for any 2+ command pipeline. Confirmed by comparing against
#' `processx::pipeline`'s own `initialize()` method, which uses
#' `conn_create_proc_pipepair()` and is documented to work on Windows.
#'
#' @returns A list with `next_pipe` (the pipe pair for this stage's
#'   stdout, or `NULL` for the last stage), `stdin_i`, and `stdout_i`.
#'
#' @keywords internal
#' @noRd
resolve_pipeline_stdio <- function(
  i,
  n_cmds,
  cmd_stdout_override,
  stdin,
  stdout,
  prev_read
) {
  next_pipe <- if (i < n_cmds) processx::conn_create_proc_pipepair() else NULL
  stdin_i <- if (i == 1L) stdin else prev_read
  stdout_i <- if (i == n_cmds) {
    cmd_stdout_override %||% stdout
  } else {
    next_pipe[[1L]]
  }
  return(list(next_pipe = next_pipe, stdin_i = stdin_i, stdout_i = stdout_i))
}

#' Spawn every pipeline stage's process, wiring their stdio pipes together
#'
#' @returns A list with `procs` (per-stage `processx::process` objects, or
#'   `NULL` for stages that failed to spawn) and `spawn_failures` (per-stage
#'   `list(status, stderr)`, or `NULL` for stages that spawned fine).
#'
#' @keywords internal
#' @noRd
run_pipeline_spawn_all <- function(
  n_cmds,
  parsed,
  missing_envs,
  resolved_backends,
  stdin,
  stdout,
  stderr,
  activate,
  tmp_dir_path,
  effective_supervise,
  cleanup_tree,
  linux_pdeathsig,
  pipeline_encoding
) {
  procs <- vector("list", n_cmds)
  spawn_failures <- vector("list", n_cmds)
  prev_read <- NULL

  for (i in seq_len(n_cmds)) {
    cmd_vec <- parsed[[i]]$cmd
    env_name_i <- parsed[[i]]$env_name

    stdio <- resolve_pipeline_stdio(
      i = i,
      n_cmds = n_cmds,
      cmd_stdout_override = parsed[[i]]$stdout,
      stdin = stdin,
      stdout = stdout,
      prev_read = prev_read
    )
    next_pipe <- stdio$next_pipe
    stdin_i <- stdio$stdin_i
    stdout_i <- stdio$stdout_i

    if (env_name_i %in% names(missing_envs)) {
      spawn_failures[[i]] <- list(
        status = 127L,
        stderr = missing_envs[[env_name_i]]
      )
    } else {
      spawned <- spawn_pipeline_process(
        cmd_vec = cmd_vec,
        env_name_i = env_name_i,
        resolved_backend = resolved_backends[[env_name_i]]$backend,
        stdin_i = stdin_i,
        stdout_i = stdout_i,
        stderr_i = parsed[[i]]$stderr %||% stderr,
        is_last = identical(i, n_cmds),
        activate = activate,
        tmp_dir_path = tmp_dir_path,
        effective_supervise = effective_supervise,
        cleanup_tree = cleanup_tree,
        linux_pdeathsig = linux_pdeathsig,
        pipeline_encoding = pipeline_encoding
      )
      if (isFALSE(is.null(spawned$failure))) {
        spawn_failures[[i]] <- spawned$failure
      } else {
        procs[[i]] <- spawned$proc
      }
    }

    # Close the parent's copies of this stage's pipe ends as soon as
    # they've been handed to a process (or would have been, had spawning
    # not failed) — never defer closing until every process in the
    # pipeline has spawned. A write end left open in the parent (even
    # though the child holds its own copy) keeps the read end from ever
    # seeing EOF once the child exits, which is the same deadlock class
    # `pump_process_io()` avoids one level down, just at the OS-handle
    # level instead of the R-read level. Mirrors `processx::pipeline`'s
    # own `initialize()`.
    if (!is.null(next_pipe)) {
      close(next_pipe[[1L]])
    }
    if (i > 1L) {
      close(prev_read)
    }
    prev_read <- if (!is.null(next_pipe)) next_pipe[[2L]] else NULL
  }

  return(list(procs = procs, spawn_failures = spawn_failures))
}

#' Drain every pipeline stage and assemble their per-process results
#'
#' @returns A list with `processes` (per-stage `condathis_result` objects),
#'   `all_statuses` (integer vector), `timeout_flag` (logical, whether any
#'   stage timed out), and `any_failed` (logical, whether any stage exited
#'   non-zero).
#'
#' @keywords internal
#' @noRd
run_pipeline_drain_all <- function(
  n_cmds,
  parsed,
  procs,
  spawn_failures,
  first_proc_streams,
  binary,
  pipeline_deadline
) {
  timeout_flag <- FALSE
  processes <- vector("list", n_cmds)
  all_statuses <- integer(n_cmds)
  any_failed <- FALSE

  for (i in seq_len(n_cmds)) {
    cmd_vec <- parsed[[i]]$cmd
    env_name_i <- parsed[[i]]$env_name
    cmd_string <- paste(shQuote(cmd_vec), collapse = " ")

    drained <- drain_pipeline_stage(
      proc_i = procs[[i]],
      spawn_failure = spawn_failures[[i]],
      is_last = identical(i, n_cmds),
      is_first = identical(i, 1L),
      first_proc_streams = first_proc_streams,
      binary = binary,
      pipeline_deadline = pipeline_deadline
    )

    if (isTRUE(drained$timeout)) {
      timeout_flag <- TRUE
    }

    all_statuses[i] <- drained$status
    if (isTRUE(drained$status != 0L) && !is.na(drained$status)) {
      any_failed <- TRUE
    }

    processes[[i]] <- new_condathis_result(
      status = drained$status,
      stdout = drained$stdout,
      stderr = drained$stderr,
      timeout = drained$timeout,
      pid = drained$pid,
      cmd = cmd_string,
      env_name = env_name_i
    )
  }

  return(list(
    processes = processes,
    all_statuses = all_statuses,
    timeout_flag = timeout_flag,
    any_failed = any_failed
  ))
}

#' Spawn a single pipeline stage's process
#'
#' Resolves the stage's activation environment and executable path, then
#' spawns it via `processx::process$new()`, translating a spawn-time error
#' (missing binary, etc.) into the same `list(status = 127L, stderr = ...)`
#' shape `run_pipeline()`'s missing-environment branch already uses —
#' `run_pipeline()` doesn't need to know *why* a stage never produced a
#' running process, only that it didn't.
#'
#' @param is_last Logical. Whether this is the last command in the
#'   pipeline — controls `poll_connection` (`NULL` for the last stage,
#'   `FALSE` for every other stage, matching `processx::pipeline`'s own
#'   `initialize()`).
#'
#' @returns A list with `proc` (the spawned `processx::process` object, or
#'   `NULL` on failure) and `failure` (`NULL` on success, otherwise
#'   `list(status, stderr)`).
#'
#' @keywords internal
#' @noRd
spawn_pipeline_process <- function(
  cmd_vec,
  env_name_i,
  resolved_backend,
  stdin_i,
  stdout_i,
  stderr_i,
  is_last,
  activate,
  tmp_dir_path,
  effective_supervise,
  cleanup_tree,
  linux_pdeathsig,
  pipeline_encoding
) {
  env_dir <- backend_get_env_dir(resolved_backend, env_name = env_name_i)

  # Both the executable path and the activation variables come from the
  # backend's own `backend_resolve_run()`, so every registered backend works
  # here rather than only `"micromamba"`. Not a behaviour change for
  # `"micromamba"`: `micromamba_backend_resolve_run()` computes exactly what
  # this function used to inline — `resolve_env_bin_path()` falling back to
  # the bare name, plus `get_micromamba_activation_envvars()`.
  #
  # Resolving the executable (rather than passing a bare name) matters
  # because the OS resolves a bare command against the *calling* R process's
  # own ambient PATH, not against `env` below (Windows' `CreateProcess`,
  # like POSIX `execvp()`, locates the executable image before the child's
  # own environment block takes effect) — so without it a command only
  # "works" by coincidence, if something of the same name happens to be
  # reachable outside `env_name_i` entirely (confirmed on Windows: a
  # 3-command pipeline using `rev` failed outright, since no `rev` exists
  # anywhere on the ambient PATH, even though the target environment has its
  # own). The backend falls back to the bare name when the command isn't
  # found inside the prefix, preserving the "command not found" behavior
  # below.
  backend_run <- backend_resolve_run(
    resolved_backend,
    cmd = cmd_vec[1L],
    args = cmd_vec[-1L],
    env_name = env_name_i,
    verbose = "silent"
  )
  validate_resolve_run(backend_run, env_name = env_name_i)
  resolved_cmd <- backend_run$command

  # `activate = FALSE` keeps the hand-rolled, activation-script-free
  # variables: that path is deliberately backend-independent (built from
  # `env_dir` alone), so it stays as-is rather than going through the
  # backend.
  activation_envvars <- if (isTRUE(activate)) {
    backend_run$env
  } else {
    get_activation_envvars(
      env_name = env_name_i,
      env_dir = env_dir,
      tmp_dir = tmp_dir_path
    )
  }

  spawn_result <- tryCatch(
    expr = {
      processx::process$new(
        command = resolved_cmd,
        args = backend_run$args,
        stdin = stdin_i,
        stdout = stdout_i,
        stderr = stderr_i,
        poll_connection = if (isFALSE(is_last)) FALSE else NULL,
        env = c("current", activation_envvars),
        supervise = effective_supervise,
        cleanup_tree = cleanup_tree,
        linux_pdeathsig = linux_pdeathsig,
        encoding = pipeline_encoding
      )
    },
    system_command_status_error = function(cnd) cnd,
    rlib_error_3_0 = function(cnd) cnd,
    c_error = function(cnd) cnd
  )

  if (inherits(spawn_result, "condition")) {
    stderr_msg <- if (
      isTRUE(stringr::str_detect(
        conditionMessage(spawn_result),
        "Native call to"
      ))
    ) {
      sprintf("System command '%s' not found\n", cmd_vec[1L])
    } else {
      "Unknown Error\n"
    }
    return(list(
      proc = NULL,
      failure = list(status = 127L, stderr = stderr_msg)
    ))
  }
  return(list(proc = spawn_result, failure = NULL))
}

#' Drain a single pipeline stage and collect its result
#'
#' Handles both the "never spawned" case (a `spawn_pipeline_process()`
#' failure, or a missing-environment placeholder) and the real-process
#' case: draining stdout/stderr *before* `wait()`ing on it, killing it if
#' the shared pipeline deadline was hit, and reading back its final exit
#' status/pid.
#'
#' @param proc_i The stage's `processx::process` object, or `NULL` if it
#'   never spawned.
#' @param spawn_failure `NULL`, or `list(status, stderr)` from a missing
#'   environment / `spawn_pipeline_process()` failure.
#' @param is_last Logical. Whether this is the pipeline's last command —
#'   only the last command's stdout is captured by R (every other
#'   command's stdout is piped straight into the next command).
#' @param is_first Logical. Whether this is the pipeline's first command —
#'   its stderr may already have been drained by the caller (interleaved
#'   with writing `input` to its stdin) and handed back as
#'   `first_proc_streams`, in which case it must not be drained again.
#' @param first_proc_streams The first stage's already-drained streams (see
#'   `is_first`), or `NULL` if there's nothing to reuse.
#' @param binary Logical. Whether streams are raw bytes or UTF-8 text.
#' @param pipeline_deadline Passed through to `pump_process_io()`.
#'
#' @returns A list with `status`, `stdout`, `stderr`, `pid`, `timeout`.
#'
#' @keywords internal
#' @noRd
drain_pipeline_stage <- function(
  proc_i,
  spawn_failure,
  is_last,
  is_first,
  first_proc_streams,
  binary,
  pipeline_deadline
) {
  if (isFALSE(is.null(spawn_failure))) {
    return(list(
      status = spawn_failure$status,
      stdout = NA_character_,
      stderr = spawn_failure$stderr,
      pid = NA_integer_,
      timeout = FALSE
    ))
  }

  empty_stream <- if (isTRUE(binary)) raw(0L) else ""

  # Drain this process's own stream(s) *before* wait()ing on it — see
  # pump_process_io() for why: wait()-then-read (or draining stdout and
  # stderr sequentially, for the last command which has both piped)
  # deadlocks once output exceeds the OS pipe buffer. Each process's
  # captured streams are independent of every other process's, so
  # draining/waiting one at a time (rather than across the whole
  # pipeline at once) is safe: the inter-process stdout-to-stdin
  # chaining is plain OS-level piping, with no R-side buffering.
  # Process 1's stderr was already fully drained above (interleaved
  # with writing it `input`), reuse that instead of draining it again.
  # Every stage shares the same absolute `pipeline_deadline`: once one
  # stage times out, later stages' own check reads as already elapsed
  # too — but `pump_process_io()` still does one last non-blocking
  # drain before reporting it, so already-buffered output (e.g. this
  # stage received before an upstream stage was killed) isn't lost.
  streams <- if (isTRUE(is_first) && isFALSE(is.null(first_proc_streams))) {
    first_proc_streams
  } else {
    pump_process_io(
      proc_i,
      want_stdout = is_last,
      want_stderr = TRUE,
      binary = binary,
      deadline = pipeline_deadline
    )
  }

  p_timeout <- isTRUE(streams$timeout)
  # Kill only *this* stage, and only after having drained it above —
  # `kill()` invalidates a process's own connection immediately
  # (confirmed empirically), discarding anything still unread, so
  # draining downstream stages before reaching this point (rather
  # than killing every process up front) is what lets them keep
  # whatever they'd already produced. Killing this one process also
  # closes its stdout pipe, so the next stage (reading from it) sees
  # EOF and can finish draining normally instead of blocking further.
  if (isTRUE(p_timeout) && proc_i$is_alive()) {
    proc_i$kill()
  }
  proc_i$wait()

  # Normalized to a fixed sentinel on timeout, same as run()/run_bin()
  # (see run_process_with_input.R) — a killed process's own reported
  # exit status is an OS/`processx` detail that differs across
  # platforms (`-9` on Linux/macOS, `2` on Windows for the identical
  # `kill()` call), not something to trust as-is.
  if (isTRUE(p_timeout)) {
    p_status <- -9L
  } else {
    p_status <- proc_i$get_exit_status()
    if (is.null(p_status)) {
      p_status <- NA_integer_
    }
  }

  return(list(
    status = p_status,
    stdout = streams$stdout %||% NA_character_,
    stderr = streams$stderr %||% empty_stream,
    pid = proc_i$get_pid(),
    timeout = p_timeout
  ))
}

#' Abort a pipeline that timed out (`error = "cancel"` only)
#'
#' @keywords internal
#' @noRd
abort_pipeline_timeout <- function(processes, timeout) {
  n_killed <- sum(
    vapply(processes, function(p) isTRUE(p$timeout), logical(1L))
  )
  cli::cli_abort(
    message = c(
      `x` = "Pipeline timed out after {timeout} seconds",
      `!` = "Killed {n_killed} still-running command(s)."
    ),
    class = "condathis_pipeline_timeout_error"
  )
}

#' Build the "Failed commands:" detail lines for the pipeline status-error
#' abort message
#'
#' @keywords internal
#' @noRd
build_pipeline_failed_lines <- function(processes) {
  failed_lines <- character()
  for (i in seq_along(processes)) {
    p <- processes[[i]]
    if (identical(p$status, 0L) || is.na(p$status)) {
      next
    }
    failed_lines <- c(
      failed_lines,
      sprintf(
        "  [%d] %s (env: %s, status: %d)",
        i,
        escape_cli_braces(p$cmd),
        escape_cli_braces(p$env_name),
        p$status
      ),
      format_pipeline_failed_stderr_lines(p)
    )
  }
  return(failed_lines)
}

#' Format one failed pipeline process's stderr as indented detail lines
#'
#' @keywords internal
#' @noRd
format_pipeline_failed_stderr_lines <- function(p) {
  if (isTRUE(is.raw(p$stderr))) {
    if (length(p$stderr) > 0L) {
      return(sprintf("       <binary data, %d bytes>", length(p$stderr)))
    }
    return(character())
  }
  if (isFALSE(nzchar(p$stderr))) {
    return(character())
  }
  stderr_lines <- strsplit(p$stderr, "\n")[[1]]
  stderr_lines <- stderr_lines[nzchar(stderr_lines)]
  return(sprintf(
    "       %s",
    escape_cli_braces(utils::head(stderr_lines, 10L))
  ))
}

#' Abort a pipeline that had one or more non-zero-exit commands
#' (`error = "cancel"` only)
#'
#' @keywords internal
#' @noRd
abort_pipeline_status_error <- function(all_statuses, processes, procs) {
  kill_processes(procs)
  failed_lines <- build_pipeline_failed_lines(processes)
  cli::cli_abort(
    message = c(
      `x` = "Pipeline failed {.value {sum(all_statuses != 0L, na.rm = TRUE)}} command(s) exited with non-zero status",
      `!` = "Failed commands:",
      failed_lines
    ),
    class = "condathis_pipeline_status_error"
  )
}

parse_cmds_spec <- function(cmds, default_env_name, default_method = "auto") {
  if (!rlang::is_list(cmds) || length(cmds) == 0L) {
    cli::cli_abort(
      message = c(`x` = "{.field cmds} must be a non-empty list."),
      class = "condathis_pipeline_invalid_cmds"
    )
  }

  parsed <- vector("list", length(cmds))
  for (i in seq_along(cmds)) {
    spec <- cmds[[i]]
    if (rlang::is_character(spec)) {
      if (length(spec) == 0L) {
        cli::cli_abort(
          message = c(`x` = "Command {i} is an empty character vector."),
          class = "condathis_pipeline_empty_cmd"
        )
      }
      cmd_vec <- spec
      env_name_i <- default_env_name
      method_i <- default_method
      stdout_i <- NULL
      stderr_i <- NULL
    } else if (rlang::is_list(spec)) {
      if (
        is.null(spec$cmd) ||
          !rlang::is_character(spec$cmd) ||
          length(spec$cmd) == 0L
      ) {
        cli::cli_abort(
          message = c(
            `x` = "Command {i} must have a non-empty {.field cmd} vector."
          ),
          class = "condathis_pipeline_invalid_cmd_spec"
        )
      }
      cmd_vec <- spec$cmd
      env_name_i <- spec$env_name %||% default_env_name
      method_i <- spec$method %||% default_method
      stdout_i <- spec$stdout %||% NULL
      stderr_i <- spec$stderr %||% NULL
    } else {
      cli::cli_abort(
        message = c(
          `x` = "Command {i} must be a character vector or a named list."
        ),
        class = "condathis_pipeline_invalid_cmd_type"
      )
    }

    parsed[[i]] <- list(
      cmd = cmd_vec,
      env_name = env_name_i,
      method = method_i,
      stdout = stdout_i,
      stderr = stderr_i
    )
  }

  return(parsed)
}

check_stdout_overrides <- function(parsed, n_cmds) {
  if (n_cmds < 2L) {
    return(invisible(NULL))
  }
  for (i in seq_len(n_cmds - 1L)) {
    if (!is.null(parsed[[i]]$stdout)) {
      cli::cli_abort(
        message = c(
          `x` = "Command {i} cannot override {.field stdout}.",
          `!` = paste(
            "Only the last command's {.field stdout} can be overridden;",
            "every other command's standard output is always piped to the",
            "next command."
          )
        ),
        class = "condathis_pipeline_invalid_stdout_override"
      )
    }
  }
  return(invisible(NULL))
}

#' Resolve the single `method` to use for every command sharing one
#' `env_name`
#'
#' All commands targeting the same `env_name` must resolve to the same
#' backend — it's one environment, not a coincidence of name — so every
#' command's `method` is considered, not just the first one found for that
#' `env_name`. `"auto"` (the no-preference default, whether inherited from
#' `run_pipeline()`'s own top-level `method` or a command's own unset
#' override) never conflicts with an explicit choice; two different
#' explicit choices for the same `env_name` do.
#'
#' @param env_name Character string.
#' @param parsed The full parsed command list from `parse_cmds_spec()`.
#'
#' @returns Character string: `"auto"`, or the single explicit method every
#'   command referencing `env_name` agrees on.
#'
#' @keywords internal
#' @noRd
resolve_pipeline_env_method <- function(env_name, parsed) {
  methods_i <- vapply(
    Filter(function(p) identical(p$env_name, env_name), parsed),
    `[[`,
    character(1L),
    "method"
  )
  explicit_methods <- unique(methods_i[methods_i != "auto"])
  if (identical(length(explicit_methods), 0L)) {
    return("auto")
  }
  if (identical(length(explicit_methods), 1L)) {
    return(explicit_methods)
  }
  cli::cli_abort(
    message = c(
      `x` = "Commands targeting environment {.field {env_name}} request conflicting backends: {.field {explicit_methods}}.",
      `!` = "Use the same {.arg method} for every command sharing an {.arg env_name}."
    ),
    class = "condathis_pipeline_conflicting_method"
  )
}

#' Resolve each unique environment's backend; auto-create the default
#' environment, and report missing/unsupported-backend custom envs
#'
#' Auto-creates the default `"condathis-env"` when missing, regardless of
#' `error_var`. For any other missing environment: aborts immediately when
#' `error_var` is `TRUE` (`error = "cancel"`), matching the previous
#' fail-fast behavior; otherwise returns the missing environment names so
#' the caller can treat commands targeting them as failed-to-spawn, in line
#' with `error = "continue"` semantics. An environment that exists under a
#' backend other than `"micromamba"` is treated the same way: `run_pipeline()`
#' can't actually execute anything through a non-`"micromamba"` backend yet
#' (see `R/run_pipeline.R`'s main spawn loop), so it's reported the same
#' as "missing" under `error = "continue"`, and aborts under
#' `error = "cancel"`. An environment that exists under more than one
#' registered backend simultaneously — `resolve_backend()`'s own
#' `condathis_backend_ambiguous_env` abort, which (unlike a single-owner
#' mismatch) always fires regardless of the `mutating` argument — gets the
#' same `error_var`-gated treatment here rather than escaping uncaught:
#' re-thrown as-is under `error = "cancel"`, degraded to "missing" under
#' `error = "continue"`.
#'
#' @returns A list with `missing_envs` (a named character vector under
#'   `error = "continue"`: names are the affected `env_name`s, values are
#'   the specific stderr message to report for each — genuinely absent,
#'   ambiguous ownership, and existing-under-an-unsupported-backend are
#'   three different situations and get three different messages, not a
#'   single generic "does not exist") and `resolved_backends` (a named
#'   list, one already-resolved backend per unique `env_name`, so the main
#'   spawn loop never triggers a second, independent `resolve_backend()`
#'   call).
#'
#' @keywords internal
#' @noRd
precreate_envs <- function(parsed, tmp_dir_path, error_var) {
  env_names <- unique(vapply(parsed, `[[`, character(1L), "env_name"))
  methods_by_env <- vapply(
    env_names,
    function(nm) resolve_pipeline_env_method(nm, parsed),
    character(1L)
  )
  names(methods_by_env) <- env_names

  missing_envs <- character()
  resolved_backends <- list()
  for (env_name_i in env_names) {
    resolved <- tryCatch(
      resolve_backend(
        env_name = env_name_i,
        method = methods_by_env[[env_name_i]],
        mutating = FALSE
      ),
      condathis_backend_ambiguous_env = function(cnd) {
        if (isTRUE(error_var)) {
          stop(cnd)
        }
        return(NULL)
      }
    )
    if (is.null(resolved)) {
      missing_envs[[env_name_i]] <- sprintf(
        "Environment '%s' exists under more than one backend; specify an explicit method to disambiguate.\n",
        env_name_i
      )
      next
    }

    if (
      isFALSE(backend_has_env(resolved$backend, env_name_i, verbose = FALSE))
    ) {
      if (identical(env_name_i, "condathis-env")) {
        create_base_env(verbose = FALSE)
        resolved <- resolve_backend(
          env_name = env_name_i,
          method = methods_by_env[[env_name_i]],
          mutating = FALSE
        )
      } else if (isTRUE(error_var)) {
        cli::cli_abort(
          message = c(
            `x` = "Environment {.field {env_name_i}} does not exist.",
            `!` = "Create it with {.fn create_env} first."
          ),
          class = "condathis_pipeline_env_not_found"
        )
      } else {
        missing_envs[[env_name_i]] <- sprintf(
          "Conda environment '%s' does not exist.\n",
          env_name_i
        )
      }
    }

    resolved_backends[[env_name_i]] <- resolved
  }
  return(list(
    missing_envs = missing_envs,
    resolved_backends = resolved_backends
  ))
}

#' Escape curly braces so text can be safely interpolated in a cli message
#'
#' `cli::cli_abort()` treats `{` / `}` in every element of `message` as
#' glue-style interpolation syntax. Captured stderr, command strings, and
#' environment names are arbitrary text and must be escaped before being
#' embedded in an abort message.
#'
#' @keywords internal
#' @noRd
escape_cli_braces <- function(x) {
  stringr::str_replace_all(
    stringr::str_replace_all(x, stringr::fixed("{"), stringr::fixed("{{")),
    stringr::fixed("}"),
    stringr::fixed("}}")
  )
}

kill_processes <- function(procs) {
  for (proc_i in procs) {
    if (!is.null(proc_i) && proc_i$is_alive()) {
      tryCatch(proc_i$kill(), error = function(e) NULL)
    }
  }
}
