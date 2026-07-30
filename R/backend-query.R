#' Check whether a single, already-resolved backend has a given environment
#'
#' Calls the `backend_env_exists()` generic directly on an already-resolved
#' backend object — no registry lookup, no `resolve_backend()` call. This
#' is the primitive `resolve_backend()`/`find_owning_backends()` use to
#' avoid the circularity of asking "which backend owns this env" by
#' calling something that itself needs to know which backend owns it.
#'
#' @param backend An already-resolved backend object.
#' @param env_name Character string with the environment name.
#' @param verbose Passed through to `backend_env_exists()`.
#'
#' @returns Logical. `FALSE` (never errors) if the backend's own
#'   `backend_env_exists()` throws for any reason.
#'
#' @keywords internal
#' @noRd
backend_has_env <- function(backend, env_name, verbose = FALSE) {
  return(tryCatch(
    isTRUE(backend_env_exists(backend, env_name = env_name, verbose = verbose)),
    error = function(e) FALSE
  ))
}

#' Find every registered backend that already has a given environment
#'
#' Iterates every *registered* backend (not gated on `backend_available()`
#' — an existing environment under an unavailable/unloaded backend is
#' still a real conflict to report, not something to silently skip past).
#'
#' @param env_name Character string with the environment name.
#' @param verbose Passed through to `backend_has_env()`.
#'
#' @returns Character vector of backend names that claim `env_name`. Length
#'   0 (new environment), 1 (unambiguous owner), or more (collision).
#'
#' @keywords internal
#' @noRd
find_owning_backends <- function(env_name, verbose = FALSE) {
  names_to_check <- list_registered_backend_names()
  owners <- names_to_check[
    vapply(
      names_to_check,
      function(nm) {
        backend_has_env(get_backend(nm), env_name = env_name, verbose = verbose)
      },
      logical(1L)
    )
  ]
  return(owners)
}

#' Bare install-root path for a single, already-resolved backend
#'
#' A trivial pass-through — its only purpose is giving internal,
#' already-backend-resolved call sites a bare-path primitive to reach for,
#' instead of the public, multi-backend, tibble-returning
#' `get_install_dir()`.
#'
#' @keywords internal
#' @noRd
install_dir_for_backend <- function(backend) {
  return(backend_get_install_dir(backend))
}

#' Bare environment-directory path for a single, already-resolved backend
#'
#' Same rationale as `install_dir_for_backend()`, for `get_env_dir()`.
#'
#' @keywords internal
#' @noRd
env_dir_for_backend <- function(backend, env_name) {
  return(backend_get_env_dir(backend, env_name = env_name))
}

#' Read an environment's backend marker file, if present
#'
#' Defense-in-depth only — never the discovery mechanism itself (directory
#' placement under a backend's own separate root already disambiguates
#' ownership structurally; see `find_owning_backends()`). Used only to
#' cross-check and warn on disagreement.
#'
#' @returns A list with `backend`/`schema_version`, or `NULL` if the
#'   marker doesn't exist or can't be read.
#'
#' @keywords internal
#' @noRd
read_backend_marker <- function(env_dir) {
  marker_path <- fs::path(env_dir, ".condathis", "backend.json")
  if (isFALSE(fs::file_exists(marker_path))) {
    return(NULL)
  }
  return(tryCatch(
    jsonlite::fromJSON(marker_path),
    error = function(e) NULL
  ))
}

#' Write an environment's backend marker file
#'
#' Called by the public `create_env()` wrapper after a successful
#' `backend_create_env()` call — never from inside a `backend_create_env.*`
#' method, so the marker format stays centralized in one place, written by
#' `condathis` itself rather than by each backend.
#'
#' @keywords internal
#' @noRd
write_backend_marker <- function(env_dir, backend_name) {
  marker_dir <- fs::path(env_dir, ".condathis")
  if (isFALSE(fs::dir_exists(marker_dir))) {
    fs::dir_create(marker_dir)
  }
  jsonlite::write_json(
    list(backend = backend_name, schema_version = 1L),
    path = fs::path(marker_dir, "backend.json"),
    auto_unbox = TRUE
  )
  return(invisible(NULL))
}
