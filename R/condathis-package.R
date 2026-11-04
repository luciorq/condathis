#' @details
#' Create an environment with [create_env()]. Run a command line tool in it
#' with [run()], or run several tools connected by pipes with
#' [run_pipeline()]. Read the output with [parse_output()]. Start with
#' `vignette("condathis")`. [condathis-options] lists the options and
#' environment variables that `condathis` reads. [condathis-conditions]
#' lists the classes of its errors and warnings.
#'
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @importFrom rlang %||%
## usethis namespace: end
NULL

#' Cache for `R.home("bin")`-derived paths, resolved at package load time
#'
#' `get_clean_conda_envvars()` sets `R_HOME = ""` so a spawned child that
#' invokes R or Rscript does not inherit the parent session's R installation.
#' A session with `R_HOME` set to `""` corrupts `R.home()` (for example
#' `/bin/Rscript` instead of the real path).
#'
#' `build_child_env()` builds child environments explicitly and passes them
#' as full `env =` blocks, so `condathis` never mutates the session's
#' `R_HOME`. The cache is defense-in-depth: it is immune to third-party code
#' that mutates `R_HOME`, and it avoids re-deriving the path on every
#' activation resolution.
#'
#' @keywords internal
#' @noRd
condathis_rscript_path_cache <- new.env(parent = emptyenv())

#' @keywords internal
#' @noRd
.onLoad <- function(libname, pkgname) {
  condathis_rscript_path_cache$path <- resolve_condathis_rscript_path()
  # `register_backend()` refuses the reserved name "micromamba", so that no
  # other package can replace the built-in backend.
  register_backend_impl("micromamba", micromamba_backend())
  invisible(NULL)
}

#' @keywords internal
#' @noRd
resolve_condathis_rscript_path <- function() {
  rscript_path <- fs::path(R.home("bin"), "Rscript")
  if (identical(.Platform$OS.type, "windows")) {
    rscript_path <- paste0(rscript_path, ".exe")
  }
  return(rscript_path)
}

#' The current R session's `Rscript` path, resolved once at package load
#'
#' @returns Character string. Falls back to resolving `R.home()` on the
#'   spot, with the same `R_HOME`-corruption caveat, if called before
#'   `.onLoad()` runs (for example via `:::` without a normal package load).
#'
#' @keywords internal
#' @noRd
get_condathis_rscript_path <- function() {
  path <- condathis_rscript_path_cache$path
  if (is.null(path)) {
    path <- resolve_condathis_rscript_path()
  }
  return(path)
}
