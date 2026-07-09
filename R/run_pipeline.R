#' Run a pipeline of commands connected with pipes
#'
#' @description
#' Executes a sequence of commands where each command's standard output is
#' piped as standard input to the next command (like a Unix shell pipeline).
#' Data flows directly between child processes via kernel-level pipes — the
#' parent R process only sees the output of the final command.
#'
#' Each command in the pipeline can run in a **different** Conda environment.
#' Commands that do not specify an environment use the default `env_name`.
#'
#' @param cmds A list of command specifications. Each element is either:
#'   \itemize{
#'     \item A character vector: `c("cmd", "arg1", ...)` — runs in the
#'       default `env_name`.
#'     \item A named list with `cmd` (character vector) and, optionally,
#'       `env_name` (character string) to specify a per-command environment,
#'       `stderr` to override the top-level `stderr` target for this command,
#'       and `stdout` to override the top-level `stdout` target — only
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
#'
#' @returns A `condathis_pipeline` S3 object with per-process results:
#'   \item{statuses}{Integer vector of exit statuses, one per command.}
#'   \item{processes}{List of per-process result lists, each with:
#'     `cmd`, `env_name`, `status`, `stdout` (`NA` for non-last processes),
#'     `stderr`, and `pid`.}
#'   \item{timeout}{Logical. Whether the pipeline timed out.}
#'
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   # On Windows, "grep" and other GNU tools are packaged under the
#'   # "m2-" prefix (MSYS2), e.g. "conda-forge::m2-grep".
#'   grep_pkg <- if (startsWith(get_sys_arch(), "Windows")) {
#'     "conda-forge::m2-grep"
#'   } else {
#'     "conda-forge::grep"
#'   }
#'
#'   create_env("bioconda::samtools", env_name = "samtools-env")
#'   create_env(grep_pkg, env_name = "grep-env")
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
#'         cmd = c("grep", "@SQ"),
#'         env_name = "grep-env"
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
  error = c("cancel", "continue"),
  env_name = "condathis-env",
  supervise = TRUE,
  cleanup_tree = TRUE,
  linux_pdeathsig = FALSE
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

  pipes <- vector("list", max(0L, n_cmds - 1L))
  if (n_cmds > 1L) {
    for (idx in seq_len(n_cmds - 1L)) {
      pipes[[idx]] <- processx::conn_create_pipepair()
    }
  }

  procs <- vector("list", n_cmds)
  spawn_failures <- vector("list", n_cmds)
  for (i in seq_len(n_cmds)) {
    cmd_vec <- parsed[[i]]$cmd
    env_name_i <- parsed[[i]]$env_name

    if (env_name_i %in% missing_envs) {
      spawn_failures[[i]] <- list(
        status = 127L,
        stderr = sprintf(
          "Conda environment '%s' does not exist.\n",
          env_name_i
        )
      )
      next
    }

    env_dir <- get_env_dir(env_name = env_name_i)

    activation_envvars <- get_activation_envvars(
      env_name = env_name_i,
      env_dir = env_dir,
      tmp_dir = tmp_dir_path
    )

    stdout_i <- if (i == n_cmds) {
      parsed[[i]]$stdout %||% stdout
    } else {
      pipes[[i]][[2L]]
    }
    stderr_i <- parsed[[i]]$stderr %||% stderr

    spawn_result <- tryCatch(
      expr = {
        processx::process$new(
          command = cmd_vec[1L],
          args = cmd_vec[-1L],
          stdin = if (i == 1L) stdin else pipes[[i - 1L]][[1L]],
          stdout = stdout_i,
          stderr = stderr_i,
          env = c("current", activation_envvars),
          supervise = supervise,
          cleanup_tree = cleanup_tree,
          linux_pdeathsig = linux_pdeathsig
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

  for (idx in seq_len(n_cmds - 1L)) {
    close(pipes[[idx]][[1L]])
    close(pipes[[idx]][[2L]])
  }
  rm(pipes)

  if (identical(stdin, "|") && !is.null(procs[[1L]])) {
    if (!is.null(input)) {
      procs[[1L]]$write_input(input)
    }
    if (procs[[1L]]$has_input_connection()) {
      close(procs[[1L]]$get_input_connection())
    }
  }

  timeout_flag <- FALSE
  for (i in seq_len(n_cmds)) {
    proc_i <- procs[[i]]
    if (!is.null(proc_i)) {
      proc_i$wait()
    }
  }

  processes <- vector("list", n_cmds)
  all_statuses <- integer(n_cmds)
  any_failed <- FALSE

  for (i in seq_len(n_cmds)) {
    proc_i <- procs[[i]]
    cmd_vec <- parsed[[i]]$cmd
    env_name_i <- parsed[[i]]$env_name
    cmd_string <- paste(shQuote(cmd_vec), collapse = " ")

    if (!is.null(spawn_failures[[i]])) {
      p_status <- spawn_failures[[i]]$status
      p_stderr <- spawn_failures[[i]]$stderr
      p_stdout <- NA_character_
      p_pid <- NA_integer_
    } else {
      p_stdout <- NA_character_
      if (i == n_cmds && isTRUE(proc_i$has_output_connection())) {
        p_stdout <- proc_i$read_all_output()
        if (is.null(p_stdout)) p_stdout <- ""
      }

      p_stderr <- ""
      if (isTRUE(proc_i$has_error_connection())) {
        p_stderr <- proc_i$read_all_error()
        if (is.null(p_stderr)) {
          p_stderr <- ""
        }
      }

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

    processes[[i]] <- list(
      cmd = cmd_string,
      env_name = env_name_i,
      status = p_status,
      stdout = p_stdout,
      stderr = p_stderr,
      pid = p_pid
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
        if (nzchar(p$stderr)) {
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
        `x` = "Pipeline failed — {sum(all_statuses != 0L, na.rm = TRUE)} command(s) exited with non-zero status",
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
