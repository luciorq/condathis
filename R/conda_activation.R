#' Build activation environment variables for a Conda environment
#'
#' Returns a named list of Conda environment variables that activate a specific
#' Conda environment. These overlay the clean base envvars from
#' `get_clean_conda_envvars()` to set `CONDA_PREFIX`, `CONDA_DEFAULT_ENV`,
#' `CONDA_SHLVL`, `PATH`, and related variables for a single environment.
#'
#' @param env_name Character string with the Conda environment name.
#' @param env_dir Character string with the absolute path to the environment
#'   directory.
#' @param tmp_dir Character string path used for `TMPDIR`.
#'
#' @returns A named list suitable for passing as environment overrides to
#'   `processx::process$new(env = c("current", ...))`.
#'
#' @keywords internal
#' @noRd
get_activation_envvars <- function(env_name, env_dir, tmp_dir) {
  env_bin_dir <- fs::path(env_dir, "bin")
  envvar_vec <- c(
    CONDA_PREFIX = env_dir,
    CONDA_DEFAULT_ENV = env_name,
    CONDA_SHLVL = "1",
    MAMBA_SHLVL = "1",
    CONDA_PROMPT_MODIFIER = paste0("(", env_name, ") "),
    MAMBA_PROMPT_MODIFIER = paste0("(", env_name, ") "),
    CONDA_ENVS_PATH = fs::path_dir(env_dir),
    TMPDIR = tmp_dir,
    PATH = paste(env_bin_dir, Sys.getenv("PATH"), sep = ":")
  )
  return(envvar_vec)
}
