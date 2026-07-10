#' Resolve the environment variables set by a real `micromamba` activation
#'
#' @description
#' `get_activation_envvars()` hand-sets a fixed handful of `CONDA_*`/
#' `MAMBA_*` variables to approximate an activated Conda environment,
#' without ever invoking `micromamba` — this is what `run_pipeline()` uses,
#' since it needs the process spawned directly (no `micromamba run` wrapper)
#' to keep kernel-pipe stdout/stdin chaining working.
#'
#' `get_micromamba_activation_envvars()` instead asks `micromamba` to do the
#' real activation (`micromamba run -n <env_name> ...`), including any
#' package-shipped `activate.d`/`deactivate.d` hook scripts, and captures
#' the *actual* resulting environment. It works by spawning `Rscript`
#' *through* `micromamba run`, having it dump its own environment as JSON,
#' and diffing that against a clean baseline (the same
#' `get_clean_conda_envvars()` state `native_cmd()`/`run_pipeline()`
#' establish before spawning anything) — so the result is only the
#' variables activation actually added or changed, ready to be used as an
#' `env = c("current", ...)` overlay, exactly like `get_activation_envvars()`.
#'
#' This is more accurate (it reflects whatever `micromamba run` really does,
#' including hook scripts) but strictly more expensive: it spawns two
#' subprocesses (`micromamba` + `Rscript`) the first time it resolves a
#' given `env_name`. Results are cached per `env_name`, invalidated
#' automatically when the environment's `conda-meta` directory changes
#' (i.e., packages are installed/removed), so repeated calls for the same,
#' unchanged environment are free.
#'
#' Not currently wired into `run_pipeline()`, `run()`, or `run_bin()` — see
#' PLAN.md's "Environment activation mechanism differs" section. It is a
#' standalone building block, factored so it can eventually be used to
#' consolidate `run()` (which currently activates by wrapping the command
#' in `micromamba run -n <env> <cmd>`) with `run_bin()` (which runs the
#' binary directly with no activation): `run()` could become "resolve
#' activation vars once, then run like `run_bin()` with `env = c("current",
#' <vars>)`" instead of a `micromamba run` wrapper.
#'
#' @param env_name Character string with the Conda environment name.
#' @param use_cache Logical. Whether to use/populate the per-`env_name`
#'   cache. Defaults to `TRUE`.
#'
#' @returns A named character vector of the environment variables that
#'   activating `env_name` via `micromamba run` adds or changes, suitable
#'   for `processx::process$new(env = c("current", ...))` /
#'   `processx::run(env = c("current", ...))`.
#'
#' @keywords internal
#' @noRd
get_micromamba_activation_envvars <- function(env_name, use_cache = TRUE) {
  env_dir <- get_env_dir(env_name = env_name)

  if (!fs::dir_exists(env_dir)) {
    cli::cli_abort(
      message = c(
        `x` = "Environment {.field {env_name}} does not exist.",
        `!` = "Path: {.path {env_dir}}"
      ),
      class = "condathis_activation_env_not_found"
    )
  }

  if (isTRUE(use_cache)) {
    cache_stamp <- activation_cache_stamp(env_dir)
    cached <- base::get0(
      x = env_name,
      envir = condathis_activation_cache,
      ifnotfound = NULL
    )
    if (!is.null(cached) && identical(cached$stamp, cache_stamp)) {
      return(cached$envvars)
    }
  }

  envvars <- resolve_micromamba_activation_envvars(
    env_name = env_name,
    env_dir = env_dir
  )

  if (isTRUE(use_cache)) {
    base::assign(
      x = env_name,
      value = list(stamp = cache_stamp, envvars = envvars),
      envir = condathis_activation_cache
    )
  }

  return(envvars)
}

#' @keywords internal
#' @noRd
condathis_activation_cache <- new.env(parent = emptyenv())

#' Clear the `get_micromamba_activation_envvars()` cache
#'
#' @param env_name Character string. If supplied, only this environment's
#'   cache entry is cleared; otherwise the entire cache is cleared.
#'
#' @keywords internal
#' @noRd
reset_micromamba_activation_cache <- function(env_name = NULL) {
  if (is.null(env_name)) {
    rm(
      list = ls(envir = condathis_activation_cache, all.names = TRUE),
      envir = condathis_activation_cache
    )
  } else if (exists(env_name, envir = condathis_activation_cache)) {
    rm(list = env_name, envir = condathis_activation_cache)
  }
  return(invisible(NULL))
}

#' A cheap fingerprint for an environment's installed packages
#'
#' Used to invalidate the activation-envvars cache when packages are
#' installed/removed, without hashing file contents.
#'
#' @keywords internal
#' @noRd
activation_cache_stamp <- function(env_dir) {
  conda_meta_dir <- fs::path(env_dir, "conda-meta")
  if (!fs::dir_exists(conda_meta_dir)) {
    return("no-conda-meta")
  }
  info <- fs::dir_info(conda_meta_dir, recurse = FALSE)
  if (nrow(info) == 0L) {
    return("empty-conda-meta")
  }
  paste(
    nrow(info),
    format(max(info$modification_time), "%Y%m%d%H%M%OS6"),
    sep = "-"
  )
}

#' Variables to drop from the activation diff
#'
#' These are artifacts of spawning a throwaway `Rscript` subprocess to do
#' the dumping (R startup vars, `processx`'s own tracking vars, shell-session
#' state) rather than anything `micromamba run` activation itself sets.
#' `TMPDIR` is also dropped: condathis manages its own per-call `TMPDIR`
#' overlay separately (see `get_activation_envvars()`), so the ephemeral
#' value picked up here from the dump subprocess should not be propagated.
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
  "^PROCESSX_PS2"
}

#' Spawn `Rscript` through `micromamba run` and diff its environment
#'
#' @keywords internal
#' @noRd
resolve_micromamba_activation_envvars <- function(env_name, env_dir) {
  # Resolved before get_clean_conda_envvars() is applied below, since that
  # sets R_HOME = "" and R.home() reads R_HOME at call time.
  rscript_path <- fs::path(R.home("bin"), "Rscript")
  if (identical(.Platform$OS.type, "windows")) {
    rscript_path <- paste0(rscript_path, ".exe")
  }

  tmp_dir_path <- withr::local_tempdir(pattern = "condathis-activation")
  withr::local_envvar(
    .new = get_clean_conda_envvars(tmp_dir = tmp_dir_path)
  )

  baseline_vars <- as.list(base::Sys.getenv())

  dump_script <- fs::path(tmp_dir_path, "dump_env.R")
  writeLines(
    "cat(jsonlite::toJSON(as.list(base::Sys.getenv()), auto_unbox = TRUE))",
    dump_script
  )

  px_res <- native_cmd(
    conda_cmd = "run",
    conda_args = c("-n", env_name),
    rscript_path,
    "--vanilla",
    dump_script,
    verbose = "silent",
    error = "cancel"
  )
  activated_vars <- jsonlite::fromJSON(px_res$stdout)

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
  changed_names <- sort(changed_names)

  envvars <- vapply(
    X = changed_names,
    FUN = function(nm) as.character(activated_vars[[nm]]),
    FUN.VALUE = character(1L)
  )

  return(envvars)
}
