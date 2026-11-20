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

# The PATH that a command `run_family_rscript()` gets from `path`. When R
# comes from a Conda environment on Windows, `Rscript` is a program of
# R's prefix, and that prefix's directories follow at the end (D14).
# Everywhere else, `path` unchanged.
run_family_rscript_path <- function(path) {
  env <- r_prefix_command_env(run_family_rscript(), child_env = c(PATH = path))
  return(unname(env[["PATH"]]))
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
    stop("unreachable", call. = FALSE)
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
  tracked <- new.env(parent = emptyenv())
  tracked$pid_files <- character(0L)
  withr::defer(
    {
      for (pid_file in tracked$pid_files) {
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
    tracked$pid_files <- c(tracked$pid_files, pid_file)
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

# The directory of a fake host prefix that the tests put on PATH: `bin` on
# Linux and macOS, `Library/bin` on Windows, where `env_bin_search_dirs()`
# lists it too.
fake_host_bin <- function(prefix) {
  if (isTRUE(is_windows())) {
    return(as.character(fs::path(prefix, "Library", "bin")))
  }
  return(as.character(fs::path(prefix, "bin")))
}

# Fake Conda prefixes under `dir`, each with `conda-meta` and a binary
# directory that holds a program `condathis-host-tool` printing the name
# of its prefix. The inner prefix has an `env_vars.d` file, the outer one
# a `conda-meta/state` file. Returns the prefixes, named.
make_fake_host_prefixes <- function(dir, names = c("outer", "inner", "pixi")) {
  prefixes <- vapply(
    names,
    function(name) as.character(fs::path(dir, name)),
    character(1L)
  )
  for (name in names) {
    fs::dir_create(fs::path(prefixes[[name]], "conda-meta"))
    bin_dir <- fake_host_bin(prefixes[[name]])
    fs::dir_create(bin_dir)
    run_family_write_tool(bin_dir, "condathis-host-tool", name)
  }
  if ("inner" %in% names) {
    env_vars_dir <- fs::path(prefixes[["inner"]], "etc", "conda", "env_vars.d")
    fs::dir_create(env_vars_dir)
    writeLines(
      paste0(
        "{\"CONDATHIS_HOST_ENVVAR\": \"from-env-vars\",",
        " \"CONDATHIS_HOST_USER\": \"other\"}"
      ),
      fs::path(env_vars_dir, "host.json")
    )
  }
  if ("outer" %in% names) {
    writeLines(
      "{\"env_vars\": {\"CONDATHIS_STATE\": \"s\"}}",
      fs::path(prefixes[["outer"]], "conda-meta", "state")
    )
  }
  return(prefixes)
}

# The variables that conda and pixi leave in a shell where they stacked
# the activations of `prefixes` (from `make_fake_host_prefixes()`): pixi
# first, then outer, then inner. `path` is the PATH they activated over.
# Empty values are left out: on Windows, an empty value unsets the
# variable of the session.
fake_nested_host_vars <- function(prefixes, keep_dir, path) {
  return(list(
    CONDA_PREFIX = prefixes[["inner"]],
    CONDA_PREFIX_1 = prefixes[["outer"]],
    CONDA_SHLVL = "2",
    MAMBA_SHLVL = "2",
    CONDA_PROMPT_MODIFIER = "(inner) ",
    MAMBA_PROMPT_MODIFIER = "(inner) ",
    CONDA_DEFAULT_ENV = "inner",
    CONDA_ENV_SHLVL_1_CONDA_PREFIX = prefixes[["pixi"]],
    CONDA_ENV_SHLVL_1_CONDATHIS_HOST_SAVED = "before",
    CONDATHIS_HOST_SAVED = "activated",
    CONDA_BACKUP_CONDATHIS_HOST_CC = "user-cc",
    CONDATHIS_HOST_CC = "conda-cc",
    CONDATHIS_HOST_SCHEMA_CONDA_BACKUP = "user-schema",
    CONDATHIS_HOST_SCHEMA = as.character(fs::path(
      prefixes[["inner"]],
      "share"
    )),
    CONDATHIS_HOST_ENVVAR = "from-env-vars",
    CONDATHIS_HOST_USER = "user",
    CONDATHIS_STATE = "s",
    CONDA_EXE = as.character(fs::path(prefixes[["outer"]], "bin", "conda")),
    CONDA_PYTHON_EXE = as.character(fs::path(
      prefixes[["outer"]],
      "bin",
      "python"
    )),
    `_CE_M` = "-m",
    MAMBA_EXE = as.character(fs::path(prefixes[["outer"]], "bin", "mamba")),
    PIXI_PROJECT_ROOT = as.character(fs::path_dir(prefixes[["pixi"]])),
    PIXI_ENVIRONMENT_NAME = "default",
    PIXI_IN_SHELL = "1",
    PIXI_HOME = as.character(fs::path(keep_dir, "pixi-home")),
    PATH = paste(
      c(
        fake_host_bin(prefixes[["inner"]]),
        fake_host_bin(prefixes[["outer"]]),
        fake_host_bin(prefixes[["pixi"]]),
        as.character(keep_dir),
        path
      ),
      collapse = .Platform$path.sep
    )
  ))
}

# The names that mark the activation of `fake_nested_host_vars()`.
fake_host_marker_names <- function() {
  return(c(
    "CONDA_PREFIX_1",
    "CONDA_ENV_SHLVL_1_CONDA_PREFIX",
    "CONDA_ENV_SHLVL_1_CONDATHIS_HOST_SAVED",
    "CONDA_BACKUP_CONDATHIS_HOST_CC",
    "CONDATHIS_HOST_SCHEMA_CONDA_BACKUP",
    "CONDA_EXE",
    "CONDA_PYTHON_EXE",
    "_CE_M",
    "MAMBA_EXE",
    "PIXI_PROJECT_ROOT",
    "PIXI_ENVIRONMENT_NAME",
    "PIXI_IN_SHELL"
  ))
}

# A fake nested host activation for the calling test: three Conda prefixes
# (outer, inner, pixi), and the variables that conda and pixi leave when
# they stack activations, set in the session (see
# `fake_nested_host_vars()`). The prefixes' binary directories go in
# front of the session PATH, then `keep_dir`, a plain directory that
# stays. Returns `prefixes`, `keep_dir` and `vars`, the variables set.
local_fake_nested_host <- function(envir = parent.frame()) {
  dir <- withr::local_tempdir(pattern = "fake-host", .local_envir = envir)
  prefixes <- make_fake_host_prefixes(dir)
  keep_dir <- as.character(fs::path(dir, "keep"))
  fs::dir_create(keep_dir)
  vars <- fake_nested_host_vars(prefixes, keep_dir, Sys.getenv("PATH"))
  withr::local_envvar(.new = vars, .local_envir = envir)
  return(invisible(list(prefixes = prefixes, keep_dir = keep_dir, vars = vars)))
}

# Whether a PATH value names a directory of `dirs`, compared as the
# operating system compares them.
path_names_any <- function(path, dirs) {
  entries <- strsplit(path, .Platform$path.sep, fixed = TRUE)[[1L]]
  return(any(path_entry_key(entries) %in% path_entry_key(dirs)))
}

# The entries that `Rscript` itself puts in front of its PATH when it
# starts, measured once per session. On Windows, the base Rprofile of R
# puts the Rtools directories there, also with `--vanilla`. Elsewhere,
# there are none.
run_family_cache <- new.env(parent = emptyenv())
rscript_start_path_prefix <- function() {
  if (!is.null(run_family_cache$rscript_prefix)) {
    return(run_family_cache$rscript_prefix)
  }
  marker <- file.path(tempdir(), "condathis-path-marker")
  res <- processx::run(
    run_family_rscript(),
    c("--vanilla", "-e", "cat(Sys.getenv('PATH'))"),
    env = c(
      "current",
      PATH = paste(marker, Sys.getenv("PATH"), sep = .Platform$path.sep)
    )
  )
  entries <- strsplit(res$stdout, .Platform$path.sep, fixed = TRUE)[[1L]]
  pos <- match(path_entry_key(marker), path_entry_key(entries))
  stopifnot(!is.na(pos))
  run_family_cache$rscript_prefix <- entries[seq_len(pos - 1L)]
  return(run_family_cache$rscript_prefix)
}

# The entries of a PATH that an `Rscript` child dumped, without those that
# `Rscript` put in front itself (see `rscript_start_path_prefix()`). So
# they are the entries of the PATH that the child was given.
rscript_dumped_path_entries <- function(path) {
  entries <- strsplit(path, .Platform$path.sep, fixed = TRUE)[[1L]]
  prefix <- rscript_start_path_prefix()
  n <- length(prefix)
  if (
    n > 0L &&
      length(entries) >= n &&
      identical(path_entry_key(entries[seq_len(n)]), path_entry_key(prefix))
  ) {
    entries <- entries[-seq_len(n)]
  }
  return(entries)
}

# Sets the session cache of `r_startup_env_vars()` to `value` for the
# calling test, and restores it afterwards.
local_r_startup_cache <- function(value, envir = parent.frame()) {
  cache <- condathis_rscript_path_cache
  old <- cache$r_startup
  cache$r_startup <- value
  withr::defer(
    {
      cache$r_startup <- old
    },
    envir = envir
  )
  return(invisible(value))
}
