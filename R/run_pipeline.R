#' Run a pipeline of commands connected with pipes
#'
#' @description
#' Runs commands connected with pipes, as `cmd1 | cmd2` in a shell. The
#' standard output of each command is the standard input of the next one.
#' The data flows between the processes through operating system pipes, not
#' through R. R gets the standard output of the last command and the
#' standard error of every command.
#'
#' Describe each command with [run_step()], which takes the same command,
#' arguments and `env_name` as [run()]. Each command can run in a
#' **different** Conda environment. Commands that do not set an environment
#' use the `env_name` of `run_pipeline()`.
#'
#' @param ... Two or more pipeline steps, built with [run_step()], in
#'   pipeline order. Splice in a list of steps, built with [list()] or
#'   [`c()`][c.condathis_run_step], with `!!!`, as in
#'   `run_pipeline(!!!steps)`. [c()] on steps gives a list
#'   of steps that later [c()] calls extend, as in
#'   `c(c(step_1, step_2), step_3)`. To add a step to a plain list or to
#'   `NULL`, wrap it in [list()], as in `c(steps, list(step))`. [c()] with a
#'   plain list or `NULL` first splits a step into its fields. Any other
#'   value aborts with class `condathis_run_pipeline_invalid_step`, so name
#'   every option below in full. Fewer than two steps abort with class
#'   `condathis_run_pipeline_too_few_commands`.
#' @param stdout Standard output target of the **last** command: `"|"` (the
#'   default) captures it in the result, a file path writes it to that file,
#'   `""` sends it to the standard output of the R process, and `NULL`
#'   discards it. The standard output of every other command goes to the
#'   next command.
#' @param stderr Standard error target for **all** processes. `"|"` (the
#'   default) captures each command's standard error in its result. A file
#'   path writes them all to that file, in command order once the pipeline
#'   finishes. `NULL` discards them. `""` sends them to the standard error
#'   of the R process. `"2>&1"` sends the standard error of each command to
#'   its standard output: to the next command, and for the last command to
#'   the `stdout` target. The `stderr` argument of [run_step()] replaces it
#'   for one command.
#' @param stdin Standard input source of the **first** command: `NULL` (the
#'   default) for no input, the path of an existing file to read, or `"|"`
#'   to write `input` to it.
#' @param input Character or raw vector written to the standard input of
#'   the first command, as in [run()]. Must be `NULL` (the default) unless
#'   `stdin = "|"`. Other values abort with class `condathis_invalid_input`.
#' @param binary Logical. Whether to return raw vectors, not UTF-8 text, for
#'   the standard error of every command and the standard output of the last
#'   one. Defaults to `FALSE`. It applies to the whole pipeline. There is no
#'   per-command setting.
#' @param error Character string that controls what happens when a command
#'   fails. With `"cancel"` (the default), `run_pipeline()` aborts with
#'   these classes:
#'   * `condathis_run_pipeline_status_error` (also
#'     `condathis_status_error`): a command exits with a non-zero status. A
#'     broken pipe can end a command that is not the last one: that does
#'     not count (see *Broken pipes*).
#'   * `condathis_run_pipeline_timeout_error` (also
#'     `condathis_timeout_error`): a timeout.
#'   * `condathis_run_pipeline_env_not_found` (also
#'     `condathis_env_not_found`): a step environment does not exist. For an
#'     [env_path()], the error also has `condathis_env_path_not_found` or
#'     `condathis_env_path_not_conda_env`.
#'   * `condathis_backend_ambiguous_env`: a step environment is found under
#'     several backends (see `method`).
#'   * `condathis_run_pipeline_resolve_failed` (also
#'     `condathis_backend_error`): the backend fails to resolve a command,
#'     for example because an `activate.d` script of the environment fails.
#'     The error keeps the condathis classes of the backend's error, for
#'     example `condathis_micromamba_status_error`, and has that error as
#'     its parent.
#'   * `condathis_backend_resolve_run_invalid`: a backend package gives an
#'     invalid command description (a bug in that package).
#'
#'   The status and timeout errors carry the fields `status`, `stdout`,
#'   `stderr` and `timeout`, as the errors of [run()] do. They also carry
#'   `result` (the `condathis_pipeline` object that `error = "continue"`
#'   returns) and `statuses`. With `"continue"`, `run_pipeline()` returns the
#'   result instead. Every step in an environment that does not exist or is
#'   found under several backends gets status 127, with the reason in its
#'   `stderr`. So does every command that cannot be resolved or started. The
#'   other steps still run. A timeout gives status -9.
#'   Invalid values abort with class `condathis_invalid_error`. See
#'   [condathis-conditions] for all classes.
#' @param env_name Character string with the default environment of the
#'   steps that do not set their own, or an environment given by
#'   [env_path()]. Defaults to `"condathis-env"`, which `run_pipeline()`
#'   creates (empty, with the backend that `method` selects) when it does
#'   not exist. `run_pipeline()` never creates any other missing environment
#'   and fails per `error`. A name must follow the rules of the `env_name`
#'   argument of [run()]. Invalid values abort with class
#'   `condathis_invalid_env_name`.
#' @param verbose Character string that controls the console output. One
#'   of `"output"`, `"silent"`, `"cmd"`, `"spinner"` and `"full"`. Usage
#'   shows the default.
#'   `"output"` prints, while the pipeline runs, what it captures: the last
#'   command's standard output and every command's standard error, when
#'   their target is `"|"`. `"cmd"` prints the whole pipeline first.
#'   `"full"` does both. `"spinner"` shows only a spinner, and `"silent"`
#'   shows nothing. `TRUE` means `"output"` and `FALSE` means `"silent"`.
#'   Every level except `"silent"` shows a spinner in interactive sessions.
#'   It also shows these messages and this warning (see
#'   [condathis-conditions]):
#'   * `condathis_micromamba_downloading` (a message): no usable
#'     `micromamba` was found, so it is downloaded.
#'   * `condathis_env_lock_waiting` and `condathis_cache_lock_waiting`
#'     (messages): the call waits for another R session.
#'   * `condathis_install_micromamba_checksum_unavailable` (a warning): the
#'     checksum of the downloaded `micromamba` could not be checked.
#'
#'   Invalid values abort with class `condathis_invalid_verbose`.
#' @param method Character string naming the default backend of the steps
#'   that do not set their own `method` (see [run_step()]). `"auto"` (the
#'   default) uses the backend that owns each environment, and otherwise the
#'   first available backend in the order of the option
#'   `condathis.backend_priority` (see [condathis-options]). Any name from
#'   [list_registered_backend_names()] selects that backend. `"micromamba"`
#'   is built in. The name of a backend whose package condathis knows also
#'   selects it, such as `"rattler"` of the `rattlerthis` package.
#'   condathis loads that package. `"native"` is a deprecated alias for
#'   `"micromamba"` (it warns once per session). If you name a backend
#'   other than the owner of an environment, condathis warns and uses the
#'   owner. Steps that share an environment must agree on the backend. The
#'   classes:
#'   * `condathis_backend_not_installed`: the package of the named backend
#'     is not installed.
#'   * `condathis_backend_mismatch_warning` (a warning): the named backend
#'     does not own the environment.
#'   * `condathis_backend_ambiguous_env`: several backends have an
#'     environment of that name, and `method` names none of them. With
#'     `error = "continue"`, its steps get status 127.
#'   * `condathis_run_pipeline_conflicting_method`: steps that share an
#'     environment do not agree on the backend.
#'   * `condathis_invalid_method`: an invalid value.
#' @param supervise Logical. Whether the `processx` supervisor watches each
#'   process: when the R session ends, even by a crash, the supervisor kills
#'   it. Defaults to `TRUE`, unlike in [run()] and [run_bin()], since a
#'   pipeline starts several connected processes. Ignored on Windows, where
#'   supervised pipelines hang.
#' @param cleanup_tree Logical. Whether to kill the process tree of each
#'   command, processes that it started in the background included. R kills
#'   the tree when it frees the process object of the command, at a garbage
#'   collection after the pipeline finishes. Defaults to `TRUE`, so that no
#'   command outlives the pipeline, unlike in [run()] and [run_bin()], where
#'   a daemon that a command starts keeps running.
#' @param linux_pdeathsig Logical. On Linux, whether each command gets
#'   `SIGTERM` when the R session ends, even by a crash. Ignored on other
#'   platforms. Defaults to `FALSE`.
#' @param timeout Number of seconds the whole pipeline may take, the
#'   activations of the environments included: one deadline for all
#'   commands, not one per command. Defaults to `Inf` (no limit).
#'   `run_pipeline()` lowers a finite value above 2147483 (about 24.8 days)
#'   to that value. When the time is up, `run_pipeline()` kills every
#'   command still running (status -9 and `timeout = TRUE` in its result).
#'   It does not start a command whose activation took the rest of the time,
#'   and counts it as killed.
#'   `error = "cancel"` then aborts with class
#'   `condathis_run_pipeline_timeout_error`, and `error = "continue"`
#'   returns the result, with `timeout = TRUE`. Values that are not a
#'   single, non-negative number abort with class
#'   `condathis_invalid_timeout`.
#' @param activate Logical. `TRUE` (the default) runs each command with the
#'   activation of its environment, as [run()] does. `FALSE` sets a fixed
#'   set of variables instead, without `activate.d` scripts (see
#'   [condathis-options]). Each command runs in the working directory of
#'   the R session, unless the activation of a backend gives another one.
#'
#' @returns A `condathis_pipeline` object, invisibly, which prints as a
#'   short summary and which [parse_output()] reads. It is a classed list
#'   with:
#'   \item{status}{Integer. The status of the pipeline: -9 when it timed
#'     out, otherwise the status of the first command that failed, or 0. A
#'     broken pipe can end a command that is not the last one: that does not
#'     count (see *Broken pipes*).}
#'   \item{statuses}{Integer vector, the exit status of each command. A
#'     command that a signal ends has the negative signal number, such as
#'     -13 for `SIGPIPE`.}
#'   \item{processes}{List of `condathis_result` objects, one per command,
#'     with the fields of a [run()] result: `stdout` is `NA` for every
#'     command but the last, `env_name` is the environment name or the
#'     directory of an [env_path()], and `timeout` is `TRUE` for the
#'     commands that the timeout killed.}
#'   \item{timeout}{Logical. Whether the pipeline timed out.}
#'   \item{cmd}{Character string. The command lines of the commands, each
#'     part quoted, joined with `" | "`.}
#'
#' @section Broken pipes:
#' A command that is not the last one ends as it would in a shell when it
#' writes again after the next command has exited. On Linux and macOS,
#' `SIGPIPE` kills it. Windows has no such signal. There, `run_pipeline()`
#' reads the pipe in place of the command that exited. It kills the writer
#' when more output comes after the pipe was empty for about one second in
#' total. It also kills the writer when more than 64 KiB comes, which is
#' what a Linux pipe holds. Output that was already in the pipe does not
#' count. Either way, the status of the writer is -13, and that is not a
#' failure. It does not make `error = "cancel"` abort, and it is not the
#' `status` of the result. So `seq 1 1000000 | head -n 1` has status 0.
#' Programs that handle `SIGPIPE` themselves, such as R and Python, exit
#' with their own status (R with 1, Python usually with 120), which counts
#' as a failure. A command that writes nothing more keeps running, on every
#' platform, and keeps its own status. On Windows, the reader that takes the
#' place of the exited command is a small `Rscript` process. When it cannot
#' start, the writer gets one second to exit on its own, and
#' `run_pipeline()` then kills it.
#'
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   # `pigz` and `ripgrep` (the `rg` binary) come from conda-forge, which
#'   # builds both for Linux, macOS and Windows. `rg` is used here instead
#'   # of GNU `grep`, which conda-forge has for Windows only as an MSYS2
#'   # package (with the "m2-" prefix).
#'   create_env("conda-forge::pigz", env_name = "pigz-env")
#'   create_env("conda-forge::ripgrep", env_name = "ripgrep-env")
#'
#'   # Pipeline with per-command environments: count the reads of a FASTQ
#'   # file shipped with condathis. In this file, the header line of each
#'   # read starts with "@read".
#'   fastq_file <- fs::path_package(
#'     "condathis", "extdata", "sample1_L001_R1_001.fastq.gz"
#'   )
#'   res <- run_pipeline(
#'     run_step(
#'       "pigz", "--decompress", "--stdout", fastq_file,
#'       env_name = "pigz-env"
#'     ),
#'     run_step("rg", "--count", "^@read", env_name = "ripgrep-env"),
#'     verbose = "silent"
#'   )
#'   print(parse_output(res))
#'   #> [1] "1086"
#'
#'   # Steps are values: build a list of them, then splice it in with `!!!`
#'   steps <- list(
#'     run_step("rg", "--version", env_name = "ripgrep-env"),
#'     run_step("rg", "ripgrep", env_name = "ripgrep-env")
#'   )
#'   print(parse_output(run_pipeline(!!!steps, verbose = "silent")))
#'   #> [1] "ripgrep 15.2.0 (rev 78115297cd)"
#' })
#' }
#'
#' @seealso [env_path()] for an environment created outside `condathis`,
#'   and [condathis-conditions] for the condition classes.
#' @family commands
#'
#' @export
run_pipeline <- function(
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
  supervise = TRUE,
  cleanup_tree = TRUE,
  linux_pdeathsig = FALSE,
  activate = TRUE,
  timeout = Inf
) {
  steps <- rlang::list2(...)
  call <- rlang::current_env()
  # First: a step spliced in by mistake as its fields binds `env_name`,
  # `method` and `stderr` of this function, which would then fail their own
  # checks with a message that hides the mistake.
  check_pipeline_steps(steps, call = call)
  error <- arg_match_classed(
    error,
    values = c("cancel", "continue"),
    class = "condathis_invalid_error",
    arg_name = "error",
    call = call
  )
  error_var <- isTRUE(identical(error, "cancel"))
  verbose_list <- parse_verbose_arg(verbose, call = call)
  method <- validate_method_arg(method, call = call)

  validate_pipeline_args(
    input = input,
    stdin = stdin,
    binary = binary,
    call = call
  )
  pipeline_encoding <- if (isTRUE(binary)) "binary" else "utf-8"
  run_args <- validate_run_args(
    fn = "run_pipeline",
    timeout = timeout,
    supervise = supervise,
    cleanup_tree = cleanup_tree,
    linux_pdeathsig = linux_pdeathsig,
    stdin = stdin,
    stdout = stdout,
    stderr = stderr,
    activate = activate,
    call = call
  )
  timeout <- run_args$timeout

  # The last argument checks: the default environment, the number of steps,
  # and the method of every step. Nothing is created before they pass
  # (rule R2).
  parsed <- parse_pipeline_steps(
    steps,
    default_env_name = env_name,
    default_method = method,
    call = call
  )
  n_cmds <- length(parsed)

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

  precreate_result <- precreate_envs(
    parsed,
    error_var = error_var,
    verbose = verbose_list$internal_verbose,
    call = call
  )
  missing_envs <- precreate_result$missing_envs
  resolved_backends <- precreate_result$resolved_backends

  # WORKAROUND(TODO-add-link): `supervise = TRUE` hangs pipelines with 2+
  # commands on native Windows. Overriding to `FALSE` fixes it in under 1s.
  # A `supervisor.exe` helper outlives the piped child and likely holds a
  # handle to the piped stdout, so the reader never sees EOF.
  # `processx::pipeline` never enables `supervise` and does not hang. Only
  # Windows is forced to `FALSE`, to keep crash-safety on other platforms.
  # Remove when supervised multi-command pipelines complete on Windows.
  effective_supervise <- if (isTRUE(is_windows())) {
    FALSE
  } else {
    supervise
  }

  if (isTRUE(verbose_list$cmd)) {
    echo_pipeline_cmd(parsed)
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
    pipeline_encoding = pipeline_encoding,
    error_var = error_var,
    pipeline_deadline = pipeline_deadline,
    call = call
  )
  procs <- spawned_all$procs
  spawn_failures <- spawned_all$spawn_failures

  # Reap the pipeline on *any* exit from here on: an unexpected error in
  # the pump or settle machinery must not leave stages running until
  # garbage collection. On normal returns (and the deliberate
  # error = "cancel" aborts) every stage has already exited and been
  # wait()ed on, so this is a no-op there - kill_processes() only touches
  # processes still alive. The orphaned-pipe watchers (Windows only) go
  # after the stages.
  orphan_watch <- new_orphan_pipe_watch(spawned_all$orphan_reads)
  on.exit(kill_processes(procs), add = TRUE)
  on.exit(close_orphan_pipe_watch(orphan_watch), add = TRUE)
  watch <- orphan_pipe_watch_funs(orphan_watch)

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
    deadline = pipeline_deadline,
    echo = isTRUE(verbose_list$output) && isFALSE(binary),
    spinner = isTRUE(verbose_list$spinner_flag),
    watch = watch
  )
  # A stage with no R-side streams is invisible to the pump. On Windows it
  # can still be blocked writing into the pipe of a stage that has exited.
  pumped$broken_pipe <- await_windows_broken_pipes(
    procs = procs,
    state = pumped$broken_pipe,
    deadline = pipeline_deadline,
    watch = watch
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

  # Before the aborts too: their errors carry it as a field, so a handler
  # gets what `error = "continue"` returns.
  result <- new_condathis_pipeline(
    statuses = all_statuses,
    processes = processes,
    timeout = timeout_flag
  )

  if (isTRUE(error_var) && isTRUE(timeout_flag)) {
    abort_pipeline_timeout(result, timeout = timeout, call = call)
  }

  if (isTRUE(error_var) && isTRUE(any_failed)) {
    abort_pipeline_status_error(result, procs = procs, call = call)
  }

  return(invisible(result))
}

#' Validate `run_pipeline()`'s top-level `input`/`binary` arguments
#'
#' @param input,stdin,binary The arguments of `run_pipeline()`.
#' @param call Environment of the function the error is reported for.
#'
#' @returns `NULL`, invisibly. Aborts with the classes of rule R1, for
#'   example `c("condathis_run_pipeline_invalid_input",
#'   "condathis_pipeline_invalid_input", "condathis_invalid_input",
#'   "condathis_invalid_arg", "condathis_error")`.
#'
#' @keywords internal
#' @noRd
validate_pipeline_args <- function(
  input,
  stdin,
  binary,
  call = rlang::caller_env()
) {
  input_class <- arg_error_class(
    "run_pipeline",
    "input",
    aliases = "condathis_pipeline_invalid_input"
  )
  # The same check as run() and run_bin().
  validate_input_with_stdin(
    input,
    stdin = stdin,
    class = input_class,
    call = call
  )
  validate_bool_arg(
    binary,
    class = arg_error_class(
      "run_pipeline",
      "binary",
      aliases = "condathis_pipeline_invalid_binary_arg"
    ),
    arg_name = "binary",
    call = call
  )
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
  stdin,
  stdout,
  prev_read
) {
  next_pipe <- if (i < n_cmds) processx::conn_create_proc_pipepair() else NULL
  stdin_i <- if (i == 1L) stdin else prev_read
  stdout_i <- if (i == n_cmds) stdout else next_pipe[[1L]]
  return(list(next_pipe = next_pipe, stdin_i = stdin_i, stdout_i = stdout_i))
}

#' Spawn every pipeline stage's process, wiring their stdio pipes together
#'
#' @param error_var Logical. `TRUE` for `error = "cancel"`: a command that
#'   cannot be resolved aborts (see `spawn_pipeline_process()`).
#' @param call Environment of `run_pipeline()`, for errors.
#'
#' @returns A list with `procs` (per-stage `processx::process` objects, or
#'   `NULL` for stages that failed to spawn), `spawn_failures` (per-stage
#'   `list(status, stderr)`, or `NULL` for stages that spawned fine),
#'   `stderr_redirects` (see `collect_pipeline_stderr_files()`) and
#'   `orphan_reads` (per-stage read end of the pipe to the next stage, kept
#'   open on Windows only, otherwise `NULL`).
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
  pipeline_encoding,
  error_var = FALSE,
  pipeline_deadline = Inf,
  call = rlang::caller_env()
) {
  procs <- vector("list", n_cmds)
  spawn_failures <- vector("list", n_cmds)
  stderr_redirects <- vector("list", n_cmds)
  prev_read <- NULL
  # On Windows the R process keeps the read end of every pipe between
  # stages, so a watcher can take it when the reader exits early (see
  # `reap_windows_broken_pipes()`). On Linux and macOS it must close it: a
  # read end left open in the R process would keep `SIGPIPE` from ever
  # ending the writer.
  keep_read_ends <- isTRUE(is_windows())
  orphan_reads <- vector("list", n_cmds)

  # If anything throws mid-loop (an unexpected spawn error class, a pipe
  # creation failure, ...), the stages spawned so far must not be left
  # running until garbage collection happens to reap them.
  spawn_all_done <- FALSE
  on.exit(
    if (isFALSE(spawn_all_done)) {
      kill_processes(procs)
      close_orphan_pipe_watch(new_orphan_pipe_watch(orphan_reads))
    },
    add = TRUE
  )

  for (i in seq_len(n_cmds)) {
    cmd_vec <- parsed[[i]]$cmd
    env_key_i <- parsed[[i]]$env_key

    stdio <- resolve_pipeline_stdio(
      i = i,
      n_cmds = n_cmds,
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
    stderr_target <- if (isTRUE(parsed[[i]]$stderr_set)) {
      parsed[[i]]$stderr
    } else {
      stderr
    }
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

    if (env_key_i %in% names(missing_envs)) {
      spawn_failures[[i]] <- list(
        status = 127L,
        stderr = missing_envs[[env_key_i]]
      )
    } else {
      spawned <- spawn_pipeline_process(
        cmd_vec = cmd_vec,
        step = parsed[[i]],
        resolved_backend = resolved_backends[[env_key_i]]$backend,
        backend_name = resolved_backends[[env_key_i]]$name,
        step_index = i,
        stdin_i = stdin_i,
        stdout_i = stdout_i,
        stderr_i = stderr_i,
        is_last = identical(i, n_cmds),
        activate = activate,
        tmp_dir_path = tmp_dir_path,
        effective_supervise = effective_supervise,
        cleanup_tree = cleanup_tree,
        linux_pdeathsig = linux_pdeathsig,
        pipeline_encoding = pipeline_encoding,
        error_var = error_var,
        pipeline_deadline = pipeline_deadline,
        call = call
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
      if (isTRUE(keep_read_ends)) {
        orphan_reads[[i - 1L]] <- prev_read
      } else {
        close(prev_read)
      }
    }
    prev_read <- if (!is.null(next_pipe)) next_pipe[[2L]] else NULL
  }

  spawn_all_done <- TRUE
  return(list(
    procs = procs,
    spawn_failures = spawn_failures,
    stderr_redirects = stderr_redirects,
    orphan_reads = orphan_reads
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
#' file holds its diagnostics when a stage failed.
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
#'   stage timed out), and `any_failed` (logical, whether any stage failed,
#'   see `is_failed_stage()`).
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

  # On timeout, record which stages are still running *before* killing any
  # of them, then kill them all. Killing stage by stage let downstream
  # stages see EOF and exit cleanly before their own liveness check, so
  # they were reported as finished (status 0, `timeout = FALSE`) although
  # they were running when the deadline passed.
  alive_at_timeout <- rep(FALSE, n_cmds)
  if (isTRUE(pumped$timeout)) {
    alive_at_timeout <- vapply(
      procs,
      function(p) isFALSE(is.null(p)) && isTRUE(p$is_alive()),
      logical(1L)
    )
    for (i in which(alive_at_timeout)) {
      tryCatch(procs[[i]]$kill(), error = function(e) NULL)
    }
  }

  for (i in seq_len(n_cmds)) {
    cmd_vec <- parsed[[i]]$cmd
    cmd_string <- format_cmd_line(cmd_vec)

    settled <- settle_pipeline_stage(
      proc_i = procs[[i]],
      spawn_failure = spawn_failures[[i]],
      stage_stdout = pumped$stdout[[i]],
      stage_stderr = pumped$stderr[[i]],
      pump_timed_out = pumped$timeout,
      binary = binary,
      pipeline_deadline = pipeline_deadline,
      alive_at_timeout = alive_at_timeout[[i]]
    )

    if (isTRUE(settled$timeout)) {
      timeout_flag <- TRUE
    }

    if (isTRUE(pumped$broken_pipe$killed[[i]]) && isFALSE(settled$timeout)) {
      settled$status <- broken_pipe_status
    }

    all_statuses[i] <- settled$status

    processes[[i]] <- new_condathis_result(
      status = settled$status,
      stdout = settled$stdout,
      stderr = settled$stderr,
      timeout = settled$timeout,
      pid = settled$pid,
      cmd = cmd_string,
      env_name = parsed[[i]]$env_label
    )
  }

  return(list(
    processes = processes,
    all_statuses = all_statuses,
    timeout_flag = timeout_flag,
    any_failed = isTRUE(any(is_failed_stage(all_statuses)))
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
#' A command that cannot be resolved aborts under `error = "cancel"`. A
#' backend error (for example a failed activation) aborts through
#' `abort_pipeline_resolve_failure()`. A `backend_resolve_run()` value that
#' breaks the contract aborts with the error of `validate_resolve_run()`,
#' which already names the backend and the `run_pipeline()` call. Under
#' `error = "continue"` both are a failure with status 127.
#'
#' @param step The stage's entry from `parse_pipeline_steps()`.
#' @param backend_name Character string, the registered name of
#'   `resolved_backend`, for errors.
#' @param step_index Integer position of the command in the pipeline, for
#'   errors.
#' @param is_last Logical. Whether this is the last command in the
#'   pipeline - controls `poll_connection` (`NULL` for the last stage,
#'   `FALSE` for every other stage, matching `processx::pipeline`'s own
#'   `initialize()`).
#' @param error_var Logical. `TRUE` for `error = "cancel"`.
#' @param call Environment of `run_pipeline()`, for errors.
#'
#' @returns A list with `proc` (the spawned `processx::process` object, or
#'   `NULL` on failure) and `failure` (`NULL` on success, otherwise
#'   `list(status, stderr)`).
#'
#' @keywords internal
#' @noRd
spawn_pipeline_process <- function(
  cmd_vec,
  step,
  resolved_backend,
  backend_name = backend_display_name(resolved_backend),
  step_index = NA_integer_,
  stdin_i,
  stdout_i,
  stderr_i,
  is_last,
  activate,
  tmp_dir_path,
  effective_supervise,
  cleanup_tree,
  linux_pdeathsig,
  pipeline_encoding,
  error_var = FALSE,
  pipeline_deadline = Inf,
  call = rlang::caller_env()
) {
  env_label <- step$env_label
  # Checked like every other `backend_get_env_dir()` value: an invalid one
  # names the backend and the `run_pipeline()` call.
  env_dir <- step$env_dir %||%
    as.character(env_dir_for_backend(
      resolved_backend,
      env_name = step$env_name,
      call = call
    ))

  # The stage's environment block before activation: the session's
  # environment with the clean-conda overlay, never `c("current", ...)`.
  # The calling session's environment is not mutated by `run_pipeline()`,
  # so inheriting it directly would leak the caller's CONDA_*/MAMBA_* state
  # into the stage. The package-cache and envs-path variables come from the
  # stage's own backend (see `child_conda_dirs()`). It is the `base_env` of
  # `backend_resolve_run()`: the backend computes its activation against
  # it.
  base_env <- build_child_env(
    tmp_dir = tmp_dir_path,
    conda_dirs = child_conda_dirs(
      resolved_backend,
      env_dir = env_dir,
      env_path = isFALSE(is.null(step$env_dir))
    )
  )

  # Both the executable path and the activation variables come from the
  # backend's `backend_resolve_run()`, so every registered backend works here.
  # For `"micromamba"`, `micromamba_backend_resolve_run()` uses
  # `resolve_env_bin_path()` (falling back to the bare name) plus
  # `get_micromamba_activation_envvars()`.
  #
  # A bare name is looked up as `run()` does (see
  # `resolve_direct_run_command()`). On Windows, processx searches a bare
  # command in the working directory and on the calling R process's PATH,
  # not on `env` below, so the binary directories of the stage's
  # environment are searched first: a 3-command pipeline using `rev` failed
  # because no `rev` exists on the PATH of R. On Linux and macOS, processx
  # sets the child's environment before `execvp()`, so the child's PATH is
  # searched. A command found nowhere stays bare, which preserves the
  # "command not found" behavior below.
  #
  # `activate = FALSE` must not call `backend_resolve_run()`: the micromamba
  # implementation resolves the full activation environment (two or three
  # process spawns on a cache miss, plus any `activate.d` hook failures)
  # before the flag could discard the result. The activation-free path resolves the
  # executable locally (same `resolve_env_bin_path()` fallback) and uses the
  # hook-free variables built from `env_dir` alone.
  # The working directory the backend gives; `NULL` keeps R's.
  stage_wd <- NULL
  if (isTRUE(activate)) {
    # A failing backend resolution (e.g. a broken activate.d hook during
    # activation) is a per-stage failure under `error = "continue"`: it gets
    # the same status-127 channel as a missing binary, and the other stages
    # still run.
    #
    # An environment given by `env_path()` has no name for
    # `backend_resolve_run()`: it is described from its directory, by
    # `backend_resolve_run_in_dir()`.
    #
    # The pipeline's one deadline also covers the activations: a stage
    # whose activation runs out of time is a stage that timed out, and the
    # stages after it time out at once.
    time_left <- function() {
      return(pipeline_deadline - proc.time()[["elapsed"]])
    }
    timed_out <- list(
      proc = NULL,
      failure = list(
        status = -9L,
        stderr = activation_timeout_stderr(env_label),
        timeout = TRUE
      )
    )
    if (isTRUE(time_left() <= 0)) {
      return(timed_out)
    }
    backend_run <- tryCatch(
      if (is.null(step$env_name)) {
        rlang::exec(
          backend_resolve_run_in_dir,
          resolved_backend,
          cmd = cmd_vec[1L],
          args = cmd_vec[-1L],
          env_dir = env_dir,
          verbose = "silent",
          base_env = base_env,
          !!!backend_resolve_args(
            resolved_backend,
            "backend_resolve_run_in_dir",
            timeout = time_left()
          )
        )
      } else {
        rlang::exec(
          backend_resolve_run,
          resolved_backend,
          cmd = cmd_vec[1L],
          args = cmd_vec[-1L],
          env_name = step$env_name,
          verbose = "silent",
          base_env = base_env,
          !!!backend_resolve_args(
            resolved_backend,
            "backend_resolve_run",
            timeout = time_left()
          )
        )
      },
      error = function(cnd) cnd
    )
    if (isTRUE(time_left() <= 0)) {
      return(timed_out)
    }
    failure_cnd <- NULL
    if (inherits(backend_run, "condition")) {
      # Re-signaled unchanged, the backend's error named an internal call
      # and no step, and a third-party backend's error had no condathis
      # class at all.
      if (isTRUE(error_var)) {
        abort_pipeline_resolve_failure(
          backend_run,
          step_index = step_index,
          cmd_name = cmd_vec[1L],
          env_label = env_label,
          backend_name = backend_name,
          call = call
        )
      }
      failure_cnd <- backend_run
    } else if (isTRUE(error_var)) {
      # A contract error goes on unchanged: it already names the backend,
      # the environment and the `run_pipeline()` call.
      validate_resolve_run(
        backend_run,
        env_name = env_label,
        backend_name = backend_name,
        call = call
      )
    } else {
      failure_cnd <- tryCatch(
        {
          validate_resolve_run(
            backend_run,
            env_name = env_label,
            backend_name = backend_name,
            call = call
          )
          NULL
        },
        error = function(cnd) cnd
      )
    }
    if (isFALSE(is.null(failure_cnd))) {
      return(list(
        proc = NULL,
        failure = list(
          status = 127L,
          stderr = resolve_failure_stderr(
            what = "command",
            env_label = env_label,
            cnd = failure_cnd
          )
        )
      ))
    }
    resolved_cmd <- backend_run$command
    stage_args <- backend_run$args
    activation_envvars <- backend_run$env
    stage_wd <- backend_run$dir
  } else {
    resolved_cmd <- resolve_env_bin_path(env_dir, cmd_vec[1L]) %||%
      cmd_vec[1L]
    stage_args <- cmd_vec[-1L]
    # Without `CONDA_ENVS_PATH`: the clean overlay sets it (see
    # `child_conda_dirs()`), so both `activate` modes give a stage the same
    # value.
    activation_envvars <- get_activation_envvars(
      env_name = env_label,
      env_dir = env_dir,
      tmp_dir = tmp_dir_path
    )
  }

  # Full explicit environment block for this stage: the block before
  # activation and the activation overlay.
  child_env <- apply_child_overlay(base_env, overlay = activation_envvars)
  resolved_cmd <- resolve_direct_run_command(resolved_cmd, env_dir = env_dir)

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
        wd = stage_wd,
        supervise = effective_supervise,
        cleanup_tree = cleanup_tree,
        linux_pdeathsig = processx_linux_pdeathsig(linux_pdeathsig),
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
      sprintf("System command '%s' not found\n", hide_secrets(cmd_vec[1L]))
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
  pipeline_deadline,
  alive_at_timeout = FALSE
) {
  if (isFALSE(is.null(spawn_failure))) {
    return(list(
      status = spawn_failure$status,
      stdout = NA_character_,
      stderr = spawn_failure$stderr,
      pid = NA_integer_,
      timeout = isTRUE(spawn_failure$timeout)
    ))
  }

  p_timeout <- FALSE
  if (isTRUE(pump_timed_out)) {
    # The shared deadline has passed and pump_pipeline_io() already took
    # its final non-blocking drain of every captured stream, so killing
    # here cannot discard readable output (`kill()` invalidates a
    # process's connections immediately, confirmed empirically). Every
    # still-running stage is killed - the documented whole-pipeline
    # timeout contract - while stages that already exited keep their real
    # status and are not marked as timed out.
    #
    # `run_pipeline_drain_all()` snapshots liveness for all stages and kills
    # them together; `alive_at_timeout` carries that snapshot.
    if (isTRUE(alive_at_timeout) || proc_i$is_alive()) {
      tryCatch(proc_i$kill(), error = function(e) NULL)
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
    wait_process_safely(proc_i, timeout = round(remaining_ms))
    if (proc_i$is_alive()) {
      tryCatch(proc_i$kill(), error = function(e) NULL)
      p_timeout <- TRUE
    }
  }
  # wait_process_safely()/exit_status_safely(): tolerate the Windows race
  # where the process handle is finalized between the liveness check (or
  # kill) above and this wait - see wait_process_safely()'s docs.
  wait_process_safely(proc_i)

  # Normalized to a fixed sentinel on timeout, same as run()/run_bin()
  # (see run_process_with_input.R) - a killed process's own reported
  # exit status is an OS/`processx` detail that differs across
  # platforms (`-9` on Linux/macOS, `2` on Windows for the identical
  # `kill()` call), not something to trust as-is.
  if (isTRUE(p_timeout)) {
    p_status <- -9L
  } else {
    p_status <- exit_status_safely(proc_i)
  }

  return(list(
    status = p_status,
    stdout = stage_stdout %||% NA_character_,
    stderr = stage_stderr %||% NA_character_,
    pid = proc_i$get_pid(),
    timeout = p_timeout
  ))
}

#' Condition fields of a pipeline status or timeout error
#'
#' The fields that the errors of `run()` and `run_bin()` carry, so one
#' handler for `condathis_status_error` or `condathis_timeout_error` works
#' for the whole run family, plus the whole result.
#'
#' @param result The `condathis_pipeline` object.
#'
#' @returns A list with `status` (the pipeline status), `stdout` (the last
#'   command's captured output, or `NA`), `stderr` (the captured standard
#'   error of every command, in command order, or `NA`), `timeout`,
#'   `result` and `statuses`.
#'
#' @keywords internal
#' @noRd
pipeline_error_fields <- function(result) {
  streams <- pipeline_output_streams(result)
  return(list(
    status = result$status,
    stdout = streams$stdout %||% NA_character_,
    stderr = streams$stderr %||% NA_character_,
    timeout = isTRUE(result$timeout),
    result = result,
    statuses = result$statuses
  ))
}

#' Abort for a command that the backend fails to resolve
#'
#' For `error = "cancel"` only. The backend's error `cnd` comes from
#' `backend_resolve_run()`, or from the micromamba activation of an
#' environment given by `env_path()`. It becomes the parent of a new error
#' that names the command, the environment, the backend and the
#' `run_pipeline()` call. The condathis classes of `cnd` stay on the new
#' error, as in `with_backend_errors()`, so a handler for them (for example
#' `condathis_cmd_status_error`) still works. Other classes of `cnd` are
#' found through the parent, with `rlang::cnd_inherits()`.
#'
#' @param cnd The backend's error condition.
#' @param step_index Integer position of the command in the pipeline.
#' @param cmd_name Character string, the command.
#' @param env_label Character string, the environment name, or the
#'   directory of an `env_path()`.
#' @param backend_name Character string, the registered backend name.
#' @param call Environment of `run_pipeline()`, for the error.
#'
#' @returns Does not return. The error has the classes
#'   `c("condathis_run_pipeline_resolve_failed", "condathis_backend_error",
#'   <the condathis classes of cnd>, "condathis_error")`.
#'
#' @keywords internal
#' @noRd
abort_pipeline_resolve_failure <- function(
  cnd,
  step_index,
  cmd_name,
  env_label,
  backend_name,
  call = rlang::caller_env()
) {
  # The shared error of the run family, so run(), run_bin() and
  # run_pipeline() report a failed resolution the same way.
  abort_resolve_failure(
    cnd,
    fn = "run_pipeline",
    cmd_name = cmd_name,
    env_label = env_label,
    backend_name = backend_name,
    step_index = step_index,
    hint = c(
      `i` = "{.code activate = FALSE} runs the command without the activation of the backend."
    ),
    call = call
  )
}

#' Abort a pipeline that timed out (`error = "cancel"` only)
#'
#' @param result The `condathis_pipeline` object, kept in the error.
#' @param timeout Numeric. The timeout of the pipeline, in seconds.
#' @param call Environment of `run_pipeline()`, for the error.
#'
#' @returns Does not return. The error has the classes
#'   `c("condathis_run_pipeline_timeout_error",
#'   "condathis_pipeline_timeout_error", "condathis_timeout_error",
#'   "condathis_error")` and the fields of `pipeline_error_fields()`.
#'
#' @keywords internal
#' @noRd
abort_pipeline_timeout <- function(
  result,
  timeout,
  call = rlang::caller_env()
) {
  n_killed <- sum(
    vapply(result$processes, function(p) isTRUE(p$timeout), logical(1L))
  )
  fields <- pipeline_error_fields(result)
  condathis_abort(
    message = c(
      `x` = "Pipeline timed out after {timeout} seconds.",
      `i` = "Killed {n_killed} still-running command{?s}."
    ),
    class = c(
      "condathis_run_pipeline_timeout_error",
      "condathis_pipeline_timeout_error",
      "condathis_timeout_error"
    ),
    status = fields$status,
    stdout = fields$stdout,
    stderr = fields$stderr,
    timeout = fields$timeout,
    result = fields$result,
    statuses = fields$statuses,
    call = call
  )
}

#' Build the "Failed commands:" detail lines for the pipeline status-error
#' abort message
#'
#' @keywords internal
#' @noRd
build_pipeline_failed_lines <- function(processes) {
  statuses <- vapply(
    processes,
    function(p) as.integer(p$status %||% NA_integer_),
    integer(1L)
  )
  failed_lines <- character()
  for (i in which(is_failed_stage(statuses))) {
    p <- processes[[i]]
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
  if (isFALSE(rlang::is_string(p$stderr)) || isTRUE(is.na(p$stderr))) {
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

#' Abort a pipeline that had one or more failed commands
#' (`error = "cancel"` only)
#'
#' @param result The `condathis_pipeline` object, kept in the error.
#' @param procs List of `processx::process` objects, killed first.
#' @param call Environment of `run_pipeline()`, for the error.
#'
#' @returns Does not return. The error has the classes
#'   `c("condathis_run_pipeline_status_error",
#'   "condathis_pipeline_status_error", "condathis_status_error",
#'   "condathis_error")` and the fields of `pipeline_error_fields()`.
#'
#' @keywords internal
#' @noRd
abort_pipeline_status_error <- function(
  result,
  procs = list(),
  call = rlang::caller_env()
) {
  kill_processes(procs)
  failed_lines <- build_pipeline_failed_lines(result$processes)
  n_failed <- sum(is_failed_stage(result$statuses))
  fields <- pipeline_error_fields(result)
  condathis_abort(
    message = c(
      `x` = "Pipeline failed: {n_failed} command{?s} exited with a non-zero status.",
      `i` = "Failed commands:",
      failed_lines
    ),
    class = c(
      "condathis_run_pipeline_status_error",
      "condathis_pipeline_status_error",
      "condathis_status_error"
    ),
    status = fields$status,
    stdout = fields$stdout,
    stderr = fields$stderr,
    timeout = fields$timeout,
    result = fields$result,
    statuses = fields$statuses,
    call = call
  )
}

#' Fill in the defaults of `run_pipeline()`'s steps
#'
#' Also checks the default `env_name`, the number of steps, and the
#' `method` of every step, so that every argument is checked before
#' `run_pipeline()` resolves or creates anything (rule R2).
#'
#' @param steps List of the values passed in `...` of `run_pipeline()`,
#'   already checked with `check_pipeline_steps()`.
#' @param default_env_name The `env_name` of `run_pipeline()`.
#' @param default_method The `method` of `run_pipeline()`.
#' @param call Calling environment, for errors.
#'
#' @returns One list per step, with `cmd` (character vector, command then
#'   arguments), `env_name` (the name, or `NULL` for an environment given by
#'   `env_path()`), `env_path` (the `condathis_env_path`, or `NULL`),
#'   `env_dir` (its directory, or `NULL`), `env_key` (character string
#'   identifying the environment: steps with the same key share one),
#'   `env_label` (character string for messages and results), `method`,
#'   `stderr` and `stderr_set`.
#'
#' @keywords internal
#' @noRd
parse_pipeline_steps <- function(
  steps,
  default_env_name,
  default_method = "auto",
  call = rlang::caller_env()
) {
  env_name_class <- pipeline_env_name_class()
  if (isTRUE(is_env_path(default_env_name))) {
    validate_env_path_object(
      default_env_name,
      class = env_name_class,
      call = call
    )
  } else {
    validate_env_name(default_env_name, class = env_name_class, call = call)
  }

  if (length(steps) < 2L) {
    condathis_abort(
      message = c(
        `x` = "A pipeline needs at least 2 steps, not {length(steps)}.",
        `i` = "Use {.fn run} to run a single command."
      ),
      class = c(
        "condathis_run_pipeline_too_few_commands",
        "condathis_pipeline_too_few_commands",
        "condathis_invalid_arg"
      ),
      call = call
    )
  }

  parsed <- lapply(steps, function(step) {
    env_value <- step$env_name %||% default_env_name
    if (isTRUE(is_env_path(env_value))) {
      env_dir <- validate_env_path_object(
        env_value,
        class = env_name_class,
        call = call
      )
      env_name <- NULL
      env_key <- paste0("path:", env_dir)
      env_label <- env_dir
    } else {
      env_dir <- NULL
      env_name <- env_value
      env_key <- env_value
      env_label <- env_value
      env_value <- NULL
    }
    list(
      cmd = c(step$cmd, step$args),
      env_name = env_name,
      env_path = env_value,
      env_dir = env_dir,
      env_key = env_key,
      env_label = env_label,
      # "native" and "micromamba" name the same backend: map the alias
      # before `resolve_pipeline_env_method()` compares steps.
      method = resolve_method_alias(step$method %||% default_method),
      stderr = step$stderr,
      stderr_set = isTRUE(step$stderr_set)
    )
  })
  parsed <- unname(parsed)

  # Steps that share an environment must agree on its backend. Checked
  # before the methods themselves, so a conflict is reported as one, even
  # when one of the names is not registered.
  for (env_key in unique(vapply(parsed, `[[`, character(1L), "env_key"))) {
    resolve_pipeline_env_method(env_key, parsed, call = call)
  }
  # A step's own method is a value of `method`: checked here, with the
  # shared classes of the method parser, before any backend call.
  for (step in steps) {
    if (isFALSE(is.null(step$method))) {
      validate_method_arg(step$method, call = call)
    }
  }
  return(parsed)
}

#' Classes of an invalid `env_name` of `run_pipeline()`
#'
#' @returns `c("condathis_run_pipeline_invalid_env_name",
#'   "condathis_pipeline_invalid_env_name", "condathis_invalid_env_name",
#'   "condathis_invalid_arg")`. The second class is the old name, kept until
#'   1.0.
#'
#' @keywords internal
#' @noRd
pipeline_env_name_class <- function() {
  return(arg_error_class(
    "run_pipeline",
    "env_name",
    aliases = "condathis_pipeline_invalid_env_name"
  ))
}

#' Check that every value in `...` of `run_pipeline()` is a valid step
#'
#' @param steps List of the values passed in `...` of `run_pipeline()`.
#' @param call Calling environment, for errors.
#'
#' @returns `steps`, invisibly.
#'
#' @keywords internal
#' @noRd
check_pipeline_steps <- function(steps, call = rlang::caller_env()) {
  step_names <- names(steps) %||% rep("", length(steps))
  for (i in seq_along(steps)) {
    if (isFALSE(is_run_step(steps[[i]]))) {
      abort_invalid_pipeline_step(
        steps[[i]],
        index = i,
        name = step_names[[i]],
        call = call
      )
    }
    # A step can be built or edited by hand: check it again, as
    # `validate_env_path_object()` does for an environment path.
    validate_run_step_object(steps[[i]], index = i, call = call)
  }
  return(invisible(steps))
}

#' Abort for a value in `...` of `run_pipeline()` that is not a step
#'
#' The hints name the likely mistake: a list of steps passed without
#' `!!!`, the fields of a step passed one by one (as `c()` and `append()`
#' leave a step added to a plain list), or a misspelled option.
#'
#' @param x The offending value.
#' @param index Integer position of `x` in `...`.
#' @param name Character string, the name of `x` in `...`, or `""`.
#' @param call Calling environment, for the error.
#'
#' @keywords internal
#' @noRd
abort_invalid_pipeline_step <- function(x, index, name, call) {
  step_fields <- names(new_run_step(cmd = ""))
  is_plain_list <- is.list(x) && isFALSE(is.object(x))
  offender <- if (nzchar(name)) {
    "Argument {.arg {name}} is not a pipeline step."
  } else {
    "Argument {index} is not a pipeline step: it is {.obj_type_friendly {x}}."
  }
  hints <- c(`i` = "Build each step with {.fn run_step}.")
  if (length(x) > 0L && isTRUE(is_run_step_list(x))) {
    hints <- c(
      hints,
      `i` = "To pass a list of steps, splice it: {.code run_pipeline(!!!steps)}."
    )
  } else if (
    isTRUE(name %in% step_fields) ||
      (isTRUE(is_plain_list) && isTRUE(any(names(x) %in% step_fields)))
  ) {
    # `c(steps, step)` and `append(steps, step)` with a plain list or
    # `NULL` as `steps` use the default `c()`, which splits `step` into
    # its fields.
    hints <- c(
      hints,
      `i` = "The fields of a step were passed one by one: {.fn c} with a plain list or {.code NULL} first splits a step into its fields.",
      `i` = "Wrap the step in {.fn list}, as in {.code c(steps, list(step))}, or start from a step, as in {.code c(step_1, step_2)}."
    )
  } else if (nzchar(name)) {
    hints <- c(
      hints,
      `i` = "Name every option of {.fn run_pipeline} in full."
    )
  }
  condathis_abort(
    message = c(`x` = offender, hints),
    class = c(
      "condathis_run_pipeline_invalid_step",
      "condathis_pipeline_invalid_step",
      "condathis_invalid_arg"
    ),
    call = call
  )
}

#' Print the "Running" line of a pipeline
#'
#' The pipeline counterpart of the line `run()` prints for
#' `verbose = "cmd"`: every command, joined by `|`, with the credentials of
#' URLs hidden (see `hide_secrets()`).
#'
#' @param parsed The result of `parse_pipeline_steps()`.
#'
#' @keywords internal
#' @noRd
echo_pipeline_cmd <- function(parsed) {
  words <- unlist(lapply(seq_along(parsed), function(i) {
    c(if (i > 1L) "|", quote_cmd_words(hide_secrets(parsed[[i]]$cmd)))
  }))
  cat(paste(c("Running", words), collapse = " "), "\n", sep = "")
  return(invisible(NULL))
}

#' Resolve the single `method` to use for every command sharing one
#' environment
#'
#' All commands targeting the same environment must resolve to the same
#' backend - it's one environment, not a coincidence of name - so every
#' command's `method` is considered, not just the first one found for that
#' environment. `"auto"` (the no-preference default, whether inherited from
#' `run_pipeline()`'s own top-level `method` or a command's own unset
#' override) never conflicts with an explicit choice; two different
#' explicit choices for the same `env_name` do.
#'
#' @param env_key Character string, the `env_key` of the environment.
#' @param parsed The full parsed command list from `parse_pipeline_steps()`.
#' @param call Environment of `run_pipeline()`, for the error.
#'
#' @returns Character string: `"auto"`, or the single explicit method every
#'   command referencing the environment agrees on. Two different explicit
#'   methods abort with `c("condathis_run_pipeline_conflicting_method",
#'   "condathis_pipeline_conflicting_method", "condathis_invalid_arg",
#'   "condathis_error")`.
#'
#' @keywords internal
#' @noRd
resolve_pipeline_env_method <- function(
  env_key,
  parsed,
  call = rlang::caller_env()
) {
  matching <- Filter(function(p) identical(p$env_key, env_key), parsed)
  env_label <- matching[[1L]]$env_label
  methods_i <- vapply(
    matching,
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
  condathis_abort(
    message = c(
      `x` = "Commands targeting environment {.field {env_label}} request conflicting backends: {.field {explicit_methods}}.",
      `i` = "Use the same {.arg method} for every command sharing an {.arg env_name}."
    ),
    class = c(
      "condathis_run_pipeline_conflicting_method",
      "condathis_pipeline_conflicting_method",
      "condathis_invalid_arg"
    ),
    call = call
  )
}

#' Resolve each unique environment's backend, auto-create the default
#' environment, and report missing custom environments
#'
#' Environments given by `env_path()` come first. They are never created:
#' each one is checked to be a Conda environment, and reported like a
#' missing environment when it is not. Checking them first means that a
#' wrong `method` for one of them aborts before the default environment is
#' created for another step (rule R2).
#'
#' Then each named environment is resolved with `resolve_backend()`, for
#' every registered backend (see `backend_resolve_run()`). The default
#' `"condathis-env"` is created when it is missing, regardless of
#' `error_var`, with the backend that `method` resolves to. Any other
#' missing environment aborts when `error_var` is `TRUE`
#' (`error = "cancel"`), with `c("condathis_run_pipeline_env_not_found",
#' "condathis_pipeline_env_not_found", "condathis_env_not_found",
#' "condathis_error")`. Otherwise it is returned, so the caller treats the
#' commands that target it as failed to start (status 127).
#'
#' An environment that exists under more than one registered backend
#' (`resolve_backend()`'s `condathis_backend_ambiguous_env` abort) gets the
#' same `error_var`-gated treatment: re-thrown as-is under
#' `error = "cancel"`, reported like a missing environment under
#' `error = "continue"`.
#'
#' When a backend cannot tell whether an environment exists (its probe is
#' `NA`, rule R5), the environment is not treated as missing: the command
#' is started, and the backend reports the real error.
#'
#' @param parsed The result of `parse_pipeline_steps()`.
#' @param error_var Logical. `TRUE` for `error = "cancel"`.
#' @param verbose Verbosity of the automatic creation of the default
#'   environment, the `internal_verbose` of `parse_strategy_verbose()`.
#' @param call Environment of `run_pipeline()`, for errors.
#'
#' @returns A list with `missing_envs` (a named character vector under
#'   `error = "continue"`: names are the affected `env_key`s, values are
#'   the specific stderr message to report for each - genuinely absent,
#'   ambiguous ownership, and an `env_path()` directory that is not a Conda
#'   environment get different messages) and `resolved_backends` (a named
#'   list, one already-resolved backend per unique `env_key`, so the main
#'   spawn loop never triggers a second, independent `resolve_backend()`
#'   call).
#'
#' @keywords internal
#' @noRd
precreate_envs <- function(
  parsed,
  error_var,
  verbose = "silent",
  call = rlang::caller_env()
) {
  env_keys <- unique(vapply(parsed, `[[`, character(1L), "env_key"))
  methods_by_env <- vapply(
    env_keys,
    function(key) resolve_pipeline_env_method(key, parsed, call = call),
    character(1L)
  )
  names(methods_by_env) <- env_keys
  first_step <- function(key) {
    return(Filter(function(p) identical(p$env_key, key), parsed)[[1L]])
  }
  is_path_key <- vapply(
    env_keys,
    function(key) is.null(first_step(key)$env_name),
    logical(1L)
  )
  not_found_class <- c(
    "condathis_run_pipeline_env_not_found",
    "condathis_pipeline_env_not_found"
  )

  missing_envs <- character()
  resolved_backends <- list()
  for (env_key_i in env_keys[is_path_key]) {
    step_i <- first_step(env_key_i)
    resolved <- resolve_env_path_target(
      step_i$env_path,
      method = methods_by_env[[env_key_i]],
      class = pipeline_env_name_class(),
      call = call
    )
    env_path_stderr <- check_env_path_usable(
      resolved$env_dir,
      error_var = error_var,
      class = not_found_class,
      call = call
    )
    if (isFALSE(is.null(env_path_stderr))) {
      missing_envs[[env_key_i]] <- env_path_stderr
    }
    resolved_backends[[env_key_i]] <- resolved
  }

  for (env_key_i in env_keys[!is_path_key]) {
    env_name_i <- first_step(env_key_i)$env_name
    resolved <- tryCatch(
      resolve_backend(
        env_name = env_name_i,
        method = methods_by_env[[env_key_i]],
        mutating = FALSE,
        call = call
      ),
      condathis_backend_ambiguous_env = function(cnd) {
        if (isTRUE(error_var)) {
          rlang::cnd_signal(cnd)
        }
        return(NULL)
      }
    )
    if (is.null(resolved)) {
      missing_envs[[env_key_i]] <- sprintf(
        "Environment '%s' exists under more than one backend; specify an explicit method to disambiguate.\n",
        env_name_i
      )
      next
    }

    # Use backend_probe_env(), not backend_has_env(): a failed listing (NA)
    # is not "absent". Treating it as absent turns a transient
    # existence-check error into a hard env-not-found abort (or a synthetic
    # 127). On NA, proceed. A genuinely missing environment still fails at
    # spawn with its own error.
    env_probe <- backend_probe_env(
      resolved$backend,
      env_name_i,
      verbose = "silent"
    )
    if (isFALSE(env_probe)) {
      if (identical(env_name_i, "condathis-env")) {
        # With the backend this call resolved to, so the new environment
        # belongs to it and not to the first backend in priority order.
        create_base_env(method = resolved$name, verbose = verbose)
        resolved <- resolve_backend(
          env_name = env_name_i,
          method = methods_by_env[[env_key_i]],
          mutating = FALSE,
          call = call
        )
      } else if (isTRUE(error_var)) {
        abort_env_not_found(env_name_i, class = not_found_class, call = call)
      } else {
        missing_envs[[env_key_i]] <- sprintf(
          "Conda environment '%s' does not exist.\n",
          env_name_i
        )
      }
    }

    resolved_backends[[env_key_i]] <- resolved
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
    if (is.null(proc_i)) {
      next
    }
    # `is_alive()` itself can fail on Windows ("The handle is invalid"),
    # which aborted the cleanup of every later stage.
    tryCatch(
      if (isTRUE(proc_i$is_alive())) proc_i$kill(),
      error = function(e) NULL
    )
  }
}

#' Is a stage's status an upstream SIGPIPE?
#'
#' A command that is not the last one is killed by `SIGPIPE` when the next
#' command stops reading early, as in `seq 1 1000000 | head -n 1`. That is
#' the normal end of such a pipeline, not a failure: it does not make
#' `error = "cancel"` abort, and `pipeline_status()` skips it (bash with
#' `pipefail` reports 141 instead). The stage keeps its real status
#' (`-13`) in `statuses`. Windows has no `SIGPIPE`;
#' `reap_windows_broken_pipes()` reproduces it there with the same status,
#' for a stage that writes after its reader exited.
#'
#' @param status Integer status of the stage, as reported by `processx`.
#' @param i Integer index of the stage.
#' @param n_cmds Integer number of stages.
#'
#' @returns Logical scalar.
#'
#' @keywords internal
#' @noRd
is_upstream_sigpipe <- function(status, i, n_cmds) {
  return(
    isTRUE(i < n_cmds) &&
      isTRUE(identical(as.integer(status), broken_pipe_status))
  )
}

#' Status of a stage ended by a broken pipe
#'
#' `-13` is how `processx` reports death by `SIGPIPE` on Linux and macOS.
#' The Windows emulation reports the same value.
#'
#' @keywords internal
#' @noRd
broken_pipe_status <- -13L

#' Seconds a Windows stage may keep running after its reader exits, when
#' its pipe cannot be watched
#'
#' The fallback of `reap_windows_broken_pipes()`, used only when no
#' orphaned-pipe watcher can be started for the stage, or the watcher fails.
#'
#' @keywords internal
#' @noRd
windows_broken_pipe_grace <- 1

#' Bytes of an orphaned pipe that never count as new output
#'
#' When a reader exits, the pipe can still hold output that the writer
#' wrote before. A Linux pipe holds 64 KiB, and output that fits in it
#' never causes `SIGPIPE`. A Windows pipe holds only 4 KiB
#' (`processx::conn_create_proc_pipepair()` creates it with the default
#' size), so a writer that wrote more is still blocked in that write when
#' its reader exits, and the rest comes after. The watcher of
#' `orphan_pipe_watch_lines()` therefore reads up to 64 KiB without
#' counting it as new output, whatever the timing. More than that is new
#' output, or output that would also block on Linux, where `SIGPIPE` then
#' ends the writer at once.
#'
#' A writer that keeps writing (`seq 1 1e9`) passes this limit within about
#' half a second: the watcher reads more than 100 KiB per second on Linux.
#'
#' @keywords internal
#' @noRd
orphan_pipe_backlog_bytes <- 65536L

#' Seconds of waiting after which output read from an orphaned pipe is new
#'
#' Output that is in the pipe when the reader exits can be read at once,
#' and so can the rest of a write that is blocked then. When the watcher
#' has to wait for bytes, the pipe ran empty, and the bytes that end the
#' wait were written after the reader exited. The watcher adds up the time
#' it waits (see `orphan_pipe_cpu_credit`) and reports new output when the
#' sum reaches this many seconds. The sum catches a writer that writes a
#' little at short intervals, not only one that writes again after one long
#' pause. Waiting too little would end a writer that never writes again,
#' and its work would be lost; waiting too long only lets a writer run on
#' for a moment. While a watcher read 60 KB of output already in the pipe,
#' the largest sum measured was 0.48 seconds on a machine with as many busy
#' processes as cores, and 0.56 seconds with twice as many. With four times
#' as many, it passed one second at times: on a machine that busy, a writer
#' that never writes again can still be ended.
#'
#' @keywords internal
#' @noRd
orphan_pipe_new_output_wait <- 1

#' Seconds of waiting that one second of work of the watcher cancels
#'
#' The watcher cannot tell a wait for a byte from a wait for the CPU on a
#' busy machine: both are time it does not run. While it reads output that
#' is already in the pipe, it waits only for the CPU, and it runs at least
#' a few percent of the time. So each second of CPU time it uses takes this
#' many seconds off the sum of `orphan_pipe_new_output_wait`, which never
#' goes below `0`. The sum then grows only while the watcher runs less than
#' 1/11 of the time, which a wait for a writer that writes a line now and
#' then gives. The watcher uses about 8 microseconds of CPU time per byte,
#' so a writer that writes more than about 10 KB per second does not make
#' the sum grow, and is caught by `orphan_pipe_backlog_bytes`.
#'
#' @keywords internal
#' @noRd
orphan_pipe_cpu_credit <- 10

#' Exit status of the orphaned-pipe watcher when the writer wrote again
#'
#' The watcher exits with status `0` when the writer closes its end of the
#' pipe, and with this status when the writer wrote after its reader
#' exited.
#'
#' @keywords internal
#' @noRd
orphan_pipe_new_output_status <- 13L

#' Initial state for `reap_windows_broken_pipes()`
#'
#' @param n Integer number of stages.
#'
#' @returns A list with one element per stage, for the pipe from that stage
#'   to the next one: `phase` (character, see `broken_pipe_transition()`),
#'   `since` (numeric, the elapsed time at which the stage entered its
#'   phase, or `NA`) and `killed` (logical, whether the stage was ended for
#'   a broken pipe).
#'
#' @keywords internal
#' @noRd
new_broken_pipe_state <- function(n) {
  return(list(
    phase = rep("reader", n),
    since = rep(NA_real_, n),
    killed = rep(FALSE, n)
  ))
}

#' Next phase of a Windows stage whose reader may have exited
#'
#' The decision of `reap_windows_broken_pipes()` for one non-last stage
#' (the writer) and the stage after it (the reader), as a pure function of
#' its inputs. `SIGPIPE` ends a writer when it writes after its reader is
#' gone, not when the reader exits: a writer that never writes again
#' finishes its work. The phases are:
#'
#' - `"reader"`: the reader is running. When it exits, the writer's pipe is
#'   watched (`"watching"`, action `"watch"`), or, when it cannot be
#'   watched, the writer gets `grace` seconds (`"grace"`).
#' - `"watching"`: a watcher reads the pipe in place of the reader (see
#'   `orphan_pipe_watch_lines()`). A watcher status of
#'   `orphan_pipe_new_output_status` means the writer wrote again: it is
#'   ended (`"broken"`, action `"kill"`). Status `0` means the writer closed
#'   its end and cannot write again (`"closed"`). Any other status means the
#'   watcher failed (`"grace"`).
#' - `"grace"`: the fallback. The writer is ended once `waited` reaches
#'   `grace`.
#' - `"exited"`, `"closed"` and `"broken"` are final. A writer that has
#'   exited moves to `"exited"` from every other phase.
#'
#' @param phase Character string. The current phase.
#' @param writer_alive Logical. Whether the writer is running.
#' @param reader_alive Logical. Whether the reader is running. `FALSE` for a
#'   reader that never started.
#' @param can_watch Logical. Whether a watcher can be started.
#' @param watcher_status Integer. The exit status of the watcher, or `NA`
#'   while it runs.
#' @param waited Numeric. Seconds since the stage entered `phase`.
#' @param grace Numeric. See `windows_broken_pipe_grace`.
#'
#' @returns A list with `phase` (the next phase) and `action`: `"none"`,
#'   `"watch"` (start a watcher) or `"kill"` (end the writer).
#'
#' @keywords internal
#' @noRd
broken_pipe_transition <- function(
  phase,
  writer_alive,
  reader_alive,
  can_watch = FALSE,
  watcher_status = NA_integer_,
  waited = 0,
  grace = windows_broken_pipe_grace
) {
  to <- function(next_phase, action = "none") {
    return(list(phase = next_phase, action = action))
  }
  if (isTRUE(phase %in% c("exited", "closed", "broken"))) {
    return(to(phase))
  }
  if (isFALSE(isTRUE(writer_alive))) {
    return(to("exited"))
  }
  if (identical(phase, "reader")) {
    if (isTRUE(reader_alive)) {
      return(to("reader"))
    }
    if (isTRUE(can_watch)) {
      return(to("watching", "watch"))
    }
    return(to("grace"))
  }
  if (identical(phase, "watching")) {
    if (isTRUE(is.na(watcher_status))) {
      return(to("watching"))
    }
    if (identical(as.integer(watcher_status), orphan_pipe_new_output_status)) {
      return(to("broken", "kill"))
    }
    if (identical(as.integer(watcher_status), 0L)) {
      return(to("closed"))
    }
    return(to("grace"))
  }
  if (isTRUE(waited >= grace)) {
    return(to("broken", "kill"))
  }
  return(to("grace"))
}

#' Reproduce `SIGPIPE` for Windows pipeline stages
#'
#' WORKAROUND: on Windows, `processx::conn_create_proc_pipepair()` creates
#' both pipe ends inheritable, and `processx` starts every child with
#' handle inheritance on (`processx` 3.9.0). Each stage therefore inherits
#' the read end of its own stdout pipe and never gets a broken pipe: after
#' the next stage exits early (`head -n 1`), it blocks forever once the
#' pipe buffer is full. On Linux and macOS both ends are close-on-exec, and
#' the writer is killed by `SIGPIPE` on its next write.
#'
#' On Windows, `run_pipeline_spawn_all()` keeps the read end of every pipe
#' between stages open in the R process. When the reader of a pipe exits
#' while the writer still runs, a watcher process takes that read end (see
#' `orphan_pipe_watch_lines()`): it reads what the writer had already
#' written, and reports when the writer writes more, that is, when the
#' pipe ran empty and more output came, or when more output came than a
#' Linux pipe holds. The writer is then ended with status `-13`, as
#' `SIGPIPE` ends it. A writer that writes nothing more keeps running and
#' keeps its own status.
#' The R process cannot read the read end itself: on Windows, `processx`
#' reads such a pipe with a blocking `ReadFile()`, which would stop the
#' pump loop until the writer writes.
#'
#' The writer is ended with its child processes (`kill_tree()`), because on
#' Windows the stage process is often only a launcher: `Rscript.exe` starts
#' R, and a conda entry point `.exe` starts `python.exe`. That child does
#' the writing, and it also holds the read end of its own pipe, so after a
#' plain `kill()` of the launcher it would block forever once the pipe is
#' full. `kill()` is the fallback when `kill_tree()` fails.
#'
#' Without a watcher (none can be started, or it fails), a writer still
#' running `windows_broken_pipe_grace` seconds after its reader exited is
#' ended. Ending one stage can leave the stage before it without a reader
#' too; later calls handle it the same way. A no-op outside Windows.
#'
#' @param procs List of `processx::process` objects, `NULL` for stages that
#'   never started.
#' @param state The previous state, from `new_broken_pipe_state()`.
#' @param before_kill Function of the stage index, called before a stage is
#'   killed so its captured streams can be drained: a kill discards unread
#'   data.
#' @param watch `NULL` (no watching), or a list of two functions of the
#'   stage index: `start(i)`, which starts the watcher of the pipe after
#'   stage `i` and returns `TRUE` on success, and `status(i)`, which returns
#'   the exit status of that watcher, or `NA` while it runs. See
#'   `orphan_pipe_watch_funs()`.
#' @param now Numeric. The current `proc.time()[["elapsed"]]`.
#'
#' @returns The updated state.
#'
#' @keywords internal
#' @noRd
reap_windows_broken_pipes <- function(
  procs,
  state,
  before_kill = function(i) NULL,
  watch = NULL,
  now = proc.time()[["elapsed"]]
) {
  n <- length(procs)
  if (isFALSE(is_windows()) || n < 2L) {
    return(state)
  }
  # `is_alive()` itself can fail on Windows ("The handle is invalid").
  alive <- function(proc) {
    return(
      isFALSE(is.null(proc)) &&
        isTRUE(tryCatch(proc$is_alive(), error = function(e) FALSE))
    )
  }
  for (i in seq_len(n - 1L)) {
    writer <- procs[[i]]
    if (is.null(writer)) {
      next
    }
    phase <- state$phase[[i]]
    since <- state$since[[i]]
    step <- broken_pipe_transition(
      phase = phase,
      writer_alive = alive(writer),
      reader_alive = alive(procs[[i + 1L]]),
      can_watch = isFALSE(is.null(watch)),
      watcher_status = if (
        identical(phase, "watching") && isFALSE(is.null(watch))
      ) {
        watch$status(i)
      } else {
        NA_integer_
      },
      waited = if (is.na(since)) 0 else now - since
    )
    next_phase <- step$phase
    if (identical(step$action, "watch") && isFALSE(isTRUE(watch$start(i)))) {
      next_phase <- "grace"
    }
    if (identical(step$action, "kill")) {
      before_kill(i)
      tryCatch(
        writer$kill_tree(),
        error = function(e) tryCatch(writer$kill(), error = function(e) NULL)
      )
      state$killed[[i]] <- TRUE
    }
    if (isFALSE(identical(next_phase, phase))) {
      state$phase[[i]] <- next_phase
      state$since[[i]] <- now
    }
  }
  return(state)
}

#' Wait out Windows stages left without a reader
#'
#' Runs after `pump_pipeline_io()`, which stops once every R-side stream is
#' closed. A stage without R-side streams can still be running then, and on
#' Windows it may never exit (see `reap_windows_broken_pipes()`). Polls
#' until every stage has exited or the deadline passes; the settle step
#' then enforces the deadline. A no-op outside Windows.
#'
#' @param procs List of `processx::process` objects or `NULL`.
#' @param state State from `new_broken_pipe_state()`.
#' @param deadline Absolute `proc.time()[["elapsed"]]` cutoff, or `Inf`.
#' @param watch As in `reap_windows_broken_pipes()`.
#'
#' @returns The updated state.
#'
#' @keywords internal
#' @noRd
await_windows_broken_pipes <- function(
  procs,
  state,
  deadline = Inf,
  watch = NULL
) {
  if (isFALSE(is_windows())) {
    return(state)
  }
  any_alive <- function() {
    any(vapply(
      procs,
      function(p) {
        isFALSE(is.null(p)) &&
          isTRUE(tryCatch(p$is_alive(), error = function(e) FALSE))
      },
      logical(1L)
    ))
  }
  while (isTRUE(any_alive()) && proc.time()[["elapsed"]] < deadline) {
    state <- reap_windows_broken_pipes(procs, state, watch = watch)
    Sys.sleep(0.05)
  }
  return(state)
}

#' R code of the orphaned-pipe watcher
#'
#' Run by `Rscript` with the read end of a pipe whose reader exited as its
#' standard input, and three arguments: `orphan_pipe_backlog_bytes`,
#' `orphan_pipe_new_output_wait` and `orphan_pipe_cpu_credit`. It reads
#' the pipe one byte at a time, so the writer is never blocked by a full
#' pipe. It keeps a sum of the time it did not run: for each byte, it adds
#' the elapsed time since the previous byte less the CPU time it used in
#' that time, and takes off the credit times that CPU time. The sum never
#' goes below `0`. It exits:
#'
#' - with status `0` at end of file: the writer closed its end (it exited),
#'   so it cannot write to the pipe again;
#' - with status `orphan_pipe_new_output_status` when the sum reaches the
#'   wait (the pipe ran empty, and the writer wrote after its reader
#'   exited), or at the first byte after the backlog bytes.
#'
#' `file("stdin", "rb")` puts the standard input in binary mode on Windows,
#' so a `0x1A` byte is not read as end of file. `readBin()` waits until the
#' byte is there. Times come from one `proc.time()` call per byte, and the
#' first wait is measured from the start of the script, so the start-up of
#' `Rscript` does not count. On Windows, CPU time is counted in clock ticks
#' of about 16 milliseconds, which only delays the credit by one tick.
#'
#' @returns Character vector of lines, 7-bit ASCII.
#'
#' @keywords internal
#' @noRd
orphan_pipe_watch_lines <- function() {
  return(c(
    "# Written by condathis. Watches a pipe whose reader has exited.",
    "args <- commandArgs(trailingOnly = TRUE)",
    "backlog <- as.numeric(args[[1L]])",
    "wait <- as.numeric(args[[2L]])",
    "credit <- as.numeric(args[[3L]])",
    "con <- file(\"stdin\", open = \"rb\")",
    "seen <- 0",
    "waited <- 0",
    "times <- proc.time()",
    "last_wall <- times[[3L]]",
    "last_cpu <- times[[1L]] + times[[2L]]",
    "repeat {",
    "  byte <- readBin(con, what = \"raw\", n = 1L)",
    "  if (length(byte) == 0L) {",
    "    quit(save = \"no\", status = 0L)",
    "  }",
    "  times <- proc.time()",
    "  wall <- times[[3L]]",
    "  cpu <- times[[1L]] + times[[2L]]",
    "  seen <- seen + 1",
    "  # Time not run, less the credit for the time run.",
    "  idle <- (wall - last_wall) - (cpu - last_cpu)",
    "  waited <- max(0, waited + idle - credit * (cpu - last_cpu))",
    "  if (seen > backlog || waited >= wait) {",
    sprintf(
      "    quit(save = \"no\", status = %dL)",
      orphan_pipe_new_output_status
    ),
    "  }",
    "  last_wall <- wall",
    "  last_cpu <- cpu",
    "}"
  ))
}

#' Path of the orphaned-pipe watcher script
#'
#' Written once per R session, in the session temporary directory: a
#' watcher can outlive the `run_pipeline()` call that started it by a
#' moment, and on Windows a file that a process has open cannot be deleted.
#'
#' @returns Character string.
#'
#' @keywords internal
#' @noRd
orphan_pipe_watch_script <- function() {
  path <- file.path(tempdir(), "condathis-orphan-pipe-watch.R")
  lines <- orphan_pipe_watch_lines()
  current <- if (isTRUE(file.exists(path))) {
    tryCatch(readLines(path, warn = FALSE), error = function(e) NULL)
  }
  if (isFALSE(identical(current, lines))) {
    writeLines(lines, path)
  }
  return(path)
}

#' Start an orphaned-pipe watcher
#'
#' @param stdin The read end of the pipe, as a `processx` connection, or
#'   `"|"` (for tests, which then write to the watcher).
#' @param backlog,wait,credit See `orphan_pipe_watch_lines()`.
#'
#' @returns A `processx::process` object.
#'
#' @keywords internal
#' @noRd
spawn_orphan_pipe_watcher <- function(
  stdin,
  backlog = orphan_pipe_backlog_bytes,
  wait = orphan_pipe_new_output_wait,
  credit = orphan_pipe_cpu_credit
) {
  # No `.exe` on Windows: `processx` adds it, as `CreateProcess()` does.
  # The watcher gets the session's temporary directory as `TMPDIR`: R makes
  # its own temporary directory there, which a killed watcher cannot
  # remove, and the session removes it when it ends.
  return(processx::process$new(
    command = file.path(R.home("bin"), "Rscript"),
    args = c(
      "--vanilla",
      "--default-packages=base",
      orphan_pipe_watch_script(),
      as.character(as.integer(backlog)),
      format_cmd_double(as.numeric(wait)),
      format_cmd_double(as.numeric(credit))
    ),
    env = c("current", TMPDIR = tempdir()),
    stdin = stdin,
    stdout = NULL,
    stderr = NULL,
    cleanup = TRUE,
    cleanup_tree = TRUE,
    windows_hide_window = TRUE
  ))
}

#' Orphaned-pipe watchers of one pipeline
#'
#' @param reads List with one element per stage: the read end of the pipe
#'   from that stage to the next one, kept open by
#'   `run_pipeline_spawn_all()` on Windows, or `NULL`.
#'
#' @returns An environment with `reads` and `watchers` (one
#'   `processx::process` or `NULL` per stage). Close it with
#'   `close_orphan_pipe_watch()`.
#'
#' @keywords internal
#' @noRd
new_orphan_pipe_watch <- function(reads) {
  ctx <- new.env(parent = emptyenv())
  ctx$reads <- reads
  ctx$watchers <- vector("list", length(reads))
  return(ctx)
}

#' The `watch` functions of `reap_windows_broken_pipes()` for a context
#'
#' @param ctx An environment from `new_orphan_pipe_watch()`.
#'
#' @returns A list with `start` and `status`.
#'
#' @keywords internal
#' @noRd
orphan_pipe_watch_funs <- function(ctx) {
  start <- function(i) {
    read_end <- ctx$reads[[i]]
    if (is.null(read_end)) {
      return(FALSE)
    }
    ctx$reads[i] <- list(NULL)
    # The watcher gets its own handle: the R process never reads this end.
    on.exit(try(close(read_end), silent = TRUE), add = TRUE)
    watcher <- tryCatch(
      spawn_orphan_pipe_watcher(read_end),
      error = function(e) NULL
    )
    if (is.null(watcher)) {
      return(FALSE)
    }
    ctx$watchers[[i]] <- watcher
    return(TRUE)
  }
  status <- function(i) {
    watcher <- ctx$watchers[[i]]
    if (is.null(watcher)) {
      return(-1L)
    }
    if (isTRUE(tryCatch(watcher$is_alive(), error = function(e) FALSE))) {
      return(NA_integer_)
    }
    # An exited watcher whose status cannot be read counts as failed.
    exit_status <- exit_status_safely(watcher)
    if (isTRUE(is.na(exit_status))) {
      return(-1L)
    }
    return(as.integer(exit_status))
  }
  return(list(start = start, status = status))
}

#' Close the read ends and end the watchers of a pipeline
#'
#' Runs when `run_pipeline()` exits. Every stage has exited by then, so a
#' watcher normally exits on its own at end of file. One that still runs
#' (a child of a stage can keep the pipe open) is ended with its children.
#'
#' @param ctx An environment from `new_orphan_pipe_watch()`.
#'
#' @keywords internal
#' @noRd
close_orphan_pipe_watch <- function(ctx) {
  for (read_end in ctx$reads) {
    if (isFALSE(is.null(read_end))) {
      try(close(read_end), silent = TRUE)
    }
  }
  ctx$reads <- vector("list", length(ctx$reads))
  for (watcher in ctx$watchers) {
    if (is.null(watcher)) {
      next
    }
    tryCatch(
      if (isTRUE(watcher$is_alive())) {
        tryCatch(watcher$kill_tree(), error = function(e) watcher$kill())
      },
      error = function(e) NULL
    )
  }
  return(invisible(NULL))
}
