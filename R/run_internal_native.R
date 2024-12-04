#' Run Command Using Native Method
#'
#' Internal function to run a command in a Conda environment using the native method.
#'
#' @inheritParams run
#'
#' @keywords internal
#' @noRd
run_internal_native <- function(cmd,
                                ...,
                                env_name = "condathis-env",
                                verbose = FALSE,
                                error = c("cancel", "continue"),
                                stdout = "|",
                                stderr = "|") {
  if (isTRUE(base::Sys.info()["sysname"] == "Windows")) {
    micromamba_bat_path <- fs::path(get_install_dir(), "condabin", "micromamba", ext = "bat")
    if (isFALSE(fs::file_exists(micromamba_bat_path))) {
      catch_res <- rlang::catch_cnd(
        expr = {
          native_cmd(
            conda_cmd = "run",
            conda_args = c("-n", "condathis-env"),
            cmd = "dir", verbose = FALSE, stdout = NULL
          )
        }
      )
      mamba_bat_path <- fs::path(get_install_dir(), "condabin", "mamba", ext = "bat")
      if (isTRUE(fs::file_exists(mamba_bat_path)) &&
        isFALSE(fs::file_exists(micromamba_bat_path))) {
        fs::file_copy(mamba_bat_path, micromamba_bat_path, overwrite = TRUE)
      }
    }
  }
  px_res <- native_cmd(
    conda_cmd = "run",
    conda_args = c(
      "-n",
      env_name
    ),
    cmd = cmd,
    ...,
    verbose = verbose,
    error = error,
    stdout = stdout,
    stderr = stderr
  )
  return(invisible(px_res))
}
