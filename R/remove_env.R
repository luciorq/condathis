#' Remove a Conda Environment
#'
#' Remove a Conda environment previously created by `create_env()`.
#'
#' @inheritParams create_env
#'
#' @export
remove_env <- function(env_name = "condathis-env",
                       verbose = "silent") {
  px_res <- native_cmd(
    conda_cmd = "env",
    conda_args = c(
      "remove",
      "-n",
      env_name,
      "--yes",
      "--quiet"
    ),
    verbose = verbose
  )
  return(invisible(px_res))
}
