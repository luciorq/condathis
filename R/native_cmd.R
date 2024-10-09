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
native_cmd <- function(conda_cmd,
                       conda_args = NULL,
                       ...,
                       verbose = FALSE,
                       stdout = "|") {
  umamba_bin_path <- micromamba_bin_path()
  env_root_dir <- get_install_dir()
  if (isFALSE(fs::file_exists(umamba_bin_path))) {
    install_micromamba(force = TRUE)
  }
  withr::local_envvar(
    .new = list(
      CONDA_SHLVL = 0,
      MAMBA_SHLVL = 0,
      CONDA_ENVS_PATH = "",
      CONDA_ROOT_PREFIX = "",
      CONDA_PREFIX = "",
      MAMBA_ENVS_PATH = "",
      MAMBA_ROOT_PREFIX = "",
      MAMBA_PREFIX = "",
      CONDARC = "",
      MAMBARC = "",
      CONDA_PROMPT_MODIFIER = "",
      MAMBA_PROMPT_MODIFIER = "",
      CONDA_DEFAULT_ENV = "",
      MAMBA_DEFAULT_ENV = ""
    )
  )
  px_res <- processx::run(
    command = fs::path_real(umamba_bin_path),
    args = c(
      "--no-rc",
      "--no-env",
      # "--log-level", "3",
      conda_cmd,
      "-r",
      env_root_dir,
      conda_args,
      ...
    ),
    spinner = TRUE,
    echo_cmd = verbose,
    echo = verbose,
    stdout = stdout
    # error_on_status = FALSE
  )
  return(px_res)
}
