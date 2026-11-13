#' Resolve the environment variables set by a real `micromamba` activation
#'
#' @description
#' `get_activation_envvars()` hand-sets a fixed handful of `CONDA_*`/
#' `MAMBA_*` variables to approximate an activated Conda environment.
#' It never invokes `micromamba`. `run_pipeline()` uses it only with
#' `activate = FALSE`, for stages that run without activation.
#'
#' `get_micromamba_activation_envvars()` asks `micromamba` to do the real
#' activation (`micromamba run -n <env_name> ...`), including any
#' package-shipped `activate.d`/`deactivate.d` hook scripts.
#' It spawns `Rscript` *through* `micromamba run`, dumps the environment
#' to a file with base R only, and diffs it against a clean baseline.
#' The baseline is the same `Rscript` dump started directly with the
#' `build_child_env()` block that `native_cmd()` hands every child, so the
#' calling session's environment is never touched (see
#' `get_activation_baseline_vars()`).
#' The result holds only the variables activation added or changed.
#' Layer it into a child environment via `build_child_env(overlay = ...)`,
#' like `get_activation_envvars()`.
#' `PATH` is special-cased: the cache stores only the directories
#' activation *adds*. The returned overlay's `PATH` is composed against the
#' live session `PATH` on every call (see `compose_activation_overlay()`).
#'
#' This reflects what `micromamba run` does, including hook scripts, but
#' costs more. The first resolution of an `env_name` starts two processes:
#' `micromamba`, and `Rscript` through it. The baseline does not depend on
#' the environment, so its `Rscript` process starts once per session for
#' all environments, and again only when the session's environment
#' variables, the micromamba root or the `Rscript` binary change.
#' Results are cached per `env_name`. The cache is invalidated when the
#' environment's `conda-meta` directory changes (packages installed or
#' removed), when the activation's own files change (the scripts of
#' `etc/conda/activate.d` and the files of `etc/conda/env_vars.d`, see
#' `activation_cache_stamp()`), and when the session's environment
#' variables change, which the activation scripts can read. So repeated
#' calls for an unchanged environment from an unchanged session are free.
#'
#' The `activate.d` scripts run with the `TMPDIR` and the user cache
#' (`XDG_CACHE_HOME`) of the command, not with micromamba's own (see
#' `activation_capture_args()`), in the working directory of the R
#' session. On Windows, their `TMP` is a directory in that `TMPDIR` (see
#' `micromamba_cmd_overlay()`), and a value that they build from it names
#' the command's `TMP`, unless they wrote something there (see
#' `rewrite_micromamba_tmp_dir()`). An activation whose values name that
#' call's `TMPDIR` is not cached, because the directory is deleted when the
#' command ends, and one whose values name the working directory is reused
#' only from that working directory (see `activation_cache_rule()`).
#'
#' Used through `micromamba_resolve_run_in_dir()`, the body of
#' `micromamba_backend_resolve_run()` and
#' `micromamba_backend_resolve_run_in_dir()`: by `run()`, and by `run_bin()` and
#' `run_pipeline()` with `activate = TRUE`. `micromamba run` starts only
#' the dump, never a command of the user.
#'
#' An environment given by `env_path()` has no name: pass `env_name = NULL`
#' and its directory as `env_dir`. Activation then uses
#' `micromamba run -p <env_dir>`, and the cache entry is keyed by the
#' directory.
#'
#' @param env_name Character string with the Conda environment name, or
#'   `NULL` for an environment given by path (see above).
#' @param use_cache Logical. Whether to use/populate the per-environment
#'   cache and the session cache of the baseline. Defaults to `TRUE`.
#'   `FALSE` dumps both environments again.
#' @param base_env Named character vector, the environment of the command
#'   before activation (`backend_resolve_run()`'s `base_env`), or `NULL`:
#'   then the scripts get the `TMPDIR` of micromamba's own process.
#' @param timeout Numeric, the seconds the activation may take. A
#'   resolution that runs out of time aborts.
#' @param env_dir The environment's directory, when the caller already
#'   resolved it. Required when `env_name` is `NULL`. Defaults to `NULL`,
#'   which computes it directly from the
#'   micromamba backend's own layout (`env_dir_for_backend()`, a pure
#'   path computation) - deliberately *not* the public `get_env_dir()`,
#'   whose backend resolution runs a `micromamba env list` subprocess on
#'   every call (even activation cache hits) and can abort on
#'   multi-backend ambiguity. This helper is micromamba-specific by
#'   definition, so the micromamba layout is always the right answer.
#'
#' @returns A named character vector of the environment variables that
#'   activating `env_name` via `micromamba run` adds or changes (including
#'   a `PATH` composed against the live session `PATH`), suitable as the
#'   `overlay` argument of `build_child_env()`. A variable that an
#'   `activate.d` script unsets is `NA`, which removes it. A missing
#'   environment directory aborts with `c("condathis_activation_env_not_found",
#'   "condathis_env_not_found", "condathis_error")`.
#'
#' @keywords internal
#' @noRd
get_micromamba_activation_envvars <- function(
  env_name,
  use_cache = TRUE,
  env_dir = NULL,
  base_env = NULL,
  timeout = Inf
) {
  env_dir <- env_dir %||%
    env_dir_for_backend(micromamba_backend(), env_name = env_name)
  env_label <- env_name %||% as.character(env_dir)

  if (!fs::dir_exists(env_dir)) {
    abort_env_not_found(
      env_label,
      class = "condathis_activation_env_not_found",
      hint = c(`i` = "Path: {.path {env_dir}}")
    )
  }

  cache_key <- activation_cache_key(env_name = env_name, env_dir = env_dir)
  if (isTRUE(use_cache)) {
    cache_stamp <- activation_cache_stamp(env_dir)
    session_env <- Sys.getenv()
    cached <- base::get0(
      x = cache_key,
      envir = condathis_activation_cache,
      ifnotfound = NULL
    )
    if (
      !is.null(cached) &&
        identical(cached$stamp, cache_stamp) &&
        identical(cached$session, session_env) &&
        (is.null(cached$wd) || identical(cached$wd, getwd()))
    ) {
      return(compose_activation_overlay(cached$resolved))
    }
  }

  resolved <- resolve_micromamba_activation_envvars(
    env_name = env_name,
    env_dir = env_dir,
    use_cache = use_cache,
    base_env = base_env,
    timeout = timeout
  )

  rule <- activation_cache_rule(
    c(
      unname(resolved$envvars[!is.na(resolved$envvars)]),
      resolved$path_prepend,
      resolved$path_append
    ),
    tmp_dir = resolved$tmp_dir,
    fixed_dirs = c(
      as.character(env_dir),
      as.character(install_dir_for_backend(micromamba_backend()))
    )
  )
  if (isTRUE(use_cache) && isTRUE(rule$cache)) {
    base::assign(
      x = cache_key,
      value = list(
        stamp = cache_stamp,
        session = session_env,
        wd = rule$wd,
        resolved = resolved
      ),
      envir = condathis_activation_cache
    )
  }

  return(compose_activation_overlay(resolved))
}

#' Whether and how an activation may be cached
#'
#' The `activate.d` scripts run in the `TMPDIR` of the call and in the
#' working directory of the R session. A value that names that `TMPDIR`
#' (a script that exports a path below it) is good for that call only: the
#' directory is deleted when the command ends. A value that names the
#' working directory (a script that exports `$PWD`) is good while the
#' working directory stays. The directories of the environment and of the
#' root are left out of that check: they are in most values, and the
#' working directory is often a directory above them (the home directory).
#' rattlerthis follows the same rule for its activation.
#'
#' @param values Character vector, the values of the activation and its
#'   `PATH` entries.
#' @param tmp_dir Character string, the `TMPDIR` the scripts ran with, or
#'   `NULL`.
#' @param wd Character string, the working directory they ran in.
#' @param fixed_dirs Character vector, directories whose paths in `values`
#'   do not count as naming the working directory.
#'
#' @returns A list with `cache` (logical) and `wd` (`NULL`, or the working
#'   directory the cached entry is bound to).
#'
#' @keywords internal
#' @noRd
activation_cache_rule <- function(
  values,
  tmp_dir,
  wd = getwd(),
  fixed_dirs = character(0L)
) {
  if (isTRUE(values_name_dir(values, tmp_dir))) {
    return(list(cache = FALSE, wd = NULL))
  }
  for (dir in fixed_dirs[nzchar(fixed_dirs)]) {
    real_dir <- tryCatch(
      normalizePath(dir, mustWork = FALSE),
      error = function(e) dir
    )
    for (one in unique(sub("[/\\\\]+$", "", c(dir, real_dir)))) {
      for (spelling in unique(c(
        one,
        gsub("\\\\", "/", one),
        gsub("/", "\\\\", one)
      ))) {
        values <- gsub(spelling, "", values, fixed = TRUE)
      }
    }
  }
  wd_spellings <- unique(c(
    wd,
    tryCatch(normalizePath(wd, mustWork = FALSE), error = function(e) wd)
  ))
  names_wd <- any(vapply(
    wd_spellings,
    function(dir) values_name_dir(values, dir),
    logical(1L)
  ))
  return(list(cache = TRUE, wd = if (isTRUE(names_wd)) wd))
}

#' Does any value name a directory?
#'
#' @param values Character vector.
#' @param dir Character string, or `NULL`/`NA`.
#'
#' @returns `TRUE` when `dir` is set and some value contains it (also with
#'   the other kind of slash on Windows).
#'
#' @keywords internal
#' @noRd
values_name_dir <- function(values, dir) {
  if (
    is.null(dir) ||
      isTRUE(is.na(dir)) ||
      isFALSE(nzchar(dir)) ||
      identical(length(values), 0L)
  ) {
    return(FALSE)
  }
  dir <- sub("[/\\\\]+$", "", as.character(dir))
  if (isFALSE(nzchar(dir))) {
    return(any(grepl("/", values, fixed = TRUE)))
  }
  spellings <- unique(c(
    dir,
    gsub("\\\\", "/", dir),
    gsub("/", "\\\\", dir)
  ))
  return(any(vapply(
    spellings,
    function(spelling) any(grepl(spelling, values, fixed = TRUE)),
    logical(1L)
  )))
}

#' Turn a cached activation resolution into a ready-to-use overlay
#'
#' `PATH` is deliberately *not* cached as a finished string. Activation's
#' `PATH` means "these environment directories, prepended to whatever `PATH`
#' the session has": a relative instruction, not an absolute value.
#' Caching the composite would freeze the session `PATH` of the call that
#' filled the cache into every later caller. Removed directories would
#' reappear, added directories would be missing, and a transient `PATH`
#' state (e.g. a scoped prefix) would leak into unrelated calls until
#' `conda-meta` changes. Composing against the live `PATH` at every call
#' keeps the cached part env-specific only.
#'
#' The directories that the activation put in front of the session's
#' `PATH` go in front of the live session `PATH`, and the ones it appended
#' after it, so an environment directory that the session's `PATH` already
#' has further back still comes first (see `split_activated_path()`).
#'
#' @param resolved A list with `envvars` (named character vector, no
#'   `PATH` entry), `path_prepend` and `path_append` (character vectors of
#'   directories).
#'
#' @keywords internal
#' @noRd
compose_activation_overlay <- function(resolved) {
  envvars <- resolved$envvars
  if (
    isTRUE(length(resolved$path_prepend) > 0L) ||
      isTRUE(length(resolved$path_append) > 0L)
  ) {
    envvars <- c(
      envvars,
      PATH = compose_path(
        resolved$path_prepend,
        Sys.getenv("PATH"),
        append = resolved$path_append
      )
    )
  }
  return(envvars)
}

#' @keywords internal
#' @noRd
condathis_activation_cache <- new.env(parent = emptyenv())

#' Activation cache key of an environment
#'
#' The name for a named environment. An environment given by path is keyed
#' by `"path:"` and its directory, which cannot collide with a name:
#' `validate_env_name()` rejects names that contain `:`.
#'
#' @param env_name Character string, or `NULL` for an environment given by
#'   path.
#' @param env_dir Character string with the environment's directory.
#'
#' @keywords internal
#' @noRd
activation_cache_key <- function(env_name, env_dir) {
  if (isFALSE(is.null(env_name))) {
    return(env_name)
  }
  return(paste0("path:", as.character(env_dir)))
}

#' `micromamba` arguments that select an environment
#'
#' @param env_name Character string, or `NULL` for an environment given by
#'   path.
#' @param env_dir Character string with the environment's directory. Used
#'   only when `env_name` is `NULL`.
#'
#' @returns `c("-n", env_name)`, or `c("-p", env_dir)`.
#'
#' @keywords internal
#' @noRd
micromamba_env_args <- function(env_name, env_dir = NULL) {
  if (isFALSE(is.null(env_name))) {
    return(c("-n", env_name))
  }
  return(c("-p", as.character(env_dir)))
}

#' Clear the `get_micromamba_activation_envvars()` cache
#'
#' @param env_name Character string. If supplied, only this environment's
#'   cache entry is cleared. Otherwise the entire cache is cleared,
#'   including the session cache of the baseline.
#'
#' @keywords internal
#' @noRd
reset_micromamba_activation_cache <- function(env_name = NULL) {
  if (is.null(env_name)) {
    rm(
      list = ls(envir = condathis_activation_cache, all.names = TRUE),
      envir = condathis_activation_cache
    )
    rm(
      list = ls(envir = condathis_activation_baseline_cache, all.names = TRUE),
      envir = condathis_activation_baseline_cache
    )
  } else if (exists(env_name, envir = condathis_activation_cache)) {
    rm(list = env_name, envir = condathis_activation_cache)
  }
  return(invisible(NULL))
}

#' A cheap fingerprint of what an environment's activation reads
#'
#' Invalidates the activation-envvars cache when packages are installed or
#' removed (the number of entries of `conda-meta` and their latest
#' modification time, without hashing their contents, which can be large),
#' and when a file that the activation itself reads changes: the scripts
#' of `etc/conda/activate.d` and the files of `etc/conda/env_vars.d`
#' (name, size and a hash of the contents, which are small; symbolic links
#' are followed). The time is kept as a number: formatting it would set
#' `TZDIR` in the session on macOS, which the cache also compares.
#'
#' @param env_dir Character string with the environment's directory.
#'
#' @returns A character vector.
#'
#' @keywords internal
#' @noRd
activation_cache_stamp <- function(env_dir) {
  conda_meta_dir <- fs::path(env_dir, "conda-meta")
  if (!fs::dir_exists(conda_meta_dir)) {
    return("no-conda-meta")
  }
  info <- fs::dir_info(conda_meta_dir, recurse = FALSE)
  meta_stamp <- if (nrow(info) == 0L) {
    "empty-conda-meta"
  } else {
    paste(
      nrow(info),
      sprintf("%.6f", as.numeric(max(info$modification_time))),
      sep = "-"
    )
  }
  script_dirs <- fs::path(
    env_dir,
    "etc",
    "conda",
    c("activate.d", "env_vars.d")
  )
  script_files <- unlist(lapply(
    script_dirs[fs::dir_exists(script_dirs)],
    function(dir) {
      return(as.character(fs::dir_ls(
        dir,
        type = c("file", "symlink"),
        all = TRUE
      )))
    }
  ))
  script_files <- sort(as.character(script_files), method = "radix")
  if (identical(length(script_files), 0L)) {
    return(meta_stamp)
  }
  script_stamp <- paste(
    fs::path_rel(script_files, env_dir),
    as.numeric(fs::file_size(script_files)),
    vapply(
      script_files,
      function(path) {
        return(tryCatch(rlang::hash_file(path), error = function(e) "unread"))
      },
      character(1L)
    ),
    sep = "|"
  )
  return(c(meta_stamp, unname(script_stamp)))
}

#' Variables to drop from the activation diff
#'
#' These variables come from the throwaway `Rscript` dump subprocess (R
#' startup vars, `processx` tracking vars, shell-session state), not from
#' `micromamba run` activation.
#' `TMPDIR` is also dropped: condathis manages its own per-call `TMPDIR`
#' overlay (see `get_activation_envvars()`), so the ephemeral dump value
#' must not propagate.
#'
#' @keywords internal
#' @noRd
activation_ignore_exact_vars <- function() {
  c(
    "TMPDIR",
    "PWD",
    "OLDPWD",
    "SHLVL",
    "_",
    "PS1",
    "R_ENVIRON",
    "R_ENVIRON_USER",
    "R_PROFILE",
    "R_PROFILE_USER",
    "R_SESSION_TMPDIR"
  )
}

#' @keywords internal
#' @noRd
activation_ignore_pattern_vars <- function() {
  # `processx` embeds a fresh hex hash into these on every subprocess it
  # spawns (e.g. `PROCESSX_PSc84243e8843f4_...` on Linux). The hash is
  # arbitrary hex, so it does not reliably start with a digit.
  # A pattern such as `^PROCESSX_PS[0-9]` leaks the variable when the hash
  # starts with a letter, and two identical resolutions then compare as
  # different. `processx` owns the whole `PROCESSX_PS*` namespace, so
  # matching the prefix is safe.
  "^PROCESSX_PS"
}

#' Session cache of the activation baseline
#'
#' Holds one entry, `entry = list(key, vars)`, filled by
#' `get_activation_baseline_vars()`. Separate from
#' `condathis_activation_cache`, whose entries are one per environment.
#'
#' @keywords internal
#' @noRd
condathis_activation_baseline_cache <- new.env(parent = emptyenv())

#' Environment of an unactivated `Rscript` dump, cached per session state
#'
#' The baseline is the same `Rscript` dump as the activated one, started
#' directly with the environment block `native_cmd()` hands the activated
#' dump. Diffing two `Rscript` dumps cancels every variable R itself sets at
#' startup (`R_HOME`, `R_PAPERSIZE_USER`, and on Windows several more),
#' which a diff against `build_child_env()` alone reported as activation
#' variables. Those leaked into every activated child: `R_HOME` pointed a
#' conda-installed R at the host R installation, defeating the
#' `R_HOME = ""` isolation of the clean-conda overlay.
#'
#' The baseline does not depend on the environment being activated. It
#' depends only on the session's environment variables (the first layer of
#' `build_child_env()`), the micromamba root (the package-cache and
#' envs-path variables of the clean overlay) and the `Rscript` binary. These
#' three values are the cache key, compared with `identical()`. A change to
#' any of them starts a new baseline process. Without the cache, every
#' activation cache miss started one more `Rscript` process. The variables
#' that differ between two dumps with the same key (`TMPDIR`, the
#' `PROCESSX_PS*` variables) are dropped from the diff.
#'
#' @param rscript_path Character string with the `Rscript` binary.
#' @param env_label Character string used in the error message of
#'   `read_activation_dump()`.
#' @param use_cache Logical. Whether to use and fill the cache.
#' @param timeout Numeric, the seconds the dump may take.
#'
#' @returns A named list of character strings, one per environment
#'   variable of the baseline dump.
#'
#' @keywords internal
#' @noRd
get_activation_baseline_vars <- function(
  rscript_path,
  env_label,
  use_cache = TRUE,
  timeout = Inf
) {
  root_dir <- install_dir_for_backend(micromamba_backend())
  cache_key <- list(
    envvars = Sys.getenv(),
    root_dir = as.character(root_dir),
    rscript_path = as.character(rscript_path)
  )
  if (isTRUE(use_cache)) {
    cached <- condathis_activation_baseline_cache$entry
    if (isFALSE(is.null(cached)) && identical(cached$key, cache_key)) {
      return(cached$vars)
    }
  }
  baseline_vars <- dump_activation_baseline(
    rscript_path = rscript_path,
    root_dir = root_dir,
    env_label = env_label,
    timeout = timeout
  )
  if (isTRUE(use_cache)) {
    condathis_activation_baseline_cache$entry <- list(
      key = cache_key,
      vars = baseline_vars
    )
  }
  return(baseline_vars)
}

#' Start the unactivated `Rscript` dump of the activation baseline
#'
#' @param rscript_path Character string with the `Rscript` binary.
#' @param root_dir Character string with the micromamba root, as
#'   `native_cmd()` gives it to `micromamba_conda_dirs()`.
#' @param env_label Character string used in the error message.
#' @param timeout Numeric, the seconds the dump may take.
#'
#' @returns A named list of character strings, one per environment
#'   variable.
#'
#' @keywords internal
#' @noRd
dump_activation_baseline <- function(
  rscript_path,
  root_dir,
  env_label,
  timeout = Inf
) {
  tmp_dir_path <- withr::local_tempdir(pattern = "condathis-baseline")
  baseline_dump <- write_activation_dump_script(
    dir_path = tmp_dir_path,
    script_name = "baseline_env.R",
    dump_name = "baseline_env.rds"
  )
  baseline_env <- build_child_env(
    tmp_dir = tmp_dir_path,
    conda_dirs = micromamba_conda_dirs(root_dir)
  )
  processx::run(
    command = rscript_path,
    args = c("--vanilla", baseline_dump$script),
    env = baseline_env,
    error_on_status = FALSE,
    timeout = timeout
  )
  return(read_activation_dump(baseline_dump$dump, env_name = env_label))
}

#' Write the `Rscript` script that dumps its environment to a file
#'
#' Both dumps write their environment to an RDS file with base R only.
#' They run `Rscript --vanilla`, which skips `.Rprofile`, so library paths
#' set there (for example by renv) are absent in the child: a dump that
#' needed any package could fail to load it. Writing to a file instead of
#' stdout also keeps banners printed by `activate.d` hook scripts out of
#' the result. The output path is embedded in the script rather than
#' passed as an argument, because on Windows `micromamba run` re-parses
#' arguments through `cmd.exe`.
#'
#' @param dir_path Character string with the directory for both files.
#' @param script_name,dump_name Character strings with the file names.
#'
#' @returns A list with `script` and `dump`, the two file paths.
#'
#' @keywords internal
#' @noRd
write_activation_dump_script <- function(dir_path, script_name, dump_name) {
  script_path <- fs::path(dir_path, script_name)
  dump_path <- fs::path(dir_path, dump_name)
  writeLines(
    paste0(
      "saveRDS(as.list(Sys.getenv()), file = ",
      deparse(as.character(dump_path)),
      ")"
    ),
    script_path
  )
  return(list(script = script_path, dump = dump_path))
}

#' Spawn `Rscript` through `micromamba run` and diff its environment
#'
#' @param env_name Character string, or `NULL` for an environment given by
#'   path.
#' @param env_dir Character string with the environment's directory.
#' @param use_cache Logical. Passed to `get_activation_baseline_vars()`.
#' @param base_env Named character vector, the environment of the command
#'   before activation, or `NULL` (see `activation_capture_args()`).
#' @param timeout Numeric, the seconds the whole resolution may take.
#'
#' @returns A list with `envvars`, `path_prepend`, `path_append` (see
#'   `compose_activation_overlay()`) and `tmp_dir`, the `TMPDIR` that the
#'   `activate.d` scripts ran with.
#'
#' @keywords internal
#' @noRd
resolve_micromamba_activation_envvars <- function(
  env_name,
  env_dir,
  use_cache = TRUE,
  base_env = NULL,
  timeout = Inf
) {
  # Use the package-load-time cache, not R.home(): the cached path is
  # immune to third-party code that mutates the session's R_HOME.
  # See condathis-package.R.
  rscript_path <- get_condathis_rscript_path()
  env_label <- env_name %||% as.character(env_dir)
  deadline <- proc.time()[["elapsed"]] + timeout
  time_left <- function() {
    left <- deadline - proc.time()[["elapsed"]]
    if (isTRUE(left <= 0)) {
      condathis_abort(
        message = c(
          `x` = "The activation of {.field {env_label}} ran out of time."
        ),
        class = "condathis_activation_timeout"
      )
    }
    return(left)
  }

  baseline_vars <- get_activation_baseline_vars(
    rscript_path = rscript_path,
    env_label = env_label,
    use_cache = use_cache,
    timeout = time_left()
  )

  tmp_dir_path <- withr::local_tempdir(pattern = "condathis-activation")
  activated_dump <- write_activation_dump_script(
    dir_path = tmp_dir_path,
    script_name = "dump_env.R",
    dump_name = "activated_env.rds"
  )

  env_args <- micromamba_env_args(env_name = env_name, env_dir = env_dir)
  capture_vars <- activation_capture_vars(base_env)
  # The `TMPDIR` of micromamba's process. On Windows, its `TMP` is a
  # directory in it, which the recorded variables leave out (see
  # `micromamba_cmd_overlay()`).
  capture_tmp_dir <- capture_vars[["TMPDIR"]] %||%
    withr::local_tempdir(pattern = "mamba-tmp")
  ensure_windows_micromamba_bat(timeout = time_left())
  # A failed activation (for example an `activate.d` script that exits
  # with an error) gets the condathis classes, not the bare error of the
  # process. The output goes to files: on Windows, a program that an
  # `activate.d` script started keeps pipes open, and `processx` waited for
  # it after a timeout had killed micromamba. With a time limit, what the
  # scripts started is stopped with micromamba when the time runs out, as
  # rattlerthis stops its activation shell.
  capture_files <- fs::path(
    tmp_dir_path,
    c("capture-out.txt", "capture-err.txt")
  )
  capture_timeout <- time_left()
  rethrow_error_cmd(
    expr = {
      px_res <- native_cmd(
        conda_cmd = "run",
        conda_args = c(activation_capture_args(capture_vars), env_args),
        rscript_path,
        "--vanilla",
        activated_dump$script,
        verbose = "silent",
        error = "continue",
        stdout = as.character(capture_files[[1L]]),
        stderr = as.character(capture_files[[2L]]),
        timeout = capture_timeout,
        cleanup_tree = isTRUE(is.finite(timeout)),
        tmp_dir = capture_tmp_dir
      )
      px_res[["stdout"]] <- read_capture_file(capture_files[[1L]])
      px_res[["stderr"]] <- read_capture_file(capture_files[[2L]])
      signal_process_failure(px_res, timeout = capture_timeout)
    }
  )
  activated_vars <- read_activation_dump(
    activated_dump$dump,
    env_name = env_label
  )
  activated_vars <- rewrite_capture_dirs(activated_vars, capture_vars)
  activated_vars <- rewrite_micromamba_tmp_dir(
    activated_vars,
    mamba_tmp_dir = micromamba_tmp_dir(capture_tmp_dir),
    base_env = base_env
  )

  changed_names <- Filter(
    f = function(nm) {
      !identical(activated_vars[[nm]], baseline_vars[[nm]])
    },
    x = names(activated_vars)
  )
  changed_names <- setdiff(changed_names, activation_ignore_exact_vars())
  changed_names <- changed_names[
    !grepl(activation_ignore_pattern_vars(), changed_names)
  ]
  changed_names <- drop_micromamba_process_vars(
    changed_names,
    activated_vars = activated_vars,
    root_dir = install_dir_for_backend(micromamba_backend()),
    tmp_dir = capture_tmp_dir
  )
  changed_names <- drop_capture_vars(
    changed_names,
    activated_vars = activated_vars,
    capture_vars = capture_vars
  )

  # Split PATH out of the value overlay and reduce it to the directories
  # activation *added*, before and after the session's (see
  # compose_activation_overlay()). On Windows the activated block may spell
  # the name differently than the baseline, so match_env_name() matches
  # case-insensitively.
  activated_path_name <- match_env_name(names(activated_vars), "PATH")
  baseline_path_name <- match_env_name(names(baseline_vars), "PATH")
  path_prepend <- character(0L)
  path_append <- character(0L)
  if (!is.na(activated_path_name)) {
    path_parts <- split_activated_path(
      activated_path = as.character(activated_vars[[activated_path_name]]),
      baseline_path = if (is.na(baseline_path_name)) {
        ""
      } else {
        as.character(baseline_vars[[baseline_path_name]])
      }
    )
    path_prepend <- path_parts$prepend
    path_append <- path_parts$append
    changed_names <- setdiff(changed_names, activated_path_name)
    # A directory that `micromamba_run_path()` appended for `micromamba run`
    # only.
    run_path <- micromamba_run_path()
    if (isFALSE(is.null(run_path))) {
      session_parts <- strsplit(Sys.getenv("PATH"), ":", fixed = TRUE)[[1L]]
      run_only <- setdiff(
        strsplit(run_path, ":", fixed = TRUE)[[1L]],
        session_parts
      )
      path_prepend <- setdiff(path_prepend, run_only)
      path_append <- setdiff(path_append, run_only)
    }
  }

  # A variable of the baseline that the activated dump lacks was unset by
  # an `activate.d` script (`unset VAR`, `set VAR=` on Windows): it is `NA`
  # in the overlay, which removes it from the command's environment, as
  # `micromamba run` removed it (see `apply_env_overrides()`). micromamba's
  # activation itself unsets none (checked with 2.10.0 on Linux, macOS and
  # Windows).
  key <- function(x) if (isTRUE(is_windows())) toupper(x) else x
  removed_names <- names(baseline_vars)[
    !(key(names(baseline_vars)) %in% key(names(activated_vars)))
  ]
  removed_names <- setdiff(removed_names, activation_ignore_exact_vars())
  removed_names <- removed_names[
    !grepl(activation_ignore_pattern_vars(), removed_names) &
      key(removed_names) != "PATH"
  ]
  removed_names <- drop_micromamba_process_vars(
    removed_names,
    activated_vars = activated_vars,
    root_dir = install_dir_for_backend(micromamba_backend()),
    tmp_dir = capture_tmp_dir
  )

  envvars <- c(
    vapply(
      X = changed_names,
      FUN = function(nm) as.character(activated_vars[[nm]]),
      FUN.VALUE = character(1L)
    ),
    rlang::set_names(rep(NA_character_, length(removed_names)), removed_names)
  )
  envvars <- envvars[order(names(envvars))]

  return(list(
    envvars = envvars,
    path_prepend = path_prepend,
    path_append = path_append,
    tmp_dir = capture_tmp_dir
  ))
}

#' The variables of the command that the `activate.d` scripts get
#'
#' `micromamba run` gives the scripts its own environment, which
#' `native_cmd()` builds: a `TMPDIR` of its own, deleted when micromamba
#' exits, and `XDG_CACHE_HOME=<root>/cache` (see `micromamba_cmd_overlay()`).
#' A script that exports a path below either one (`$TMPDIR/x`,
#' `${XDG_CACHE_HOME:-$HOME/.cache}/x`) then gave every later command of
#' the environment a deleted directory, or one in condathis's root. The
#' scripts get the values of the command instead, with the `-e` option of
#' `micromamba run`, which sets variables for the activation and the
#' command it starts, not for micromamba itself: the `TMPDIR` of
#' `base_env`, and its `XDG_CACHE_HOME`. `-e` cannot unset a variable, so
#' when `base_env` has no `XDG_CACHE_HOME`, the scripts get it empty, which
#' they read as unset (`${XDG_CACHE_HOME:-$HOME/.cache}`, `%XDG_CACHE_HOME%`
#' of a batch file).
#'
#' @param base_env Named character vector, or `NULL` (then nothing is
#'   set).
#'
#' @returns A named list of character strings.
#'
#' @keywords internal
#' @noRd
activation_capture_vars <- function(base_env) {
  if (is.null(base_env)) {
    return(list())
  }
  value_of <- function(name) {
    hit <- match_env_name(names(base_env), name)
    if (isTRUE(is.na(hit))) {
      return(NA_character_)
    }
    return(unname(as.character(base_env[[hit]])))
  }
  vars <- list()
  tmp_dir <- value_of("TMPDIR")
  if (isFALSE(is.na(tmp_dir)) && isTRUE(nzchar(tmp_dir))) {
    vars[["TMPDIR"]] <- tmp_dir
  }
  vars[["XDG_CACHE_HOME"]] <- value_of("XDG_CACHE_HOME") %|na|% ""
  return(vars)
}

#' Turn the directories of micromamba's process into the command's
#'
#' On Windows, `micromamba run -e` sets no variable that micromamba's own
#' process has (its environment block keeps the first spelling), so the
#' `activate.d` scripts see `XDG_CACHE_HOME=<root>/cache` there (see
#' `activation_capture_vars()`). A value of the activated dump that names
#' the directory the scripts saw names the command's instead: the session's
#' `XDG_CACHE_HOME`, or nothing when it has none, as a batch file expands an
#' unset variable. The same holds for `TMPDIR`, which the capture gets from
#' the command (`native_cmd(tmp_dir =)`), so it differs only when a script
#' changed it. The variables themselves are left as the dump has them.
#' micromamba's `TMP` on Windows is handled by
#' `rewrite_micromamba_tmp_dir()`.
#'
#' @param activated_vars Named list, the activated dump.
#' @param capture_vars Named list, from `activation_capture_vars()`.
#'
#' @returns `activated_vars`, with those values rewritten.
#'
#' @keywords internal
#' @noRd
rewrite_capture_dirs <- function(activated_vars, capture_vars) {
  for (name in intersect(names(capture_vars), c("TMPDIR", "XDG_CACHE_HOME"))) {
    seen_name <- match_env_name(names(activated_vars), name)
    if (isTRUE(is.na(seen_name))) {
      next
    }
    seen <- as.character(activated_vars[[seen_name]])
    wanted <- as.character(capture_vars[[name]])
    if (isFALSE(nzchar(seen)) || isTRUE(identical(seen, wanted))) {
      next
    }
    spellings <- unique(c(
      seen,
      gsub("\\\\", "/", seen),
      gsub("/", "\\\\", seen)
    ))
    for (nm in setdiff(names(activated_vars), seen_name)) {
      value <- activated_vars[[nm]]
      for (spelling in spellings) {
        value <- gsub(spelling, wanted, value, fixed = TRUE)
      }
      activated_vars[[nm]] <- value
    }
  }
  return(activated_vars)
}

#' Turn micromamba's `TMP` into the command's
#'
#' On Windows, the `activate.d` scripts see micromamba's own `TMP` while
#' the activation is recorded: a directory in the `TMPDIR` of the capture
#' (see `micromamba_tmp_dir()`), which `micromamba run -e` cannot change.
#' When the scripts left nothing in it, it is removed, and a value of the
#' activated dump that names it (`%TMP%\x`, also `TMP` itself when a script
#' changed it) names the command's `TMP` instead: the `TMP` of `base_env`,
#' or nothing when it has none, as a batch file expands an unset variable.
#' The value is then the one that micromamba gave when it ran with the
#' session's `TMP`, and the activation can be cached. A `TMP` that no script
#' changed is left as it is: it is dropped later (see
#' `drop_micromamba_process_vars()`).
#'
#' When a script wrote something there, the directory and the values are
#' left as they are. The command shares the `TMPDIR` with the capture, so
#' it finds what the script wrote, and the activation is not cached, as
#' with a script that writes to `$TMPDIR` on Linux and macOS (see
#' `activation_cache_rule()`).
#'
#' @param activated_vars Named list, the activated dump.
#' @param mamba_tmp_dir Character string, micromamba's `TMP`, or `NULL`:
#'   then nothing is changed.
#' @param base_env Named character vector, the environment of the command
#'   before activation, or `NULL`: then the command's `TMP` is the
#'   session's.
#'
#' @returns `activated_vars`, with those values rewritten.
#'
#' @keywords internal
#' @noRd
rewrite_micromamba_tmp_dir <- function(
  activated_vars,
  mamba_tmp_dir,
  base_env = NULL
) {
  if (is.null(mamba_tmp_dir)) {
    return(activated_vars)
  }
  left <- list.files(mamba_tmp_dir, all.files = TRUE, no.. = TRUE)
  if (isTRUE(length(left) > 0L)) {
    return(activated_vars)
  }
  unlink(mamba_tmp_dir, recursive = TRUE)
  wanted <- if (is.null(base_env)) {
    Sys.getenv("TMP", unset = "")
  } else {
    hit <- match_env_name(names(base_env), "TMP")
    if (isTRUE(is.na(hit))) "" else unname(as.character(base_env[[hit]]))
  }
  spellings <- unique(c(
    mamba_tmp_dir,
    gsub("\\\\", "/", mamba_tmp_dir),
    gsub("/", "\\\\", mamba_tmp_dir)
  ))
  tmp_name <- match_env_name(names(activated_vars), "TMP")
  for (nm in names(activated_vars)) {
    value <- activated_vars[[nm]]
    if (identical(nm, tmp_name) && identical(value, mamba_tmp_dir)) {
      next
    }
    for (spelling in spellings) {
      value <- gsub(spelling, wanted, value, fixed = TRUE)
    }
    activated_vars[[nm]] <- value
  }
  return(activated_vars)
}

#' Read the output file of the activation capture
#'
#' @param path Character string.
#'
#' @returns The text of the file, or `""` when it cannot be read.
#'
#' @keywords internal
#' @noRd
read_capture_file <- function(path) {
  if (isFALSE(fs::file_exists(path))) {
    return("")
  }
  text <- tryCatch(
    readLines(path, warn = FALSE, encoding = "UTF-8"),
    error = function(e) character(0L)
  )
  return(paste(text, collapse = "\n"))
}

#' The `micromamba run` options that set the capture's variables
#'
#' @param capture_vars Named list, from `activation_capture_vars()`.
#'
#' @returns Character vector, `-e NAME=value` for each variable.
#'
#' @keywords internal
#' @noRd
activation_capture_args <- function(capture_vars) {
  return(as.character(unlist(lapply(names(capture_vars), function(name) {
    return(c("-e", paste0(name, "=", capture_vars[[name]])))
  }))))
}

#' Drop the variables that the capture set itself from an activation diff
#'
#' A variable of `activation_capture_vars()` that still has the value the
#' capture gave it was not set by the activation: `XDG_CACHE_HOME` that the
#' session does not set, for example.
#'
#' @param changed_names Character vector, the names that differ from the
#'   baseline.
#' @param activated_vars Named list, the activated dump.
#' @param capture_vars Named list, from `activation_capture_vars()`.
#'
#' @returns `changed_names` without those variables.
#'
#' @keywords internal
#' @noRd
drop_capture_vars <- function(changed_names, activated_vars, capture_vars) {
  dropped <- vapply(
    changed_names,
    function(nm) {
      capture_name <- match_env_name(names(capture_vars), nm)
      if (isTRUE(is.na(capture_name))) {
        return(FALSE)
      }
      return(identical(
        as.character(activated_vars[[nm]]),
        as.character(capture_vars[[capture_name]])
      ))
    },
    logical(1L),
    USE.NAMES = FALSE
  )
  return(changed_names[!dropped])
}

#' Drop the variables of micromamba's own process from an activation diff
#'
#' `native_cmd()` gives `micromamba run` the variables of
#' `micromamba_cmd_overlay()`, and the activation dump inherits them, so
#' they differ from the baseline although no activation set them. They
#' belong to micromamba's process, not to the environment:
#'
#' * `MAMBA_ROOT_PREFIX` is always dropped, whatever its value: the
#'   commands that users run keep `MAMBA_ROOT_PREFIX = ""` of
#'   `get_clean_conda_envvars()` on every OS. On Windows, micromamba's
#'   activation also exports its root itself.
#' * The other variables of the overlay are dropped when they still have
#'   the value `condathis` gave micromamba, such as `TMP` on Windows, which
#'   the baseline has from the session. A value that an `activate.d` script
#'   set is kept, also a `TMP` set to the command's `TMPDIR`: micromamba's
#'   is a directory in it.
#'
#' @param changed_names Character vector, the names that differ from the
#'   baseline.
#' @param activated_vars Named list, the activated dump.
#' @param root_dir Character string, the micromamba root that
#'   `native_cmd()` used.
#' @param tmp_dir Character string, the `TMPDIR` that `native_cmd()` gave
#'   `micromamba run`, or `NULL`.
#'
#' @returns `changed_names` without those variables.
#'
#' @keywords internal
#' @noRd
drop_micromamba_process_vars <- function(
  changed_names,
  activated_vars,
  root_dir,
  tmp_dir = NULL
) {
  overlay <- micromamba_cmd_overlay(
    conda_cmd = "run",
    conda_args = character(0L),
    root_dir = root_dir,
    tmp_dir = tmp_dir
  )
  key <- function(x) if (isTRUE(is_windows())) toupper(x) else x
  dropped <- vapply(
    changed_names,
    function(nm) {
      if (isTRUE(identical(key(nm), "MAMBA_ROOT_PREFIX"))) {
        return(TRUE)
      }
      overlay_name <- match_env_name(names(overlay), nm)
      if (isTRUE(is.na(overlay_name))) {
        return(FALSE)
      }
      return(identical(
        as.character(activated_vars[[nm]]),
        as.character(overlay[[overlay_name]])
      ))
    },
    logical(1L),
    USE.NAMES = FALSE
  )
  return(changed_names[!dropped])
}

#' Make sure `condabin/micromamba.bat` exists on Windows
#'
#' WORKAROUND: on Windows, `micromamba run` activates the environment
#' through `<root>/condabin/micromamba.bat`, but micromamba only writes
#' `mamba.bat` there on its first `run`. A first call therefore primes the
#' directory, and `mamba.bat` is copied to `micromamba.bat` when it is
#' still missing. Call this before any `native_cmd(conda_cmd = "run")`.
#' Does nothing on other platforms or when the file already exists.
#'
#' The priming call runs in a throwaway, empty environment (a temporary
#' directory with only `conda-meta`), never in the environment about to be
#' activated: a `micromamba run` there would run its `activate.d` scripts
#' once more, so the first activation on Windows ran them twice. The call
#' may fail: only its side effect on `condabin/` matters.
#'
#' @param timeout Numeric, the seconds the priming call may take.
#'
#' @returns `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
ensure_windows_micromamba_bat <- function(timeout = Inf) {
  if (isFALSE(is_windows())) {
    return(invisible(NULL))
  }
  condabin_dir <- fs::path(
    install_dir_for_backend(micromamba_backend()),
    "condabin"
  )
  micromamba_bat_path <- fs::path(condabin_dir, "micromamba", ext = "bat")
  if (isTRUE(fs::file_exists(micromamba_bat_path))) {
    return(invisible(NULL))
  }
  prime_prefix <- fs::path(
    withr::local_tempdir(pattern = "condathis-prime"),
    "env"
  )
  fs::dir_create(fs::path(prime_prefix, "conda-meta"))
  fs::file_create(fs::path(prime_prefix, "conda-meta", "history"))
  catch_res <- rlang::catch_cnd(
    expr = {
      native_cmd(
        conda_cmd = "run",
        conda_args = micromamba_env_args(
          env_name = NULL,
          env_dir = as.character(prime_prefix)
        ),
        "dir",
        verbose = "silent",
        stdout = NULL,
        timeout = timeout
      )
    }
  )
  base::rm(catch_res)
  mamba_bat_path <- fs::path(condabin_dir, "mamba", ext = "bat")
  if (
    isTRUE(fs::file_exists(mamba_bat_path)) &&
      isFALSE(fs::file_exists(micromamba_bat_path))
  ) {
    fs::file_copy(
      path = mamba_bat_path,
      new_path = micromamba_bat_path,
      overwrite = TRUE
    )
  }
  return(invisible(NULL))
}

#' Directories an activated `PATH` adds before and after a baseline `PATH`
#'
#' Both `PATH` values come from `Rscript` dumps, so the entries that
#' `Rscript` itself puts in front at its start (Rtools on Windows) lead
#' both: they are skipped first. Then the baseline block starts where the
#' activated `PATH` has the first remaining baseline entry. The entries
#' before it were put in front by the activation, in its order. This
#' includes those that the session's `PATH` already has further back. An
#' environment directory at the end of the session's `PATH` still comes
#' first, as with `micromamba run`. The entries after it that the baseline
#' lacks were appended by an `activate.d` script. When the first baseline
#' entry is not in the activated `PATH`, every entry that the baseline
#' lacks counts as put in front.
#'
#' On Windows, entries compare as Windows compares directories: without
#' case, with `/` the same as `\\`, and without a trailing separator
#' except at a root (see `path_entry_key()`).
#' micromamba spells the session's entries with backslashes, so an entry
#' that the session spells with `/` is not an added directory.
#'
#' @param activated_path,baseline_path Character strings.
#'
#' @returns A list with `prepend` and `append`, character vectors without
#'   empty entries.
#'
#' @keywords internal
#' @noRd
split_activated_path <- function(activated_path, baseline_path) {
  sep <- .Platform$path.sep
  activated_parts <- strsplit(activated_path %||% "", sep, fixed = TRUE)[[1L]]
  activated_parts <- activated_parts[nzchar(activated_parts)]
  baseline_parts <- strsplit(baseline_path %||% "", sep, fixed = TRUE)[[1L]]
  baseline_parts <- baseline_parts[nzchar(baseline_parts)]
  key <- function(x) path_entry_key(x)
  distinct <- function(x) x[!duplicated(key(x))]
  activated_keys <- key(activated_parts)
  baseline_keys <- key(baseline_parts)
  common <- 0L
  while (
    common < min(length(activated_parts), length(baseline_parts)) &&
      identical(activated_keys[[common + 1L]], baseline_keys[[common + 1L]])
  ) {
    common <- common + 1L
  }
  rest <- activated_parts[seq_along(activated_parts) > common]
  baseline_rest <- baseline_keys[seq_along(baseline_keys) > common]
  start <- if (identical(length(baseline_rest), 0L)) {
    NA_integer_
  } else {
    match(baseline_rest[[1L]], key(rest))
  }
  if (identical(length(baseline_rest), 0L)) {
    # The whole baseline leads the activated `PATH`: the rest was appended,
    # unless there is no baseline at all.
    added <- distinct(rest[!(key(rest) %in% baseline_keys)])
    if (identical(length(baseline_parts), 0L)) {
      return(list(prepend = added, append = character(0L)))
    }
    return(list(prepend = character(0L), append = added))
  }
  if (isTRUE(is.na(start))) {
    return(list(
      prepend = distinct(rest[!(key(rest) %in% baseline_keys)]),
      append = character(0L)
    ))
  }
  before <- rest[seq_len(start - 1L)]
  after <- rest[seq_along(rest) >= start]
  return(list(
    prepend = distinct(before),
    append = distinct(
      after[!(key(after) %in% c(baseline_keys, key(before)))]
    )
  ))
}

#' Read the environment written by the activation dump subprocess
#'
#' A missing, unreadable or malformed dump file aborts with a classed error
#' that names the environment and activation as the cause.
#'
#' @param dump_file Path to the RDS file written by the dump script.
#' @param env_name Character string used in the error message.
#'
#' @returns A named list of character strings, one per environment
#'   variable.
#'
#' @keywords internal
#' @noRd
read_activation_dump <- function(dump_file, env_name) {
  parsed <- if (isTRUE(fs::file_exists(dump_file))) {
    tryCatch(readRDS(dump_file), error = function(e) NULL)
  }
  is_valid <- rlang::is_list(parsed) &&
    isTRUE(length(parsed) > 0L) &&
    rlang::is_named(parsed) &&
    all(vapply(parsed, rlang::is_string, logical(1L)))
  if (isFALSE(is_valid)) {
    condathis_abort(
      message = c(
        `x` = "Failed to resolve the activation environment for {.field {env_name}}.",
        `i` = "The activation dump did not produce a readable result.",
        `i` = paste(
          "This can happen when an {.file activate.d} hook script in the",
          "environment fails or stops the process before it finishes."
        )
      ),
      class = "condathis_activation_dump_error"
    )
  }
  return(parsed)
}
