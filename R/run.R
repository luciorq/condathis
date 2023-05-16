#' Run Command Line tools tools in a Conda environment.
#' @export
run <- function(cmd, ..., env_name) {
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


list_envs <- function() {
  umamba_bin_path <- micromamba_bin_path()
  processx::run(
    command = fs::path_real(umamba_bin_path),
    args = c(
      "env",
      "list"
    )
  )$stdout |>
    cat()
}



create_env <- function(packages, env_name){
  umamba_bin_path <- micromamba_bin_path()
  processx::run(
    command = fs::path_real(umamba_bin_path),
    args = c(
      "create",
      "-n",
      env_name,
      "--yes",
      "--quiet",
      "-c",
      "bioconda",
      "-c",
      "conda-forge",
      packages
    )
  )$stdout |>
    cat()
}

