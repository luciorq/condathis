#' Run a binary without environment activation
#'
#' Executes a binary using files from a target Conda environment, but without
#' running environment activation scripts.
#' This is a lower-level execution mode than `run()`.
#'
#' @param cmd Character string with the command to execute.
#' @param ... Additional unnamed command arguments passed to `cmd`.
#' @param env_name Character string with the target environment name.
#'   Defaults to `"condathis-env"`.
#' @param verbose Character string controlling console output.
#'   Supported values are `"output"`, `"silent"`, `"cmd"`, `"spinner"`,
#'   and `"full"`. Defaults to `"output"`.
#' @param error Character string that controls error behavior.
#'   Supported values are `"cancel"` and `"continue"`.
#'   Defaults to `"cancel"`.
#' @param stdout Standard output target.
#'   Defaults to `"|"` (capture stdout in the returned object).
#'   Provide a file path to redirect stdout to a file.
#' @param stderr Standard error target.
#'   Defaults to `"|"` (capture stderr in the returned object).
#'   Provide a file path to redirect stderr to a file.
#' @param stdin Standard input source.
#'   Defaults to `NULL` (no stdin stream).
#'   Provide a file path to use file contents as stdin, or `"|"` to write
#'   `input` to the process.
#' @param input Character or raw vector written to the process's standard
#'   input when `stdin = "|"`. Defaults to `NULL`. Ignored (and must not be
#'   set) when `stdin` is not `"|"`. Note: live stdout/stderr echoing,
#'   spinner, and timeout are not available when `input` triggers the
#'   writable-stdin code path.
#' @param supervise Logical. Whether the process should be supervised by the
#'   `processx` supervisor for crash-safe cleanup. Defaults to `FALSE`.
#' @param cleanup_tree Logical. Whether to clean up the child process tree
#'   on crash/interrupt. Defaults to `FALSE`.
#' @param linux_pdeathsig Logical. On Linux, whether to send `SIGKILL` to the
#'   child process if the parent R process dies. Has no effect on other
#'   platforms. Defaults to `FALSE`.
#'
#' @returns A `condathis_result` S3 object (a classed list, still usable as
#'   a plain list) with `status`, `stdout`, `stderr`, `timeout`, `pid`,
#'   `cmd`, and `env_name`.
#'
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   # Example assumes that 'my-env' exists and contains 'python'
#'   # Run 'python' with a script in 'my-env' environment
#'   condathis::run_bin(
#'     "python", "-c", "import sys; print(sys.version)",
#'     env_name = "my-env"
#'   )
#'
#'   # Run 'ls' command with additional arguments
#'   condathis::run_bin("ls", "-la", env_name = "my-env")
#' })
#' }
#'
#' @export
run_bin <- function(
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
  supervise = FALSE,
  cleanup_tree = FALSE,
  linux_pdeathsig = FALSE
) {
  error <- rlang::arg_match(error)
  if (identical(error, "cancel")) {
    error_var <- TRUE
  } else {
    error_var <- FALSE
  }

  rlang::check_dots_unnamed()

  if (!is.null(input) && !identical(stdin, "|")) {
    cli::cli_abort(
      message = c(
        `x` = "{.field input} can only be used when {.field stdin} is {.val {\"|\"}}."
      ),
      class = "condathis_run_invalid_input"
    )
  }

  verbose_list <- parse_strategy_verbose(verbose = verbose)

  verbose_output <- verbose_list$output
  if (isFALSE(stderr %in% c("|", ""))) {
    verbose_output <- FALSE
  }

  env_dir <- get_env_dir(env_name = env_name)
  cmd_path <- fs::path(env_dir, "bin", cmd)

  if (
    isFALSE(fs::file_exists(cmd_path)) &&
      isTRUE(fs::file_exists(Sys.which(cmd)))
  ) {
    cmd_path <- normalizePath(Sys.which(cmd), mustWork = FALSE)
  }
  tmp_dir_path <- withr::local_tempdir(pattern = "condathis-tmp")
  withr::local_envvar(
    .new = get_clean_conda_envvars(tmp_dir = tmp_dir_path)
  )
  withr::local_path(
    new = list(fs::path(env_dir, "bin")),
    action = "prefix"
  )
  args_vector <- c(...)
  if (isTRUE(rlang::is_null(args_vector))) {
    args_vector <- character(length = 0L)
  }
  px_res <- rethrow_error_run(
    expr = {
      if (identical(stdin, "|")) {
        run_process_with_input(
          command = cmd_path,
          args = args_vector,
          input = input,
          stdout = stdout,
          stderr = stderr,
          echo_cmd = verbose_list$cmd,
          echo = verbose_output,
          error_on_status = error_var,
          cleanup_tree = cleanup_tree,
          supervise = supervise,
          linux_pdeathsig = linux_pdeathsig
        )
      } else {
        processx::run(
          command = cmd_path,
          args = args_vector,
          spinner = verbose_list$spinner_flag,
          echo_cmd = verbose_list$cmd,
          echo = verbose_output,
          stdout = stdout,
          stderr = stderr,
          stdin = stdin,
          error_on_status = error_var,
          cleanup_tree = cleanup_tree,
          supervise = supervise,
          linux_pdeathsig = linux_pdeathsig
        )
      }
    }
  )

  cmd_string <- paste(
    shQuote(as.character(c(cmd, args_vector))),
    collapse = " "
  )
  result <- new_condathis_result(
    status = px_res$status,
    stdout = px_res$stdout,
    stderr = px_res$stderr,
    timeout = if (is.null(px_res$timeout)) FALSE else px_res$timeout,
    pid = if (is.null(px_res$pid)) NA_integer_ else px_res$pid,
    cmd = cmd_string,
    env_name = env_name
  )
  return(invisible(result))
}
