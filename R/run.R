#' Run Command-Line Tools in a Conda Environment
#'
#' This function allows the execution of command-line tools within a specified Conda environment.
#' It runs the provided command in the designated Conda environment using the Micromamba binaries managed by the `condathis` package.
#' The function supports multiple execution methods, including native execution, Docker containers, and Singularity containers.
#'
#' @param cmd Character. The main command to be executed in the Conda environment.
#'
#' @param ... Additional arguments to be passed to the command. These arguments will be passed directly to the command executed in the Conda environment.
#'   File paths should not contain special characters or spaces.
#'
#' @param env_name Character. The name of the Conda environment where the tool will be run. Defaults to `"condathis-env"`.
#'   If the specified environment does not exist, it will be created automatically using `create_env()`.
#'
#' @param method Character string. The method to use for running the command. Options are `"native"`, `"auto"`, `"docker"`, or `"singularity"`. Defaults to `"native"`.
#'   If `"auto"` is selected, the function will automatically choose the appropriate method based on the system and available resources.
#' @param container_name Character string. The name of the container to be used when running the command via Docker or Singularity. Defaults to `"condathis-micromamba-base"`.
#' @param image_name Character string. The name of the Docker image to use when the method is `"docker"`. Defaults to `"luciorq/condathis-micromamba:latest"`.
#' @param mount_paths Character vector. Host paths to be mounted in the container. Useful when using Docker or Singularity methods.
#' @param packages Character vector. Additional Conda packages to install in the environment before running the command.
#' @param channels Character vector. Conda channels to use when installing packages. Defaults to `c("bioconda", "conda-forge")`.
#' @param additional_channels Character vector. Additional Conda channels to include when installing packages.
#' @param sif_image_path Character string. The file path to the Singularity image file (`.sif`) to use when the method is `"singularity"`.
#' @param gpu_container Logical. Whether to enable GPU support in the container. Defaults to `FALSE`.
#' @param verbose Logical. Whether to display detailed output messages. Defaults to `FALSE`.
#' @param error Character string. How to handle errors. Options are `"cancel"` or `"continue"`. Defaults to `"cancel"`.
#' @param stdout Character string or `"|"`. Standard output option. Defaults to `"|"`, which keeps stdout in the R object returned by `run()`.
#'   A character string can be used to define a file path to be used as standard output (e.g., `"output.txt"`).
#'
#' @param stdout Default: "|" keep stdout to the R object
#'   returned by `run()`.
#'   A character string can be used to define a file path to be used as standard output. e.g: "output.txt".
#'   
#' @param stdout Default: "|" keep stderr to the R object
#'   returned by `run()`.
#'   A character string can be used to define a file path to be used as standard error. e.g: "error.txt".
#'
#' @return An object of class `list` representing the result of the command execution.
#'   Contains information about the standard output, standard error, and exit status of the command.
#'
#' @details
#' The `run()` function provides a flexible way to execute command-line tools within Conda environments.
#' It leverages Micromamba for environment management and supports execution via native methods or containerization technologies like Docker and Singularity.
#' This is particularly useful for reproducible research and ensuring that specific versions of tools are used.
#'
#' @examples
#' \dontrun{
#' ## Run a simple command in the default Conda environment
#' run("ls", "-l")
#'
#' ## Run a command in a specific Conda environment
#' run("python script.py", env_name = "my-conda-env")
#'
#' ## Run a command with additional arguments
#' run("my-command", "--arg1", "--arg2=value", env_name = "my-conda-env")
#'
#' ## Run a command using Docker
#' run("python script.py", method = "docker")
#'
#' ## Run a command with GPU support in a container
#' run("my-gpu-command", gpu_container = TRUE)
#' }
#' @seealso
#' \code{\link{install_micromamba}}, \code{\link{create_env}}
#'
#' @export
run <- function(cmd,
                ...,
                env_name = "condathis-env",
                method = c(
                  "native",
                  "auto",
                  "docker",
                  "singularity"
                ),
                container_name = "condathis-micromamba-base",
                image_name = "luciorq/condathis-micromamba:latest",
                mount_paths = NULL,
                packages = NULL,
                channels = c(
                  "bioconda",
                  "conda-forge"
                ),
                additional_channels = NULL,
                sif_image_path = NULL,
                gpu_container = FALSE,
                verbose = FALSE,
                error = c("cancel", "continue"),
                stdout = "|",
                stderr = "|") {
  rlang::check_required(cmd)

  if (is.null(cmd)) {
    cli::cli_abort(
      message = c(
        `x` = "{.field cmd} need to be a {.code character} string."
      ),
      class = "condathis_run_null_cmd"
    )
  }


  error <- rlang::arg_match(error)

  method <- rlang::arg_match(method)

  method_to_use <- method

  if (is.null(packages)) {
    packages_to_search <- cmd
  } else {
    packages_to_search <- packages
  }

  if (isTRUE(method_to_use == "auto")) {
    method_to_use <- define_method_to_use(
      packages = packages_to_search,
      channels = channels,
      additional_channels = additional_channels,
      container_name = container_name,
      image_name = image_name,
      sif_image_path = sif_image_path
    )
  }

  if (isTRUE(method_to_use == "native")) {
    px_res <- run_internal_native(
      cmd = cmd,
      ...,
      env_name = env_name,
      verbose = verbose,
      error = error,
      stdout = stdout,
      stderr = stderr
    )
  } else if (isTRUE(method_to_use == "docker")) {
    px_res <- run_internal_docker(
      cmd = cmd,
      ...,
      env_name = env_name,
      container_name = container_name,
      image_name = image_name,
      mount_paths = mount_paths,
      gpu_container = gpu_container,
      verbose = verbose,
      stdout = stdout
    )
  } else if (isTRUE(method_to_use == "singularity")) {
    px_res <- run_internal_singularity(
      cmd = cmd,
      ...,
      env_name = env_name,
      sif_image_path = sif_image_path,
      mount_paths = mount_paths,
      gpu_container = gpu_container,
      verbose = verbose,
      stdout = stdout
    )
  }

  return(invisible(px_res))
}

#' Run Command Using Native Method
#'
#' Internal function to run a command in a Conda environment using the native method.
#'
#' @inheritParams run
run_internal_native <- function(cmd,
                                ...,
                                env_name = "condathis-env",
                                verbose = FALSE,
                                error = c("cancel", "continue"),
                                stdout = "|",
                                stderr = "|") {
  if (isTRUE(base::Sys.info()["sysname"] == "Windows")) {
    micromamba_bat_path <- fs::path(get_install_dir(), "condabin", "micromamba", ext = "bat")
    if (isFALSE(fs::file_exists(micromamba_bat_path))) {
      catch_res <- rlang::catch_cnd(
        expr = {
          native_cmd(
            conda_cmd = "run",
            conda_args = c("-n", "condathis-env"),
            cmd = "dir", verbose = FALSE, stdout = NULL
          )
        }
      )
      mamba_bat_path <- fs::path(get_install_dir(), "condabin", "mamba", ext = "bat")
      if (isTRUE(fs::file_exists(mamba_bat_path)) &&
        isFALSE(fs::file_exists(micromamba_bat_path))) {
        fs::file_copy(mamba_bat_path, micromamba_bat_path, overwrite = TRUE)
      }
    }
  }
  px_res <- native_cmd(
    conda_cmd = "run",
    conda_args = c(
      "-n",
      env_name
    ),
    cmd = cmd,
    ...,
    verbose = verbose,
    error = error,
    stdout = stdout,
    stderr = stderr
  )
  return(invisible(px_res))
}

#' Run Command Using Docker
#'
#' Internal function to run a command in a Conda environment using Docker.
#'
#' @inheritParams run
run_internal_docker <- function(cmd,
                                ...,
                                env_name = "condathis-env",
                                container_name = "condathis-micromamba-base",
                                image_name = "luciorq/condathis-micromamba:latest",
                                mount_paths = NULL,
                                gpu_container = FALSE,
                                verbose = TRUE,
                                stdout = "|") {
  stop_if_not_installed("dockerthis")
  env_root_dir <- get_install_dir()
  env_root_dir <- fs::path(paste0(env_root_dir, "-docker"))
  user_arg <- format_user_arg_string()
  if (isTRUE(gpu_container)) {
    gpu_args <- c("--gpus", "all")
  } else {
    gpu_args <- NULL
  }
  px_res <- dockerthis::docker_run(
    "micromamba",
    "--no-env",
    "--no-rc",
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
      paste0("--workdir=", fs::path_wd()),
      "--platform=linux/amd64",
      user_arg,
      "--rm",
      gpu_args
    ),
    mount_paths = c(
      env_root_dir,
      fs::path_wd(),
      mount_paths
    )
  )
  return(invisible(px_res))
}

#' Run Command Using Singularity
#'
#' Internal function to run a command in a Conda environment using Singularity.
#'
#' @inheritParams run
run_internal_singularity <- function(cmd,
                                     ...,
                                     env_name = "condathis-env",
                                     sif_image_path = NULL,
                                     mount_paths = NULL,
                                     gpu_container = FALSE,
                                     verbose = FALSE,
                                     stdout = "|") {
  invisible(is_singularity_available())
  env_root_dir <- get_install_dir()
  env_root_dir <- fs::path(paste0(env_root_dir, "-docker"))
  if (isFALSE(fs::dir_exists(env_root_dir))) {
    fs::dir_create(env_root_dir)
    fs::dir_create(env_root_dir, "home")
  }
  sif_dir <- fs::path(env_root_dir, "sif")
  if (isFALSE(fs::dir_exists(sif_dir))) {
    fs::dir_create(sif_dir)
  }
  if (is.null(sif_image_path)) {
    sif_image_path <- fs::path(sif_dir, "condathis-micromamba", ext = "sif")
  }
  if (isTRUE(sif_image_path == fs::path(sif_dir, "condathis-micromamba", ext = "sif"))) {
    if (isFALSE(fs::file_exists(sif_image_path))) {
      build_container_image_singularity()
    }
  }
  mount_path_arg <- c()
  if (isFALSE(is.null(mount_paths))) {
    for (mount_path in mount_paths) {
      if (isTRUE(stringr::str_detect(mount_path, pattern = ":"))) {
        mount_temp_vec <- unlist(stringr::str_split(mount_path, pattern = ":"))
        if (isFALSE(fs::dir_exists(mount_temp_vec[1]))) {
          cli::cli_abort(
            message = c(
              `x` = "{.path {mount_temp_vec[1]}} do not exist."
            ),
            class = "condathis_run_singularity_missing_mount_path"
          )
        }
        mount_path_abs <- fs::path_abs(mount_temp_vec[1])
        mount_path_target <- fs::path_abs(mount_temp_vec[2])
      } else {
        if (isFALSE(fs::dir_exists(mount_path))) {
          cli::cli_abort(
            message = c(
              `x` = "{.path {mount_path}} do not exist."
            ),
            class = "condathis_run_singularity_missing_mount_path"
          )
        }
        mount_path_abs <- fs::path_abs(mount_path)
        mount_path_target <- mount_path_abs
      }
      mount_path_arg <- c(
        mount_path_arg,
        "--bind",
        paste0(mount_path_abs, ":", mount_path_target)
      )
    }
  }
  if (isTRUE(gpu_container)) {
    gpu_args <- "--nv"
  } else {
    gpu_args <- NULL
  }
  px_res <- singularity_cmd(
    "exec",
    gpu_args,
    "-e",
    "-H",
    paste0(env_root_dir, "/home"),
    "-W",
    fs::path_wd(),
    mount_path_arg,
    sif_image_path,
    "micromamba",
    "--no-env",
    "--no-rc",
    "run",
    "-r",
    env_root_dir,
    "-n",
    env_name,
    # "--quiet",
    cmd,
    ...
  )
  return(invisible(px_res))
}
