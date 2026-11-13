#' Clean the package caches of condathis
#'
#' @description
#' Removes the package and metadata caches of condathis and of every
#' registered backend, and nothing else:
#' * For the built-in micromamba backend, the package cache, `pkgs`, and
#'   the repodata cache, `cache`, in its data directory (see
#'   [get_install_dir()]).
#' * For every other backend, its own package and metadata caches, and
#'   `conda-pkgs` in its data directory. `conda-pkgs` is the package cache
#'   of the Conda tools that run in its environments (see *Child processes*
#'   in [register_backend()]).
#' * The contents of the condathis cache directory,
#'   `tools::R_user_dir("condathis", "cache")`.
#'
#' `clean_cache()` never deletes the per-user caches of conda, mamba and
#' micromamba, such as `~/.cache/conda`, which other tools share.
#'
#' @inheritParams condathis-params
#'
#' @returns A `condathis_result` object, invisibly: a classed list with
#'   `status`, `stdout`, `stderr`, `timeout`, `pid`, `cmd` and `env_name`.
#'   The values come from the micromamba command that ran, and `cmd` is its
#'   command line.
#'   When no micromamba command ran, `status` is `0`, `timeout` is `FALSE`
#'   and the other fields are `NA`. `pid` is always `NA`, and so is
#'   `env_name`: the caches are not tied to an environment.
#'
#' @details
#' Environments keep the files of their packages. These files usually share
#' disk space with the package cache through hard links. You free that space
#' only by also removing those environments (see [list_envs()] and
#' [remove_env()]).
#'
#' When the micromamba package cache does not exist, micromamba has nothing
#' to clean. `clean_cache()` then starts no process and does not install
#' micromamba. It still deletes the repodata cache and clears the condathis
#' cache directory.
#'
#' `clean_cache()` loads a backend whose package condathis knows, such as
#' `"rattler"` of the `rattlerthis` package, when its data directory has
#' caches or environments. When that package is not installed,
#' `clean_cache()` does not clean its caches and warns with class
#' `condathis_backend_not_installed`.
#'
#' `clean_cache()` waits until no other R session creates an environment
#' or installs packages. Those sessions wait until it is done (see *Other R
#' sessions* in [create_env()]).
#'
#' When a backend fails to clean its caches, `clean_cache()` still cleans
#' the caches of the other backends and the directories above. Then it
#' aborts with the first failure. That error has the classes
#' `condathis_clean_cache_failed` and `condathis_backend_error`, and the
#' error of the backend as its parent. When `clean_cache()` cannot delete a
#' directory itself, it aborts with class `condathis_clean_cache_failed` the
#' same way.
#'
#' @section Removing everything:
#' `clean_cache()` keeps micromamba and the environments. To remove
#' everything that `condathis` installed, delete its data and cache
#' directories, in an R session that runs no `condathis` command at the
#' same time:
#'
#' ```r
#' unlink(condathis::get_install_dir()$path, recursive = TRUE)
#' unlink(tools::R_user_dir("condathis", "cache"), recursive = TRUE)
#' ```
#'
#' The condathis data directory, the `path` of the `"micromamba"` row of
#' [get_install_dir()], holds the micromamba binary that
#' [install_micromamba()] downloaded, every environment, the package and
#' repodata caches, the lock files and the configuration file that
#' `condathis` writes for micromamba. The data
#' directories of the other backends that use [backend_root_dir()] are
#' inside it. [get_install_dir()] also lists the data directory of a
#' registered backend that chose its own.
#'
#' This leaves alone what `condathis` did not install: a micromamba that
#' `condathis` found elsewhere (see *micromamba discovery* in
#' [condathis-options]), environments that you passed as [env_path()],
#' the lines that micromamba added to `~/.conda/environments.txt`, the pip
#' cache on macOS and Windows (see [get_install_dir()]), and on Windows the
#' Start Menu shortcuts that `condathis` 0.1.4 and earlier added (see
#' [remove_env()]).
#'
#' @family setup
#' @seealso [condathis-conditions] for every condition class.
#'
#' @examples
#' condathis::with_sandbox_dir({
#'   condathis::clean_cache(verbose = "output")
#' })
#'
#' @export
clean_cache <- function(
  verbose = c(
    "output",
    "silent",
    "cmd",
    "spinner",
    "full"
  )
) {
  verbose_list <- parse_verbose_arg(verbose)
  # No R session creates an environment or installs packages while the
  # caches are deleted, and none starts until they are (see
  # `local_cache_lock()`). Without a data directory there is no cache to
  # delete, and none is created for the lock.
  if (isTRUE(fs::dir_exists(get_condathis_path()))) {
    cache_lock <- local_cache_lock(
      exclusive = TRUE,
      verbose = verbose_list$strategy
    )
    env_lock_before_change(cache_lock)
  }
  # A known backend package with environments or caches is loaded, so its
  # backend is registered. A package that cannot be loaded warns here, once
  # per session.
  known_warned <- known_backend_warned()
  load_known_backends(caches = TRUE)
  just_warned <- known_backend_warned() & !known_warned
  # No work that a backend still does in this R process may write into a
  # cache while it is deleted.
  quiesce_registered_backends(call = rlang::current_env())

  # Every backend cleans its caches, also after another one failed: the
  # first failure is raised once everything else is done.
  failures <- list()
  micromamba_res <- NULL
  clean_cache_call <- rlang::current_env()
  for (nm in backend_names_by_priority()) {
    backend_res <- tryCatch(
      clean_backend_cache(
        nm,
        verbose = verbose_list$strategy,
        call = clean_cache_call
      ),
      error = function(e) e
    )
    if (isTRUE(inherits(backend_res, "error"))) {
      failures <- c(failures, list(backend_res))
    } else if (identical(nm, "micromamba")) {
      micromamba_res <- backend_res
    }
  }

  for (pkgs_dir in backend_conda_pkgs_dirs()) {
    delete_failure <- delete_cache_dir(pkgs_dir, call = clean_cache_call)
    if (isFALSE(is.null(delete_failure))) {
      failures <- c(failures, list(delete_failure))
    }
  }
  warn_uncleaned_known_backends(
    skip = names(known_backend_packages)[just_warned]
  )

  r_user_cache <- fs::path(
    tools::R_user_dir(package = "condathis", which = "cache")
  )
  if (fs::dir_exists(r_user_cache)) {
    cache_failure <- tryCatch(
      {
        for (content_item in fs::dir_ls(r_user_cache)) {
          # A link is deleted, never followed: `fs::file_delete()` deletes
          # the files in the directory that a link points to.
          if (isTRUE(fs::is_link(content_item))) {
            fs::link_delete(content_item)
          } else {
            fs::file_delete(content_item)
          }
        }
        NULL
      },
      error = function(e) {
        return(clean_cache_dir_error(r_user_cache, e, call = clean_cache_call))
      }
    )
    if (isFALSE(is.null(cache_failure))) {
      failures <- c(failures, list(cache_failure))
    }
  }

  if (isTRUE(length(failures) > 0L)) {
    rlang::cnd_signal(failures[[1L]])
  }

  if (isTRUE(verbose_list$strategy %in% c("full", "output"))) {
    condathis_inform(
      message = c(
        `v` = "Cache successfully removed."
      )
    )
  }

  result <- micromamba_res %||%
    new_condathis_result(
      status = 0L,
      stdout = NA_character_,
      stderr = NA_character_,
      timeout = FALSE,
      pid = NA_integer_,
      cmd = NA_character_,
      env_name = NA_character_
    )
  return(invisible(result))
}

#' Run the `backend_clean_cache()` function of one registered backend
#'
#' @param name Character string, the registered backend name.
#' @param verbose One of the five verbose strings.
#' @param call Environment of `clean_cache()`, for errors.
#'
#' @returns `NULL` when the backend had nothing to clean, else a
#'   `condathis_result` from `new_clean_cache_result()`. A failure of the
#'   backend aborts with `c("condathis_clean_cache_failed",
#'   "condathis_backend_error", <the condathis_* classes of its error>,
#'   "condathis_error")`, with its error as the parent (see
#'   `with_backend_errors()`).
#'
#' @keywords internal
#' @noRd
clean_backend_cache <- function(name, verbose, call = rlang::caller_env()) {
  px_res <- with_backend_errors(
    backend_clean_cache(get_backend(name, call = call), verbose = verbose),
    fn = "clean_cache",
    backend_name = name,
    action = "clean its caches",
    call = call
  )
  return(new_clean_cache_result(px_res, backend_name = name, call = call))
}

#' Check the value that `backend_clean_cache()` returned
#'
#' The rules of `new_backend_result()`, with messages that name no
#' environment: `NULL` means "nothing to clean". Any other value that is
#' not a list counts as `list()`. From a list, `status`, `stdout`,
#' `stderr`, `timeout`, `pid` and `cmd` are read, with exact names, and
#' every other element is ignored.
#'
#' @param px_res The value the backend returned.
#' @param backend_name Character string, the registered backend name.
#' @param call Environment of `clean_cache()`, for errors.
#'
#' @returns `NULL` for `NULL`, else a `condathis_result` with status `0L`
#'   and `env_name = NA`. A `status` that is not a whole number aborts with
#'   `c("condathis_backend_invalid_return",
#'   "condathis_backend_contract_violation", "condathis_error")`. A
#'   non-zero status aborts with `c("condathis_clean_cache_failed",
#'   "condathis_backend_error", "condathis_error")` and the fields
#'   `status`, `stdout` and `stderr`: a backend must signal its failures.
#'
#' @keywords internal
#' @noRd
new_clean_cache_result <- function(
  px_res,
  backend_name,
  call = rlang::caller_env()
) {
  if (is.null(px_res)) {
    return(NULL)
  }
  if (isFALSE(is.list(px_res))) {
    px_res <- list()
  }
  is_whole_number <- function(x) {
    return(
      isTRUE(is.numeric(x)) &&
        identical(length(x), 1L) &&
        isFALSE(is.na(x)) &&
        isTRUE(x == trunc(x)) &&
        isTRUE(abs(x) <= .Machine$integer.max)
    )
  }
  stream_or_na <- function(x) {
    if (isTRUE(rlang::is_string(x)) || isTRUE(is.raw(x))) {
      return(x)
    }
    return(NA_character_)
  }

  status <- px_res[["status"]]
  if (is.null(status)) {
    status <- 0L
  } else if (isTRUE(is_whole_number(status))) {
    status <- as.integer(status)
  } else {
    condathis_abort(
      message = c(
        `x` = "Backend {.field {backend_name}} returned an invalid {.field status} from {.fn backend_clean_cache}.",
        `i` = "{.field status} must be a single whole number, not {.obj_type_friendly {status}}."
      ),
      class = c(
        "condathis_backend_invalid_return",
        "condathis_backend_contract_violation"
      ),
      call = call
    )
  }
  stdout <- stream_or_na(px_res[["stdout"]])
  stderr <- stream_or_na(px_res[["stderr"]])
  if (isFALSE(identical(status, 0L))) {
    condathis_abort(
      message = c(
        `x` = "Backend {.field {backend_name}} returned exit status {.val {status}} from {.fn backend_clean_cache}.",
        `i` = "A backend must signal an error when an operation fails."
      ),
      class = c("condathis_clean_cache_failed", "condathis_backend_error"),
      status = status,
      stdout = stdout,
      stderr = stderr,
      call = call
    )
  }
  pid <- px_res[["pid"]]
  cmd <- px_res[["cmd"]]
  return(new_condathis_result(
    status = status,
    stdout = stdout,
    stderr = stderr,
    timeout = isTRUE(px_res[["timeout"]]),
    pid = if (isTRUE(is_whole_number(pid))) as.integer(pid) else NA_integer_,
    cmd = if (isTRUE(rlang::is_string(cmd))) {
      hide_secrets(cmd)
    } else {
      NA_character_
    },
    env_name = NA_character_
  ))
}

#' The `conda-pkgs` directories that `clean_cache()` empties
#'
#' condathis points the package cache of Conda tools run in the
#' environments of a backend other than micromamba at `<root>/conda-pkgs`
#' (see `child_conda_dirs()`), and owns that directory in every backend
#' root. These are that directory in `backend_root_dir()` of every
#' registered or known backend name other than `"micromamba"`, and, for a
#' registered backend with a root of its own, the one that its children
#' get (see `backend_conda_pkgs_dir()`): never one next to an `envs`
#' directory outside the root of the backend. Nothing is created:
#' `backend_get_env_dir()` only computes a path, and the root of the
#' backend is asked for only when the directory that would hold
#' `conda-pkgs` exists.
#'
#' @returns Character vector of paths, without duplicates. They need not
#'   exist.
#'
#' @keywords internal
#' @noRd
backend_conda_pkgs_dirs <- function() {
  registered <- setdiff(backend_names_by_priority(), "micromamba")
  dirs <- character(0L)
  for (nm in union(registered, names(known_backend_packages))) {
    dirs <- c(
      dirs,
      as.character(fs::path(backend_root_path(nm), "conda-pkgs"))
    )
    if (isFALSE(nm %in% registered)) {
      next
    }
    env_pkgs_dir <- tryCatch(
      {
        backend <- get_backend(nm)
        env_dir <- env_dir_for_backend(backend, "condathis-env")
        if (isTRUE(fs::dir_exists(fs::path_dir(fs::path_dir(env_dir))))) {
          child_conda_dirs(backend, env_dir = env_dir)$pkgs_dir
        }
      },
      error = function(e) NULL
    )
    dirs <- c(dirs, env_pkgs_dir)
  }
  return(unique(dirs))
}

#' Delete a cache directory of condathis
#'
#' A symbolic link is removed, never followed.
#'
#' @param path Character string, the directory. Nothing happens when it
#'   does not exist.
#' @param call Environment of `clean_cache()`, for errors.
#'
#' @returns `NULL` when `path` no longer exists, else the error from
#'   `clean_cache_dir_error()`, not signaled.
#'
#' @keywords internal
#' @noRd
delete_cache_dir <- function(path, call = rlang::caller_env()) {
  return(tryCatch(
    {
      if (isTRUE(fs::is_link(path))) {
        fs::link_delete(path)
      } else if (isTRUE(fs::dir_exists(path))) {
        fs::dir_delete(path)
      }
      NULL
    },
    error = function(e) {
      return(clean_cache_dir_error(path, e, call = call))
    }
  ))
}

#' The error of a cache directory that `clean_cache()` could not empty
#'
#' @param path Character string, the directory.
#' @param cnd The error of the deletion.
#' @param call Environment of `clean_cache()`.
#'
#' @returns An error condition of class `c("condathis_clean_cache_failed",
#'   "condathis_error")`, with `cnd` as its parent. Not signaled.
#'
#' @keywords internal
#' @noRd
clean_cache_dir_error <- function(path, cnd, call = rlang::caller_env()) {
  return(rlang::catch_cnd(
    condathis_abort(
      message = c(`x` = "Could not empty the cache directory {.path {path}}."),
      class = "condathis_clean_cache_failed",
      parent = cnd,
      call = call
    ),
    classes = "error"
  ))
}

#' Which known backends got their once-per-session warning
#'
#' @returns Logical vector, one element per name of
#'   `known_backend_packages`: whether the warning of
#'   `known_backend_warn_id()` was given in this session.
#'
#' @keywords internal
#' @noRd
known_backend_warned <- function() {
  return(vapply(
    names(known_backend_packages),
    function(name) {
      return(isTRUE(condathis_warn_once_state[[known_backend_warn_id(name)]]))
    },
    logical(1L),
    USE.NAMES = FALSE
  ))
}

#' Warn about the caches of known backends that are not registered
#'
#' `clean_cache()` cannot ask a backend whose package is missing to clean
#' its caches. When the root of such a backend still has an entry other
#' than `envs` (its `conda-pkgs` directory is already deleted), this warns
#' on every call.
#'
#' @param skip Character vector of backend names to leave out: those whose
#'   package failed to load in this call, which `load_known_backends()`
#'   already warned about.
#'
#' @returns `NULL`, invisibly. Warns with
#'   `c("condathis_backend_not_installed", "condathis_warning")`, or
#'   `condathis_backend_load_failed` instead of the first class when the
#'   package is installed but its backend is not registered.
#'
#' @keywords internal
#' @noRd
warn_uncleaned_known_backends <- function(skip = character(0L)) {
  for (name in setdiff(unregistered_known_backend_names(), skip)) {
    if (isFALSE(backend_has_cache_entries(name))) {
      next
    }
    pkg <- known_backend_packages[[name]]
    root <- backend_root_path(name)
    status <- known_backend_unloaded_status(name)
    cause <- known_backend_cause(status$reason, form = "its")
    condathis_warn(
      message = c(
        `!` = paste0(
          "The caches of backend {.field {name}} in {.path {root}} were not cleaned: ",
          cause,
          "."
        )
      ),
      class = known_backend_condition_class(status),
      parent = status$cnd
    )
  }
  return(invisible(NULL))
}

#' The `backend_clean_cache()` function of the micromamba backend
#'
#' Deletes the package cache, `<root>/pkgs`, with `micromamba clean`, and
#' the repodata cache, `<root>/cache`, from R. Nothing outside the root.
#'
#' @param backend The micromamba backend object.
#' @param verbose One of the five verbose strings.
#'
#' @returns The result of `native_cmd()`, or `NULL` when there was no
#'   package cache: then no process starts and micromamba is not
#'   installed.
#'
#' @keywords internal
#' @noRd
micromamba_backend_clean_cache <- function(
  backend,
  verbose = c("output", "silent", "cmd", "spinner", "full")
) {
  verbose_list <- parse_strategy_verbose(verbose = verbose)

  # `--force-pkgs-dirs` deletes the whole `<root>/pkgs`
  # (`ensure_condathis_rc_file()` pins `pkgs_dirs` there): the packages,
  # the archives, the index cache and the lock files. Without that
  # directory the command has nothing to do, so it is skipped: running it
  # could download micromamba, and the search for a binary starts a process
  # for each candidate. No `--all`: since micromamba 2.6.1 it also deletes
  # the whole `<user cache>/conda`, files of other tools included, and the
  # user cache is outside the root whenever `native_cmd()` does not set it.
  root_dir <- get_condathis_path()
  pkgs_dir <- fs::path(root_dir, "pkgs")
  px_res <- NULL
  if (isTRUE(fs::dir_exists(pkgs_dir))) {
    px_res <- rethrow_error_cmd(
      expr = {
        native_cmd(
          conda_cmd = "clean",
          conda_args = c(
            "--yes",
            "--force-pkgs-dirs",
            verbose_list$quiet_flag
          ),
          verbose = verbose_list,
          error = "cancel"
        )
      }
    )
  }

  # The sharded repodata cache, under the `XDG_CACHE_HOME` that
  # `native_cmd()` gives micromamba: the part of `--all` that is in the
  # root.
  repodata_cache <- micromamba_cache_dir(root_dir)
  if (isTRUE(fs::dir_exists(repodata_cache))) {
    fs::dir_delete(repodata_cache)
  }
  return(px_res)
}
