#' Install Packages in a Existing Conda Environment
#' @param packages Character vector with the names of the packages and
#'   version strings if necessary.
#' @param env_name Name of the Conda environment where the packages are
#'   going to be installed. Defaults to 'condathis-env'.
#'
#' @inheritParams create_env
#'
#' @export
install_packages <- function(packages,
                             env_name = "condathis-env",
                             channels = c(
                               "bioconda",
                               "conda-forge"
                             ),
                             additional_channels = NULL,
                             verbose = "silent") {
  if (isFALSE(any(list_envs() %in% env_name))) {
    create_env(
      packages = NULL,
      env_name = env_name,
      verbose = verbose
    )
  }
  channels_arg <- format_channels_args(
    additional_channels,
    channels
  )
  px_res <- native_cmd(
    conda_cmd = "install",
    conda_args = c(
      "-n",
      env_name,
      "--yes",
      "--quiet",
      "--no-channel-priority",
      "--override-channels",
      "--channel-priority=0",
      channels_arg
    ),
    packages,
    verbose = verbose
  )
  cat(px_res$stdout)
  invisible(px_res$status)
}
