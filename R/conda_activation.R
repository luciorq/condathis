#' Build activation environment variables for a Conda environment
#'
#' The fixed activation of `run_pipeline(activate = FALSE)`: the variables
#' that activate one Conda environment, without its `activate.d` scripts.
#' They set `CONDA_PREFIX`, `CONDA_DEFAULT_ENV`, `CONDA_SHLVL`, `PATH` and
#' related variables.
#'
#' `CONDA_ENVS_PATH` is not set here. It comes from the clean overlay of
#' `build_child_env()` (see `child_conda_dirs()`), so a pipeline stage gets
#' the same value with `activate = TRUE` and `activate = FALSE`, and as a
#' command of `run()` or `run_bin()`.
#'
#' @param env_name Character string with the Conda environment name, or the
#'   directory of an environment given by `env_path()`.
#' @param env_dir Character string with the absolute path to the environment
#'   directory.
#' @param tmp_dir Character string path used for `TMPDIR`.
#'
#' @returns A named character vector, for the `overlay` argument of
#'   `build_child_env()`.
#'
#' @keywords internal
#' @noRd
get_activation_envvars <- function(env_name, env_dir, tmp_dir) {
  # Use `env_bin_search_dirs()` and `compose_path()`, not a hardcoded
  # `<env_dir>/bin` plus `":"`. Windows conda environments place binaries
  # across `<env_dir>`, `Scripts/`, `Library/bin/` and other directories, and
  # the Windows PATH separator differs from POSIX.
  envvar_vec <- c(
    CONDA_PREFIX = env_dir,
    CONDA_DEFAULT_ENV = env_name,
    CONDA_SHLVL = "1",
    MAMBA_SHLVL = "1",
    CONDA_PROMPT_MODIFIER = paste0("(", env_name, ") "),
    MAMBA_PROMPT_MODIFIER = paste0("(", env_name, ") "),
    TMPDIR = tmp_dir,
    PATH = compose_path(
      env_bin_search_dirs(env_dir),
      Sys.getenv("PATH")
    )
  )
  return(envvar_vec)
}
