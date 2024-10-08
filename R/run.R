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
#' @param stdout Default: "|" keep stdout to the R object
#'   returned by `run()`.
#'   A character string can be used to define a file path to be used as standard output. e.g: "output.txt".
#'
#' @param mount_paths Character vector. Host paths to be mounted in container.
#'
#' @inheritParams create_env
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
                stdout = "|") {
  if (is.null(cmd)) {
    cli::cli_abort(
      message = c(
        `x` = "{.field cmd} need to be a {.code character} string."
      ),
      class = "condathis_run_null_cmd"
    )
  }

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
      verbose = verbose,
      stdout = stdout,
      env_name = env_name
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

#' @inheritParams run
run_internal_native <- function(cmd,
                                ...,
                                env_name = "condathis-env",
                                verbose = FALSE,
                                stdout = "|") {
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
    stdout = stdout
  )
  return(invisible(px_res))
}

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
