#' Undo the activation of the R session in a child's environment
#'
#' @description
#' R can run inside an activated Conda or pixi environment, or inside
#' several nested ones: R itself installed in a Conda environment, R
#' started from a shell where `conda activate` or `pixi shell` ran, or R
#' started through a pixi global binary, which activates its environment
#' first. The session's environment then carries that activation: the
#' binary directories of those environments on `PATH`, and the variables
#' that conda, micromamba and pixi use to stack activations. A child of
#' `condathis` that inherited them found a program of R's own environment
#' in place of one that its environment lacks.
#'
#' `isolate_host_env()` is the first layer of isolation of every child
#' (see `build_child_env()`). It works on a snapshot of the session's
#' environment and never changes the session itself:
#'
#' 1. Variables that the deactivation scripts of conda-forge packages
#'    restore are restored: `CONDA_BACKUP_<X>` (the compiler packages: a
#'    non-empty backup is the value of `<X>` before the activation, an
#'    empty one means `<X>` was unset), `<X>_CONDA_BACKUP` (glib, the same
#'    rule), and `CONDA_ENV_SHLVL_<n>_<X>` (rattler and pixi: the value of
#'    `<X>` before the activation of level `n`; the smallest `n` wins).
#' 2. The variables that mark an activation are removed:
#'    `CONDA_PREFIX_<n>`, `CONDA_ENV_SHLVL_<n>_*`, the backups above,
#'    `CONDA_EXE`, `CONDA_PYTHON_EXE`, `_CE_CONDA`, `_CE_M`, `MAMBA_EXE`,
#'    and the markers of `pixi shell`: `PIXI_PROJECT_*`,
#'    `PIXI_WORKSPACE_*`, `PIXI_ENVIRONMENT_*`, `PIXI_PROMPT`,
#'    `PIXI_IN_SHELL` and `PIXI_EXE`. The configuration of pixi
#'    (`PIXI_HOME`, `PIXI_CACHE_DIR`, ...) stays.
#' 3. A variable that the `conda-meta/state` file or an
#'    `etc/conda/env_vars.d` file of a host prefix sets is removed when
#'    the session has exactly that value.
#' 4. The binary directories (`env_bin_search_dirs()`) of every host
#'    prefix are removed from `PATH` (see `host_env_prefixes()`).
#' 5. What R's own startup changed is undone, and every `R_*` and `_R_*`
#'    variable is removed (see `undo_r_startup_env()`).
#'
#' `CONDA_PREFIX`, `CONDA_SHLVL`, `CONDA_DEFAULT_ENV` and the other
#' variables of `get_clean_conda_envvars()` are left to that layer, which
#' comes next.
#'
#' Limits: a value that an `activate.d` script of a host prefix set stays,
#' unless one of the backups above restores it (compiler flags,
#' `JAVA_HOME`, ...), and so does a `PATH` entry that such a script added
#' other than the binary directories of the prefix. A binary directory of
#' an environment whose variables are gone stays too: a pixi global binary
#' that started the shell, whose `CONDA_PREFIX` a later one replaced
#' without stacking it, leaves its directory on `PATH` with nothing that
#' names its prefix.
#'
#' @param env Named list, a snapshot of an environment, such as
#'   `as.list(Sys.getenv())`.
#' @param r_prefix Character string, the Conda prefix that R runs from, or
#'   `NULL` (see `condathis_r_prefix()`).
#' @param on_windows Logical. Whether to apply the Windows rules: names
#'   compare without case, and `PATH` entries compare as Windows compares
#'   directories (see `path_entry_key()`).
#' @param is_prefix Function of one directory, `TRUE` when it is a Conda
#'   prefix. For the tests.
#' @param r_startup Named character vector, the values of R's startup
#'   (see `r_startup_env_vars()`), or `NULL`.
#'
#' @returns `env` with the activation of the host undone. When nothing
#'   applies, `env` itself, identical.
#'
#' @keywords internal
#' @noRd
isolate_host_env <- function(
  env,
  r_prefix = condathis_r_prefix(),
  on_windows = is_windows(),
  is_prefix = is_conda_prefix,
  r_startup = r_startup_env_vars()
) {
  prefixes <- host_env_prefixes(
    env,
    r_prefix = r_prefix,
    on_windows = on_windows,
    is_prefix = is_prefix
  )
  env <- restore_host_backups(env, on_windows = on_windows)
  env <- drop_host_markers(env, on_windows = on_windows)
  env <- drop_host_env_vars(env, prefixes, on_windows = on_windows)

  path_name <- match_env_name(names(env), "PATH", on_windows = on_windows)
  if (isFALSE(is.na(path_name))) {
    path <- as.character(env[[path_name]])
    stripped <- strip_host_path(path, prefixes, on_windows = on_windows)
    if (isFALSE(identical(stripped, path))) {
      env[[path_name]] <- stripped
    }
  }
  env <- undo_r_startup_env(
    env,
    r_startup = r_startup,
    on_windows = on_windows
  )
  return(env)
}

#' Undo the startup of R in a child's environment
#'
#' @description
#' R changes its own environment when it starts, and every child of the
#' session inherited those changes: the front end, `etc/ldpaths`,
#' `etc/Renviron` and the base profile of R set `R_HOME`, `R_LIBS_USER`,
#' `R_LIBS_SITE` and other `R_*` variables, `EDITOR`, `PAGER`, `MAKE`,
#' `SED`, `TAR` and `LN_S`, put R's library directories in front of
#' `LD_LIBRARY_PATH` (Linux) or `DYLD_FALLBACK_LIBRARY_PATH` (macOS), and
#' on Windows set `CURL_CA_BUNDLE` to R's own certificates and put the
#' Rtools directories in front of `PATH`. A command of a Conda environment
#' then loaded R's libraries or certificates, and an R of that environment
#' loaded packages built for the R of the session. `undo_r_startup_env()`
#' is the last step of `isolate_host_env()`:
#'
#' 1. On Windows, the entries of each `R_RTOOLS<n>_PATH` are removed from
#'    the front of `PATH`, where the base profile of R put them. Entries
#'    elsewhere in `PATH` stay: the user put them there.
#' 2. Each variable of `r_startup` (see `r_startup_env_vars()`) is removed
#'    when the session has exactly the value that R's startup gives it. For
#'    `LD_LIBRARY_PATH`, `DYLD_FALLBACK_LIBRARY_PATH` and
#'    `DYLD_LIBRARY_PATH`, the part that R put in front is removed, and
#'    what follows it stays. A value that the user set stays.
#' 3. Every variable whose name starts with `R_` or `_R_` is removed,
#'    whoever set it: only R reads them, and an R that a command starts
#'    sets its own.
#'
#' @param env Named list, an environment snapshot.
#' @param r_startup Named character vector from `r_startup_env_vars()`, or
#'   `NULL` to skip step 2.
#' @param on_windows Logical. Whether to apply the Windows rules.
#'
#' @returns `env` without the changes of R's startup.
#'
#' @keywords internal
#' @noRd
undo_r_startup_env <- function(
  env,
  r_startup = NULL,
  on_windows = is_windows()
) {
  env_names <- names(env)
  path_name <- match_env_name(env_names, "PATH", on_windows = on_windows)
  if (isTRUE(on_windows) && isFALSE(is.na(path_name))) {
    rtools_names <- env_names[grepl(
      "^R_RTOOLS[0-9]+_PATH$",
      env_names,
      ignore.case = TRUE
    )]
    for (rtools_name in rtools_names) {
      env[[path_name]] <- strip_leading_path_entries(
        as.character(env[[path_name]]),
        strsplit(as.character(env[[rtools_name]]), ";", fixed = TRUE)[[1L]],
        on_windows = TRUE
      )
    }
  }

  path_like <- r_startup_path_var_names()
  sep <- if (isTRUE(on_windows)) ";" else ":"
  for (name in names(r_startup)) {
    hit <- match_env_name(names(env), name, on_windows = on_windows)
    if (isTRUE(is.na(hit))) {
      next
    }
    value <- as.character(env[[hit]])
    r_value <- as.character(r_startup[[name]])
    if (identical(value, r_value)) {
      env[[hit]] <- NULL
    } else if (
      env_name_key(name, on_windows) %in%
        env_name_key(path_like, on_windows) &&
        isTRUE(nzchar(r_value)) &&
        startsWith(value, paste0(r_value, sep))
    ) {
      env[[hit]] <- substring(value, nchar(r_value) + 2L)
    }
  }

  is_r_var <- grepl("^_?R_", names(env), ignore.case = on_windows)
  return(env[!is_r_var])
}

#' Remove entries from the front of a `PATH`
#'
#' @param path Character string, a `PATH` value.
#' @param entries Character vector, the entries that some program put in
#'   front of `path`, in their order.
#' @param on_windows Logical. Whether to apply the Windows rules (see
#'   `path_entry_key()`).
#'
#' @returns `path` without `entries`, when it starts with all of them, in
#'   their order. Otherwise `path` itself.
#'
#' @keywords internal
#' @noRd
strip_leading_path_entries <- function(
  path,
  entries,
  on_windows = is_windows()
) {
  entries <- entries[nzchar(entries)]
  sep <- if (isTRUE(on_windows)) ";" else ":"
  current <- strsplit(path %||% "", sep, fixed = TRUE)[[1L]]
  n <- length(entries)
  if (identical(n, 0L) || isTRUE(length(current) < n)) {
    return(path)
  }
  if (
    isFALSE(identical(
      path_entry_key(current[seq_len(n)], on_windows = on_windows),
      path_entry_key(entries, on_windows = on_windows)
    ))
  ) {
    return(path)
  }
  return(paste(current[-seq_len(n)], collapse = sep))
}

#' The variables that R's startup sets, other than `R_*`
#'
#' @returns A character vector of names. See `undo_r_startup_env()`.
#'
#' @keywords internal
#' @noRd
r_startup_var_names <- function() {
  return(c(
    "EDITOR",
    "PAGER",
    "MAKE",
    "SED",
    "TAR",
    "LN_S",
    "CURL_CA_BUNDLE",
    "MSYS2_ENV_CONV_EXCL",
    r_startup_path_var_names()
  ))
}

#' The variables of `r_startup_var_names()` that are lists of directories
#'
#' @returns A character vector of names.
#'
#' @keywords internal
#' @noRd
r_startup_path_var_names <- function() {
  return(c(
    "LD_LIBRARY_PATH",
    "DYLD_FALLBACK_LIBRARY_PATH",
    "DYLD_LIBRARY_PATH"
  ))
}

#' The values that R's startup gives to the variables it sets
#'
#' The values depend on the R installation (`etc/ldpaths`, `etc/Renviron`,
#' `etc/Renviron.site`), so they are measured once per R session: R's own
#' `Rscript` starts with the session's environment, without the activation
#' of the session, the `R_*` variables and the variables of
#' `r_startup_var_names()`, and without the user's `.Renviron` and
#' `.Rprofile`. It records the value it then has for each variable of
#' `r_startup_var_names()`. The answer is kept in
#' `condathis_rscript_path_cache` as `r_startup`.
#'
#' @param use_cache Logical. Whether to use and fill the session cache.
#' @param rscript_path Character string, R's own `Rscript`.
#' @param timeout Numeric, seconds.
#'
#' @returns A named character vector, or `NULL` when `Rscript` failed: then
#'   only the other steps of `undo_r_startup_env()` apply.
#'
#' @keywords internal
#' @noRd
r_startup_env_vars <- function(
  use_cache = TRUE,
  rscript_path = get_condathis_rscript_path(),
  timeout = 60
) {
  if (isTRUE(use_cache)) {
    cached <- condathis_rscript_path_cache$r_startup
    if (isFALSE(is.null(cached))) {
      return(if (identical(cached, NA)) NULL else cached)
    }
  }
  values <- tryCatch(
    measure_r_startup_env_vars(rscript_path, timeout = timeout),
    error = function(cnd) NULL
  )
  if (isTRUE(use_cache)) {
    condathis_rscript_path_cache$r_startup <- values %||% NA
  }
  return(values)
}

#' Start `Rscript` once to read the values of R's startup
#'
#' @inheritParams r_startup_env_vars
#'
#' @returns A named character vector, or `NULL`.
#'
#' @keywords internal
#' @noRd
measure_r_startup_env_vars <- function(rscript_path, timeout = 60) {
  on_windows <- is_windows()
  names_ <- r_startup_var_names()
  env <- isolate_host_env(as.list(Sys.getenv()), r_startup = NULL)
  env <- env[
    !(env_name_key(names(env), on_windows) %in%
      env_name_key(names_, on_windows))
  ]
  dir <- withr::local_tempdir(pattern = "condathis-r-startup")
  renviron <- file.path(dir, "empty.Renviron")
  file.create(renviron)
  out <- file.path(dir, "env.rds")
  env[["R_ENVIRON_USER"]] <- renviron
  env[["TMPDIR"]] <- dir
  env <- c(env, as.list(internal_rscript_vars()))
  child_env <- r_prefix_command_env(rscript_path, child_env = unlist(env))
  res <- processx::run(
    command = rscript_path,
    args = c(
      "--no-init-file",
      "-e",
      "saveRDS(as.list(Sys.getenv()), commandArgs(TRUE)[[1L]])",
      out
    ),
    env = child_env,
    error_on_status = FALSE,
    timeout = timeout,
    windows_hide_window = TRUE
  )
  if (isFALSE(identical(res$status, 0L)) || isFALSE(file.exists(out))) {
    return(NULL)
  }
  measured <- readRDS(out)
  keys <- env_name_key(names(measured), on_windows)
  hits <- keys %in% env_name_key(names_, on_windows)
  return(vapply(
    measured[hits],
    function(x) as.character(x)[[1L]],
    character(1L)
  ))
}

#' The `PATH` a child of `condathis` starts from
#'
#' The session's `PATH` without the activation of the R session (see
#' `isolate_host_env()`): the `PATH` of `build_child_env()` before any
#' activation. For code that composes a child's `PATH` outside
#' `build_child_env()`. Never the session's own `PATH`, which would put the
#' binary directories of R's own environments back.
#'
#' @returns A character string, `""` when the session has no `PATH`.
#'
#' @keywords internal
#' @noRd
isolated_session_path <- function() {
  env <- isolate_host_env(as.list(Sys.getenv()))
  return(env_block_path(env))
}

#' The host prefixes of an environment snapshot
#'
#' The candidates, in this order: `CONDA_PREFIX`, every
#' `CONDA_PREFIX_<n>` (the stack of conda and micromamba), every
#' `CONDA_ENV_SHLVL_<n>_CONDA_PREFIX` (the stack of rattler and pixi), and
#' R's own prefix. Only a candidate that is a Conda prefix (a directory
#' with `conda-meta`) counts: a `CONDA_PREFIX` such as `/usr` must never
#' remove `/usr/bin` from `PATH`.
#'
#' The rule is the same on every OS. On Windows, R's own prefix also
#' leaves the `PATH` of the commands: a command runs as in a shell where
#' that prefix was never activated. Only the `Rscript` that records an
#' activation (see `micromamba_run_path()`) and a command that is itself a
#' program of R's prefix (see `r_prefix_command_env()`) get the binary
#' directories of R's prefix back, at the end of their `PATH`, for their
#' DLLs.
#'
#' @inheritParams isolate_host_env
#'
#' @returns A character vector, every host prefix, without two prefixes of
#'   the same key (see `path_entry_key()`).
#'
#' @keywords internal
#' @noRd
host_env_prefixes <- function(
  env,
  r_prefix = condathis_r_prefix(),
  on_windows = is_windows(),
  is_prefix = is_conda_prefix
) {
  env_names <- names(env)
  values_of <- function(pattern) {
    hits <- env_names[grepl(pattern, env_names, ignore.case = on_windows)]
    return(as.character(unlist(env[hits], use.names = FALSE)))
  }
  conda_prefix_name <- match_env_name(
    env_names,
    "CONDA_PREFIX",
    on_windows = on_windows
  )
  candidates <- c(
    if (isFALSE(is.na(conda_prefix_name))) {
      as.character(env[[conda_prefix_name]])
    },
    values_of("^CONDA_PREFIX_[0-9]+$"),
    values_of("^CONDA_ENV_SHLVL_[0-9]+_CONDA_PREFIX$"),
    as.character(r_prefix)
  )
  candidates <- candidates[!is.na(candidates) & nzchar(candidates)]
  keep <- vapply(
    candidates,
    function(dir) isTRUE(is_prefix(dir)),
    logical(1L),
    USE.NAMES = FALSE
  )
  prefixes <- candidates[keep]
  return(prefixes[
    !duplicated(path_entry_key(prefixes, on_windows = on_windows))
  ])
}

#' A `PATH` without the binary directories of some prefixes
#'
#' The entries are split on `;` on Windows and on `:` elsewhere. An entry
#' is removed when it names a directory of `env_bin_search_dirs()` of one
#' of `prefixes`, compared with `path_entry_key()` (on Windows, also
#' without the quotes around an entry). Off Windows, an entry must be
#' written as `env_bin_search_dirs()` writes it. The other entries stay as
#' they are, empty ones included: `<root>/condabin` of `conda init`,
#' `~/.pixi/bin`, and every directory that is not a binary directory of a
#' prefix.
#'
#' @param path Character string, a `PATH` value.
#' @param prefixes Character vector of prefixes.
#' @param on_windows Logical. Whether to apply the Windows rules.
#'
#' @returns A character string. `path` itself when nothing is removed.
#'
#' @keywords internal
#' @noRd
strip_host_path <- function(path, prefixes, on_windows = is_windows()) {
  if (
    identical(length(prefixes), 0L) ||
      isFALSE(length(path) == 1L) ||
      isTRUE(is.na(path)) ||
      isFALSE(nzchar(path))
  ) {
    return(path)
  }
  sep <- if (isTRUE(on_windows)) ";" else ":"
  # The separator added at the end keeps a trailing empty entry, which
  # `strsplit()` drops.
  parts <- strsplit(paste0(path, sep), sep, fixed = TRUE)[[1L]]
  bin_dirs <- unlist(lapply(
    prefixes,
    function(prefix) {
      return(as.character(env_bin_search_dirs(prefix, on_windows = on_windows)))
    }
  ))
  bin_keys <- path_entry_key(bin_dirs, on_windows = on_windows)
  entries <- parts
  if (isTRUE(on_windows)) {
    entries <- gsub("^\"|\"$", "", entries)
  }
  drop <- nzchar(entries) &
    path_entry_key(entries, on_windows = on_windows) %in% bin_keys
  if (isFALSE(any(drop))) {
    return(path)
  }
  return(paste(parts[!drop], collapse = sep))
}

#' Restore the variables that a host activation saved
#'
#' See step 1 of `isolate_host_env()`. A backup of `PATH` is never
#' restored: `PATH` is handled by `strip_host_path()`. A backup of
#' `CONDA_PREFIX` of rattler and pixi names a host prefix (see
#' `host_env_prefixes()`) and is not restored either.
#'
#' @inheritParams isolate_host_env
#'
#' @returns `env`, with the saved values back. The backups stay: they are
#'   removed by `drop_host_markers()`.
#'
#' @keywords internal
#' @noRd
restore_host_backups <- function(env, on_windows = is_windows()) {
  key <- function(x) env_name_key(x, on_windows = on_windows)
  env_names <- names(env)
  restore <- function(env, target, value) {
    if (isFALSE(nzchar(target)) || identical(key(target), "PATH")) {
      return(env)
    }
    if (isTRUE(nzchar(value))) {
      return(set_env_value(env, target, value, on_windows = on_windows))
    }
    return(unset_env_value(env, target, on_windows = on_windows))
  }
  for (pattern in c("^CONDA_BACKUP_(.+)$", "^(.+)_CONDA_BACKUP$")) {
    backups <- env_names[grepl(pattern, env_names, ignore.case = on_windows)]
    for (backup in backups) {
      target <- sub(pattern, "\\1", backup, ignore.case = on_windows)
      env <- restore(env, target, as.character(env[[backup]]))
    }
  }

  stack_pattern <- "^CONDA_ENV_SHLVL_([0-9]+)_(.+)$"
  stacked <- env_names[grepl(
    stack_pattern,
    env_names,
    ignore.case = on_windows
  )]
  if (isTRUE(length(stacked) > 0L)) {
    levels <- as.integer(sub(
      stack_pattern,
      "\\1",
      stacked,
      ignore.case = on_windows
    ))
    targets <- sub(stack_pattern, "\\2", stacked, ignore.case = on_windows)
    keep <- !(key(targets) %in% c("CONDA_PREFIX", "PATH"))
    stacked <- stacked[keep]
    levels <- levels[keep]
    targets <- targets[keep]
    first <- order(levels)
    first <- first[!duplicated(key(targets[first]))]
    for (i in first) {
      env <- set_env_value(
        env,
        targets[[i]],
        as.character(env[[stacked[[i]]]]),
        on_windows = on_windows
      )
    }
  }
  return(env)
}

#' Remove the variables that mark a host activation
#'
#' See step 2 of `isolate_host_env()`.
#'
#' @inheritParams isolate_host_env
#'
#' @returns `env` without those variables.
#'
#' @keywords internal
#' @noRd
drop_host_markers <- function(env, on_windows = is_windows()) {
  env_names <- names(env)
  patterns <- c(
    "^CONDA_PREFIX_[0-9]+$",
    "^CONDA_ENV_SHLVL_[0-9]+_",
    "^CONDA_BACKUP_",
    "_CONDA_BACKUP$",
    "^PIXI_(PROJECT|WORKSPACE|ENVIRONMENT)_"
  )
  exact <- c(
    "CONDA_EXE",
    "CONDA_PYTHON_EXE",
    "_CE_CONDA",
    "_CE_M",
    "MAMBA_EXE",
    "PIXI_PROMPT",
    "PIXI_IN_SHELL",
    "PIXI_EXE"
  )
  key <- function(x) env_name_key(x, on_windows = on_windows)
  drop <- key(env_names) %in% key(exact)
  for (pattern in patterns) {
    drop <- drop | grepl(pattern, env_names, ignore.case = on_windows)
  }
  if (isFALSE(any(drop))) {
    return(env)
  }
  return(env[!drop])
}

#' Remove the variables that the `env_vars` of host prefixes set
#'
#' See step 3 of `isolate_host_env()`. The files are `conda-meta/state`
#' (a JSON object whose `env_vars` object `conda env config vars set`
#' writes) and each `etc/conda/env_vars.d/*.json` file (a flat JSON
#' object). A file that cannot be read or parsed is skipped. Only a
#' variable with exactly the value of the file is removed: the user may
#' have set another value since.
#'
#' @inheritParams isolate_host_env
#' @param prefixes Character vector of host prefixes.
#'
#' @returns `env` without those variables.
#'
#' @keywords internal
#' @noRd
drop_host_env_vars <- function(env, prefixes, on_windows = is_windows()) {
  for (prefix in prefixes) {
    for (vars in read_prefix_env_vars(prefix)) {
      for (name in names(vars)) {
        value <- vars[[name]]
        if (isFALSE(rlang::is_string(value)) || isFALSE(nzchar(name))) {
          next
        }
        hit <- match_env_name(names(env), name, on_windows = on_windows)
        if (
          isFALSE(is.na(hit)) &&
            identical(as.character(env[[hit]]), value)
        ) {
          env[[hit]] <- NULL
        }
      }
    }
  }
  return(env)
}

#' The `env_vars` files of a Conda prefix, parsed
#'
#' @param prefix Character string, a Conda prefix.
#'
#' @returns A list of named lists, one for each file that could be read.
#'
#' @keywords internal
#' @noRd
read_prefix_env_vars <- function(prefix) {
  read_object <- function(path) {
    parsed <- tryCatch(
      jsonlite::read_json(path, simplifyVector = FALSE),
      error = function(e) NULL
    )
    if (isFALSE(is.list(parsed)) || isFALSE(rlang::is_named(parsed))) {
      return(NULL)
    }
    return(parsed)
  }
  result <- list()
  state_file <- file.path(prefix, "conda-meta", "state")
  if (isTRUE(file.exists(state_file))) {
    state <- read_object(state_file)
    if (isTRUE(is.list(state$env_vars)) && rlang::is_named(state$env_vars)) {
      result <- c(result, list(state$env_vars))
    }
  }
  env_vars_dir <- file.path(prefix, "etc", "conda", "env_vars.d")
  if (isTRUE(dir.exists(env_vars_dir))) {
    files <- sort(list.files(
      env_vars_dir,
      pattern = "\\.json$",
      full.names = TRUE
    ))
    for (file in files) {
      vars <- read_object(file)
      if (isFALSE(is.null(vars))) {
        result <- c(result, list(vars))
      }
    }
  }
  return(result)
}

#' Whether a directory is a Conda prefix
#'
#' @param dir Character string.
#'
#' @returns `TRUE` when `dir` has a `conda-meta` directory.
#'
#' @keywords internal
#' @noRd
is_conda_prefix <- function(dir) {
  if (isFALSE(rlang::is_string(dir)) || isFALSE(nzchar(dir))) {
    return(FALSE)
  }
  return(isTRUE(dir.exists(file.path(dir, "conda-meta"))))
}

#' The Conda prefix that R runs from
#'
#' R of a Conda environment lives in `<prefix>/lib/R` on Linux and macOS,
#' and in `<prefix>/Lib/R` on Windows. The first of the 1 to 3 parents of
#' `R.home()` that is a Conda prefix is R's prefix. CRAN R and the R of a
#' Linux distribution have none. The answer for the session is computed
#' once and kept in `condathis_rscript_path_cache`, with the `R.home()`
#' of package load (see `get_condathis_r_home()`).
#'
#' @param r_home Character string, the R home directory.
#' @param use_cache Logical. Whether to use and fill the session cache.
#'   Defaults to `TRUE` only when `r_home` is not given.
#'
#' @returns A character string, or `NULL`.
#'
#' @keywords internal
#' @noRd
condathis_r_prefix <- function(
  r_home = get_condathis_r_home(),
  use_cache = missing(r_home)
) {
  if (isTRUE(use_cache)) {
    cached <- condathis_rscript_path_cache$r_prefix
    if (isFALSE(is.null(cached))) {
      return(if (is.na(cached)) NULL else cached)
    }
  }
  prefix <- NA_character_
  if (isTRUE(rlang::is_string(r_home)) && isTRUE(nzchar(r_home))) {
    dir <- r_home
    for (i in seq_len(3L)) {
      dir <- as.character(fs::path_dir(dir))
      if (isTRUE(is_conda_prefix(dir))) {
        prefix <- dir
        break
      }
    }
  }
  if (isTRUE(use_cache)) {
    condathis_rscript_path_cache$r_prefix <- prefix
  }
  return(if (is.na(prefix)) NULL else prefix)
}

#' The key under which two environment variable names are the same
#'
#' @param x Character vector of names.
#' @param on_windows Logical. On Windows, names compare without case.
#'
#' @returns A character vector.
#'
#' @keywords internal
#' @noRd
env_name_key <- function(x, on_windows = is_windows()) {
  if (isTRUE(on_windows)) {
    return(toupper(x))
  }
  return(x)
}

#' Set a variable of an environment snapshot under its existing spelling
#'
#' @param env Named list.
#' @param name,value Character strings.
#' @param on_windows Logical. On Windows, names compare without case.
#'
#' @returns `env`.
#'
#' @keywords internal
#' @noRd
set_env_value <- function(env, name, value, on_windows = is_windows()) {
  hit <- match_env_name(names(env), name, on_windows = on_windows)
  env[[hit %|na|% name]] <- value
  return(env)
}

#' Remove a variable from an environment snapshot, in every spelling
#'
#' @inheritParams set_env_value
#'
#' @returns `env`.
#'
#' @keywords internal
#' @noRd
unset_env_value <- function(env, name, on_windows = is_windows()) {
  hits <- env_name_key(names(env), on_windows) == env_name_key(name, on_windows)
  if (isFALSE(any(hits))) {
    return(env)
  }
  return(env[!hits])
}
