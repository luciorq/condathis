#' Registry of registered backends
#'
#' A package-level environment (not a list) so `register_backend()` can
#' mutate it in place without `<<-` or a mutable global list.
#'
#' @keywords internal
#' @noRd
backend_registry <- new.env(parent = emptyenv())

#' The 10 generic names every backend must implement
#'
#' @keywords internal
#' @noRd
backend_contract_names <- c(
  "backend_create_env",
  "backend_install",
  "backend_remove_env",
  "backend_list_envs",
  "backend_env_exists",
  "backend_list_packages",
  "backend_get_env_dir",
  "backend_get_install_dir",
  "backend_resolve_run",
  "backend_available"
)

#' Session-scoped flag for the once-per-session `method = "native"` warning
#'
#' @keywords internal
#' @noRd
condathis_native_warned <- new.env(parent = emptyenv())
condathis_native_warned$warned <- FALSE

#' Register a condathis backend implementation
#'
#' The extension point for packages that provide an alternative execution
#' engine for `condathis` (e.g. an in-process `rattler`-based solver, or a
#' container-based engine). Once registered, the backend becomes selectable
#' through the `method` argument of every environment-management function
#' (`create_env()`, `run()`, `list_envs()`, ...), and participates in
#' `method = "auto"` resolution.
#'
#' `backend` is a classed, named list (a "vtable"), not an S3 object with
#' methods already attached: its element names must be exactly the 10
#' contract function names listed below, each a function implementing that
#' part of the contract. `register_backend()` validates the vtable is
#' complete, then registers each entry for S3 dispatch from inside
#' `condathis`'s own namespace — the backend package does not need to
#' `Imports`/`Depends` on `condathis` or register anything in its own
#' `NAMESPACE`.
#'
#' @section The backend contract:
#' `backend` must be built as
#' `structure(list(<the 10 functions>), class = c("condathis_backend_<name>", "condathis_backend"))`
#' — the first class is what S3 dispatch keys on, so it must be unique to
#' this backend. The 10 required element names are:
#'
#' * `backend_create_env(backend, packages, env_file, env_name, channels,
#'   channel_priority, additional_channels, platform, overwrite, verbose)`
#' * `backend_install(backend, packages, env_name, channels,
#'   channel_priority, additional_channels, verbose)`
#' * `backend_remove_env(backend, env_name, verbose)`
#' * `backend_list_envs(backend, verbose)` — returns a bare character
#'   vector of environment names.
#' * `backend_env_exists(backend, env_name, verbose)` — returns a single
#'   logical.
#' * `backend_list_packages(backend, env_name, verbose)` — returns a data
#'   frame with at least `name`, `version`, `build_number`, and `channel`
#'   columns; extra backend-specific columns are allowed.
#' * `backend_get_env_dir(backend, env_name)` — returns the environment's
#'   directory path.
#' * `backend_get_install_dir(backend)` — returns the backend's own
#'   install root. Each backend must use its own separate root: directory
#'   placement under that root is how `condathis` determines which backend
#'   owns an existing environment.
#' * `backend_resolve_run(backend, cmd, args, env_name, verbose)` —
#'   returns `list(command, args, env, dir)` describing how to execute
#'   `cmd` inside `env_name`.
#' * `backend_available(backend)` — returns a single logical; gates
#'   `method = "auto"` selection for *new* environments.
#'
#' Creation/installation/removal functions signal an error condition on
#' failure; their return values are not otherwise inspected. `condathis`
#' builds its own user-facing result objects.
#'
#' @section Registering from a backend package:
#' Register from your package's `.onLoad()`, and *also* hook `condathis`'s
#' own load event: the registry lives inside `condathis`'s namespace, so if
#' `condathis` is ever unloaded and reloaded after your package registered,
#' the registration would silently be lost without the hook. The combined
#' pattern covers both load orders:
#'
#' ```r
#' .onLoad <- function(libname, pkgname) {
#'   register_self <- function(...) {
#'     condathis::register_backend("mybackend", new_backend_mybackend())
#'   }
#'   if (requireNamespace("condathis", quietly = TRUE)) {
#'     register_self()
#'   }
#'   setHook(packageEvent("condathis", "onLoad"), register_self)
#'   invisible(NULL)
#' }
#'
#' .onUnload <- function(libpath) {
#'   if (isNamespaceLoaded("condathis")) {
#'     condathis::unregister_backend("mybackend")
#'   }
#' }
#' ```
#'
#' @param name Character string identifying this backend (e.g.
#'   `"micromamba"`, `"rattler"`). This is the value users pass as
#'   `method =`. Re-registering an existing name overwrites it.
#' @param backend A classed, named list of the 10 contract functions — see
#'   *The backend contract* below.
#' @param call Calling environment reported in error conditions. Defaults
#'   to the caller's environment.
#'
#' @returns `name`, invisibly. Signals a condition of class
#'   `condathis_backend_contract_violation` (naming exactly which contract
#'   functions are missing) if the vtable is incomplete.
#'
#' @seealso [unregister_backend()], [list_registered_backend_names()]
#'
#' @examples
#' \dontrun{
#' # Inside a backend package's .onLoad() (see the registration section
#' # for the full, load-order-safe pattern):
#' condathis::register_backend("mybackend", new_backend_mybackend())
#' }
#'
#' @export
register_backend <- function(name, backend, call = rlang::caller_env()) {
  if (
    isFALSE(rlang::is_character(name)) ||
      isFALSE(identical(length(name), 1L)) ||
      is.na(name)
  ) {
    cli::cli_abort(
      message = c(
        `x` = "{.arg name} must be a single, non-missing character string."
      ),
      class = "condathis_backend_invalid_name",
      call = call
    )
  }

  missing_generics <- backend_contract_names[
    vapply(
      backend_contract_names,
      function(generic_name) isFALSE(is.function(backend[[generic_name]])),
      logical(1L)
    )
  ]
  if (isTRUE(length(missing_generics) > 0L)) {
    cli::cli_abort(
      message = c(
        `x` = "Backend {.field {name}} does not implement the full backend contract.",
        `!` = "Missing: {.field {missing_generics}}."
      ),
      class = "condathis_backend_contract_violation",
      call = call
    )
  }

  backend_class <- class(backend)[[1L]]
  for (generic_name in backend_contract_names) {
    base::registerS3method(
      genname = generic_name,
      class = backend_class,
      method = backend[[generic_name]],
      envir = asNamespace("condathis")
    )
  }

  assign(name, backend, envir = backend_registry)
  return(invisible(name))
}

#' Unregister a condathis backend
#'
#' Removes a backend previously added with [register_backend()]: the
#' registry entry and the S3 methods that were registered for its class.
#' Intended for a backend package's `.onUnload()` (see the registration
#' section of [register_backend()]), so an unloaded package never leaves
#' behind a registered backend whose functions belong to a namespace that
#' no longer exists.
#'
#' Unregistering a name that isn't currently registered is a silent no-op
#' (returning `FALSE`), never an error — unload hooks shouldn't fail on
#' cleanup that has nothing left to clean.
#'
#' @param name Character string with the backend name to unregister.
#' @param call Calling environment reported in error conditions. Defaults
#'   to the caller's environment.
#'
#' @returns Logical, invisibly: `TRUE` if a backend was unregistered,
#'   `FALSE` if no backend by that name was registered.
#'
#' @seealso [register_backend()], [list_registered_backend_names()]
#'
#' @examples
#' \dontrun{
#' # Inside a backend package's .onUnload():
#' condathis::unregister_backend("mybackend")
#' }
#'
#' @export
unregister_backend <- function(name, call = rlang::caller_env()) {
  if (
    isFALSE(rlang::is_character(name)) ||
      isFALSE(identical(length(name), 1L)) ||
      is.na(name)
  ) {
    cli::cli_abort(
      message = c(
        `x` = "{.arg name} must be a single, non-missing character string."
      ),
      class = "condathis_backend_invalid_name",
      call = call
    )
  }
  if (isFALSE(exists(name, envir = backend_registry, inherits = FALSE))) {
    return(invisible(FALSE))
  }

  backend <- get(name, envir = backend_registry, inherits = FALSE)
  backend_class <- class(backend)[[1L]]

  # Also drop the S3 methods `register_backend()` registered for this
  # class — a stale method would hold the last reference to the backend
  # package's (possibly unloaded) namespace. The runtime S3 methods table
  # is not locked (it must accept `registerS3method()` calls after
  # namespace sealing), so entries can be removed the same way they were
  # added.
  s3_table <- asNamespace("condathis")[[".__S3MethodsTable__."]]
  for (generic_name in backend_contract_names) {
    method_name <- paste0(generic_name, ".", backend_class)
    if (isTRUE(exists(method_name, envir = s3_table, inherits = FALSE))) {
      rm(list = method_name, envir = s3_table)
    }
  }

  rm(list = name, envir = backend_registry)
  return(invisible(TRUE))
}

#' Retrieve a registered backend by name
#'
#' @keywords internal
#' @noRd
get_backend <- function(name, call = rlang::caller_env()) {
  if (isFALSE(exists(name, envir = backend_registry, inherits = FALSE))) {
    cli::cli_abort(
      message = c(
        `x` = "No backend named {.field {name}} is registered.",
        `!` = "Registered backends: {.field {list_registered_backend_names()}}."
      ),
      class = "condathis_backend_not_registered",
      call = call
    )
  }
  return(get(name, envir = backend_registry, inherits = FALSE))
}

#' List every currently registered backend name
#'
#' Returns the names of every backend currently registered with
#' [register_backend()], whether or not each is currently available
#' (`backend_available()`). These are the valid values for the `method`
#' argument of `condathis`'s environment-management functions, alongside
#' `"auto"`. `"micromamba"`, the built-in backend, is always present.
#'
#' @returns A sorted character vector of registered backend names.
#'
#' @seealso [register_backend()], [unregister_backend()]
#'
#' @examples
#' condathis::list_registered_backend_names()
#'
#' @export
list_registered_backend_names <- function() {
  return(sort(ls(envir = backend_registry)))
}

#' Validate a `method` argument against the currently registered backends
#'
#' @keywords internal
#' @noRd
validate_method_arg <- function(method, call = rlang::caller_env()) {
  if (
    isFALSE(rlang::is_character(method)) ||
      isFALSE(identical(length(method), 1L)) ||
      is.na(method)
  ) {
    cli::cli_abort(
      message = c(
        `x` = "{.arg method} must be a single, non-missing character string."
      ),
      class = "condathis_invalid_method_arg",
      call = call
    )
  }
  valid_values <- c("auto", list_registered_backend_names(), "native")
  if (isFALSE(method %in% valid_values)) {
    cli::cli_abort(
      message = c(
        `x` = "{.arg method} must be one of {.val {valid_values}}, not {.val {method}}."
      ),
      class = "condathis_invalid_method_arg",
      call = call
    )
  }
  return(method)
}

#' Resolve the deprecated `"native"` alias to `"micromamba"`
#'
#' Warns once per session (class `condathis_deprecated_method_native`),
#' not on every call.
#'
#' @keywords internal
#' @noRd
resolve_method_alias <- function(method) {
  if (identical(method, "native")) {
    if (isFALSE(condathis_native_warned$warned)) {
      cli::cli_warn(
        message = c(
          `!` = "{.val native} is a deprecated alias for {.val micromamba}.",
          `i` = "Use {.code method = \"micromamba\"} instead."
        ),
        class = "condathis_deprecated_method_native"
      )
      condathis_native_warned$warned <- TRUE
    }
    return("micromamba")
  }
  return(method)
}

#' Resolve a backend when no specific environment is involved
#'
#' Used both for `env_name = NULL` callers (e.g. `get_install_dir()`) and
#' for a genuinely new environment (nothing to disambiguate against yet).
#'
#' @keywords internal
#' @noRd
resolve_backend_by_priority <- function(method, call = rlang::caller_env()) {
  if (isFALSE(identical(method, "auto"))) {
    backend <- get_backend(method, call = call)
    return(list(backend = backend, name = method))
  }
  priority <- getOption(
    "condathis.backend_priority",
    c("rattler", "micromamba")
  )
  candidates <- intersect(priority, list_registered_backend_names())
  for (candidate in candidates) {
    backend <- get_backend(candidate, call = call)
    if (isTRUE(backend_available(backend))) {
      return(list(backend = backend, name = candidate))
    }
  }
  cli::cli_abort(
    message = c(`x` = "No registered backend is currently available."),
    class = "condathis_backend_none_available",
    call = call
  )
}

#' Resolve a backend for an environment that already exists under exactly
#' one registered backend
#'
#' @keywords internal
#' @noRd
resolve_backend_existing_env <- function(
  env_name,
  method,
  owner,
  mutating,
  call = rlang::caller_env()
) {
  if (identical(method, "auto") || identical(method, owner)) {
    backend <- get_backend(owner, call = call)
    return(list(backend = backend, name = owner))
  }

  if (isTRUE(mutating)) {
    cli::cli_abort(
      message = c(
        `x` = "Environment {.field {env_name}} is owned by backend {.field {owner}}, not {.field {method}}.",
        `!` = "Remove it first, or use {.code method = \"{owner}\"}."
      ),
      class = "condathis_backend_mismatch",
      call = call
    )
  }

  cli::cli_warn(
    message = c(
      `!` = "Environment {.field {env_name}} is owned by backend {.field {owner}}, not {.field {method}}.",
      `i` = "Using {.field {owner}} instead."
    ),
    class = "condathis_backend_mismatch_warning"
  )
  backend <- get_backend(owner, call = call)
  return(list(backend = backend, name = owner))
}

#' Resolve a backend for an environment that exists under more than one
#' registered backend simultaneously
#'
#' @keywords internal
#' @noRd
resolve_backend_ambiguous_env <- function(
  env_name,
  method,
  owners,
  call = rlang::caller_env()
) {
  if (isTRUE(method %in% owners)) {
    backend <- get_backend(method, call = call)
    return(list(backend = backend, name = method))
  }
  cli::cli_abort(
    message = c(
      `x` = "Environment {.field {env_name}} exists under more than one backend: {.field {owners}}.",
      `!` = "Specify an explicit {.arg method} to disambiguate."
    ),
    class = "condathis_backend_ambiguous_env",
    call = call
  )
}

#' Resolve which backend a call should use
#'
#' The shared dispatch point for every backend-touching public function.
#'
#' @param env_name Character string, or `NULL` when the caller has no
#'   specific environment in mind (e.g. `get_install_dir()`).
#' @param method Character string: `"auto"`, a registered backend name, or
#'   the deprecated `"native"` alias.
#' @param mutating Logical. Whether the caller is about to create/modify/
#'   remove the environment (`TRUE`: a backend/marker mismatch aborts) or
#'   only read from it (`FALSE`: a mismatch warns and uses the actual
#'   owner instead).
#' @param call Calling environment, passed to `cli::cli_abort()`/`cli_warn()`.
#'
#' @returns A list with `backend` (the resolved backend object) and `name`
#'   (its registered name).
#'
#' @keywords internal
#' @noRd
resolve_backend <- function(
  env_name = NULL,
  method = "auto",
  mutating = FALSE,
  call = rlang::caller_env()
) {
  method <- resolve_method_alias(validate_method_arg(method, call = call))

  if (rlang::is_null(env_name)) {
    return(resolve_backend_by_priority(method, call = call))
  }

  owners <- find_owning_backends(env_name)

  if (identical(length(owners), 0L)) {
    return(resolve_backend_by_priority(method, call = call))
  }
  if (identical(length(owners), 1L)) {
    return(resolve_backend_existing_env(
      env_name = env_name,
      method = method,
      owner = owners[[1L]],
      mutating = mutating,
      call = call
    ))
  }
  return(resolve_backend_ambiguous_env(
    env_name = env_name,
    method = method,
    owners = owners,
    call = call
  ))
}

# --- The 10 backend contract generics -------------------------------------
# Signatures match rattlerthis's already-implemented adapter
# (R/condathis-backend.R) exactly, so wiring a second backend later is
# mechanical, not a renegotiation.

#' @keywords internal
#' @noRd
backend_create_env <- function(
  backend,
  packages = NULL,
  env_file = NULL,
  env_name = "condathis-env",
  channels = c("conda-forge", "bioconda"),
  channel_priority = c("disabled", "strict", "flexible"),
  additional_channels = NULL,
  platform = NULL,
  overwrite = FALSE,
  verbose = c("output", "silent", "cmd", "spinner", "full")
) {
  UseMethod("backend_create_env")
}

#' @keywords internal
#' @noRd
backend_install <- function(
  backend,
  packages,
  env_name = "condathis-env",
  channels = c("conda-forge", "bioconda"),
  channel_priority = c("disabled", "strict", "flexible"),
  additional_channels = NULL,
  verbose = c("output", "silent", "cmd", "spinner", "full")
) {
  UseMethod("backend_install")
}

#' @keywords internal
#' @noRd
backend_remove_env <- function(
  backend,
  env_name = "condathis-env",
  verbose = c("silent", "cmd", "output", "spinner", "full")
) {
  UseMethod("backend_remove_env")
}

#' @keywords internal
#' @noRd
backend_list_envs <- function(backend, verbose = "silent") {
  UseMethod("backend_list_envs")
}

#' @keywords internal
#' @noRd
backend_env_exists <- function(backend, env_name, verbose = "silent") {
  UseMethod("backend_env_exists")
}

#' @keywords internal
#' @noRd
backend_list_packages <- function(
  backend,
  env_name = "condathis-env",
  verbose = "silent"
) {
  UseMethod("backend_list_packages")
}

#' @keywords internal
#' @noRd
backend_get_env_dir <- function(backend, env_name = "condathis-env") {
  UseMethod("backend_get_env_dir")
}

#' @keywords internal
#' @noRd
backend_get_install_dir <- function(backend) {
  UseMethod("backend_get_install_dir")
}

#' @keywords internal
#' @noRd
backend_resolve_run <- function(
  backend,
  cmd,
  args = character(0L),
  env_name = "condathis-env",
  verbose = "silent"
) {
  UseMethod("backend_resolve_run")
}

#' @keywords internal
#' @noRd
backend_available <- function(backend) {
  UseMethod("backend_available")
}
