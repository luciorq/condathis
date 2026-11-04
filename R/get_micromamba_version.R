#' Get the installed micromamba version
#'
#' @param umamba_path Character path to the micromamba executable.
#'   Defaults to `NULL`, which uses `micromamba_bin_path()`.
#'
#' @returns A character string with the micromamba version, `"X.Y.Z"`.
#'   A missing file aborts with class
#'   `condathis_micromamba_bin_path_not_executable`, and output without a
#'   version with class `condathis_micromamba_version_not_detected`. The
#'   old classes `condathis_umamba_*` are kept until 1.0.
#'
#' @keywords internal
#' @noRd
get_micromamba_version <- function(umamba_path = NULL) {
  if (rlang::is_null(umamba_path)) {
    umamba_path <- micromamba_bin_path()
  }
  umamba_bin_path <- base::normalizePath(umamba_path, mustWork = FALSE)
  if (isFALSE(fs::file_exists(umamba_bin_path))) {
    condathis_abort(
      message = c(
        `x` = "{.path {umamba_bin_path}} is not an executable file."
      ),
      class = c(
        "condathis_micromamba_bin_path_not_executable",
        "condathis_umamba_bin_path_not_executable"
      )
    )
  }
  # The session's environment, with the `MAMBA_ROOT_PREFIX` that every
  # micromamba process of condathis gets: without it, micromamba aborts
  # before it prints the version when its default root exists but is not a
  # Conda prefix (see `micromamba_cmd_overlay()`). The
  # root is not created: micromamba does not use it for `--version`. It
  # keeps the session's `TMPDIR` and `TMP`: `--version` writes no temporary
  # files (micromamba 2.10.0, Linux and Windows).
  version_env <- unlist(apply_env_overrides(
    as.list(Sys.getenv()),
    micromamba_process_envvars(get_condathis_path())
  ))
  px_res <- processx::run(
    command = fs::path_real(umamba_bin_path),
    args = c(
      "--no-rc",
      "--no-env",
      "--version"
    ),
    env = version_env,
    spinner = FALSE,
    echo_cmd = FALSE,
    echo = FALSE,
    stdout = "|",
    stderr = NULL,
    error_on_status = FALSE
  )
  # Extract from the whole output, so empty output, or a version on a later
  # line, still gives one string or `NA`.
  version_string <- stringr::str_extract(
    paste(parse_output(px_res, stream = "both"), collapse = "\n"),
    pattern = stringr::regex(r"(\d+\.\d+\.\d+)")
  )
  if (isTRUE(rlang::is_chr_na(version_string))) {
    condathis_abort(
      message = c(
        `x` = "The version of {.path {umamba_path}} could not be detected."
      ),
      class = c(
        "condathis_micromamba_version_not_detected",
        "condathis_umamba_version_not_detected"
      )
    )
  }
  return(version_string)
}
