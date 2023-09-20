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
build_container_image <- function(dockerfile_path = NULL,
                                  image_name = "luciorq/condathis-micromamba:latest",
                                  force = FALSE,
                                  method = "docker") {
  if (isTRUE(method == "docker")) {
    stop_if_not_installed("dockerthis")
    if (is.null(dockerfile_path)) {
      dockerfile_path <- fs::path_package(
        "dockerthis", "dockerfiles", "micromamba",
        ext = "dockerfile"
      )
    }
    px_res <- dockerthis::docker_build_image(
      dockerfile_path = dockerfile_path,
      image_name = image_name,
      force = FALSE,
      platform_arg = "linux/amd64"
    )
  } else if (isTRUE(method == "singularity")) {
    px_res <- build_container_image_singularity(
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
build_container_image_singularity <- function(image_name = "luciorq/condathis-micromamba:latest",
                                              registry_name = "docker") {
  # singularity build img.sif docker://luciorq/condathis-micromamba:latest
  invisible(is_singularity_available())
  env_root_dir <- get_install_dir()
  env_root_dir <- fs::path(paste0(env_root_dir, "-docker"))
  sif_dir <- fs::path(env_root_dir, "sif")
  if (isFALSE(fs::dir_exists(sif_dir))) {
    fs::dir_create(sif_dir)
  }
  sif_image_path <- fs::path(sif_dir, "condathis-micromamba", ext = "sif")
  if (fs::file_exists(sif_image_path)) {
    fs::file_delete(sif_image_path)
  }
  remote_image_path <- paste0(registry_name, "://", image_name)
  px_res <- singularity_cmd(
    "build",
    sif_image_path,
    remote_image_path
  )
  return(invisible(px_res))
}
