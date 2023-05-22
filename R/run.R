
#' Run Command Line tools in a Conda environment.
#'
#' This function allows the execution of command line tools within a specific Conda environment.
#'   It runs the provided cmd command in the designated Conda environment,
#'   using the Micromamba binaries managed by the `condathis` package.
#'
#' @param cmd Character. The main command to be executed in the Conda environment.
#'
#' @param ... Additional arguments to be used in the command. These arguments will be passed directly to the command executed in the Conda environment.
#'   File paths should not contain special character or spaces.
#'
#' @param env_name Character. The name of the Conda environment where the tool will be run. Defaults to 'condathis-env'. If the specified environment does not exist, it will be created automatically using create_env() function from the `condathis` package.
#'
#' @examples
#' ## Run a simple command in the default Conda environment
#' run("ls", "-l")
#'
#' ## Run a command in a specific Conda environment
#' run("python script.py", env_name = "my-conda-env")
#'
#' ## Run a command with additional arguments
#' run("my-command", "--arg1", "--arg2=value", env_name = "my-conda-env")
#' @seealso
#' \code{\link{install_micromamba}}, \code{\link{create_env}}
#' @export
run <- function(cmd, ..., env_name = "condathis-env") {
  umamba_bin_path <- micromamba_bin_path()
  env_root_dir <- get_install_dir()

  if (!any(stringr::str_detect(list_envs(), paste0(env_name, "$")))) {
    create_env(packages = cmd, env_name = env_name)
  }

  withr::local_envvar(list(CONDA_SHLVL = 0))
  # withr::local_envvar(list(CONDARC = paste0(Sys.getenv("HOME"),".config/conda/condarc")))
  px_res <- processx::run(
    command = fs::path_real(umamba_bin_path),
    args = c(
      "run",
      "--clean-env",
      "-r",
      env_root_dir,
      "-n",
      env_name,
      cmd,
      ...
    ),
    spinner = TRUE
  )
  if (isTRUE(px_res$status == 0)) {
    cat(px_res$stdout)
    invisible(px_res)
  } else {
    return(px_res)
  }
}
