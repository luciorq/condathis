#' @keywords internal
"_PACKAGE"

## usethis namespace: start
## usethis namespace: end
NULL

#' Cache for `R.home("bin")`-derived paths, resolved at package load time
#'
#' `get_clean_conda_envvars()` sets `R_HOME = ""` via `withr::local_envvar()`
#' so a spawned child (which may itself invoke R/Rscript, e.g. inside a
#' target Conda environment) doesn't inherit the parent session's R
#' installation. Since that's a real (session-wide, if temporary) mutation
#' of `Sys.getenv("R_HOME")`, any code that calls `R.home()` while such a
#' scope is active anywhere up the call stack gets a corrupted result
#' (empirically: `/bin/Rscript` instead of the real path). Resolving once
#' at package load — before any condathis function has had a chance to
#' touch `R_HOME` — sidesteps the ordering problem entirely, rather than
#' requiring every caller to resolve `R.home()` before its own
#' `get_clean_conda_envvars()` call (which does not compose: a caller
#' further up the stack may have already applied its own).
#'
#' @keywords internal
#' @noRd
condathis_rscript_path_cache <- new.env(parent = emptyenv())

#' @keywords internal
#' @noRd
.onLoad <- function(libname, pkgname) {
  condathis_rscript_path_cache$path <- resolve_condathis_rscript_path()
  register_backend("micromamba", new_backend_micromamba())
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
#'   `.onLoad()` has run — e.g. via `:::` without a normal package load.
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
