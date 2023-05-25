#' Stop execution if `dockerthis` package is not installed.
#' @param pkg_name Character. Name of the R package to check.
stop_if_not_installed <- function(pkg_name = "dockerthis") {
  if (!requireNamespace(pkg_name, quietly = TRUE)) {
    cli::cli_abort(c(
      `x` = "{.pkg {pkg_name}} is not installed.",
      `!` = "Install from GitHub using {.code remotes::install_github(\"luciorq/{pkg_name}\")}."
    ))
  }
}

#' Build Micromamba Container Image
#' @param dockerfile_path Character. Path to Dockerfile.
#'
#' @param image_name Character. Image name used for the contanier image.
#'   Defaults to `"condathis-micromamba:latest"`.
#'
#' @param force Logical. Should image be removed before building.
#'   Defaults to FALSE.
#'
#' @param method Character. One of `c("docker", "singularity")`.
#'
#' @export
build_micromamba_image <- function(dockerfile_path = NULL,
                                   image_name = "luciorq/condathis-micromamba:latest",
                                   force = FALSE,
                                   method = "docker") {
  if (isTRUE(method == "docker")) {
    stop_if_not_installed("dockerthis")
    if (is.null(dockerfile_path)) {
      dockerfile_path <- fs::path_package(
        "dockerthis", "dockerfiles", "micromamba", ext = "dockerfile"
      )
    }
    px_res <- dockerthis::docker_build_image(
      dockerfile_path = dockerfile_path,
      image_name = image_name,
      force = FALSE,
      platform_arg = "linux/amd64"
    )
  } else if (isTRUE(method == "singularity")) {
    px_res <- build_micromamba_image_singularity(
      image_name = image_name,
      registry_name = "docker"
    )
  }

  return(invisible(px_res))
}

#' Build Singularity / Apptainer Image
#' @param image_name Character. Image name used for the container image,
#'  containing the remote repository, separated by forward slash.
#'   Defaults to `"luciorq/condathis-micromamba:latest"`.
#' @param registry_name Character. Container Registry where image already
#'   exists. Defaults to `"docker"` (Docker Hub).
build_micromamba_image_singularity <- function(image_name = "luciorq/condathis-micromamba:latest",
                                               registry_name = "docker") {
  # singularity build img.sif docker://luciorq/condathis-micromamba:latest
  invisible(is_singularity_available())
  env_root_dir <- get_install_dir()
  env_root_dir <- fs::path(paste0(env_root_dir, "-docker"))
  sif_dir <- fs::path(env_root_dir, "sif")
  if (!fs::dir_exists(sif_dir)) {
    fs::dir_create(sif_dir)
  }
  sif_image_path <- fs::path(sif_dir, "condathis-micromamba", ext = "sif")
  remote_image_path <- paste0(registry_name, "://", image_name)
  px_res <- singularity_cmd(
    "build",
    sif_image_path,
    remote_image_path
  )
  return(invisible(px_res))
}

#' Are Singularity or Apptainer CLIs available
#'
#' Test if Singularity or Apptainer CLIs are available on PATH.
#'
is_singularity_available <- function() {
  # TODO(luciorq): Add support for `apptainer`
  # + from: <https://github.com/apptainer/apptainer>
  singularity_bin_path <- Sys.which("singularity")
  if (isTRUE(singularity_bin_path == "")) {
    singularity_bin_path <- Sys.which("apptainer")
  }
  if (!fs::file_exists(singularity_bin_path)) {
    cli::cli_abort(c(
      `x` = "{.pkg singularity} or {.pkg apptainer} command-line interfaces are not available.",
      `!` = "Check {.url https://sylabs.io/docs/} or {.url https://github.com/apptainer/apptainer} for more information."
    ))
  }
  singularity_bin_path <- fs::path(singularity_bin_path)
  return(singularity_bin_path)
}


singularity_cmd <- function(..., verbose = TRUE) {
  singularity_bin_path <- is_singularity_available()
  px_res <- processx::run(command = singularity_bin_path, args = c(...),
                          echo = verbose, echo_cmd = TRUE, spinner = TRUE)
  return(invisible(px_res))
}

#' Format user string for Docker
#'
format_user_arg_string <- function() {
  user_arg <- "--user=dockerthis"
  if (isTRUE(Sys.info()["sysname"] == "Linux")) {
    user_id <- system("id -u", intern = TRUE)
    user_group_id <- system("id -g", intern = TRUE)
    user_arg = paste0("--user=", user_id, ":", user_group_id)
  }
  return(user_arg)
}
