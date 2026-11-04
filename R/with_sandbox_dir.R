#' Run code with temporary home and data directories
#'
#' Evaluates code with temporary home, data, cache, configuration and
#' state directories. It is meant for examples and tests. `condathis` puts
#' the environments, packages and micromamba binary that it installs into
#' the sandbox, with every backend, not into your own directories. No Conda
#' configuration file of yours is in reach.
#'
#' Processes that `condathis` starts ignore the session's Conda settings.
#' Code that starts micromamba or conda itself must pass `--no-rc` and
#' `--no-env` to do the same.
#'
#' The sandbox lasts exactly as long as the call. Before
#' `with_sandbox_dir()` returns, also after an error in `code`, it does
#' these steps in this order:
#'
#' * It restores the working directory.
#' * It restores every environment variable, including ones that `code`
#'   set, changed or removed itself.
#' * It stops the processes that use the sandbox, and their children, if
#'   they are still running. These are the processes that `condathis`
#'   starts for `code`. A process counts when its executable or one of its
#'   arguments is a path inside the sandbox. It also counts when it runs
#'   with a `condathis` environment or package cache inside the sandbox.
#'   Other processes started inside `code` keep running, for example the
#'   `processx` supervisor, `callr` sessions and `mirai` daemons.
#' * It waits until every backend has finished its work in the R session.
#' * It deletes the sandbox directories, with every environment, package
#'   and micromamba binary installed into them. When it cannot delete them,
#'   `with_sandbox_dir()` warns with class
#'   `condathis_with_sandbox_dir_cleanup_failed`. An interrupt during this
#'   cleanup leaves them in the session's temporary directory.
#'
#' `with_sandbox_dir()` does not reset options and objects that `code`
#' assigns: `code` runs in `.local_envir`, as with `withr::with_envvar()`.
#' It does not change [tempdir()] or `TMPDIR` either, so files that `code`
#' writes there stay.
#'
#' @param code Expression to evaluate with the temporary directories.
#' @param .local_envir Environment `code` is evaluated in.
#'   Defaults to `parent.frame()`.
#'
#' @returns The value of `code`, visible or invisible as in `code`.
#'
#' @family setup
#'
#' @examples
#' condathis::with_sandbox_dir(print(fs::path_home()))
#' condathis::with_sandbox_dir(print(tools::R_user_dir("condathis")))
#' @export
with_sandbox_dir <- function(code, .local_envir = base::parent.frame()) {
  sandbox_root <- base::tempfile(pattern = "condathis-sandbox-")
  tmp_home_path <- fs::path(sandbox_root, "home")
  tmp_data_path <- fs::path(sandbox_root, "data")
  tmp_cache_path <- fs::path(sandbox_root, "cache")
  tmp_config_path <- fs::path(sandbox_root, "config")
  tmp_state_path <- fs::path(sandbox_root, "state")
  fs::dir_create(c(
    tmp_home_path,
    tmp_data_path,
    tmp_cache_path,
    tmp_config_path,
    tmp_state_path
  ))

  # A value that is not valid in the session's encoding is read byte by
  # byte; `Sys.getenv()` reports what it cannot read at all.
  old_envvars <- current_envvars() %||% base::Sys.getenv()
  old_wd <- base::getwd()
  old_descendants <- process_keys(sandbox_descendants())
  # Every process started from here on inherits this variable, which is how
  # `ps::ps_find_tree()` finds them at the end, also after their parent
  # exited.
  process_marker <- ps::ps_mark_tree()
  base::on.exit(
    cleanup_sandbox(
      sandbox_root = sandbox_root,
      process_marker = process_marker,
      old_descendants = old_descendants,
      old_envvars = old_envvars,
      old_wd = old_wd,
      call = rlang::current_env()
    ),
    add = TRUE
  )

  base::Sys.setenv(
    `HOME` = tmp_home_path,
    `USERPROFILE` = tmp_home_path,
    `LOCALAPPDATA` = tmp_data_path,
    `APPDATA` = tmp_data_path,
    `R_USER_DATA_DIR` = tmp_data_path,
    `XDG_DATA_HOME` = tmp_data_path,
    `R_USER_CACHE_DIR` = tmp_cache_path,
    `XDG_CACHE_HOME` = tmp_cache_path,
    # micromamba's package extraction reads the configuration files of
    # `XDG_CONFIG_HOME` (see `?condathis-options`).
    `R_USER_CONFIG_DIR` = tmp_config_path,
    `XDG_CONFIG_HOME` = tmp_config_path,
    `XDG_STATE_HOME` = tmp_state_path
  )
  code <- base::substitute(expr = code)
  return(rlang::eval_bare(expr = code, env = .local_envir))
}

#' Undo everything a `with_sandbox_dir()` call did
#'
#' Restores the working directory and the environment variables first, so
#' that an interrupt during the slower steps that follow never leaves the
#' session in the sandbox. Then it stops the sandbox's processes, with
#' `stop_sandbox_processes()`: on Windows, a running process keeps its
#' files from being deleted. Then it waits until no registered backend
#' works in the R process any more (`quiesce_registered_backends()`), so
#' that no work of a backend that runs in this process, such as an install
#' that an interrupt did not stop at once, writes into the sandbox while
#' it is deleted. An interrupt during these steps skips the delete.
#'
#' @param sandbox_root Character string. The sandbox directory to delete.
#' @param process_marker Character string from `ps::ps_mark_tree()`.
#' @param old_descendants Character vector from `process_keys()`: the
#'   descendants that existed when the sandbox was set up.
#' @param old_envvars Named character vector from `Sys.getenv()`, taken
#'   before the sandbox was set up.
#' @param old_wd Character string. The working directory to restore.
#' @param call Environment of the `with_sandbox_dir()` call, which the
#'   warning for an invalid value of `backend_quiesce()` names.
#'
#' @returns `NULL`, invisibly. Warns with class
#'   `c("condathis_with_sandbox_dir_cleanup_failed",
#'   "condathis_sandbox_cleanup_failed", "condathis_warning")` if the
#'   sandbox directory could not be deleted. The second class is the old
#'   name, kept until 1.0.
#'
#' @keywords internal
#' @noRd
cleanup_sandbox <- function(
  sandbox_root,
  process_marker,
  old_descendants,
  old_envvars,
  old_wd,
  call = rlang::caller_env()
) {
  tryCatch(
    {
      if (
        isFALSE(identical(base::getwd(), old_wd)) &&
          isTRUE(base::dir.exists(old_wd))
      ) {
        base::setwd(old_wd)
      }
    },
    error = function(e) NULL
  )
  tryCatch(restore_envvars(old_envvars), error = function(e) NULL)

  tryCatch(
    stop_sandbox_processes(
      sandbox_root = sandbox_root,
      process_marker = process_marker,
      old_descendants = old_descendants
    ),
    error = function(e) NULL
  )
  # A backend that does not answer gives a warning, and the cleanup goes
  # on.
  tryCatch(quiesce_registered_backends(call = call), error = function(e) NULL)

  if (isFALSE(delete_sandbox_root(sandbox_root))) {
    condathis_warn(
      message = c(
        `!` = "Could not delete the sandbox directory {.path {sandbox_root}}."
      ),
      class = c(
        "condathis_with_sandbox_dir_cleanup_failed",
        "condathis_sandbox_cleanup_failed"
      )
    )
  }
  return(invisible(NULL))
}

#' Delete a sandbox directory
#'
#' Tries up to ten times, 0.2 seconds apart: a process stopped a moment ago
#' can hold its files open for a little while on Windows.
#'
#' @param sandbox_root Character string. The sandbox directory.
#'
#' @returns `TRUE` when the directory no longer exists, `FALSE` otherwise.
#'
#' @keywords internal
#' @noRd
delete_sandbox_root <- function(sandbox_root) {
  for (attempt in seq_len(10L)) {
    base::unlink(sandbox_root, recursive = TRUE, force = TRUE)
    if (isFALSE(base::dir.exists(sandbox_root))) {
      return(TRUE)
    }
    base::Sys.sleep(0.2)
  }
  return(isFALSE(base::dir.exists(sandbox_root)))
}

#' Stop the processes that use a sandbox
#'
#' Only processes started while the sandbox was active are candidates.
#' They are found two ways. Descendants of this R process that did not
#' exist when the sandbox was set up are found by parent ID, which works on
#' every platform but misses processes whose parent already exited.
#' Processes carrying `process_marker` are found by environment variable,
#' which also finds those, but not on macOS for system binaries such as
#' `/bin/sh`, or for a process that has not finished starting.
#'
#' A candidate is stopped only if it uses the sandbox (see
#' `process_uses_sandbox()`), together with its children. Every process
#' started inside the sandbox inherits its `HOME` and the marker, so these
#' alone do not tell the commands of `code` from session helpers that were
#' first started inside it. Stopping the `processx` supervisor that way left
#' every later `supervise = TRUE` process of the session without crash
#' cleanup, because `processx` only checks that it knows a supervisor ID.
#' The supervisor is never stopped, even if it is a child of a stopped
#' process.
#'
#' @inheritParams cleanup_sandbox
#'
#' @returns The stopped processes, as a list of `ps_handle` objects,
#'   invisibly.
#'
#' @keywords internal
#' @noRd
stop_sandbox_processes <- function(
  sandbox_root,
  process_marker,
  old_descendants
) {
  descendants <- sandbox_descendants()
  new_descendants <- descendants[
    !process_keys(descendants) %in% old_descendants
  ]
  marked <- tryCatch(
    ps::ps_find_tree(process_marker),
    error = function(e) list()
  )
  candidates <- unique_processes(c(new_descendants, marked))
  if (identical(length(candidates), 0L)) {
    return(invisible(list()))
  }

  root_forms <- sandbox_root_forms(sandbox_root)
  windows <- is_windows()
  uses_sandbox <- vapply(
    candidates,
    function(p) {
      info <- process_details(p)
      return(tryCatch(
        process_uses_sandbox(
          exe = info$exe,
          cmdline = info$cmdline,
          environ = info$environ,
          root_forms = root_forms,
          windows = windows
        ),
        error = function(e) FALSE
      ))
    },
    logical(1L)
  )
  users <- candidates[uses_sandbox]
  children <- lapply(users, function(p) {
    return(tryCatch(
      ps::ps_children(p, recursive = TRUE),
      error = function(e) list()
    ))
  })
  to_stop <- unique_processes(c(users, unlist(children, recursive = FALSE)))

  supervisor_pid <- processx_supervisor_pid()
  supervisor_exe <- processx_supervisor_exe()
  is_supervisor <- vapply(
    to_stop,
    function(p) {
      return(is_processx_supervisor(
        p,
        supervisor_pid = supervisor_pid,
        supervisor_exe = supervisor_exe,
        windows = windows
      ))
    },
    logical(1L)
  )
  to_stop <- to_stop[!is_supervisor]
  if (identical(length(to_stop), 0L)) {
    return(invisible(list()))
  }

  stopped <- tryCatch(
    {
      ps::ps_kill(to_stop)
      TRUE
    },
    error = function(e) FALSE
  )
  # `ps_kill()` signals an error when one process of the list cannot be
  # stopped, so the others are tried one by one.
  if (isFALSE(stopped)) {
    for (p in to_stop) {
      tryCatch(ps::ps_kill(p), error = function(e) NULL)
    }
  }
  return(invisible(to_stop))
}

#' Tell whether a process uses a sandbox
#'
#' A process uses the sandbox when its executable, one of its arguments, or
#' one of the variables in `sandbox_process_envvars()` names a path inside
#' it. These are the processes `condathis` starts there: micromamba gets
#' `-r <root>`, and environment binaries live in the root. micromamba and
#' the commands of its environments get `CONDA_ENVS_PATH` and
#' `CONDA_PKGS_DIRS` naming directories in the micromamba root. A command
#' of another backend's environment gets `CONDA_ENVS_PATH` naming the
#' parent of its environment, and, when that parent is `<root>/envs`,
#' `CONDA_PKGS_DIRS` naming `<root>/conda-pkgs` (see `child_conda_dirs()`).
#' Once activated, a command also gets `CONDA_PREFIX`. The variables that
#' `with_sandbox_dir()` sets itself, such as `HOME`, are not checked: every
#' process started inside the sandbox inherits them.
#'
#' @param exe Character string: the executable of the process, or `NA`.
#' @param cmdline Character vector: its command-line arguments.
#' @param environ Named character vector: its environment variables. Empty
#'   when they cannot be read.
#' @param root_forms Character vector from `sandbox_root_forms()`.
#' @param windows Logical. Whether to compare paths the Windows way:
#'   ignoring case, with `\` and `/` as the same separator.
#'
#' @returns `TRUE` or `FALSE`.
#'
#' @keywords internal
#' @noRd
process_uses_sandbox <- function(
  exe,
  cmdline,
  environ,
  root_forms,
  windows = is_windows()
) {
  env_names <- names(environ)
  if (is.null(env_names)) {
    env_names <- character(length(environ))
  }
  env_values <- unname(environ[
    toupper(env_names) %in% sandbox_process_envvars()
  ])
  strings <- c(exe, cmdline, env_values)
  strings <- strings[!is.na(strings) & nzchar(strings)]
  return(any(mentions_sandbox(
    strings,
    root_forms = root_forms,
    windows = windows
  )))
}

#' Environment variables that tie a process to a sandbox
#'
#' `condathis` sets the first three for every process it starts (see
#' `get_clean_conda_envvars()`). For micromamba and the commands of its
#' environments, `CONDA_ENVS_PATH` and both package-cache variables name
#' directories in the micromamba root, which is the condathis data
#' directory. For a command of another backend's environment,
#' `CONDA_ENVS_PATH` names the parent of its environment, and both
#' package-cache variables name `<root>/conda-pkgs` when that parent is
#' `<root>/envs`, else they are empty (see `child_conda_dirs()`). The root
#' of such a backend is inside the condathis data directory unless the
#' backend has its own (see `backend_root_dir()`), so these paths are in
#' the sandbox too. Activating an environment sets `CONDA_PREFIX`.
#'
#' @returns Character vector of variable names, in upper case.
#'
#' @keywords internal
#' @noRd
sandbox_process_envvars <- function() {
  return(c(
    "CONDA_ENVS_PATH",
    "CONDA_PKGS_DIRS",
    "MAMBA_PKGS_DIRS",
    "CONDA_PREFIX"
  ))
}

#' Find strings that name a path inside a sandbox
#'
#' A string matches when it contains one of `root_forms` followed by a path
#' separator, by its end, or by a character that cannot continue a file
#' name, such as a space or a quote. The root itself matches too.
#'
#' @param x Character vector.
#' @inheritParams process_uses_sandbox
#'
#' @returns Logical vector, one element per element of `x`.
#'
#' @keywords internal
#' @noRd
mentions_sandbox <- function(x, root_forms, windows = is_windows()) {
  x <- canonical_path_string(x, windows = windows)
  matches <- logical(length(x))
  for (form in root_forms) {
    # The next character must not continue the root's last name: otherwise
    # `<tmp>/condathis-sandbox-1a` would match `<tmp>/condathis-sandbox-1`.
    pattern <- paste0("\\Q", form, "\\E(?:$|[^A-Za-z0-9._-])")
    # Byte-wise, so a command line that is not valid UTF-8 cannot fail the
    # whole cleanup.
    matches <- matches | grepl(pattern, x, perl = TRUE, useBytes = TRUE)
  }
  return(matches)
}

#' The spellings of a sandbox root that a process can see
#'
#' The root comes from `tempfile()`. Processes can name it through a
#' symbolic link (`/var` and `/private/var` on macOS), as a Windows 8.3
#' short name, or in a long form. All of them are compared.
#' `canonical_path_string()` makes the number of separators between two
#' names irrelevant.
#'
#' @param sandbox_root Character string. The sandbox directory. If it does
#'   not exist, only its spelling is used.
#' @inheritParams process_uses_sandbox
#'
#' @returns Character vector from `canonical_path_string()`.
#'
#' @keywords internal
#' @noRd
sandbox_root_forms <- function(sandbox_root, windows = is_windows()) {
  forms <- c(
    sandbox_root,
    base::normalizePath(sandbox_root, winslash = "/", mustWork = FALSE),
    tryCatch(as.character(fs::path_real(sandbox_root)), error = function(e) {
      NA_character_
    })
  )
  forms <- canonical_path_string(forms, windows = windows)
  forms <- sub("/+$", "", forms)
  return(unique(forms[!is.na(forms) & nzchar(forms)]))
}

#' Write paths in one form for comparison
#'
#' @param x Character vector.
#' @inheritParams process_uses_sandbox
#'
#' @returns Character vector, with one `/` for each run of `/`. On Windows,
#'   also in lower case and with `/` for every `\`.
#'
#' @keywords internal
#' @noRd
canonical_path_string <- function(x, windows = is_windows()) {
  if (isTRUE(windows)) {
    x <- tolower(gsub("\\", "/", x, fixed = TRUE))
  }
  # `tempdir()` keeps a separator that ends `TMPDIR`, as in
  # `/var/folders/.../T//Rtmp...` on macOS. `fs::path()` removes it, so the
  # sandbox's `HOME` and `XDG_*` paths have one separator there. `/var` is a
  # symbolic link on macOS, so the real path of the root does not give that
  # spelling either. Byte-wise, so a command line that is not valid UTF-8
  # cannot fail the cleanup.
  x <- gsub("/{2,}", "/", x, useBytes = TRUE)
  return(x)
}

#' Read what `process_uses_sandbox()` needs about a process
#'
#' @param p A `ps_handle` object.
#'
#' @returns A list with `exe` (character string or `NA`), `cmdline`
#'   (character vector) and `environ` (named character vector). Each one
#'   that cannot be read, for example for a process that has exited, is
#'   `NA` or empty.
#'
#' @keywords internal
#' @noRd
process_details <- function(p) {
  return(list(
    exe = tryCatch(ps::ps_exe(p), error = function(e) NA_character_),
    cmdline = tryCatch(ps::ps_cmdline(p), error = function(e) character(0L)),
    environ = tryCatch(
      unclass(ps::ps_environ(p)),
      error = function(e) character(0L)
    )
  ))
}

#' Tell whether a process is the `processx` supervisor
#'
#' `processx` starts one supervisor per session, the first time a process
#' is started with `supervise = TRUE`, from the `supervisor` binary in its
#' `bin` directory (see `processx:::supervisor_start()`). Its ID is in
#' `processx:::supervisor_info$pid`.
#'
#' @param p A `ps_handle` object.
#' @param supervisor_pid Integer from `processx_supervisor_pid()`, or
#'   `NULL`.
#' @param supervisor_exe Character string from `processx_supervisor_exe()`,
#'   or `NA`.
#' @inheritParams process_uses_sandbox
#'
#' @returns `TRUE` or `FALSE`.
#'
#' @keywords internal
#' @noRd
is_processx_supervisor <- function(
  p,
  supervisor_pid,
  supervisor_exe,
  windows = is_windows()
) {
  pid <- tryCatch(ps::ps_pid(p), error = function(e) NA_integer_)
  if (isTRUE(length(supervisor_pid) == 1L) && isTRUE(pid == supervisor_pid)) {
    return(TRUE)
  }
  if (isTRUE(is.na(supervisor_exe))) {
    return(FALSE)
  }
  exe <- tryCatch(
    base::normalizePath(ps::ps_exe(p), winslash = "/", mustWork = FALSE),
    error = function(e) NA_character_
  )
  return(isTRUE(
    canonical_path_string(exe, windows = windows) ==
      canonical_path_string(supervisor_exe, windows = windows)
  ))
}

#' The process ID of this session's `processx` supervisor
#'
#' `processx` does not export it, so it is read from the `supervisor_info`
#' environment of its namespace.
#'
#' @returns Integer, or `NULL` if no supervisor was started.
#'
#' @keywords internal
#' @noRd
processx_supervisor_pid <- function() {
  if (isFALSE(base::isNamespaceLoaded("processx"))) {
    return(NULL)
  }
  info <- tryCatch(
    base::get0(
      "supervisor_info",
      envir = base::asNamespace("processx"),
      inherits = FALSE
    ),
    error = function(e) NULL
  )
  if (isFALSE(is.environment(info))) {
    return(NULL)
  }
  pid <- suppressWarnings(as.integer(info$pid))
  if (isFALSE(length(pid) == 1L) || isTRUE(is.na(pid))) {
    return(NULL)
  }
  return(pid)
}

#' The path of the `processx` supervisor binary
#'
#' Same location as `processx:::supervisor_path()` for an installed
#' `processx`.
#'
#' @returns Character string, or `NA` if the binary is not found.
#'
#' @keywords internal
#' @noRd
processx_supervisor_exe <- function() {
  name <- if (isTRUE(is_windows())) "supervisor.exe" else "supervisor"
  path <- base::system.file(
    paste0("bin", base::Sys.getenv("R_ARCH")),
    name,
    package = "processx"
  )
  if (isFALSE(nzchar(path))) {
    return(NA_character_)
  }
  return(base::normalizePath(path, winslash = "/", mustWork = FALSE))
}

#' Set the environment variables back to a `Sys.getenv()` snapshot
#'
#' Removes variables that were added since, and resets the ones that were
#' changed or removed.
#'
#' @param old_envvars Named character vector from `Sys.getenv()`.
#'
#' @returns `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
restore_envvars <- function(old_envvars) {
  if (isTRUE(length(old_envvars) == 0L)) {
    return(invisible(NULL))
  }
  current <- current_envvars()
  if (is.null(current)) {
    # The variables cannot be listed: set every old value again, so at
    # least those are back.
    tryCatch(
      base::do.call(base::Sys.setenv, as.list(old_envvars)),
      error = function(e) NULL
    )
    return(invisible(NULL))
  }
  added <- base::setdiff(names(current), names(old_envvars))
  if (isTRUE(length(added) > 0L)) {
    base::Sys.unsetenv(added)
  }
  old_names <- names(old_envvars)
  # `identical()`, not `!=`: a value that is not valid in the session's
  # encoding cannot be compared with `!=`. A removed variable is `NA`.
  now_values <- unname(current[old_names])
  old_values <- unname(old_envvars)
  same <- vapply(
    seq_along(old_names),
    function(i) identical(now_values[[i]], old_values[[i]]),
    logical(1L)
  )
  changed <- old_names[!same]
  changed <- changed[!is.na(changed)]
  if (isTRUE(length(changed) > 0L)) {
    base::do.call(base::Sys.setenv, as.list(old_envvars[changed]))
  }
  return(invisible(NULL))
}

#' The environment variables of the R process
#'
#' [Sys.getenv()] fails with "invalid multibyte string" when a value is
#' not valid in the session's encoding (such as `"caf\xe9"` in a UTF-8
#' session). The values are then read in the C locale, byte by byte.
#'
#' @returns A named character vector, as from [Sys.getenv()], or `NULL`
#'   when the variables cannot be read at all.
#'
#' @keywords internal
#' @noRd
current_envvars <- function() {
  # The failing call also warns ("input string ... is invalid in this
  # locale") before it fails.
  return(tryCatch(
    base::suppressWarnings(base::Sys.getenv()),
    error = function(e) {
      old_locale <- base::Sys.getlocale("LC_CTYPE")
      base::on.exit(
        base::suppressWarnings(base::Sys.setlocale("LC_CTYPE", old_locale)),
        add = TRUE
      )
      base::suppressWarnings(base::Sys.setlocale("LC_CTYPE", "C"))
      tryCatch(
        base::suppressWarnings(base::Sys.getenv()),
        error = function(e) NULL
      )
    }
  ))
}

#' Descendants of this R process
#'
#' @returns A list of `ps_handle` objects.
#'
#' @keywords internal
#' @noRd
sandbox_descendants <- function() {
  return(tryCatch(
    ps::ps_children(ps::ps_handle(), recursive = TRUE),
    error = function(e) list()
  ))
}

#' Identify processes by ID and creation time
#'
#' A process ID alone can be reused by a later process.
#'
#' @param procs A list of `ps_handle` objects.
#'
#' @returns Character vector, one key per process.
#'
#' @keywords internal
#' @noRd
process_keys <- function(procs) {
  return(vapply(
    procs,
    function(p) {
      tryCatch(
        paste(
          ps::ps_pid(p),
          format(as.numeric(ps::ps_create_time(p)), nsmall = 3)
        ),
        error = function(e) NA_character_
      )
    },
    character(1L)
  ))
}

#' Remove duplicates from a list of processes
#'
#' Processes whose key cannot be read are dropped: they have exited.
#'
#' @param procs A list of `ps_handle` objects.
#'
#' @returns A list of `ps_handle` objects.
#'
#' @keywords internal
#' @noRd
unique_processes <- function(procs) {
  keys <- process_keys(procs)
  keep <- !is.na(keys) & !duplicated(keys)
  return(procs[keep])
}
