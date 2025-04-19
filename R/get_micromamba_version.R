get_micromamba_version <- function(umamba_path = NULL) {
  if (rlang::is_null(umamba_path)) {
    umamba_path <- micromamba_bin_path()
  }
  umamba_bin_path <- base::normalizePath(umamba_path, mustWork = FALSE)
  if (isFALSE(fs::file_exists(umamba_bin_path))) {
    cli::cli_abort(
      message = c(
        `x` = "{.path {umamba_bin_path}} is not an executable file"
      ),
      class = "condathis_umamba_bin_path_not_executable"
    )
  }
  px_res <- processx::run(
    command = fs::path_real(umamba_bin_path),
    args = c(
      "--no-rc",
      "--no-env",
      "--version"
    ),
    spinner = FALSE,
    echo_cmd = FALSE,
    echo = FALSE,
    stdout = "|",
    stderr = NULL,
    error_on_status = FALSE
  )
  version_string <- parse_output(px_res)
  version_string <- stringr::str_extract(
    version_string,
    pattern = r"(\d+\.\d+\.\d+)"
  )
  if (isTRUE(rlang::is_chr_na(version_string))) {
    cli::cli_abort(
      message = c(
        `x` = "Version could not be detected for {.path {umamba_path}}"
      ),
      class = "condathis_umamba_version_not_detected"
    )
  }
  return(version_string)
}
