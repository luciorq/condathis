#' Get Clean Conda/Mamba Environment Variables
#'
#' Returns a named list of Conda and Mamba environment variables set to empty
#' strings (or specific values) to ensure isolation from any existing conda
#' installation. Used by [run_bin()] and [run()] (actually, any command
#' calling `native_cmd()`), via `withr::local_envvar()`.
#'
#' Key isolation decisions:
#' - `R_HOME = ""` prevents conda-installed R from conflicting with the
#'   host R session.
#' - `CONDA_SHLVL`/`MAMBA_SHLVL` reset to `"0"` to prevent shell-level
#'   confusion.
#' - All prefix/path/rc variables cleared to avoid interference from
#'   the user's conda configuration.
#'
#' @param tmp_dir Character string. Path for `TMPDIR`. Must be provided.
#' @param envs_dir Character string. Path to set for `CONDA_ENVS_PATH`.
#'   Defaults to `NULL` (set to empty string). When provided (e.g., by
#'   `native_cmd()`), `CONDA_ENVS_PATH` is set to this value.
#'
#' @returns A named list suitable for passing to `withr::local_envvar()`.
#'
#' @keywords internal
#' @noRd
get_clean_conda_envvars <- function(tmp_dir, envs_dir = NULL) {
  envvar_list <- list(
    `TMPDIR` = tmp_dir,
    `CONDA_SHLVL` = "0",
    `MAMBA_SHLVL` = "0",
    `CONDA_ENVS_PATH` = envs_dir %||% "",
    `CONDA_ENVS_DIRS` = NULL,
    `CONDA_ROOT_PREFIX` = "",
    `CONDA_PREFIX` = "",
    `MAMBA_ENVS_PATH` = "",
    `MAMBA_ENVS_DIRS` = "",
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
  return(envvar_list)
}
