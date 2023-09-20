#' Install Packages in a Existing Conda Environment
#' @param packages Character vector with the names of the packages and
#'   version strings if necessary.
#' @param env_name Name of the Conda environment where the packages are
#'   going to be installed. Defaults to 'condathis-env'.
#' @export
install_packages <- function(packages, env_name = "condathis-env") {
  if (!any(stringr::str_detect(list_envs(), paste0(env_name, "$")))) {
    create_env(packages = NULL, env_name = env_name)
  }
  px_res <- native_cmd(
    conda_cmd = "install",
    conda_args = c(
      "-n",
      env_name,
      "--yes",
      "--quiet",
      "-c",
      "defaults",
      "-c",
      "bioconda",
      "-c",
      "conda-forge",
      packages
    ),
    verbose = FALSE
  )
  px_res$stdout |>
    cat()
  invisible(px_res$status)
}
