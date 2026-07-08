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
#'     \item A named list with `cmd` (character vector) and `env_name`
#'       (character string, optional) to specify a per-command environment.
#'   }
#' @param stdout Standard output target for the **last** process.
#'   `"|"` (default) captures output in the result. Use a file path to
#'   redirect to a file, or `NULL` to discard.
#' @param stderr Standard error target for **all** processes.
#'   `"|"` (default) captures stderr per-process. Use a file path to
#'   redirect all stderr to a file, or `NULL` to discard.
#' @param stdin Standard input source for the **first** process.
#'   `NULL` (default) discards input. Provide a file path to redirect file
#'   contents as stdin.
#' @param error Character string controlling error behavior.
#'   Supported values are `"cancel"` and `"continue"`.
#'   Defaults to `"cancel"`.
#' @param env_name Character string with the default Conda environment name
#'   for commands that do not specify their own.
#'   Defaults to `"condathis-env"`.
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
#'   create_env("bioconda::samtools", env_name = "samtools-env")
#'   create_env("conda-forge::grep", env_name = "grep-env")
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
  error = c("cancel", "continue"),
  env_name = "condathis-env"
) {
  error <- rlang::arg_match(error)
  error_var <- isTRUE(identical(error, "cancel"))

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

  check_envs_exist(parsed)
  precreate_envs(parsed, tmp_dir_path = tmp_dir_path)

  pipes <- vector("list", max(0L, n_cmds - 1L))
  if (n_cmds > 1L) {
    for (idx in seq_len(n_cmds - 1L)) {
      pipes[[idx]] <- processx::conn_create_pipepair()
    }
  }

  procs <- vector("list", n_cmds)
  for (i in seq_len(n_cmds)) {
    cmd_vec <- parsed[[i]]$cmd
    env_name_i <- parsed[[i]]$env_name
    env_dir <- get_env_dir(env_name = env_name_i)

    activation_envvars <- get_activation_envvars(
      env_name = env_name_i,
      env_dir = env_dir,
      tmp_dir = tmp_dir_path
    )

    procs[[i]] <- processx::process$new(
      command = cmd_vec[1L],
      args = cmd_vec[-1L],
      stdin = if (i == 1L) stdin else pipes[[i - 1L]][[1L]],
      stdout = if (i == n_cmds) stdout else pipes[[i]][[2L]],
      stderr = "|",
      env = c("current", activation_envvars),
      supervise = TRUE,
      cleanup_tree = TRUE
    )
  }

  for (idx in seq_len(n_cmds - 1L)) {
    close(pipes[[idx]][[1L]])
    close(pipes[[idx]][[2L]])
  }
  rm(pipes)

  timeout_flag <- FALSE
  for (i in seq_len(n_cmds)) {
    proc_i <- procs[[i]]
    proc_i$wait()
  }

  processes <- vector("list", n_cmds)
  all_statuses <- integer(n_cmds)
  any_failed <- FALSE

  for (i in seq_len(n_cmds)) {
    proc_i <- procs[[i]]
    cmd_vec <- parsed[[i]]$cmd
    env_name_i <- parsed[[i]]$env_name

    p_stdout <- NA_character_
    if (i == n_cmds) {
      p_stdout <- proc_i$read_all_output()
      if (is.null(p_stdout)) p_stdout <- ""
    }

    p_stderr <- proc_i$read_all_error()
    if (is.null(p_stderr)) {
      p_stderr <- ""
    }

    p_status <- proc_i$get_exit_status()
    if (is.null(p_status)) {
      p_status <- NA_integer_
    }
    p_pid <- proc_i$get_pid()

    all_statuses[i] <- p_status
    if (isTRUE(p_status != 0L) && !is.na(p_status)) {
      any_failed <- TRUE
    }

    cmd_string <- paste(shQuote(cmd_vec), collapse = " ")
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
            p$cmd,
            p$env_name,
            p$status
          )
        )
        if (nzchar(p$stderr)) {
          stderr_lines <- strsplit(p$stderr, "\n")[[1]]
          stderr_lines <- stderr_lines[nzchar(stderr_lines)]
          for (sl in utils::head(stderr_lines, 10L)) {
            failed_lines <- c(failed_lines, sprintf("       %s", sl))
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
      env_name = env_name_i
    )
  }

  return(parsed)
}

check_envs_exist <- function(parsed) {
  env_names <- unique(vapply(parsed, `[[`, character(1L), "env_name"))
  for (env_name_i in env_names) {
    env_dir <- get_env_dir(env_name = env_name_i)
    if (!fs::dir_exists(env_dir)) {
      cli::cli_abort(
        message = c(
          `x` = "Environment {.field {env_name_i}} does not exist.",
          `!` = "Path: {.path {env_dir}}"
        ),
        class = "condathis_pipeline_env_not_found"
      )
    }
  }
}

precreate_envs <- function(parsed, tmp_dir_path) {
  env_names <- unique(vapply(parsed, `[[`, character(1L), "env_name"))
  for (env_name_i in env_names) {
    if (!env_exists(env_name = env_name_i, verbose = FALSE)) {
      if (identical(env_name_i, "condathis-env")) {
        create_base_env(verbose = FALSE)
      } else {
        cli::cli_abort(
          message = c(
            `x` = "Environment {.field {env_name_i}} does not exist.",
            `!` = "Create it with {.fn create_env} first."
          ),
          class = "condathis_pipeline_env_not_found"
        )
      }
    }
  }
}

kill_processes <- function(procs) {
  for (proc_i in procs) {
    if (proc_i$is_alive()) {
      tryCatch(proc_i$kill(), error = function(e) NULL)
    }
  }
}
