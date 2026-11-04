# Helpers of the tests of the environment lock (test-env_lock.R): other R
# sessions (callr) that race this one, a stub backend that every session
# registers alike, and a local channel with two packages.
#
# A session copies the environment variables and library paths of this
# process when it starts, so it works in the test sandbox of this process
# (see setup.R), and it gets this process's micromamba binary.

# Waits until `condition()` is TRUE, polling every 50 ms, at most `timeout`
# seconds. The test errors when the time runs out, so a broken expectation
# never hangs the run.
lock_wait_until <- function(condition, timeout = 120, what = "the condition") {
  started <- Sys.time()
  repeat {
    if (isTRUE(condition())) {
      return(invisible(TRUE))
    }
    waited <- as.numeric(difftime(Sys.time(), started, units = "secs"))
    if (isTRUE(waited > timeout)) {
      stop("Timed out after ", timeout, " s waiting for ", what, ".")
    }
    Sys.sleep(0.05)
  }
}

# The source directory of condathis when this process loaded it with
# pkgload (devtools::test(), testthat::test_local()), or `NULL` for an
# installed condathis (R CMD check).
condathis_source_dir <- function() {
  path <- getNamespaceInfo("condathis", "path")
  if (isTRUE(file.exists(file.path(path, "R", "create_env.R")))) {
    return(path)
  }
  return(NULL)
}

# A new R session with this condathis loaded, closed (killed when busy)
# when the caller ends. `micromamba_path` is the binary it uses.
local_lock_session <- function(micromamba_path = NULL, env = parent.frame()) {
  session <- callr::r_session$new(
    options = callr::r_session_options(libpath = .libPaths()),
    wait = TRUE
  )
  withr::defer(session$close(), envir = env)
  session$run(
    function(source_dir, micromamba_path) {
      if (is.null(source_dir)) {
        loadNamespace("condathis")
      } else {
        pkgload::load_all(
          source_dir,
          quiet = TRUE,
          helpers = FALSE,
          attach_testthat = FALSE,
          export_all = FALSE
        )
      }
      if (isFALSE(is.null(micromamba_path))) {
        options(condathis.micromamba_path = micromamba_path)
      }
      return(invisible(NULL))
    },
    args = list(
      source_dir = condathis_source_dir(),
      micromamba_path = micromamba_path
    )
  )
  return(session)
}

# Sends an interrupt, as Ctrl-C does, to a session that runs a call:
# SIGINT on Linux and macOS, CTRL+BREAK on Windows, where callr's
# `interrupt()` sends CTRL+C, which never reaches the R of a callr session
# (it runs in a process group of its own).
interrupt_lock_session <- function(session) {
  if (isTRUE(is_windows())) {
    ps::ps_interrupt(session$as_ps_handle(), ctrl_c = FALSE)
  } else {
    session$interrupt()
  }
  return(invisible(session))
}

# Whether this process ignores SIGINT. R on Linux keeps SIGINT ignored when
# it starts with it ignored, as a background job of a shell script does,
# and its R children ignore it too, so `interrupt_lock_session()` cannot
# reach them. Linux only (it reads `/proc/self/status`); `FALSE` elsewhere.
sigint_ignored <- function() {
  if (isFALSE(file.exists("/proc/self/status"))) {
    return(FALSE)
  }
  status <- readLines("/proc/self/status")
  ign <- sub(
    "^SigIgn:[[:space:]]*",
    "",
    grep("^SigIgn:", status, value = TRUE)
  )
  if (isFALSE(identical(length(ign), 1L))) {
    return(FALSE)
  }
  # The mask is hexadecimal; signal n is bit n - 1, so SIGINT (2) is 2 in
  # the last digit.
  last <- strtoi(substring(ign, nchar(ign)), 16L)
  return(isTRUE(bitwAnd(last, 2L) != 0L))
}

# The marker files of a call that `start_lock_call()` started: `in` when it
# reached the backend function `hook` (its lock is held then), `waiting`
# when it said that it waits for a lock (of an environment or of the
# package caches), and `go`, which the test creates to let a held call go
# on.
lock_marker <- function(sync_dir, label, what) {
  return(file.path(sync_dir, paste0(label, ".", what)))
}

# Runs condathis's exported function `fn` with the list `args` in
# `session`, and returns at once (see `lock_call_outcome()`). When the call
# reaches the backend function `hook`, it creates the marker `in`, and with
# `hold = TRUE` it then waits there until the marker `go` exists, holding
# the lock of the environment. It creates `waiting` when it says that it
# waits for the lock. The value of the call is a list: `value` ("done",
# "error" or "interrupted"), `error_class` and `error_message` (`NULL`
# without an error), `messages` (the first class of each message) and
# `waited` (whether it said that it waits).
start_lock_call <- function(
  session,
  fn,
  args,
  hook,
  sync_dir,
  label,
  hold = FALSE
) {
  session$call(
    function(fn, args, hook, in_file, go_file, waiting_file, hold) {
      ns <- asNamespace("condathis")
      tracer <- bquote({
        file.create(.(in_file))
        if (isTRUE(.(hold))) {
          while (isFALSE(file.exists(.(go_file)))) {
            Sys.sleep(0.05)
          }
        }
      })
      suppressMessages(trace(hook, tracer = tracer, where = ns, print = FALSE))
      on.exit(suppressMessages(untrace(hook, where = ns)), add = TRUE)
      error_class <- NULL
      error_message <- NULL
      messages <- character(0L)
      value <- withCallingHandlers(
        tryCatch(
          {
            do.call(getExportedValue("condathis", fn), args)
            "done"
          },
          interrupt = function(cnd) "interrupted",
          error = function(cnd) {
            error_class <<- class(cnd)
            error_message <<- conditionMessage(cnd)
            return("error")
          }
        ),
        message = function(cnd) {
          if (
            inherits(
              cnd,
              c("condathis_env_lock_waiting", "condathis_cache_lock_waiting")
            )
          ) {
            file.create(waiting_file)
          }
          messages <<- c(messages, class(cnd)[[1L]])
          invokeRestart("muffleMessage")
        }
      )
      return(list(
        value = value,
        error_class = error_class,
        error_message = error_message,
        messages = messages,
        waited = any(
          c("condathis_env_lock_waiting", "condathis_cache_lock_waiting") %in%
            messages
        )
      ))
    },
    args = list(
      fn = fn,
      args = args,
      hook = hook,
      in_file = lock_marker(sync_dir, label, "in"),
      go_file = lock_marker(sync_dir, label, "go"),
      waiting_file = lock_marker(sync_dir, label, "waiting"),
      hold = hold
    )
  )
  return(invisible(session))
}

# The outcome of the call that `start_lock_call()` started, which must
# return within `timeout` seconds: its value, or a list with the `value`
# "timeout" or "session error".
lock_call_outcome <- function(session, timeout = 300) {
  state <- session$poll_process(as.integer(timeout * 1000))
  if (isFALSE(identical(state, "ready"))) {
    return(list(value = "timeout"))
  }
  out <- session$read()
  if (isFALSE(is.null(out$error))) {
    return(list(
      value = "session error",
      error_message = conditionMessage(out$error)
    ))
  }
  return(out$result)
}

# Whether another process can take the lock of `env_name` now. Asked from a
# new R process: this process would get a lock that it holds itself.
env_lock_is_free <- function(env_name) {
  return(callr::r(
    function(path) {
      lock <- filelock::lock(path, exclusive = TRUE, timeout = 0)
      return(isFALSE(is.null(lock)))
    },
    args = list(path = as.character(env_lock_path(env_name))),
    libpath = .libPaths()
  ))
}

# Registers the stub backend `"lockstub"` in this session, for the caller
# only, or (from a session, with `env = NULL`) for the rest of the session.
# Self-contained, so a session can run it. Its environments are conda
# prefixes in its default root, `backend_root_dir("lockstub")`, which every
# session of the test sandbox shares. Each package of a create or an
# install gets a package record (version 1.0, from conda-forge, noarch), so
# condathis's default `list_packages()` lists it. An install into a missing
# environment fails. Removal is condathis's default.
register_lock_stub <- function(env = NULL) {
  root <- function() {
    return(as.character(condathis::backend_root_dir("lockstub")))
  }
  env_dir <- function(env_name) {
    return(file.path(root(), "envs", env_name))
  }
  write_records <- function(env_name, packages) {
    for (pkg in as.character(packages)) {
      record <- list(
        name = pkg,
        version = "1.0",
        build = "0",
        build_number = 0L,
        channel = "https://conda.anaconda.org/conda-forge",
        subdir = "noarch",
        url = paste0(
          "https://conda.anaconda.org/conda-forge/noarch/",
          pkg,
          "-1.0-0.conda"
        )
      )
      jsonlite::write_json(
        record,
        file.path(env_dir(env_name), "conda-meta", paste0(pkg, "-1.0-0.json")),
        auto_unbox = TRUE
      )
    }
    return(invisible(NULL))
  }
  backend <- structure(
    list(
      backend_create_env = function(
        backend,
        packages = NULL,
        env_name = "condathis-env",
        ...
      ) {
        dir.create(
          file.path(env_dir(env_name), "conda-meta"),
          recursive = TRUE
        )
        file.create(file.path(env_dir(env_name), "conda-meta", "history"))
        write_records(env_name, packages)
        return(invisible(NULL))
      },
      backend_install = function(
        backend,
        packages,
        env_name = "condathis-env",
        ...
      ) {
        if (isFALSE(dir.exists(file.path(env_dir(env_name), "conda-meta")))) {
          stop("Environment '", env_name, "' is missing.")
        }
        write_records(env_name, packages)
        return(invisible(NULL))
      },
      backend_resolve_run = function(backend, cmd, args = character(0L), ...) {
        return(list(command = cmd, args = args, env = NULL, dir = NULL))
      }
    ),
    class = c("condathis_backend_lockstub", "condathis_backend")
  )
  condathis::register_backend("lockstub", backend)
  if (isFALSE(is.null(env))) {
    withr::defer(condathis::unregister_backend("lockstub"), envir = env)
  }
  return(invisible("lockstub"))
}

# A local channel with two noarch packages, `lkpkg-a` and `lkpkg-b`, each
# with one file, `share/<name>.txt`. Returns its `file://` URL.
lock_test_channel <- function(.local_envir = parent.frame()) {
  channel_dir <- fs::path(
    withr::local_tempdir(.local_envir = .local_envir),
    "lkchannel"
  )
  fs::dir_create(fs::path(channel_dir, "noarch"))
  entries <- list()
  for (name in c("lkpkg-a", "lkpkg-b")) {
    pkg_dir <- fs::path(withr::local_tempdir(), "pkg")
    fs::dir_create(fs::path(pkg_dir, c("info", "share")))
    rel_path <- paste0("share/", name, ".txt")
    writeLines(name, fs::path(pkg_dir, rel_path))
    index <- list(
      name = name,
      version = "1.0",
      build = "0",
      build_number = 0L,
      depends = character(),
      license = "MIT",
      noarch = "generic",
      subdir = "noarch"
    )
    jsonlite::write_json(
      index,
      fs::path(pkg_dir, "info", "index.json"),
      auto_unbox = TRUE
    )
    writeLines(rel_path, fs::path(pkg_dir, "info", "files"))
    jsonlite::write_json(
      list(
        paths = list(list(
          `_path` = rel_path,
          path_type = "hardlink",
          sha256 = compute_sha256(fs::path(pkg_dir, rel_path)),
          size_in_bytes = as.numeric(fs::file_size(fs::path(pkg_dir, rel_path)))
        )),
        paths_version = 1L
      ),
      fs::path(pkg_dir, "info", "paths.json"),
      auto_unbox = TRUE
    )
    pkg_file <- paste0(name, "-1.0-0.tar.bz2")
    tarball <- fs::path(channel_dir, "noarch", pkg_file)
    withr::with_dir(pkg_dir, {
      utils::tar(
        tarfile = tarball,
        files = c("info", "share"),
        compression = "bzip2",
        tar = "internal"
      )
    })
    entries[[pkg_file]] <- c(
      index,
      list(
        md5 = unname(tools::md5sum(tarball)),
        sha256 = compute_sha256(tarball),
        size = as.numeric(fs::file_size(tarball))
      )
    )
  }
  jsonlite::write_json(
    list(
      info = list(subdir = "noarch"),
      packages = entries,
      `packages.conda` = structure(list(), names = character()),
      repodata_version = 1L
    ),
    fs::path(channel_dir, "noarch", "repodata.json"),
    auto_unbox = TRUE
  )
  channel_dir <- normalizePath(channel_dir, winslash = "/", mustWork = TRUE)
  return(paste0("file://", if (isTRUE(is_windows())) "/", channel_dir))
}
