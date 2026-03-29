#' Check if the Dependencies are Satisfied in the Environment
#'
#' This function checks if the installed packages in the environment satisfy the
#' specified package requirements. It parses each package specification in
#' `pkg_str_vector`, extracts the package name and version constraints, and
#' compares them against the installed packages in the environment. The function
#' returns a logical vector where each element corresponds to whether the
#' respective package specification is satisfied by the installed packages.
#'
#' @param pkg_str_vector A character vector of package specifications,
#'   e.g. `c("conda-forge::numpy>=1.8,<2|1.9", "python=3.13")`.
#' @param env_name A character string specifying the name of the Conda
#'   environment.
#' @param verbose A character string specifying the verbosity level for the
#'  `list_packages()` function. Defaults to "silent".
#'
#' @returns A logical vector indicating whether each package specification in
#' `pkg_str_vector` is satisfied by the packages in the environment.
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
