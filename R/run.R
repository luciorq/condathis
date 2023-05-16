#' Run Command Line tools tools in a Conda environment.
#' @param cmd Main CLI command to be executed in the Conda environment.
#' @param ... Additional arguments used in the command.
#' @param env_name Name of the Conda Environment where the tool is run.
#'   Defaults to 'condathis-env'.
#' @export
run <- function(cmd, ..., env_name = "condathis-env") {
  umamba_bin_path <- micromamba_bin_path()

  withr::local_envvar(list(CONDA_SHLVL = 0))
  # withr::local_envvar(list(CONDARC = paste0(Sys.getenv("HOME"),".config/conda/condarc")))
  px_res <- processx::run(
    command = fs::path_real(umamba_bin_path),
    args = c(
      "run",
      "--clean-env",
      "-n",
      env_name,
      cmd,
      ...
    )
  )
  if (isTRUE(px_res$status == 0)) {
    cat(px_res$stdout)
    invisible(px_res)
  } else(
    return(px_res)
  )
}
