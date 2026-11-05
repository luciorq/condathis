# Helpers for the tests of run() and run_bin().

# Absolute path of the Rscript of this R session: an existing file on
# Linux, macOS and Windows. A stub backend can start it directly, so these
# tests need neither micromamba nor the network.
run_family_rscript <- function() {
  exe <- if (isTRUE(is_windows())) "Rscript.exe" else "Rscript"
  return(normalizePath(
    file.path(R.home("bin"), exe),
    winslash = "/",
    mustWork = TRUE
  ))
}

# A stub backend from `local_stub_backend()` (helper-stub-backend.R) for the
# calling test, which is also the only backend that name-addressed calls
# probe, so micromamba never starts.
local_run_family_stub <- function(
  name = "stub-run",
  ...,
  envs = "stub-env",
  envir = parent.frame()
) {
  stub <- local_stub_backend(name, ..., envs = envs, envir = envir)
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() name,
    .package = "condathis",
    .env = envir
  )
  return(invisible(stub))
}

# Mocks that fail the test when the run family gets past argument checks
# (rule R2): no backend is resolved and nothing is spawned.
local_no_backend_calls <- function(envir = parent.frame()) {
  fail_called <- function(...) {
    testthat::fail("A backend was resolved before the arguments were checked.")
    stop("unreachable")
  }
  testthat::local_mocked_bindings(
    resolve_backend = fail_called,
    resolve_env_path_target = fail_called,
    create_base_env = fail_called,
    .package = "condathis",
    .env = envir
  )
  return(invisible(NULL))
}

# A program called `name` in `dir` that prints `text`: a shell script on
# Linux and macOS, a `.cmd` file on Windows, where `PATHEXT` finds it.
run_family_write_tool <- function(dir, name, text) {
  if (isTRUE(is_windows())) {
    path <- fs::path(dir, paste0(name, ".cmd"))
    writeLines(c("@echo off", paste("echo", text)), path)
  } else {
    path <- fs::path(dir, name)
    writeLines(c("#!/bin/sh", paste("echo", text)), path)
    fs::file_chmod(path, "u+x")
  }
  return(invisible(path))
}

# Scripts that leave a daemon behind, for the `cleanup_tree` tests. The
# spawner starts the sleeper with `processx` and `cleanup = FALSE`, then
# waits until the sleeper has written its process ID, so the caller can
# always find it. `args(pid_file)` gives the arguments of `Rscript` that
# run the spawner. Every daemon is stopped when the calling test ends.
local_run_family_daemon <- function(envir = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = envir)
  sleeper <- file.path(dir, "sleeper.R")
  spawner <- file.path(dir, "spawner.R")
  writeLines(
    c(
      "pid_file <- commandArgs(TRUE)[[1L]]",
      # Written to a temporary name first, so a reader never sees half.
      "writeLines(as.character(Sys.getpid()), paste0(pid_file, '.tmp'))",
      "file.rename(paste0(pid_file, '.tmp'), pid_file)",
      "Sys.sleep(60)"
    ),
    sleeper
  )
  writeLines(
    c(
      "args <- commandArgs(TRUE)",
      "lib_paths <- strsplit(args[[1L]], .Platform$path.sep, fixed = TRUE)",
      ".libPaths(c(lib_paths[[1L]], .libPaths()))",
      "processx::process$new(",
      "  args[[2L]],",
      "  c('--vanilla', args[[3L]], args[[4L]]),",
      "  cleanup = FALSE",
      ")",
      "for (i in seq_len(400L)) {",
      "  if (file.exists(args[[4L]])) break",
      "  Sys.sleep(0.05)",
      "}"
    ),
    spawner
  )
  lib_paths <- paste(.libPaths(), collapse = .Platform$path.sep)
  pid_files <- character(0L)
  withr::defer(
    {
      for (pid_file in pid_files) {
        pid <- run_family_read_pid(pid_file)
        if (isTRUE(run_family_pid_running(pid))) {
          tryCatch(
            ps::ps_kill(ps::ps_handle(pid)),
            error = function(e) NULL
          )
        }
      }
    },
    envir = envir
  )
  args <- function(pid_file) {
    pid_files <<- c(pid_files, pid_file)
    return(c(
      "--vanilla",
      spawner,
      lib_paths,
      run_family_rscript(),
      sleeper,
      pid_file
    ))
  }
  return(list(dir = dir, args = args))
}

# The process ID in `pid_file`, or `NA`.
run_family_read_pid <- function(pid_file) {
  if (isFALSE(file.exists(pid_file))) {
    return(NA_integer_)
  }
  pid <- suppressWarnings(as.integer(readLines(pid_file, warn = FALSE)))
  if (isFALSE(length(pid) == 1L) || isTRUE(is.na(pid))) {
    return(NA_integer_)
  }
  return(pid)
}

# Whether `pid` still runs. A zombie does not count (see
# `process_running()`): on Linux a killed process is one until it is
# reaped, and in a container whose first process never reaps, a killed
# process whose parent has ended stays one. A process that is gone has no
# handle at all.
run_family_pid_running <- function(pid) {
  if (isTRUE(is.na(pid))) {
    return(FALSE)
  }
  return(tryCatch(
    isTRUE(process_running(ps::ps_handle(pid))),
    error = function(e) FALSE
  ))
}

# Whether `pid` still runs after up to `wait` seconds: Windows ends a
# killed process asynchronously.
run_family_pid_survives <- function(pid, wait = 10) {
  deadline <- Sys.time() + wait
  while (isTRUE(run_family_pid_running(pid))) {
    if (Sys.time() > deadline) {
      return(TRUE)
    }
    Sys.sleep(0.1)
  }
  return(FALSE)
}
