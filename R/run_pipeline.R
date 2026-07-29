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
#'       `stderr` to override the top-level `stderr` target for this command,
#'       and `stdout` to override the top-level `stdout` target, only
#'       allowed on the **last** command, since every other command's
#'       standard output is always piped to the next command.
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
#'   via `get_micromamba_activation_envvars()`, a real `micromamba run`
#'   activation (including package `activate.d` hook scripts), cached per
#'   `env_name`. Defaults to `TRUE`. Set to `FALSE` to use the original,
#'   faster hand-rolled activation (`get_activation_envvars()`: a fixed set
#'   of `CONDA_*`/`MAMBA_*` variables, no `activate.d` execution). The
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
  supervise = TRUE,
  cleanup_tree = TRUE,
  linux_pdeathsig = FALSE,
  activate = TRUE,
  timeout = Inf
) {
  error <- rlang::arg_match(error)
  error_var <- isTRUE(identical(error, "cancel"))

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

  parsed <- parse_cmds_spec(cmds, default_env_name = env_name)
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
  missing_envs <- precreate_envs(
    parsed,
    tmp_dir_path = tmp_dir_path,
    error_var = error_var
  )

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

  procs <- vector("list", n_cmds)
  spawn_failures <- vector("list", n_cmds)
  prev_read <- NULL

  for (i in seq_len(n_cmds)) {
    cmd_vec <- parsed[[i]]$cmd
    env_name_i <- parsed[[i]]$env_name

    # `conn_create_proc_pipepair()`, not `conn_create_pipepair()`, is the
    # constructor documented for wiring two child processes together
    # (`?processx::processx_connections`): its ends are synchronous/
    # blocking, which is "required for child-process stdin/stdout on
    # Windows". `conn_create_pipepair()`'s ends are non-blocking, meant for
    # R-side reading/writing (e.g. this package's own `pump_process_io()`,
    # used for `run()`/`run_bin()`'s `stdin = "|"` handling) — using it here
    # instead is what caused `run_pipeline()` to hang indefinitely on
    # Windows for any 2+ command pipeline. Confirmed by comparing against
    # `processx::pipeline`'s own `initialize()` method, which uses
    # `conn_create_proc_pipepair()` and is documented to work on Windows.
    next_pipe <- if (i < n_cmds) processx::conn_create_proc_pipepair() else NULL
    stdin_i <- if (i == 1L) stdin else prev_read
    stdout_i <- if (i == n_cmds) {
      parsed[[i]]$stdout %||% stdout
    } else {
      next_pipe[[1L]]
    }

    if (env_name_i %in% missing_envs) {
      spawn_failures[[i]] <- list(
        status = 127L,
        stderr = sprintf(
          "Conda environment '%s' does not exist.\n",
          env_name_i
        )
      )
    } else {
      env_dir <- get_env_dir(env_name = env_name_i)

      activation_envvars <- if (isTRUE(activate)) {
        get_micromamba_activation_envvars(env_name = env_name_i)
      } else {
        get_activation_envvars(
          env_name = env_name_i,
          env_dir = env_dir,
          tmp_dir = tmp_dir_path
        )
      }

      stderr_i <- parsed[[i]]$stderr %||% stderr

      # A bare command name is resolved by the OS against the *calling* R
      # process's own ambient PATH, not against `env` above (Windows'
      # `CreateProcess`, like POSIX `execvp()`, locates the executable
      # image before the child's own environment block takes effect) — so
      # without this, a command only "works" here by coincidence, if
      # something of the same name happens to already be reachable outside
      # `env_name_i` entirely (confirmed on Windows: a 3-command pipeline
      # using `rev` failed outright, since no `rev` exists anywhere on the
      # ambient PATH, even though the target environment has its own).
      # Falls back to the bare name, preserving the existing
      # "command not found" behavior below, when `cmd_vec[1L]` isn't found
      # inside `env_dir` itself (e.g. it's expected to resolve via `PATH`
      # some other way, or genuinely doesn't exist).
      resolved_cmd <- resolve_env_bin_path(env_dir, cmd_vec[1L]) %||%
        cmd_vec[1L]

      spawn_result <- tryCatch(
        expr = {
          processx::process$new(
            command = resolved_cmd,
            args = cmd_vec[-1L],
            stdin = stdin_i,
            stdout = stdout_i,
            stderr = stderr_i,
            poll_connection = if (i < n_cmds) FALSE else NULL,
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
        spawn_failures[[i]] <- list(status = 127L, stderr = stderr_msg)
      } else {
        procs[[i]] <- spawn_result
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

  timeout_flag <- FALSE
  processes <- vector("list", n_cmds)
  all_statuses <- integer(n_cmds)
  any_failed <- FALSE

  for (i in seq_len(n_cmds)) {
    proc_i <- procs[[i]]
    cmd_vec <- parsed[[i]]$cmd
    env_name_i <- parsed[[i]]$env_name
    cmd_string <- paste(shQuote(cmd_vec), collapse = " ")

    p_timeout <- FALSE
    if (!is.null(spawn_failures[[i]])) {
      p_status <- spawn_failures[[i]]$status
      p_stderr <- spawn_failures[[i]]$stderr
      p_stdout <- NA_character_
      p_pid <- NA_integer_
    } else {
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
      streams <- if (identical(i, 1L) && !is.null(first_proc_streams)) {
        first_proc_streams
      } else {
        pump_process_io(
          proc_i,
          want_stdout = identical(i, n_cmds),
          want_stderr = TRUE,
          binary = binary,
          deadline = pipeline_deadline
        )
      }

      p_timeout <- isTRUE(streams$timeout)
      if (isTRUE(p_timeout)) {
        # Kill only *this* stage, and only after having drained it above —
        # `kill()` invalidates a process's own connection immediately
        # (confirmed empirically), discarding anything still unread, so
        # draining downstream stages before reaching this point (rather
        # than killing every process up front) is what lets them keep
        # whatever they'd already produced. Killing this one process also
        # closes its stdout pipe, so the next stage (reading from it) sees
        # EOF and can finish draining normally instead of blocking further.
        timeout_flag <- TRUE
        if (proc_i$is_alive()) {
          proc_i$kill()
        }
      }
      proc_i$wait()

      p_stdout <- streams$stdout %||% NA_character_
      p_stderr <- streams$stderr %||% empty_stream

      p_status <- proc_i$get_exit_status()
      if (is.null(p_status)) {
        p_status <- NA_integer_
      }
      p_pid <- proc_i$get_pid()
    }

    all_statuses[i] <- p_status
    if (isTRUE(p_status != 0L) && !is.na(p_status)) {
      any_failed <- TRUE
    }

    processes[[i]] <- new_condathis_result(
      status = p_status,
      stdout = p_stdout,
      stderr = p_stderr,
      timeout = p_timeout,
      pid = p_pid,
      cmd = cmd_string,
      env_name = env_name_i
    )
  }

  if (isTRUE(error_var) && isTRUE(timeout_flag)) {
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

  if (isTRUE(error_var) && isTRUE(any_failed)) {
    kill_processes(procs)
    failed_lines <- character()
    for (i in seq_len(n_cmds)) {
      p <- processes[[i]]
      if (!identical(p$status, 0L) && !is.na(p$status)) {
        failed_lines <- c(
          failed_lines,
          sprintf(
            "  [%d] %s (env: %s, status: %d)",
            i,
            escape_cli_braces(p$cmd),
            escape_cli_braces(p$env_name),
            p$status
          )
        )
        if (isTRUE(is.raw(p$stderr))) {
          if (length(p$stderr) > 0L) {
            failed_lines <- c(
              failed_lines,
              sprintf("       <binary data, %d bytes>", length(p$stderr))
            )
          }
        } else if (nzchar(p$stderr)) {
          stderr_lines <- strsplit(p$stderr, "\n")[[1]]
          stderr_lines <- stderr_lines[nzchar(stderr_lines)]
          for (sl in utils::head(stderr_lines, 10L)) {
            failed_lines <- c(
              failed_lines,
              sprintf("       %s", escape_cli_braces(sl))
            )
          }
        }
      }
    }
    cli::cli_abort(
      message = c(
        `x` = "Pipeline failed {.value {sum(all_statuses != 0L, na.rm = TRUE)}} command(s) exited with non-zero status",
        `!` = "Failed commands:",
        failed_lines
      ),
      class = "condathis_pipeline_status_error"
    )
  }

  result <- new_condathis_pipeline(
    statuses = all_statuses,
    processes = processes,
    timeout = timeout_flag
  )

  return(invisible(result))
}

parse_cmds_spec <- function(cmds, default_env_name) {
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

#' Ensure the default environment exists, and report missing custom envs
#'
#' Auto-creates the default `"condathis-env"` when missing, regardless of
#' `error_var`. For any other missing environment: aborts immediately when
#' `error_var` is `TRUE` (`error = "cancel"`), matching the previous
#' fail-fast behavior; otherwise returns the missing environment names so
#' the caller can treat commands targeting them as failed-to-spawn, in line
#' with `error = "continue"` semantics.
#'
#' @keywords internal
#' @noRd
precreate_envs <- function(parsed, tmp_dir_path, error_var) {
  env_names <- unique(vapply(parsed, `[[`, character(1L), "env_name"))
  missing_envs <- character()
  for (env_name_i in env_names) {
    if (!env_exists(env_name = env_name_i, verbose = FALSE)) {
      if (identical(env_name_i, "condathis-env")) {
        create_base_env(verbose = FALSE)
      } else if (isTRUE(error_var)) {
        cli::cli_abort(
          message = c(
            `x` = "Environment {.field {env_name_i}} does not exist.",
            `!` = "Create it with {.fn create_env} first."
          ),
          class = "condathis_pipeline_env_not_found"
        )
      } else {
        missing_envs <- c(missing_envs, env_name_i)
      }
    }
  }
  return(missing_envs)
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
