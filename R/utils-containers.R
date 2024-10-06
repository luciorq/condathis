#' Stop execution if `dockerthis` package is not installed.
#' @param pkg_name Character. Name of the R package to check.
#' @param org_name Character. Name of the Remote organization
#'   where development version of package is hosted.
stop_if_not_installed <- function(pkg_name = "dockerthis", org_name = "luciorq") {
  if (!requireNamespace(pkg_name, quietly = TRUE)) {
    cli::cli_abort(
      c(
        `x` = "{.pkg {pkg_name}} is not installed.",
        `!` = "Install with: {.code install.packages('{pkg_name}', repos = c('https://{org_name}.r-universe.dev', getOption('repos'))}.",
        `!` = "Or from GitHub using: {.code remotes::install_github('{org_name}/{pkg_name}')}."
      ),
      class = "condathis_missing_suggest"
    )
  }
}

#' Are Singularity or Apptainer CLIs available
#'
#' Test if Singularity or Apptainer CLIs are available on PATH.
#'
is_singularity_available <- function() {
  singularity_bin_path <- Sys.which("singularity")
  if (isTRUE(singularity_bin_path == "")) {
    singularity_bin_path <- Sys.which("apptainer")
  }
  if (!fs::file_exists(singularity_bin_path)) {
    cli::cli_abort(
      c(
        `x` = "{.pkg singularity} or {.pkg apptainer} command-line interfaces are not available.",
        `!` = "Check {.url https://sylabs.io/docs/} or {.url https://github.com/apptainer/apptainer} for more information."
      ),
      class = "condathis_singularity_not_installed"
    )
  }
  singularity_bin_path <- fs::path(singularity_bin_path)
  return(singularity_bin_path)
}

singularity_cmd <- function(...,
                            verbose = TRUE,
                            stdout = "|") {
  singularity_bin_path <- is_singularity_available()
  px_res <- processx::run(
    command = singularity_bin_path,
    args = c(...),
    echo = verbose,
    echo_cmd = verbose,
    spinner = TRUE,
    stdout = "|"
  )
  return(invisible(px_res))
}

#' Format user string for Docker
#'
format_user_arg_string <- function() {
  user_arg <- "--user=dockerthis"
  if (isTRUE(Sys.info()["sysname"] == "Linux")) {
    user_id <- system("id -u", intern = TRUE)
    user_group_id <- system("id -g", intern = TRUE)
    user_arg <- paste0("--user=", user_id, ":", user_group_id)
  }
  return(user_arg)
}
