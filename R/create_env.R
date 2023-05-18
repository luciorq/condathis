#' Create Conda Environment with specific packages
#' @param packages Character vector with the names of the packages and
#'   version strings if necessary.
#' @param env_name Name of the Conda environment where the packages are
#'   going to be installed. Defaults to 'condathis-env'.
#' @export
create_env <- function(packages = NULL, env_name = "condathis-env") {
  umamba_bin_path <- micromamba_bin_path()
  env_root_dir <- get_install_dir()

  px_res <- processx::run(
    command = fs::path_real(umamba_bin_path),
    args = c(
      "create",
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
