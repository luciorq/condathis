
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
#' @inheritParams create_env
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
run <- function(cmd,
                ...,
                env_name = "condathis-env",
                method = "auto",
                container_name = "condathis-micromamba-base",
                image_name = "luciorq/condathis-micromamba:latest",
                mount_paths = NULL) {
  method_to_use <- method[1]
  if (method_to_use == "auto") {
    cli::cli_inform(c(
      `!` = "{.code method = \"auto\"} is not implemented yet.",
      `v` = "Using {.code method = \"native\"} instead."
    ))
    method_to_use <- "native"
  }
  if (isTRUE(method_to_use == "native")) {
    px_res <- run_internal_native(
      cmd = cmd, ..., env_name = env_name
    )
  } else if (isTRUE(method_to_use == "docker")) {
    px_res <- run_internal_docker(
      cmd = cmd, ..., env_name = env_name
    )
  } else if (isTRUE(method_to_use == "singularity")) {
    cli::cli_abort(c(
      `x` = "Method {.code \"singularity\"} is not implemented yet."
    ))
  }
  return(invisible(px_res))
}

#' @inheritParams run
run_internal_native <- function(cmd,
                                ...,
                                env_name = "condathis-env") {
  umamba_bin_path <- micromamba_bin_path()
  env_root_dir <- get_install_dir()

  # if (!any(stringr::str_detect(list_envs(), paste0(env_name, "$")))) {
  #  create_env(packages = cmd, env_name = env_name)
  # }

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
  return(invisible(px_res))
}

#' @inheritParams run
run_internal_docker <- function(cmd,
                                ...,
                                env_name = "condathis-env",
                                container_name = "condathis-micromamba-base",
                                image_name = "luciorq/condathis-micromamba:latest",
                                mount_paths = NULL
                                ) {
  stop_if_not_installed("dockerthis")
  env_root_dir <- get_install_dir()
  env_root_dir <- fs::path(paste0(env_root_dir, "-docker"))
  user_arg <- format_user_arg_string()
  px_res <- dockerthis::docker_run(
    "micromamba",
    "run",
    "-r",
    env_root_dir,
    "-n",
    env_name,
    # "--quiet",
    cmd,
    ...,
    container_name = container_name,
    image_name = image_name,
    docker_args = c(
      "-e",
      paste0("HOME=", env_root_dir, "/home"),
      "--platform=linux/amd64",
      user_arg,
      "--rm"
    ),
    mount_paths = c(
      env_root_dir,
      mount_paths
    )
  )
  return(invisible(px_res))
}
