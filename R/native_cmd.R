#' Run Micromamba Command
#'
#' Run a command using micromamba executable in the native backend.
#'
#' @param conda_cmd Character. Conda subcommand to be run.
#'   E.g. "create", "install", "env", "--help", "--version".
#'
#' @param conda_args Character vector. Additional arguments passed to
#'   the Conda command.
#'
#' @inheritParams run
#'
#' @keywords internal
#' @noRd
native_cmd <- function(conda_cmd,
                       conda_args = NULL,
                       ...,
                       verbose = "full",
                       error = c("cancel", "continue"),
                       stdout = "|",
                       stderr = "|") {
  rlang::check_required(conda_cmd)
  error <- rlang::arg_match(error)
  if (isTRUE(identical(error, "cancel"))) {
    error_var <- TRUE
  } else {
    error_var <- FALSE
  }

  umamba_bin_path <- micromamba_bin_path()
  env_root_dir <- get_install_dir()

  if (isFALSE(fs::file_exists(umamba_bin_path))) {
    install_micromamba(force = TRUE)
  }
  umamba_bin_path <- base::normalizePath(umamba_bin_path, mustWork = FALSE)
  tmp_dir_path <- withr::local_tempdir(pattern = "mamba-tmp")
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
      `CONDA_PKGS_DIRS` = "",
      `MAMBA_PKGS_DIRS` = "",
      `R_HOME` = ""
    )
  )
  verbose_list <- parse_strategy_verbose(strategy = verbose)
  verbose_cmd <- verbose_list$cmd
  verbose_output <- verbose_list$output
  spinner_flag <- rlang::is_interactive()

  if (isFALSE(stderr %in% c("|", ""))) {
    verbose_output <- FALSE
  }
  callback_fun_out <- NULL
  callback_fun_err <- NULL
  px_res <- processx::run(
    command = fs::path_real(umamba_bin_path),
    args = c(
      "--no-rc",
      "--no-env",
      conda_cmd,
      "-r",
      env_root_dir,
      conda_args,
      ...
    ),
    spinner = spinner_flag,
    echo_cmd = verbose_cmd,
    echo = verbose_output,
    stdout = stdout,
    stdout_line_callback = callback_fun_out,
    stderr = stderr,
    stderr_line_callback = callback_fun_err,
    error_on_status = error_var
  )
  return(invisible(px_res))
}
