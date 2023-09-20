#' Run Micromamba Command
#'
#' Run a command using micromamba executable in the native backend.
#'
#' @inheritParams run
#'
#' @export
native_cmd <- function(conda_cmd,
                       conda_args = NULL,
                       ...,
                       verbose = TRUE,
                       stdout = "|") {
  umamba_bin_path <- micromamba_bin_path()
  env_root_dir <- get_install_dir()
  withr::local_envvar(
    .new = list(
      CONDA_SHLVL = 0
      # CONDA_ENVS_PATH = "",
      # CONDA_ROOT_PREFIX = "",
      # MAMBA_ENVS_PATH = "",
      # MAMBA_ROOT_PREFIX = "",
      # CONDARC = ""
    )
  )
  # withr::local_envvar(list(CONDARC = fs::path(Sys.getenv("HOME"),".config","conda", "condarc")))
  px_res <- processx::run(
    command = fs::path_real(umamba_bin_path),
    args = c(
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
}
