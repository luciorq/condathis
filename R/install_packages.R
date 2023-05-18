#' Install Packages in a Existing Conda Environment
#' @param packages Character vector with the names of the packages and
#'   version strings if necessary.
#' @param env_name Name of the Conda environment where the packages are
#'   going to be installed. Defaults to 'condathis-env'.
#' @export
install_packages <- function(packages, env_name = "condathis-env") {
  umamba_bin_path <- micromamba_bin_path()
  env_root_dir <- get_install_dir()

  if (!any(stringr::str_detect(list_envs(), paste0(env_name, "$")))) {
    create_env(packages = NULL, env_name = env_name)
  }

  px_res <- processx::run(
    command = fs::path_real(umamba_bin_path),
    args = c(
      "install",
      "-r",
      env_root_dir,
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
    spinner = TRUE
  )
  px_res$stdout |>
    cat()
  invisible(px_res$status)
}
