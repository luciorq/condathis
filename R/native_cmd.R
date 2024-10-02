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
                       verbose = TRUE,
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
      MAMBARC = ""
    )
  )
  px_res <- processx::run(
    command = fs::path_real(umamba_bin_path),
    args = c(
      "--no-rc",
      "--no-env",
      # "--log-level", "3",
      conda_cmd,
      conda_args,
      "-r",
      env_root_dir,
      ...
    ),
    spinner = TRUE,
    echo_cmd = verbose,
    echo = verbose,
    stdout = stdout
  )
  return(px_res)
}
