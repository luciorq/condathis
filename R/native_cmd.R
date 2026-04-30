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
native_cmd <- function(
  conda_cmd,
  conda_args = NULL,
  ...,
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
  rlang::check_required(conda_cmd)

  error <- rlang::arg_match(error)
  if (isTRUE(identical(error, "cancel"))) {
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

  # Try to find a valid micromamba from any known location
  umamba_bin_path <- get_best_micromamba_path()

  if (is.null(umamba_bin_path)) {
    # No valid micromamba found anywhere — install to internal path
    install_micromamba(force = TRUE, verbose = verbose_list$internal_verbose)
    umamba_bin_path <- micromamba_bin_path()
  }

  env_root_dir <- get_install_dir()
  env_envs_dir <- fs::path(env_root_dir, "envs")
  umamba_bin_path <- base::normalizePath(umamba_bin_path, mustWork = FALSE)
  tmp_dir_path <- withr::local_tempdir(pattern = "mamba-tmp")
  withr::local_envvar(
    .new = get_clean_conda_envvars(
      tmp_dir = tmp_dir_path,
      envs_dir = env_envs_dir
    )
  )

  callback_fun_out <- NULL
  callback_fun_err <- NULL

  px_res <- processx::run(
    command = fs::path_real(umamba_bin_path),
    args = c(
      "--no-rc",
      "--no-env",
      "-r",
      env_root_dir,
      conda_cmd,
      conda_args,
      ...
    ),
    spinner = verbose_list$spinner_flag,
    echo_cmd = verbose_list$cmd,
    echo = verbose_output,
    stdout = stdout,
    stdout_line_callback = callback_fun_out,
    stderr = stderr,
    stderr_line_callback = callback_fun_err,
    stdin = stdin,
    error_on_status = error_var
  )

  return(invisible(px_res))
}
