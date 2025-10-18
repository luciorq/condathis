check_micromamba_version <- function(
  umamba_path = NULL,
  target_version = "2.3.3"
) {
  # rlang::is_string(target_version)
  version_string <- get_micromamba_version(umamba_path)
  compare_res <- utils::compareVersion(version_string, target_version)

  if (isTRUE(identical(compare_res, 0L))) {
    return(TRUE)
  } else {
    return(FALSE)
  }
}
