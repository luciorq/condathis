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
#'   Provide a file path to use file contents as stdin.
#'
#' @returns A process result list (from `processx::run()`) with command output,
#'   error output, exit status, and timeout information.
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
  stdin = NULL
) {
  error <- rlang::arg_match(error)
  if (identical(error, "cancel")) {
    error_var <- TRUE
  } else {
    error_var <- FALSE
  }

  rlang::check_dots_unnamed()

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
      processx::run(
        command = cmd_path,
        args = args_vector,
        spinner = verbose_list$spinner_flag,
        echo_cmd = verbose_list$cmd,
        echo = verbose_output,
        stdout = stdout,
        stderr = stderr,
        stdin = stdin,
        error_on_status = error_var
      )
    }
  )
  return(invisible(px_res))
}
