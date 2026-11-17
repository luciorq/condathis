#' Build activation environment variables for a Conda environment
#'
#' The fixed activation of `run()`, `run_bin()` and `run_pipeline()` with
#' `activate = FALSE`: the variables that activate one Conda environment,
#' computed by `condathis` without any backend function, and without the
#' `activate.d` scripts and `env_vars.d` files of its packages. They set
#' `CONDA_PREFIX`, `CONDA_DEFAULT_ENV`, `CONDA_SHLVL` and `MAMBA_SHLVL`
#' (both `"1"`), empty prompt modifiers (see
#' `child_activation_level_vars()`), and `PATH`: the environment's binary
#' directories in front of `base_path`.
#'
#' `TMPDIR` and `CONDA_ENVS_PATH` are not set here. They come from the
#' clean overlay of `build_child_env()` (see `child_conda_dirs()`), so a
#' command gets the same values with `activate = TRUE` and
#' `activate = FALSE`.
#'
#' @param env_name Character string with the Conda environment name, or the
#'   directory of an environment given by `env_path()`.
#' @param env_dir Character string with the absolute path to the environment
#'   directory.
#' @param base_path Character string, the `PATH` of `base_env`, which has
#'   no binary directory of the R session's own environments (see
#'   `isolate_host_env()`). Defaults to `isolated_session_path()`.
#'
#' @returns A named character vector, for the `overlay` argument of
#'   `build_child_env()` or `apply_child_overlay()`.
#'
#' @keywords internal
#' @noRd
get_activation_envvars <- function(
  env_name,
  env_dir,
  base_path = isolated_session_path()
) {
  # `env_bin_search_dirs()`, not a hardcoded `<env_dir>/bin` plus `":"`:
  # Windows Conda environments place binaries across `<env_dir>`,
  # `Scripts/`, `Library/bin/` and other directories, and the Windows PATH
  # separator differs from POSIX. `prepend_path_dirs()` keeps one copy of
  # each directory, however `base_path` spells it.
  envvar_vec <- c(
    CONDA_PREFIX = as.character(env_dir),
    CONDA_DEFAULT_ENV = as.character(env_name),
    child_activation_level_vars(),
    PATH = prepend_path_dirs(
      env_bin_search_dirs(env_dir),
      base_path %||% ""
    )
  )
  return(envvar_vec)
}

#' The activation level of every command of the run family
#'
#' A command of `run()`, `run_bin()` and `run_pipeline()` runs in exactly
#' one activated environment, whatever the R session runs in, in both
#' `activate` modes and for every backend (see `compose_child_env()`):
#' `CONDA_SHLVL` and `MAMBA_SHLVL` are both `"1"`, as after one
#' `conda activate`, so a `conda deactivate` or `conda activate` in the
#' command starts from that one level, never from a level of the R
#' session. The prompt modifiers are empty: a shell that the command
#' starts shows no name of an environment, neither the command's nor one
#' of the R session.
#'
#' `micromamba` itself, which runs in no environment, gets the values of
#' `get_clean_conda_envvars()`: `"0"` and `""`.
#'
#' @returns A named character vector.
#'
#' @keywords internal
#' @noRd
child_activation_level_vars <- function() {
  return(c(
    CONDA_SHLVL = "1",
    MAMBA_SHLVL = "1",
    CONDA_PROMPT_MODIFIER = "",
    MAMBA_PROMPT_MODIFIER = ""
  ))
}
