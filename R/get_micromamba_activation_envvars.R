#' Resolve the environment variables set by a real `micromamba` activation
#'
#' @description
#' `get_activation_envvars()` hand-sets a fixed handful of `CONDA_*`/
#' `MAMBA_*` variables to approximate an activated Conda environment,
#' without ever invoking `micromamba` - this is what `run_pipeline()` uses,
#' since it needs the process spawned directly (no `micromamba run` wrapper)
#' to keep kernel-pipe stdout/stdin chaining working.
#'
#' `get_micromamba_activation_envvars()` instead asks `micromamba` to do the
#' real activation (`micromamba run -n <env_name> ...`), including any
#' package-shipped `activate.d`/`deactivate.d` hook scripts, and captures
#' the *actual* resulting environment. It works by spawning `Rscript`
#' *through* `micromamba run`, having it dump its own environment as JSON,
#' and diffing that against a clean baseline (the same `build_child_env()`
#' construction `native_cmd()` hands every child, so the calling session's
#' environment is never touched) - the result is only the variables
#' activation actually added or changed, ready to be layered into a child
#' environment via `build_child_env(overlay = ...)`, exactly like
#' `get_activation_envvars()`. `PATH` is special-cased: the cache stores
#' only the directories activation *adds*, and the returned overlay's
#' `PATH` is composed against the live session `PATH` on every call (see
#' `compose_activation_overlay()`).
#'
#' This is more accurate (it reflects whatever `micromamba run` really does,
#' including hook scripts) but strictly more expensive: it spawns two
#' subprocesses (`micromamba` + `Rscript`) the first time it resolves a
#' given `env_name`. Results are cached per `env_name`, invalidated
#' automatically when the environment's `conda-meta` directory changes
#' (i.e., packages are installed/removed), so repeated calls for the same,
#' unchanged environment are free.
#'
#' Not currently wired into `run_pipeline()`, `run()`, or `run_bin()` - see
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
#'   activating `env_name` via `micromamba run` adds or changes (including
#'   a `PATH` composed against the live session `PATH`), suitable as the
#'   `overlay` argument of `build_child_env()`.
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
      return(compose_activation_overlay(cached$resolved))
    }
  }

  resolved <- resolve_micromamba_activation_envvars(
    env_name = env_name,
    env_dir = env_dir
  )

  if (isTRUE(use_cache)) {
    base::assign(
      x = env_name,
      value = list(stamp = cache_stamp, resolved = resolved),
      envir = condathis_activation_cache
    )
  }

  return(compose_activation_overlay(resolved))
}

#' Turn a cached activation resolution into a ready-to-use overlay
#'
#' `PATH` is deliberately *not* cached as a finished string: activation's
#' `PATH` is "these environment directories, prepended to whatever `PATH`
#' the session has" - a relative instruction, not an absolute value.
#' Caching the composite (as this used to) froze the session `PATH` of
#' whichever call happened to fill the cache into every later caller:
#' directories the user removed from `PATH` afterwards were resurrected,
#' additions were missing, and one caller's transient `PATH` state (e.g. a
#' scoped prefix) leaked into unrelated calls until `conda-meta` happened
#' to change. Composing against the live `PATH` at every call keeps the
#' cached part env-specific only.
#'
#' @param resolved A list with `envvars` (named character vector, no
#'   `PATH` entry) and `path_prepend` (character vector of directories).
#'
#' @keywords internal
#' @noRd
compose_activation_overlay <- function(resolved) {
  envvars <- resolved$envvars
  if (isTRUE(length(resolved$path_prepend) > 0L)) {
    envvars <- c(
      envvars,
      PATH = compose_path(resolved$path_prepend, Sys.getenv("PATH"))
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
  # `processx` embeds a fresh hex hash into these on every subprocess it
  # spawns (observed e.g. `PROCESSX_PSc84243e8843f4_...` on Linux and
  # `PROCESSX_PSf046e9e523d_...` on Windows) - the hash is arbitrary hex,
  # not a decimal counter, so it does not reliably start with a digit.
  # Matching `^PROCESSX_PS[0-9]` only caught it when the hash happened to
  # start with 0-9, leaking the variable through otherwise (non-
  # deterministically on Linux, deterministically whenever the hash starts
  # with a letter, as reproduced on Windows), which broke the caching test
  # by making two otherwise-identical resolutions of the same env compare
  # as different. The whole `PROCESSX_PS*` namespace is owned by
  # `processx`, so matching just the prefix is safe.
  "^PROCESSX_PS"
}

#' Spawn `Rscript` through `micromamba run` and diff its environment
#'
#' @keywords internal
#' @noRd
resolve_micromamba_activation_envvars <- function(env_name, env_dir) {
  # Resolved from the package-load-time cache rather than R.home() as
  # defense-in-depth: condathis itself no longer mutates the session's
  # R_HOME (children get their environment via build_child_env()), but
  # the cached path is free and immune to any third-party code that does.
  # See condathis-package.R.
  rscript_path <- get_condathis_rscript_path()

  tmp_dir_path <- withr::local_tempdir(pattern = "condathis-activation")

  # The baseline is what a condathis child receives *before* activation:
  # the same explicit construction native_cmd() hands the dump subprocess
  # below - not the calling session's own environment, which is never
  # mutated. (native_cmd()'s per-call TMPDIR differs from this one, and it
  # sets CONDA_ENVS_PATH; TMPDIR is in the ignore list and the
  # CONDA_ENVS_PATH delta is a stable, env-root-specific value that is
  # harmless to carry in the overlay.)
  baseline_vars <- as.list(build_child_env(tmp_dir = tmp_dir_path))

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

  # PATH is split out of the value overlay and reduced to the directories
  # activation *added* (see compose_activation_overlay() for why the
  # composite must never be cached). Name matching is case-insensitive on
  # Windows via match_env_name(), where the activated block may spell it
  # differently than the baseline.
  activated_path_name <- match_env_name(names(activated_vars), "PATH")
  baseline_path_name <- match_env_name(names(baseline_vars), "PATH")
  path_prepend <- character(0L)
  if (!is.na(activated_path_name)) {
    path_prepend <- diff_path_prepend(
      activated_path = as.character(activated_vars[[activated_path_name]]),
      baseline_path = if (is.na(baseline_path_name)) {
        ""
      } else {
        as.character(baseline_vars[[baseline_path_name]])
      }
    )
    changed_names <- setdiff(changed_names, activated_path_name)
  }

  changed_names <- sort(changed_names)
  envvars <- vapply(
    X = changed_names,
    FUN = function(nm) as.character(activated_vars[[nm]]),
    FUN.VALUE = character(1L)
  )

  return(list(envvars = envvars, path_prepend = path_prepend))
}

#' Directories an activated `PATH` adds over a baseline `PATH`
#'
#' Order-preserving set difference of the activated `PATH`'s entries
#' against the baseline's. Entries activation appended (rather than
#' prepended) end up prepended on recomposition - an acceptable
#' approximation, since conda activation prepends in practice.
#'
#' @keywords internal
#' @noRd
diff_path_prepend <- function(activated_path, baseline_path) {
  sep <- .Platform$path.sep
  activated_parts <- strsplit(activated_path, sep, fixed = TRUE)[[1L]]
  baseline_parts <- strsplit(baseline_path %||% "", sep, fixed = TRUE)[[1L]]
  added <- activated_parts[!(activated_parts %in% baseline_parts)]
  return(added[nzchar(added)])
}
