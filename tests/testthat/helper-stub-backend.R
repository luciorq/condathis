# A stub backend for tests, registered for the calling test only.
#
# The stub keeps its environments as directories under its own root,
# `<root>/envs/<env_name>`, so it needs no network and no micromamba. Every
# generic records its call in `stub$calls`: one list per call, with
# `generic` (the generic name) and `args` (the arguments condathis passed,
# without `backend`). `stub_calls(stub, "backend_install")` returns the
# calls of one generic.
#
# Named functions in `...` replace generics, for example
# `local_stub_backend("stub-a", backend_env_exists = function(...) stop("x"))`.
# A replacement gets the same arguments as the generic. A `NULL` leaves the
# generic out of the object, so condathis uses its default, for example
# `local_stub_backend("stub-a", backend_remove_env = NULL)`.
# `backend_resolve_run_in_dir()` is left out unless `...` gives it, so a
# stub cannot run an environment given by `env_path()` by default.
#
# `available` is what `backend_available()` returns. `envs` names
# environments that exist from the start.
#
# `default_root = TRUE` keeps the environments in the root that condathis
# assigns, `backend_root_dir(name)`, which is created only when needed and
# deleted at the end of the test: the stub then leaves out
# `backend_get_install_dir()`, `backend_get_env_dir()`, `backend_list_envs()`
# and `backend_env_exists()`, so the defaults of condathis answer, and its
# environments get `conda-meta/history`, as conda prefixes. The root is
# looked up on every call, so it follows `with_sandbox_dir()`.
#
# Returns a list: `name`, `root` (an `fs_path`; with `default_root = TRUE`
# the root when the stub was made), `backend` (the registered object) and
# `calls` (an environment whose `calls` element holds the record).
#
# Other backends are still probed by name-addressed calls. Mock the
# priority order to keep a test away from micromamba:
# `testthat::local_mocked_bindings(backend_names_by_priority = function() c("stub-a"))`.
local_stub_backend <- function(
  name,
  ...,
  available = TRUE,
  envs = character(0L),
  default_root = FALSE,
  envir = parent.frame()
) {
  overrides <- list(...)
  if (isTRUE(default_root)) {
    root <- backend_root_dir(name)
    if (isFALSE(fs::dir_exists(root))) {
      withr::defer(
        {
          if (isTRUE(fs::dir_exists(root))) {
            fs::dir_delete(root)
          }
        },
        envir = envir
      )
    }
  } else {
    root <- fs::path(withr::local_tempdir(.local_envir = envir))
    fs::dir_create(fs::path(root, "envs"))
  }
  stub_root <- function() {
    if (isTRUE(default_root)) {
      return(backend_root_dir(name))
    }
    return(root)
  }
  make_env_dir <- function(env_name) {
    env_dir <- fs::path(stub_root(), "envs", env_name)
    fs::dir_create(env_dir)
    if (isTRUE(default_root)) {
      fs::dir_create(fs::path(env_dir, "conda-meta"))
      fs::file_create(fs::path(env_dir, "conda-meta", "history"))
    }
    return(invisible(env_dir))
  }
  for (env_name in envs) {
    make_env_dir(env_name)
  }
  record <- new.env(parent = emptyenv())
  record$calls <- list()

  defaults <- list(
    backend_create_env = function(backend, env_name = "condathis-env", ...) {
      make_env_dir(env_name)
      return(invisible(NULL))
    },
    backend_install = function(backend, ...) {
      return(invisible(NULL))
    },
    backend_remove_env = function(backend, env_name = "condathis-env", ...) {
      fs::dir_delete(fs::path(stub_root(), "envs", env_name))
      return(invisible(NULL))
    },
    backend_list_envs = function(backend, ...) {
      # condathis keeps replaced environments in `<root>/envs/#trash`.
      env_names <- as.character(fs::path_file(
        fs::dir_ls(fs::path(root, "envs"), type = "directory")
      ))
      return(setdiff(env_names, env_trash_name()))
    },
    backend_env_exists = function(backend, env_name, ...) {
      return(isTRUE(fs::dir_exists(fs::path(root, "envs", env_name))))
    },
    backend_list_packages = function(backend, ...) {
      return(data.frame(
        name = character(0L),
        version = character(0L),
        build_number = integer(0L),
        build_string = character(0L),
        channel = character(0L),
        platform = character(0L),
        stringsAsFactors = FALSE
      ))
    },
    backend_get_env_dir = function(backend, env_name = "condathis-env") {
      return(fs::path(root, "envs", env_name))
    },
    backend_get_install_dir = function(backend) {
      return(root)
    },
    backend_resolve_run = function(
      backend,
      cmd,
      args = character(0L),
      ...
    ) {
      return(list(command = cmd, args = args, env = character(0L), dir = NULL))
    },
    backend_available = function(backend) {
      return(available)
    },
    backend_clean_cache = function(backend, ...) {
      return(NULL)
    },
    backend_quiesce = function(backend, ...) {
      return(invisible(TRUE))
    },
    backend_native_platform = function(backend) {
      return(NA_character_)
    },
    backend_can_solve = function(backend, ...) {
      return(NA)
    }
  )
  unknown <- setdiff(
    names(overrides),
    c(names(defaults), "backend_resolve_run_in_dir")
  )
  if (length(unknown) > 0L) {
    stop("Unknown generic(s) for the stub: ", paste(unknown, collapse = ", "))
  }
  if (isTRUE(default_root)) {
    defaults[c(
      "backend_get_install_dir",
      "backend_get_env_dir",
      "backend_list_envs",
      "backend_env_exists"
    )] <- NULL
  }
  # `modifyList()` drops the elements that `overrides` sets to `NULL`.
  impls <- utils::modifyList(defaults, overrides)

  # The recorder takes every argument, so condathis passes the optional
  # ones (`timeout` of the resolution functions); the implementation gets
  # only those that it takes.
  recorder <- function(generic, impl) {
    force(generic)
    force(impl)
    return(function(backend, ...) {
      call_args <- list(...)
      record$calls[[length(record$calls) + 1L]] <- list(
        generic = generic,
        args = call_args
      )
      impl_args <- names(formals(impl))
      if (isFALSE("..." %in% impl_args)) {
        call_args <- call_args[
          !nzchar(rlang::names2(call_args)) |
            rlang::names2(call_args) %in% impl_args
        ]
      }
      return(do.call(impl, c(list(backend), call_args)))
    })
  }
  vtable <- lapply(names(impls), function(nm) recorder(nm, impls[[nm]]))
  names(vtable) <- names(impls)

  backend_class <- paste0(
    "condathis_backend_test_",
    gsub("[^A-Za-z0-9]", "_", name)
  )
  backend <- structure(vtable, class = c(backend_class, "condathis_backend"))
  register_backend(name, backend)
  withr::defer(unregister_backend(name), envir = envir)
  return(invisible(list(
    name = name,
    root = root,
    backend = backend,
    calls = record
  )))
}

# The recorded calls of a stub from `local_stub_backend()`, optionally only
# those of one generic.
stub_calls <- function(stub, generic = NULL) {
  calls <- stub$calls$calls
  if (is.null(generic)) {
    return(calls)
  }
  return(Filter(function(x) identical(x$generic, generic), calls))
}
