#' Check whether dependencies are already satisfied
#'
#' Compares requested package specs with installed packages in an environment.
#'
#' @param pkg_str_vector Character vector of package MatchSpec strings.
#' @param env_name Character string with the environment name.
#' @param verbose Character string passed to `list_packages()`.
#'   Defaults to `"silent"`.
#'
#' @returns A logical vector with one value per input specification.
#'
#' @keywords internal
#' @noRd
satisfies_dependencies <- function(
  pkg_str_vector,
  env_name,
  verbose = "silent"
) {
  pkg_str_vector <- as.character(pkg_str_vector)
  if (isTRUE(length(pkg_str_vector) == 0L)) {
    return(logical(0L))
  }
  installed_pkgs_df <- list_packages(
    env_name = env_name,
    verbose = verbose
  )
  output_vector <- vector(mode = "logical", length = length(pkg_str_vector))
  for (i in seq_along(pkg_str_vector)) {
    pkg_match_spec <- parse_match_spec(pkg_str_vector[i])
    pkg_name_str <- pkg_match_spec$name
    installed_version <- installed_pkgs_df[
      installed_pkgs_df$name %in% pkg_name_str,
    ]$version
    if (isTRUE(length(installed_version) > 0L)) {
      output_vector[i] <- version_spec_contains(
        version_string = installed_version,
        spec_string = pkg_match_spec$version
      )
    } else {
      output_vector[i] <- FALSE
    }
  }

  return(output_vector)
}
