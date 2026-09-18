#' @keywords internal
"_PACKAGE"

## usethis namespace: start
## usethis namespace: end
NULL

#' Cache for `R.home("bin")`-derived paths, resolved at package load time
#'
#' Historical context: `get_clean_conda_envvars()`'s `R_HOME = ""`
#' override (so a spawned child that itself invokes R/Rscript doesn't
#' inherit the parent session's R installation) used to be applied to the
#' *calling session* via `withr::local_envvar()`, and any `R.home()` call
#' made while such a scope was active anywhere up the stack got a
#' corrupted result (empirically: `/bin/Rscript` instead of the real
#' path). This load-time cache was introduced to sidestep that.
#'
#' Child environments are now built explicitly by `build_child_env()` and
#' passed as full `env =` blocks - condathis never mutates the session's
#' `R_HOME` anymore - so the original hazard is gone. The cache is kept as
#' cheap defense-in-depth: it is immune to any third-party code that does
#' mutate `R_HOME`, and avoids re-deriving the path on every activation
#' resolution.
#'
#' @keywords internal
#' @noRd
condathis_rscript_path_cache <- new.env(parent = emptyenv())

#' @keywords internal
#' @noRd
.onLoad <- function(libname, pkgname) {
  condathis_rscript_path_cache$path <- resolve_condathis_rscript_path()
  register_backend("micromamba", micromamba_backend())
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
#'   spot (with the same `R_HOME`-corruption caveat) if called before
#'   `.onLoad()` has run - e.g. via `:::` without a normal package load.
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
