#' Run a command in an environment using native execution
#'
#' Internal wrapper around `native_cmd()` for `micromamba run`.
#'
#' @param cmd Character string with the command to execute.
#' @param ... Additional unnamed command arguments passed to `cmd`.
#' @param env_name Character string with the target environment name.
#'   Defaults to `"condathis-env"`.
#' @param verbose Character string controlling console output.
#'   Supported values are `"output"`, `"silent"`, `"cmd"`, `"spinner"`,
#'   and `"full"`. Defaults to `"output"`.
#' @param error Character string that controls error behavior.
#'   Supported values are `"cancel"` and `"continue"`.
#'   Defaults to `"cancel"`.
#' @param stdout Standard output target. Defaults to `"|"`.
#' @param stderr Standard error target. Defaults to `"|"`.
#' @param stdin Standard input source. Defaults to `NULL`.
#'
#' @returns A process result list from `processx::run()`.
#'
#' @keywords internal
#' @noRd
run_internal_native <- function(
  cmd,
  ...,
  env_name = "condathis-env",
  verbose = c(
    "output",
    "silent",
    "cmd",
    "spinner",
    "full"
  ),
  error = c("cancel", "continue"),
  stdout = "|",
  stderr = "|",
  stdin = NULL
) {
  if (identical(base::Sys.info()["sysname"], c(sysname = "Windows"))) {
    micromamba_bat_path <- fs::path(
      get_install_dir(),
      "condabin",
      "micromamba",
      ext = "bat"
    )
    if (isFALSE(fs::file_exists(micromamba_bat_path))) {
      catch_res <- rlang::catch_cnd(
        expr = {
          native_cmd(
            conda_cmd = "run",
            conda_args = c("-n", "condathis-env"),
            "dir",
            verbose = "silent",
            stdout = NULL
          )
        }
      )
      base::rm(catch_res)
      mamba_bat_path <- fs::path(
        get_install_dir(),
        "condabin",
        "mamba",
        ext = "bat"
      )
      if (
        isTRUE(fs::file_exists(mamba_bat_path)) &&
          isFALSE(fs::file_exists(micromamba_bat_path))
      ) {
        fs::file_copy(
          path = mamba_bat_path,
          new_path = micromamba_bat_path,
          overwrite = TRUE
        )
      }
    }
  }
  px_res <- native_cmd(
    conda_cmd = "run",
    conda_args = c(
      "-n",
      env_name
    ),
    cmd,
    ...,
    verbose = verbose,
    error = error,
    stdout = stdout,
    stderr = stderr,
    stdin = stdin
  )
  return(invisible(px_res))
}
