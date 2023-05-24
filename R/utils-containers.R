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
#' @param image_name Character. Image name used for the contaier image.
#'   Defaults to `"condathis-micromamba:latest"`.
#'
#' @param force Logical. Should image be removed before building.
#'   Defaults to FALSE.
#'
#' @export
build_micromamba_image <- function(dockerfile_path = NULL,
                                   image_name = "condathis-micromamba:latest",
                                   force = FALSE) {
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
  return(invisible(px_res))
}

# run_cmd_umamba_docker <- function () {
#
# }

# @param run_as_user Default TRUE. By default Docker run the container as the
#   root user, what is a really bad idea in most use cases.
#   Only change that to FALSE if you really know what you are doing.
#   Find more information at <>

#' Run Command Inside Docker Container
#'
#' Run command line tools inside Linux containers using Docker Client CLI.
#'
#' @param cmd Character. Command
#'
# @export
# run_cmd <- function(cmd,
#                 ...,
#                 container_name = "dockerthis-base",
#                 image_name = "dockerthis-umamba:latest",
#                 docker_args = c("--platform=linux/amd64",
#                                 "--user=dockerthis",
#                                 "-it",
#                                 "-d"),
#                 mount_paths = NULL,
#                 run_as_user = TRUE) {
#   mount_path_arg <- c()
#   if (!is.null(mount_paths)) {
#     for (mount_path in mount_paths) {
#       if (fs::file_exists(mount_path)) {
#         cli::cli_abort(c(
#           `x` = "{.field mount_path} needs to be a directory.",
#           `!` = "File {.file {mount_path}} supplied to {.field mount_path} argument."
#         ))
#       }
#       if (fs::dir_exists(mount_path)) {
#         mount_path_real <- fs::path_real(mount_path)
#         mount_path_arg <- c(
#           mount_path_arg,
#           "-v",
#           paste0(mount_path_real,":",mount_path_real)
#         )
#       }
#     }
#   }
#
#   container_df <- docker_list_containers()
#   if (isTRUE(container_name %in% container_df$Names)) {
#     if ("running" %in% container_df[container_df$Names == container_name, ]$State) {
#       docker_exec(cmd = cmd, ..., container_name = container_name)
#     }
#     if ("exited" %in% container_df[container_df$Names == container_name, ]$State) {
#       docker_start_container(container_name = container_name)
#       container_df <- docker_list_containers()
#       if ("running" %in% container_df[container_df$Names == container_name, ]$State) {
#         docker_exec(cmd = cmd, ..., container_name = container_name)
#       } else {
#         cli::cli_abort(c(
#           `x` = "Container {.pkg {container_name}} is not starting properly.",
#           `!` = "Removing the container with {.fn dockerthis::docker_remove_container(\"{container_name}\")} and try again."
#         ))
#       }
#     }
#   } else {
#     px_res <- docker_run(
#       cmd,
#       ...,
#       docker_args,
#       mount_path_arg,
#       container_name,
#       image_name,
#     )
#   }
#   return(invisible(px_res))
# }

