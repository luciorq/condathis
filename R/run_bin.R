#' Run a Binary from a Conda Environment Without Environment Activation
#'
#' Executes a binary command from a specified Conda environment without
#' activating the environment or using its environment variables.
#' This function temporarily clears Conda and Mamba-related environment
#' variables to prevent interference, ensuring that the command runs in a clean
#' environment.
#' Usually this is not what the user wants as this mode of execution does not
#' load environment variables and scripts defined in the environment
#' `activate.d`, check [run()] for the stable function to use.
#'
#' @inheritParams run
#'
#' @return An object of class `list` representing the result of the command
#'   execution. Contains information about the standard output, standard error,
#'   and exit status of the command.
#'
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   # Example assumes that 'my-env' exists and contains 'python'
#'   # Run 'python' with a script in 'my-env' environment
#'   condathis::run_bin(
#'     "python", "-c", "import sys; print(sys.version)",
#'     env_name = "my-env",
#'     verbose = "output"
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
    verbose = "silent",
    error = c("cancel", "continue"),
    stdout = "|",
    stderr = "|") {
  error <- rlang::arg_match(error)
  if (isTRUE(identical(error, "cancel"))) {
    error_var <- TRUE
  } else {
    error_var <- FALSE
  }

  verbose_list <- parse_strategy_verbose(strategy = verbose)
  verbose_cmd <- verbose_list$cmd
  verbose_output <- verbose_list$output
  spinner_flag <- rlang::is_interactive()

  env_dir <- get_env_dir(env_name = env_name)
  cmd_path <- fs::path(env_dir, "bin", cmd)

  if (isFALSE(fs::file_exists(cmd_path)) && isTRUE(fs::file_exists(Sys.which(cmd)))) {
    cmd_path <- normalizePath(Sys.which(cmd), mustWork = FALSE)
  }
  tmp_dir_path <- withr::local_tempdir(pattern = "condathis-tmp")
  withr::local_envvar(
    .new = list(
      `TMPDIR` = tmp_dir_path,
      `CONDA_SHLVL` = "0",
      `MAMBA_SHLVL` = "0",
      `CONDA_ENVS_PATH` = "",
      `CONDA_ROOT_PREFIX` = "",
      `CONDA_PREFIX` = "",
      `MAMBA_ENVS_PATH` = "",
      `MAMBA_ROOT_PREFIX` = "",
      `MAMBA_PREFIX` = "",
      `CONDARC` = "",
      `MAMBARC` = "",
      `CONDA_PROMPT_MODIFIER` = "",
      `MAMBA_PROMPT_MODIFIER` = "",
      `CONDA_DEFAULT_ENV` = "",
      `MAMBA_DEFAULT_ENV` = "",
      `R_HOME` = ""
    )
  )
  withr::local_path(
    new = list(fs::path(env_dir, "bin")),
    action = "prefix"
  )
  args_vector <- c(...)
  if (isTRUE(is.null(args_vector))) {
    args_vector <- character(length = 0L)
  }

  px_res <- rethrow_error_run(
    expr = {
      processx::run(
        command = cmd_path,
        args = args_vector,
        spinner = spinner_flag,
        echo_cmd = verbose_cmd,
        echo = verbose_output,
        stdout = stdout,
        stderr = stderr,
        error_on_status = error_var
      )
    }
  )

  return(invisible(px_res))
}
