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
#'       (see `method` below - only the `"micromamba"` backend can
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
#'   redirect all stderr to a file - each command's stderr is written to
#'   the file grouped in command order once the pipeline finishes, so
#'   commands never overwrite each other's output - or `NULL` to discard.
#'   Can be overridden per-command (see `cmds`).
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
#'   today - and the only one that can actually execute a command so far.
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
#'   # specific example only runs on Linux/macOS regardless - there's no
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

  # No session-wide environment scope here: each stage's child environment
  # is constructed explicitly at spawn time via `build_child_env()` (see
  # `spawn_pipeline_process()`), so the calling R session's environment is
  # never touched.
  tmp_dir_path <- withr::local_tempdir(pattern = "condathis-tmp")

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
  # native Windows for any 2+ command pipeline - confirmed via a clean A/B
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

  # Reap the pipeline on *any* exit from here on: an unexpected error in
  # the pump or settle machinery must not leave stages running until
  # garbage collection. On normal returns (and the deliberate
  # error = "cancel" aborts) every stage has already exited and been
  # wait()ed on, so this is a no-op there - kill_processes() only touches
  # processes still alive.
  on.exit(kill_processes(procs), add = TRUE)

  # Drain every stage's R-side streams (each stage's stderr, the last
  # stage's stdout) *concurrently*, interleaved with writing `input` to
  # the first stage's stdin - see pump_pipeline_io() for why no sequential
  # per-stage draining order can avoid deadlocking once the data flowing
  # through the pipeline exceeds the OS pipe buffers (reproduced
  # empirically with `seq 1 500000 | cat`).
  pumped <- pump_pipeline_io(
    procs = procs,
    input = if (identical(stdin, "|")) input else NULL,
    binary = binary,
    deadline = pipeline_deadline
  )

  drained_all <- run_pipeline_drain_all(
    n_cmds = n_cmds,
    parsed = parsed,
    procs = procs,
    spawn_failures = spawn_failures,
    pumped = pumped,
    binary = binary,
    pipeline_deadline = pipeline_deadline
  )
  processes <- drained_all$processes
  all_statuses <- drained_all$all_statuses
  timeout_flag <- drained_all$timeout_flag
  any_failed <- drained_all$any_failed

  # Before the aborts below, so a redirected-to-file stderr holds its
  # diagnostics exactly when a stage failed or timed out.
  collect_pipeline_stderr_files(spawned_all$stderr_redirects)

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
#' used for `run()`/`run_bin()`'s `stdin = "|"` handling) - using it here
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
  stderr_redirects <- vector("list", n_cmds)
  prev_read <- NULL

  # If anything throws mid-loop (an unexpected spawn error class, a pipe
  # creation failure, ...), the stages spawned so far must not be left
  # running until garbage collection happens to reap them.
  spawn_all_done <- FALSE
  on.exit(
    if (isFALSE(spawn_all_done)) {
      kill_processes(procs)
    },
    add = TRUE
  )

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

    # A user-supplied stderr *file* target cannot be handed to every
    # stage directly: each `process$new()` opens (and truncates) the path
    # independently, so stages clobber each other's output - the second
    # spawn wipes what the first already wrote, and concurrent stages
    # write from a shared offset 0 (confirmed empirically). Each stage
    # writes to its own temp file instead; the user's file is assembled
    # once, in command order, after the pipeline settles (see
    # collect_pipeline_stderr_files()).
    stderr_target <- parsed[[i]]$stderr %||% stderr
    stderr_i <- stderr_target
    if (isTRUE(is_stderr_file_target(stderr_target))) {
      stderr_i <- as.character(
        fs::path(tmp_dir_path, sprintf("stage-%d-stderr.log", i))
      )
      stderr_redirects[[i]] <- list(
        user_path = as.character(stderr_target),
        tmp_path = stderr_i
      )
    }

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
        stderr_i = stderr_i,
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
    # not failed) - never defer closing until every process in the
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

  spawn_all_done <- TRUE
  return(list(
    procs = procs,
    spawn_failures = spawn_failures,
    stderr_redirects = stderr_redirects
  ))
}

#' Is a pipeline stderr target a file path?
#'
#' `processx`'s non-file stderr targets are `NULL` (discard), `"|"`
#' (capture), `""` (inherit the console), and `"2>&1"`; anything else that
#' is a single string is a file path.
#'
#' @keywords internal
#' @noRd
is_stderr_file_target <- function(target) {
  isTRUE(rlang::is_character(target)) &&
    isTRUE(identical(length(target), 1L)) &&
    isFALSE(target %in% c("|", "", "2>&1"))
}

#' Assemble user-facing stderr files from the per-stage temp files
#'
#' For every distinct user-supplied stderr path, concatenates (in command
#' order) the temp files of the stages redirected to it, writing the
#' user's file exactly once. Byte-level copy, so binary stderr streams
#' survive untouched. Runs before the `error = "cancel"` aborts, so the
#' file the user asked for holds its diagnostics precisely when a stage
#' failed - the moment it matters most.
#'
#' @param stderr_redirects Per-stage list of `list(user_path, tmp_path)`
#'   entries (or `NULL` for stages with a non-file stderr target).
#'
#' @keywords internal
#' @noRd
collect_pipeline_stderr_files <- function(stderr_redirects) {
  redirects <- Filter(Negate(is.null), stderr_redirects)
  if (identical(length(redirects), 0L)) {
    return(invisible(NULL))
  }
  user_paths <- unique(vapply(redirects, `[[`, character(1L), "user_path"))
  for (user_path in user_paths) {
    chunks <- lapply(redirects, function(redirect) {
      if (
        identical(redirect$user_path, user_path) &&
          isTRUE(fs::file_exists(redirect$tmp_path))
      ) {
        readBin(
          redirect$tmp_path,
          what = "raw",
          n = fs::file_size(redirect$tmp_path)
        )
      } else {
        raw(0L)
      }
    })
    writeBin(do.call(c, chunks), user_path)
  }
  return(invisible(NULL))
}

#' Settle every pipeline stage and assemble their per-process results
#'
#' Runs after `pump_pipeline_io()` has already drained every R-side
#' stream, so per stage this only has to enforce the shared deadline,
#' kill what is still running past it, and collect exit statuses.
#'
#' @param pumped The `pump_pipeline_io()` result: per-stage `stdout`/
#'   `stderr` stream lists plus the pipeline-wide `timeout` flag.
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
  pumped,
  binary,
  pipeline_deadline
) {
  timeout_flag <- isTRUE(pumped$timeout)
  processes <- vector("list", n_cmds)
  all_statuses <- integer(n_cmds)
  any_failed <- FALSE

  for (i in seq_len(n_cmds)) {
    cmd_vec <- parsed[[i]]$cmd
    env_name_i <- parsed[[i]]$env_name
    cmd_string <- paste(shQuote(cmd_vec), collapse = " ")

    settled <- settle_pipeline_stage(
      proc_i = procs[[i]],
      spawn_failure = spawn_failures[[i]],
      stage_stdout = pumped$stdout[[i]],
      stage_stderr = pumped$stderr[[i]],
      pump_timed_out = pumped$timeout,
      binary = binary,
      pipeline_deadline = pipeline_deadline
    )

    if (isTRUE(settled$timeout)) {
      timeout_flag <- TRUE
    }

    all_statuses[i] <- settled$status
    if (isTRUE(settled$status != 0L) && !is.na(settled$status)) {
      any_failed <- TRUE
    }

    processes[[i]] <- new_condathis_result(
      status = settled$status,
      stdout = settled$stdout,
      stderr = settled$stderr,
      timeout = settled$timeout,
      pid = settled$pid,
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
#' shape `run_pipeline()`'s missing-environment branch already uses -
#' `run_pipeline()` doesn't need to know *why* a stage never produced a
#' running process, only that it didn't.
#'
#' @param is_last Logical. Whether this is the last command in the
#'   pipeline - controls `poll_connection` (`NULL` for the last stage,
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
  # this function used to inline - `resolve_env_bin_path()` falling back to
  # the bare name, plus `get_micromamba_activation_envvars()`.
  #
  # Resolving the executable (rather than passing a bare name) matters
  # because the OS resolves a bare command against the *calling* R process's
  # own ambient PATH, not against `env` below (Windows' `CreateProcess`,
  # like POSIX `execvp()`, locates the executable image before the child's
  # own environment block takes effect) - so without it a command only
  # "works" by coincidence, if something of the same name happens to be
  # reachable outside `env_name_i` entirely (confirmed on Windows: a
  # 3-command pipeline using `rev` failed outright, since no `rev` exists
  # anywhere on the ambient PATH, even though the target environment has its
  # own). The backend falls back to the bare name when the command isn't
  # found inside the prefix, preserving the "command not found" behavior
  # below.
  # `activate = FALSE` must not touch `backend_resolve_run()` at all: the
  # micromamba implementation resolves the full activation environment
  # (two subprocess spawns on a cache miss, plus any `activate.d` hook
  # failure modes) before the flag could discard its result - so a user
  # who set `activate = FALSE` precisely to skip activation still paid
  # for it, and a failing activation hook aborted the whole pipeline
  # regardless of `error = "continue"`. The activation-free path resolves
  # the executable locally (same `resolve_env_bin_path()` fallback the
  # backend uses) and keeps the hand-rolled, hook-free variables, built
  # from `env_dir` alone.
  if (isTRUE(activate)) {
    # A failing backend resolution (e.g. a broken activate.d hook during
    # activation) is routed into the same spawn-failure channel as a
    # missing binary, so it honors `error = "continue"`/"cancel" like any
    # other per-stage failure instead of escaping and aborting the whole
    # pipeline unconditionally.
    backend_run <- tryCatch(
      {
        resolved_run <- backend_resolve_run(
          resolved_backend,
          cmd = cmd_vec[1L],
          args = cmd_vec[-1L],
          env_name = env_name_i,
          verbose = "silent"
        )
        validate_resolve_run(resolved_run, env_name = env_name_i)
        resolved_run
      },
      error = function(cnd) cnd
    )
    if (inherits(backend_run, "condition")) {
      return(list(
        proc = NULL,
        failure = list(
          status = 127L,
          stderr = paste0(
            "Failed to resolve command for environment '",
            env_name_i,
            "': ",
            conditionMessage(backend_run),
            "\n"
          )
        )
      ))
    }
    resolved_cmd <- backend_run$command
    stage_args <- backend_run$args
    activation_envvars <- backend_run$env
  } else {
    resolved_cmd <- resolve_env_bin_path(env_dir, cmd_vec[1L]) %||%
      cmd_vec[1L]
    stage_args <- cmd_vec[-1L]
    activation_envvars <- get_activation_envvars(
      env_name = env_name_i,
      env_dir = env_dir,
      tmp_dir = tmp_dir_path
    )
  }

  # Full explicit environment block for this stage (clean conda overlay +
  # activation overlay), never `c("current", ...)` - the calling session's
  # environment is not mutated by `run_pipeline()`, so inheriting it
  # directly would leak the caller's CONDA_*/MAMBA_* state into the stage.
  child_env <- build_child_env(
    tmp_dir = tmp_dir_path,
    overlay = activation_envvars
  )

  spawn_result <- tryCatch(
    expr = {
      processx::process$new(
        command = resolved_cmd,
        args = stage_args,
        stdin = stdin_i,
        stdout = stdout_i,
        stderr = stderr_i,
        poll_connection = if (isFALSE(is_last)) FALSE else NULL,
        env = child_env,
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

#' Settle a single pipeline stage and collect its result
#'
#' Handles both the "never spawned" case (a `spawn_pipeline_process()`
#' failure, or a missing-environment placeholder) and the real-process
#' case. Stream draining already happened pipeline-wide in
#' `pump_pipeline_io()`; this enforces the shared deadline (killing the
#' stage if still running past it), waits for exit, and reads back the
#' final status/pid.
#'
#' @param proc_i The stage's `processx::process` object, or `NULL` if it
#'   never spawned.
#' @param spawn_failure `NULL`, or `list(status, stderr)` from a missing
#'   environment / `spawn_pipeline_process()` failure.
#' @param stage_stdout,stage_stderr This stage's already-drained streams
#'   from `pump_pipeline_io()` (`NULL` when the stream was not piped to
#'   R).
#' @param pump_timed_out Logical. Whether `pump_pipeline_io()` hit the
#'   shared pipeline deadline.
#' @param binary Logical. Whether streams are raw bytes or UTF-8 text.
#' @param pipeline_deadline Absolute deadline, enforced here with a
#'   bounded `wait()` for stages the pump could not observe.
#'
#' @returns A list with `status`, `stdout`, `stderr`, `pid`, `timeout`.
#'
#' @keywords internal
#' @noRd
settle_pipeline_stage <- function(
  proc_i,
  spawn_failure,
  stage_stdout,
  stage_stderr,
  pump_timed_out,
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

  p_timeout <- FALSE
  if (isTRUE(pump_timed_out)) {
    # The shared deadline has passed and pump_pipeline_io() already took
    # its final non-blocking drain of every captured stream, so killing
    # here cannot discard readable output (`kill()` invalidates a
    # process's connections immediately, confirmed empirically). Every
    # still-running stage is killed - the documented whole-pipeline
    # timeout contract - while stages that already exited keep their real
    # status and are not marked as timed out.
    if (proc_i$is_alive()) {
      proc_i$kill()
      p_timeout <- TRUE
    }
  } else if (isTRUE(is.finite(pipeline_deadline))) {
    # All watched streams hit EOF before the deadline, but a stage with no
    # R-side streams (e.g. `stderr = NULL` on a non-last command) - or one
    # that closed its streams and kept running - is invisible to the pump,
    # so the deadline must be enforced here with a *bounded* wait. A bare
    # `wait()` silently disabled `timeout` for exactly those stages
    # (measured: a 1s deadline waiting the full 6s of a sleeping child).
    remaining_ms <- max(
      0,
      (pipeline_deadline - proc.time()[["elapsed"]]) * 1000
    )
    proc_i$wait(timeout = round(remaining_ms))
    if (proc_i$is_alive()) {
      proc_i$kill()
      p_timeout <- TRUE
    }
  }
  proc_i$wait()

  # Normalized to a fixed sentinel on timeout, same as run()/run_bin()
  # (see run_process_with_input.R) - a killed process's own reported
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
    stdout = stage_stdout %||% NA_character_,
    stderr = stage_stderr %||% empty_stream,
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
#' backend - it's one environment, not a coincidence of name - so every
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
#' registered backend simultaneously - `resolve_backend()`'s own
#' `condathis_backend_ambiguous_env` abort, which (unlike a single-owner
#' mismatch) always fires regardless of the `mutating` argument - gets the
#' same `error_var`-gated treatment here rather than escaping uncaught:
#' re-thrown as-is under `error = "cancel"`, degraded to "missing" under
#' `error = "continue"`.
#'
#' @returns A list with `missing_envs` (a named character vector under
#'   `error = "continue"`: names are the affected `env_name`s, values are
#'   the specific stderr message to report for each - genuinely absent,
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
          rlang::cnd_signal(cnd)
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

    # backend_probe_env(), not backend_has_env(): a *failed* listing (NA)
    # must not be treated as "absent" - refusing to run over a transient
    # existence-check hiccup turned a recoverable blip into a hard
    # env-not-found abort (or a synthetic 127) for environments that are
    # right there. On NA, proceed optimistically; a genuinely missing
    # environment still fails at spawn with its own clear error.
    env_probe <- backend_probe_env(
      resolved$backend,
      env_name_i,
      verbose = FALSE
    )
    if (isFALSE(env_probe)) {
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
