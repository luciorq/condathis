#' Execute Code in a Temporary Directory
#'
#' @description
#' Runs user-defined code inside a temporary directory, setting up a temporary
#' working environment. This function is intended for use in examples and tests
#' and ensures that no data is written to the user's file space.
#' Environment variables such as `HOME`, `APPDATA`, `R_USER_DATA_DIR`,
#' `XDG_DATA_HOME`, `LOCALAPPDATA`, and `USERPROFILE` are redirected to
#' temporary directories.
#'
#' @details
#' This function is not designed for direct use by package users. It is primarily
#' used to create an isolated environment during examples and tests. The temporary
#' directories are created automatically and cleaned up after execution.
#'
#' @param code [expression]
#'   An expression containing the user-defined code to be executed in the
#'   temporary environment.
#'
#' @param .local_envir [environment]
#'  The environment to use for scoping.
#'
#' @return
#' Returns `NULL` invisibly.
#'
#' @examples
#' condathis::with_sandbox_dir(print(fs::path_home()))
#' condathis::with_sandbox_dir(print(tools::R_user_dir("condathis")))
#'
#' @export
with_sandbox_dir <- function(code, .local_envir = base::parent.frame()) {
  tmp_home_path <- withr::local_tempdir(
    pattern = "tmp-home",
    .local_envir = .local_envir
  )
  tmp_data_path <- withr::local_tempdir(
    pattern = "tmp-data",
    .local_envir = .local_envir
  )

  if (isFALSE(fs::dir_exists(tmp_home_path))) {
    fs::dir_create(tmp_home_path)
  }
  if (isFALSE(fs::dir_exists(tmp_data_path))) {
    fs::dir_create(tmp_data_path)
  }
  withr::local_envvar(
    .new = list(
      `HOME` = tmp_home_path,
      `USERPROFILE` = tmp_home_path,
      `LOCALAPPDATA` = tmp_data_path,
      `APPDATA` = tmp_data_path,
      `R_USER_DATA_DIR` = tmp_data_path,
      `XDG_DATA_HOME` = tmp_data_path
    ),
    .local_envir = .local_envir
  )
  code <- base::substitute(expr = code)
  rlang::eval_bare(expr = code, env = .local_envir)
  return(invisible(NULL))
}
