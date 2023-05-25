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
