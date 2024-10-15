#' List Packages Installed Inside Environment
#' @inheritParams run
#' @export
list_packages <- function(env_name = "condathis-env", verbose = "silent") {
  px_res <- native_cmd(
    conda_cmd = "list",
    conda_args = c(
      "-n",
      env_name,
      "--quiet",
      "--json"
    ),
    verbose = verbose
  )
  if (isTRUE(px_res$status == 0)) {
    pkgs_df <- jsonlite::fromJSON(px_res$stdout)
    pkgs_df <- tibble::as_tibble(pkgs_df)
    if (isTRUE(length(pkgs_df) == 0)) {
      pkgs_df <- tibble::tibble(
        "base_url" = character(0L),
        "build_number" = integer(0L),
        "build_string" = character(0L),
        "channel" = character(0L),
        "dist_name" = character(0L),
        "name" = character(0L),
        "platform" = character(0L),
        "version" = character(0L)
      )
    }
  }
  return(pkgs_df)
}
