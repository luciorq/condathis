#' Hold the lock of an environment until the calling function returns
#'
#' `create_env()`, `install_packages()` and `remove_env()` change an
#' environment only while they hold its lock, for every backend, so two R
#' sessions never change one environment at the same time. Without it,
#' `remove_env()` deleted an environment while another session installed
#' into it, and `create_env(overwrite = TRUE)` replaced an environment
#' while another session installed into it: micromamba then finished both
#' and left the packages of both requests in the new environment, and
#' rattler failed both. The lock covers the whole call, from the backend
#' resolution to the last change: the existence checks, the set-aside and
#' the restore of `with_env_dir_replacement()`, and the backend's work.
#'
#' The lock is keyed on the environment name, not on a backend: names are
#' one name space for every backend, so two sessions that create one name
#' with two backends do not both succeed. A session that already holds the
#' lock gets it again at once (`filelock` counts the handles of a file in
#' one process), as when `install_packages()` creates the missing default
#' environment with `create_env()`.
#'
#' A second session waits (see `acquire_condathis_lock()`): when another
#' session holds the lock, it waits up to `env_lock_notice_ms()`
#' milliseconds, then informs that it waits (class
#' `condathis_env_lock_waiting`, unless `verbose` is `"silent"`) and waits
#' without a time limit. An interrupt (Ctrl-C) stops the wait. When the
#' lock cannot be taken at all (a file system without lock support, a
#' directory that cannot be written), the call goes on without it: the
#' lock must never make a call fail. `env_lock_before_change()` then warns
#' once per session, with class `condathis_env_lock_unavailable`, when the
#' call goes on to change something, so a call that changes nothing (an
#' environment that already has the requested packages) does not warn.
#'
#' @param env_name Character string, a valid environment name.
#' @param verbose Character string, the verbose strategy of the caller.
#' @param .local_envir Environment whose exit releases the lock.
#'
#' @returns The lock holder (see `local_condathis_lock()`), invisibly.
#'
#' @keywords internal
#' @noRd
local_env_lock <- function(
  env_name,
  verbose = "output",
  .local_envir = parent.frame()
) {
  return(local_condathis_lock(
    lock_path = env_lock_path(env_name),
    exclusive = TRUE,
    kind = "env",
    env_name = env_name,
    verbose = verbose,
    .local_envir = .local_envir
  ))
}

#' Hold the lock of the package caches until the calling function returns
#'
#' `create_env()` and `install_packages()` hold it shared, so any number
#' of them run at once, and `clean_cache()` holds it exclusive: it waits
#' until no other R session creates or installs, and they wait until it is
#' done. Without it, `clean_cache()` deleted micromamba's package cache,
#' its lock files included, while another session downloaded into it, and
#' that create failed. The waiting, the notice (class
#' `condathis_cache_lock_waiting`) and the fallback without a lock are
#' those of `local_env_lock()`. A create or install takes it after the
#' lock of its environment, never before, so no two sessions wait for each
#' other.
#'
#' @param exclusive Logical. `TRUE` for `clean_cache()`.
#' @param verbose Character string, the verbose strategy of the caller.
#' @param .local_envir Environment whose exit releases the lock.
#'
#' @returns The lock holder (see `local_condathis_lock()`), invisibly.
#'
#' @keywords internal
#' @noRd
local_cache_lock <- function(
  exclusive = FALSE,
  verbose = "output",
  .local_envir = parent.frame()
) {
  return(local_condathis_lock(
    lock_path = cache_lock_path(),
    exclusive = exclusive,
    kind = "cache",
    verbose = verbose,
    .local_envir = .local_envir
  ))
}

#' Take a lock of condathis and release it when a function returns
#'
#' The exit handler is registered before the lock is taken, so an
#' interrupt right after the wait still releases it.
#'
#' @param lock_path Character string, the lock file.
#' @param exclusive Logical, the kind of lock.
#' @param kind `"env"` or `"cache"`, for the messages.
#' @param env_name Character string, the environment of an `"env"` lock.
#' @param verbose Character string, the verbose strategy of the caller.
#' @param .local_envir Environment whose exit releases the lock.
#'
#' @returns An environment, the holder, invisibly: `lock` (the
#'   `filelock_lock` object, or `NULL`), `path`, `kind`, `env_name` and
#'   `unavailable` (the reason why no lock could be taken, or `NULL`).
#'
#' @keywords internal
#' @noRd
local_condathis_lock <- function(
  lock_path,
  exclusive,
  kind,
  env_name = NULL,
  verbose = "output",
  .local_envir = parent.frame()
) {
  holder <- new.env(parent = emptyenv())
  holder$lock <- NULL
  holder$path <- as.character(lock_path)
  holder$kind <- kind
  holder$env_name <- env_name
  holder$unavailable <- NULL
  withr::defer(release_condathis_lock(holder), envir = .local_envir)
  taken <- acquire_condathis_lock(
    lock_path,
    exclusive = exclusive,
    kind = kind,
    env_name = env_name,
    verbose = verbose
  )
  if (isTRUE(inherits(taken, "error"))) {
    holder$unavailable <- conditionMessage(taken)
  } else {
    holder$lock <- taken
  }
  return(invisible(holder))
}

#' Warn when a call changes something without its locks
#'
#' Called by `create_env()`, `install_packages()`, `remove_env()` and
#' `clean_cache()` right before their first change, with the holders of
#' the locks they took. A lock that could not be taken warns once per
#' session, with class `condathis_env_lock_unavailable`.
#'
#' @param ... Lock holders from `local_env_lock()` and
#'   `local_cache_lock()`.
#'
#' @returns `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
env_lock_before_change <- function(...) {
  for (holder in list(...)) {
    reason <- holder$unavailable
    if (is.null(reason)) {
      next
    }
    if (identical(holder$kind, "env")) {
      env_name <- holder$env_name
      message <- c(
        `!` = "Could not lock environment {.field {env_name}}, so another R session could change it at the same time.",
        `i` = "{reason}"
      )
    } else {
      message <- c(
        `!` = "Could not lock the package caches, so another R session could clean them while they are used.",
        `i` = "{reason}"
      )
    }
    condathis_warn_once(
      id = "env_lock_unavailable",
      message = message,
      class = "condathis_env_lock_unavailable"
    )
  }
  return(invisible(NULL))
}

#' Release a lock that `local_condathis_lock()` took
#'
#' The owner entry of the session (see `acquire_condathis_lock()`) is
#' deleted when its last hold of the lock ends, before the lock itself is
#' released.
#'
#' @param holder Environment, the holder.
#'
#' @returns `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
release_condathis_lock <- function(holder) {
  lock <- holder$lock
  holder$lock <- NULL
  if (is.null(lock)) {
    return(invisible(NULL))
  }
  suspendInterrupts({
    state <- condathis_lock_state[[holder$path]]
    if (isFALSE(is.null(state))) {
      state$depth <- state$depth - 1L
      if (isTRUE(state$depth > 0L)) {
        condathis_lock_state[[holder$path]] <- state
      } else {
        rm(list = holder$path, envir = condathis_lock_state)
        delete_lock_owner_entry(state$entry)
      }
    }
    filelock::unlock(lock)
  })
  return(invisible(NULL))
}

#' The locks that this R session holds
#'
#' One element per lock file: `list(depth, entry)`, the number of holds and
#' the owner entry of this session (see `acquire_condathis_lock()`).
#'
#' @keywords internal
#' @noRd
condathis_lock_state <- new.env(parent = emptyenv())

#' The lock file of an environment
#'
#' `<condathis data directory>/locks/<name>.lock`: outside every
#' environment directory and every backend root, so `list_envs()` never
#' sees it, a removal or a replacement of the environment never moves it,
#' and `clean_cache()` never deletes it. It follows `with_sandbox_dir()`.
#' The name is lower case (ASCII letters only, as in the C locale), so the
#' names that open one directory on a file system that ignores case share
#' one lock on every OS. The file stays after use: deleting a lock file that
#' another session waits for lets a third session take a new file of the
#' same name at the same time.
#'
#' @param env_name Character string, a valid environment name.
#'
#' @returns An `fs_path`.
#'
#' @keywords internal
#' @noRd
env_lock_path <- function(env_name) {
  lock_name <- chartr(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
    "abcdefghijklmnopqrstuvwxyz",
    env_name
  )
  return(fs::path(env_lock_dir(), paste0(lock_name, ".lock")))
}

#' The lock file of the package caches
#'
#' `<condathis data directory>/locks/#cache.lock`. An environment name
#' never contains `#` (see `validate_env_name()`), so no environment lock
#' has this name.
#'
#' @returns An `fs_path`.
#'
#' @keywords internal
#' @noRd
cache_lock_path <- function() {
  return(fs::path(env_lock_dir(), "#cache.lock"))
}

#' The directory of the environment locks
#'
#' @returns An `fs_path`, `<condathis data directory>/locks`.
#'
#' @keywords internal
#' @noRd
env_lock_dir <- function() {
  return(fs::path(get_condathis_path(), "locks"))
}

#' How long a session waits for a lock before it says so
#'
#' @returns Integer, milliseconds.
#'
#' @keywords internal
#' @noRd
env_lock_notice_ms <- function() {
  return(2000L)
}

#' Take a lock, waiting for other sessions
#'
#' `filelock::lock()` is called only with `timeout = Inf`, which returns
#' with the lock, or with an error when the wait is interrupted (it then
#' closes its file handle). A call with a finite time limit that runs out
#' returns `NULL` and keeps its file descriptor or handle open (filelock
#' 1.0.3): on Windows such a handle keeps the lock file from being deleted,
#' so `with_sandbox_dir()` could not delete its directory, and a timed wait
#' could end holding the lock with a handle that nothing releases, so the
#' session then waited for itself forever.
#'
#' So the session does not ask filelock whether another session holds the
#' lock. Every session that holds a lock has an owner entry, a file named
#' `<x|s>-<pid>-<start time>` in the directory `<lock file>.owners`. When
#' another live process has an entry that conflicts with the request (any
#' entry for an exclusive lock, an exclusive one for a shared lock), the
#' session waits up to `env_lock_notice_ms()` for it to go, then says that
#' it waits (unless `verbose` is `"silent"`), then takes the lock. The
#' entries only decide about the message: the lock itself is the file
#' lock. An entry whose process has ended (a crash) is deleted.
#'
#' @param lock_path Character string, the lock file.
#' @param exclusive Logical, the kind of lock.
#' @param kind `"env"` or `"cache"`, for the message.
#' @param env_name Character string, the environment of an `"env"` lock.
#' @param verbose Character string, the verbose strategy of the caller.
#'
#' @returns A `filelock_lock` object, or the error when the file cannot be
#'   locked. An interrupt during the wait is signaled as an interrupt.
#'
#' @keywords internal
#' @noRd
acquire_condathis_lock <- function(
  lock_path,
  exclusive,
  kind,
  env_name = NULL,
  verbose = "output"
) {
  lock_path <- as.character(lock_path)
  prepared <- tryCatch(
    {
      lock_dir <- fs::path_dir(lock_path)
      if (isFALSE(fs::dir_exists(lock_dir))) {
        fs::dir_create(lock_dir)
      }
      NULL
    },
    error = function(cnd) cnd
  )
  if (isFALSE(is.null(prepared))) {
    return(prepared)
  }
  state <- condathis_lock_state[[lock_path]]
  owners_dir <- lock_owners_dir(lock_path)
  if (
    is.null(state) &&
      isTRUE(lock_held_by_others(owners_dir, exclusive = exclusive))
  ) {
    started <- Sys.time()
    while (
      isTRUE(
        as.numeric(difftime(Sys.time(), started, units = "secs")) <
          env_lock_notice_ms() / 1000
      ) &&
        isTRUE(lock_held_by_others(owners_dir, exclusive = exclusive))
    ) {
      Sys.sleep(0.05)
    }
    if (
      isTRUE(lock_held_by_others(owners_dir, exclusive = exclusive)) &&
        isFALSE(identical(verbose, "silent"))
    ) {
      inform_lock_waiting(kind, env_name = env_name, exclusive = exclusive)
    }
  }
  lock <- try_env_lock(lock_path, timeout = Inf, exclusive = exclusive)
  if (isTRUE(inherits(lock, "error"))) {
    return(lock)
  }
  suspendInterrupts({
    if (is.null(state)) {
      state <- list(
        depth = 0L,
        entry = write_lock_owner_entry(owners_dir, exclusive = exclusive)
      )
    }
    state$depth <- state$depth + 1L
    condathis_lock_state[[lock_path]] <- state
  })
  return(lock)
}

#' Say that a call waits for a lock of another session
#'
#' @param kind `"env"` or `"cache"`.
#' @param env_name Character string, the environment of an `"env"` lock.
#' @param exclusive Logical, the kind of lock requested.
#'
#' @returns `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
inform_lock_waiting <- function(kind, env_name = NULL, exclusive = TRUE) {
  if (identical(kind, "env")) {
    condathis_inform(
      message = c(
        `i` = "Waiting for another R session to finish changing environment {.field {env_name}}."
      ),
      class = "condathis_env_lock_waiting"
    )
  } else if (isTRUE(exclusive)) {
    condathis_inform(
      message = c(
        `i` = "Waiting for other R sessions to finish creating environments or installing packages."
      ),
      class = "condathis_cache_lock_waiting"
    )
  } else {
    condathis_inform(
      message = c(
        `i` = "Waiting for another R session to finish cleaning the package caches."
      ),
      class = "condathis_cache_lock_waiting"
    )
  }
  return(invisible(NULL))
}

#' The directory of the owner entries of a lock file
#'
#' @param lock_path Character string, the lock file.
#'
#' @returns A character string, `<lock file>.owners`.
#'
#' @keywords internal
#' @noRd
lock_owners_dir <- function(lock_path) {
  return(paste0(as.character(lock_path), ".owners"))
}

#' Write the owner entry of this session
#'
#' Best effort: an entry that cannot be written only means that a waiting
#' session does not say that it waits.
#'
#' @param owners_dir Character string, from `lock_owners_dir()`.
#' @param exclusive Logical, the kind of lock held.
#'
#' @returns The path of the entry, or `NULL`.
#'
#' @keywords internal
#' @noRd
write_lock_owner_entry <- function(owners_dir, exclusive) {
  entry <- fs::path(
    owners_dir,
    sprintf(
      "%s-%d-%.3f",
      if (isTRUE(exclusive)) "x" else "s",
      Sys.getpid(),
      lock_process_start_time(Sys.getpid())
    )
  )
  written <- tryCatch(
    {
      if (isFALSE(fs::dir_exists(owners_dir))) {
        fs::dir_create(owners_dir)
      }
      fs::file_create(entry)
      TRUE
    },
    error = function(cnd) FALSE
  )
  if (isFALSE(written)) {
    return(NULL)
  }
  return(as.character(entry))
}

#' Delete an owner entry, if there is one
#'
#' Its directory goes too when it is empty then. Another session that
#' writes its entry at that moment may fail to: it then only does not get
#' a waiting session's notice.
#'
#' @param entry Character string, or `NULL`.
#'
#' @returns `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
delete_lock_owner_entry <- function(entry) {
  if (isFALSE(is.null(entry))) {
    tryCatch(fs::file_delete(entry), error = function(cnd) NULL)
    owners_dir <- fs::path_dir(entry)
    tryCatch(
      {
        if (identical(length(fs::dir_ls(owners_dir, all = TRUE)), 0L)) {
          fs::dir_delete(owners_dir)
        }
      },
      error = function(cnd) NULL
    )
  }
  return(invisible(NULL))
}

#' Whether another live process holds a lock that conflicts with a request
#'
#' @param owners_dir Character string, from `lock_owners_dir()`.
#' @param exclusive Logical, the kind of lock requested: an exclusive
#'   request conflicts with every entry, a shared one only with exclusive
#'   entries.
#'
#' @returns Logical scalar. The entries of processes that have ended are
#'   deleted.
#'
#' @keywords internal
#' @noRd
lock_held_by_others <- function(owners_dir, exclusive) {
  entries <- tryCatch(
    as.character(fs::dir_ls(owners_dir, type = "file", all = TRUE)),
    error = function(cnd) character(0L)
  )
  if (identical(length(entries), 0L)) {
    return(FALSE)
  }
  parts <- regmatches(
    fs::path_file(entries),
    regexec("^([xs])-([0-9]+)-([0-9.]+)$", fs::path_file(entries))
  )
  for (i in seq_along(entries)) {
    fields <- parts[[i]]
    if (isFALSE(identical(length(fields), 4L))) {
      next
    }
    pid <- as.integer(fields[[3L]])
    if (isTRUE(is.na(pid)) || isTRUE(identical(pid, Sys.getpid()))) {
      next
    }
    if (isFALSE(exclusive) && isFALSE(identical(fields[[2L]], "x"))) {
      next
    }
    if (isTRUE(lock_owner_alive(pid, as.numeric(fields[[4L]])))) {
      return(TRUE)
    }
    delete_lock_owner_entry(entries[[i]])
  }
  return(FALSE)
}

#' Whether the process of an owner entry still runs
#'
#' The start time tells a process apart from a later one that got the
#' same process ID. A process whose start time cannot be read counts as
#' running.
#'
#' @param pid Integer, the process ID.
#' @param start_time Numeric, its start time in seconds.
#'
#' @returns Logical scalar.
#'
#' @keywords internal
#' @noRd
lock_owner_alive <- function(pid, start_time) {
  current <- lock_process_start_time(pid)
  if (is.null(current)) {
    return(FALSE)
  }
  if (isTRUE(is.na(current)) || isTRUE(is.na(start_time))) {
    return(TRUE)
  }
  return(isTRUE(abs(current - start_time) < 1))
}

#' The start time of a process
#'
#' @param pid Integer, the process ID.
#'
#' @returns Numeric seconds, `NA` when the process runs but its start time
#'   cannot be read, or `NULL` when no such process runs.
#'
#' @keywords internal
#' @noRd
lock_process_start_time <- function(pid) {
  handle <- tryCatch(ps::ps_handle(as.integer(pid)), error = function(e) NULL)
  if (is.null(handle)) {
    return(NULL)
  }
  # A zombie has ended: its entry must not make other sessions wait.
  running <- tryCatch(process_running(handle), error = function(e) TRUE)
  if (isFALSE(running)) {
    return(NULL)
  }
  return(tryCatch(
    as.numeric(ps::ps_create_time(handle)),
    error = function(e) NA_real_
  ))
}

#' Wait for the lock file of an environment
#'
#' @param lock_path Character string, from `env_lock_path()`.
#' @param timeout Milliseconds to wait. `acquire_condathis_lock()` passes
#'   only `Inf` (see there).
#' @param exclusive Logical, the kind of lock.
#'
#' @returns A `filelock_lock` object, `NULL` when the time ran out, or the
#'   error when the file cannot be locked at all. On Windows, `filelock`
#'   turns an interrupt during a wait into the error "Locking interrupted";
#'   it is signaled as an interrupt again, as on Linux and macOS.
#'
#' @keywords internal
#' @noRd
try_env_lock <- function(lock_path, timeout = Inf, exclusive = TRUE) {
  return(tryCatch(
    {
      lock_dir <- fs::path_dir(lock_path)
      if (isFALSE(fs::dir_exists(lock_dir))) {
        fs::dir_create(lock_dir)
      }
      filelock::lock(
        as.character(lock_path),
        exclusive = exclusive,
        timeout = timeout
      )
    },
    error = function(cnd) {
      if (identical(conditionMessage(cnd), "Locking interrupted")) {
        rlang::interrupt()
      }
      return(cnd)
    }
  ))
}
