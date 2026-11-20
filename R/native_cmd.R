#' Run a micromamba command for the micromamba backend
#'
#' Executes `micromamba` under the managed Conda root used by `condathis`.
#' Installs micromamba first when no usable binary is found, unless
#' `install = FALSE`, and says so unless the `verbose` of the running call
#' is `"silent"` (see `install_micromamba_for_command()`).
#'
#' @param conda_cmd Character string with a micromamba subcommand.
#' @param conda_args Character vector of the micromamba options that
#'   `condathis` itself passes, such as `-n <env>` and
#'   `micromamba_quiet_args`. Defaults to `NULL`.
#' @param ... Additional unnamed arguments appended after `conda_args`: the
#'   package specifications, or for `micromamba run` the command it starts
#'   (the activation dump) and its arguments. They never change how
#'   `native_cmd()` behaves, except that `micromamba_cmd_overlay()` reads
#'   the environment file of `create` (`-f <file>`).
#' @param verbose Character string controlling console output.
#'   Supported values are `"output"`, `"silent"`, `"cmd"`, `"spinner"`,
#'   and `"full"`. Defaults to `"output"`.
#' @param error Character string that controls error behavior.
#'   Supported values are `"cancel"` and `"continue"`.
#'   Defaults to `"cancel"`.
#' @param stdout Standard output target.
#'   Defaults to `"|"`.
#' @param stderr Standard error target.
#'   Defaults to `"|"`.
#' @param stdin Standard input source.
#'   Defaults to `NULL`. Use `"|"` together with `input` for writable stdin.
#' @param input Character or raw vector written to the process's standard
#'   input when `stdin = "|"`. Defaults to `NULL`.
#' @param cleanup_tree Logical. Whether to clean up the child process tree
#'   after the process has finished. Defaults to `FALSE`.
#' @param encoding Character string. Assumed encoding for stdout/stderr.
#'   Defaults to `"utf-8"`. Use `"binary"` for raw byte output.
#' @param linux_pdeathsig Logical. On Linux, whether micromamba gets
#'   `SIGTERM` when the R session ends, even by a crash. Ignored on other
#'   platforms. Defaults to `FALSE`.
#' @param supervise Logical. Whether the process should be supervised by the
#'   `processx` supervisor for crash-safe cleanup. Defaults to `FALSE`.
#' @param timeout Numeric. Maximum number of seconds to let the command run
#'   before it's killed. Defaults to `Inf` (no limit).
#' @param tmp_dir Character string, the `TMPDIR` of the micromamba process,
#'   on Windows also where its `TMP` is (see `micromamba_cmd_overlay()`), or
#'   `NULL` (the default) for a new temporary directory, removed when the
#'   command returns. The activation capture of `run` passes the `TMPDIR` of
#'   the command it records the activation for (see
#'   `resolve_micromamba_activation_envvars()`).
#' @param install Logical. `TRUE` (the default) installs micromamba when no
#'   usable binary is found. `FALSE` aborts instead, before any process
#'   starts, with class `c("condathis_micromamba_not_installed",
#'   "condathis_error")`. The read-only listings of the micromamba backend
#'   pass `FALSE` and then read the file system, because a query never
#'   installs micromamba (decision D3).
#'
#' @returns A process result list from `processx::run()` (or an equivalent
#'   list from `run_process_with_input()` when `stdin = "|"`), with an extra
#'   element `cmd`: the exact command line that ran, each element quoted
#'   with `shQuote()`, starting with the real path of the micromamba binary,
#'   with the credentials of channel URLs hidden (see `format_cmd_line()`).
#'   The micromamba backend's create, install and remove results carry it,
#'   and `create_env()`, `install_packages()` and `remove_env()` report it.
#'
#' @keywords internal
#' @noRd
native_cmd <- function(
  conda_cmd,
  conda_args = NULL,
  ...,
  verbose = c(
    "output",
    "silent",
    "cmd",
    "spinner",
    "full"
  ),
  error = c("cancel", "continue"),
  stdout = "|",
  stderr = "|",
  stdin = NULL,
  input = NULL,
  cleanup_tree = FALSE,
  encoding = "utf-8",
  linux_pdeathsig = FALSE,
  supervise = FALSE,
  timeout = Inf,
  install = TRUE,
  tmp_dir = NULL
) {
  rlang::check_required(conda_cmd)

  error <- rlang::arg_match(error)
  if (isTRUE(identical(error, "cancel"))) {
    error_var <- TRUE
  } else {
    error_var <- FALSE
  }

  rlang::check_dots_unnamed()

  verbose_list <- parse_strategy_verbose(verbose = verbose)

  verbose_output <- native_cmd_echo(
    output = verbose_list$output,
    conda_args = conda_args,
    stderr = stderr,
    encoding = encoding
  )

  umamba_bin_path <- get_best_micromamba_path()

  if (is.null(umamba_bin_path) && isFALSE(install)) {
    condathis_abort(
      message = c(
        `x` = "No usable micromamba binary was found.",
        `i` = "It is installed by the first command that changes an environment."
      ),
      class = "condathis_micromamba_not_installed"
    )
  }
  if (is.null(umamba_bin_path)) {
    # No valid micromamba found anywhere: install to the internal path.
    umamba_bin_path <- install_micromamba_for_command(verbose_list)
  }

  env_root_dir <- install_dir_for_backend(micromamba_backend())
  umamba_bin_path <- base::normalizePath(umamba_bin_path, mustWork = FALSE)
  umamba_exec_path <- fs::path_real(umamba_bin_path)
  tmp_dir_path <- tmp_dir %||% withr::local_tempdir(pattern = "mamba-tmp")

  # `--rc-file` instead of `--no-rc`: micromamba then reads only this
  # file, not the user's own `.condarc`/`.mambarc`, and `--no-env` keeps
  # ignoring `MAMBA_*`/`CONDA_*` settings. The file pins `pkgs_dirs` to the
  # `condathis` package cache. With no configuration at all, micromamba
  # also used the user's global `~/.mamba/pkgs`, which `clean_cache()` then
  # deleted. The package extraction that micromamba starts as a
  # subprocess (`micromamba package extract`) gets neither option, so it
  # still reads the user's files (see `?condathis-options`).
  cmd_args <- c(
    "--rc-file",
    ensure_condathis_rc_file(env_root_dir),
    "--no-env",
    "-r",
    env_root_dir,
    conda_cmd,
    conda_args,
    ...
  )

  # Pass the child environment block as a full `env =` replacement. Never
  # modify the calling R session's environment: a temporary change of
  # `R_HOME` would corrupt parent-side `R.home()` calls. The root resolved above for
  # `-r` also gives the child's package-cache and envs-path variables, so
  # the root is resolved once per call. The overlay keeps the files that
  # micromamba writes to per-user directories under the root.
  overlay <- micromamba_cmd_overlay(
    conda_cmd = conda_cmd,
    conda_args = conda_args,
    root_dir = env_root_dir,
    specs = list(...),
    tmp_dir = tmp_dir_path
  )
  # On Windows, micromamba's own `TMP`, a directory in its `TMPDIR`. It
  # goes with the `TMPDIR`, also with the batch files of a stopped `run`.
  # The activation capture shares the `TMPDIR` with the command: what an
  # `activate.d` script wrote there stays until the command ends (see
  # `rewrite_micromamba_tmp_dir()`).
  mamba_tmp_dir <- overlay[["TMP"]]
  if (isFALSE(is.null(mamba_tmp_dir))) {
    fs::dir_create(mamba_tmp_dir)
  }
  child_env <- build_child_env(
    tmp_dir = tmp_dir_path,
    conda_dirs = micromamba_conda_dirs(env_root_dir),
    overlay = overlay
  )

  px_res <- execute_command(
    command = umamba_exec_path,
    args = cmd_args,
    env = child_env,
    # `list` starts `python -m pip`, which imports `pip` from its working
    # directory first: it runs in its temporary directory. It passes only
    # `-n <name>` or an absolute `-p <prefix>`. The other commands keep
    # R's working directory, against which micromamba resolves relative
    # paths of the user.
    wd = if (isTRUE(identical(conda_cmd, "list"))) tmp_dir_path,
    spinner = verbose_list$spinner_flag,
    echo_cmd = verbose_list$cmd,
    echo = verbose_output,
    stdout = stdout,
    stderr = stderr,
    stdin = stdin,
    input = input,
    error_on_status = error_var,
    cleanup_tree = cleanup_tree,
    supervise = supervise,
    linux_pdeathsig = linux_pdeathsig,
    encoding = encoding,
    timeout = timeout
  )

  # The exact command line, for the `cmd` field of the results of
  # `create_env()`, `install_packages()` and `remove_env()`, with the
  # credentials of channel URLs hidden. Quoted as `run()` quotes its own
  # `cmd`, so the two fields read the same way.
  px_res[["cmd"]] <- format_cmd_line(c(umamba_exec_path, cmd_args))

  return(invisible(px_res))
}

#' Install micromamba for a command that found no usable binary
#'
#' `native_cmd()` calls it when `get_best_micromamba_path()` finds nothing.
#' A download of an executable must never happen unannounced, so it says
#' first, with a message of class `condathis_micromamba_downloading`, that
#' no usable binary was found and which version it downloads to where,
#' for every `verbose` level except `"silent"`. `install_micromamba()`
#' itself gives its other messages only for `"output"` and `"full"`, and
#' the internal verbosity of a command is `"spinner"` at the default
#' `"output"` (see `parse_strategy_verbose()`), so without this message the
#' first `create_env()` downloaded the binary without a word.
#'
#' The level is the one of the running exported call (see
#' `local_call_verbose()`), when there is one, not the one of the command:
#' the probes of a call run silently, and on macOS arm64 and Windows one of
#' them is the first command of `create_env()`. The same level, as
#' `internal_verbose`, goes to `install_micromamba()`, so that its warning
#' about a binary that could not be verified shows too.
#'
#' @param verbose_list List, the parsed `verbose` of the command (see
#'   `parse_strategy_verbose()`), used outside of an exported call.
#'
#' @returns The path of the installed binary, from `micromamba_bin_path()`.
#'   A failed download aborts in `install_micromamba()`.
#'
#' @keywords internal
#' @noRd
install_micromamba_for_command <- function(verbose_list) {
  verbose_list <- parse_strategy_verbose(
    verbose = call_verbose() %||% verbose_list$strategy %||% "output"
  )
  # jarl-ignore unused_object: interpolated by cli in the message below
  umamba_bin_path <- micromamba_bin_path()
  if (isFALSE(identical(verbose_list$strategy, "silent"))) {
    # jarl-ignore unused_object: interpolated by cli in the message below
    micromamba_version <- micromamba_default_version
    condathis_inform(
      message = c(
        `i` = "No usable {.pkg micromamba} binary was found.",
        `i` = "Downloading {.pkg micromamba} {.val {micromamba_version}} to {.path {umamba_bin_path}}."
      ),
      class = "condathis_micromamba_downloading"
    )
  }
  install_micromamba(force = TRUE, verbose = verbose_list$internal_verbose)
  return(micromamba_bin_path())
}

#' Environment variables of micromamba's own processes
#'
#' Every micromamba process that `condathis` starts gets
#' `MAMBA_ROOT_PREFIX=<root>`. micromamba (2.8.1, 2.9.0 and 2.10.0 checked)
#' resolves a default root when it starts, before it reads `-r`, and aborts
#' (status 134, even for `--version`) when it exists but is not a Conda
#' prefix: the
#' default root is `<user data>/mamba` (`XDG_DATA_HOME`, else
#' `~/.local/share`, and on Windows else the RoamingAppData known folder),
#' or `~/micromamba` when that one is a prefix. libmamba reads
#' `MAMBA_ROOT_PREFIX` from the environment itself, also with `--no-env`
#' (`get_root_prefix()` in `context.cpp`), and then resolves no default
#' root. The commands that users run never get this value: their
#' `MAMBA_ROOT_PREFIX` is `""` (see `get_clean_conda_envvars()` and
#' `drop_micromamba_process_vars()`).
#'
#' libmamba writes some files to per-user directories whatever its
#' configuration says (checked in the sources of micromamba 2.9.0 and
#' 2.10.0, and with both binaries on Linux, macOS and Windows):
#'
#' * The sharded repodata cache goes to
#'   `<user cache>/conda/pkgs/cache/shards`, not to `pkgs_dirs`, and
#'   `clean --all` deletes the whole `<user cache>/conda`. `run` keeps a
#'   file for each running process in `<user cache>/mamba/proc`. The user
#'   cache is `XDG_CACHE_HOME`, else `~/.cache`, and on Windows else the
#'   LocalAppData known folder, which ignores the `LOCALAPPDATA` variable.
#'   No rc key, flag or `MAMBA_*` variable moves it, so every command gets
#'   `XDG_CACHE_HOME=<root>/cache`. `condathis` runs `run` only to record
#'   an activation: the recorded variables leave this value out, so the
#'   commands of `run()` keep the session's user cache, and the `activate.d`
#'   scripts of the environment get the user cache of the command (see
#'   `activation_capture_vars()`).
#' * `env list` and `env remove` rewrite `~/.conda/environments.txt` (the
#'   home is `HOME`, on Windows `USERPROFILE`): they drop every line whose
#'   directory is not an environment at that moment, and sort the others.
#'   Both get the home `<root>/home`, which need not exist. The listing
#'   finds the environments of `<root>/envs` in that directory, not in the
#'   registry. The removal names its environment with `-n` under `-r`,
#'   needs no credentials, and leaves the user's registry alone.
#'   `micromamba_backend_remove_env()` then deletes only the line of the
#'   removed environment (see `micromamba_unregister_env()`). On Windows,
#'   when the removal
#'   unlinks a package with a `Menu/*.json` file, micromamba creates the
#'   Start Menu folder under the home, `<root>/home/AppData/...`, to remove
#'   its shortcuts (even with `shortcuts: false`), so shortcuts that an
#'   earlier `condathis` added to the user's Start Menu stay there.
#' * `create` appends the new environment to `~/.conda/environments.txt`
#'   (`register_env()` in `environments_manager.cpp`; `register_envs`
#'   cannot be set from an rc file). It gets the home `<root>/home` too,
#'   unless that would lose something the real home gives it (see
#'   `micromamba_create_keeps_home()`). A dry run registers nothing and
#'   keeps the real home.
#'
#' `install` and the other commands keep the real home: micromamba reads
#' saved credentials from it, and expands `~` in paths with it.
#'
#' On Windows, libmamba writes its temporary files to the directory that
#' `GetTempPath()` gives (`TMP`, else `TEMP`), not to `TMPDIR`. `run`
#' writes two batch files there (`mamba_act<random>.bat` and
#' `mamba_bat_<random>.bat`, micromamba 2.10.0) and deletes them only when
#' it exits normally, so each `run` that `condathis` stopped (a timeout, an
#' interrupt) left them in the user's `%TEMP%`. Every command gets
#' `TMP=<tmp_dir>\mamba-tmp` (see `micromamba_tmp_dir()`), a directory that
#' `native_cmd()` creates in its `TMPDIR`, which is deleted when the call
#' returns. `TEMP` is not changed, and the commands that users run keep the
#' session's `TMP`: while an activation is recorded, the `activate.d`
#' scripts see micromamba's `TMP`, a value that they build from it names
#' the command's `TMP` when they wrote nothing there (see
#' `rewrite_micromamba_tmp_dir()`), and the recorded variables leave it out
#' (see `drop_micromamba_process_vars()`).
#' It is not the `TMPDIR` itself, so a script that sets `TMP` to the
#' command's `TMPDIR` is still recorded.
#'
#' `create` and `install` run the pip or uv of the environment for the
#' `pip:` section of an environment file, so they get the variables of
#' `micromamba_pip_install_vars()`. `list` runs `python -m pip inspect` in
#' the environment, so it gets the variables of
#' `micromamba_pip_inspect_vars()`. With the Python variables of every
#' child (see `python_isolation_envvars()`), pip then installs into and
#' reports only the environment itself.
#'
#' @param conda_cmd Character string with the micromamba subcommand.
#' @param conda_args Character vector of the options `condathis` passes.
#' @param root_dir Character string with the already-resolved root.
#' @param specs List of the other arguments of the command (the `...` of
#'   `native_cmd()`): for `create`, the package specs or
#'   `c("-f", <env_file>)`.
#' @param tmp_dir Character string, the `TMPDIR` of the command, where the
#'   `TMP` directory is on Windows (see `micromamba_tmp_dir()`), or `NULL`
#'   (then no `TMP` is set).
#'
#' @returns A named list for the `overlay` of `build_child_env()`. Reads
#'   the file system only for `create`, in `micromamba_create_keeps_home()`.
#'
#' @keywords internal
#' @noRd
micromamba_cmd_overlay <- function(
  conda_cmd,
  conda_args,
  root_dir,
  specs = NULL,
  tmp_dir = NULL
) {
  overlay <- micromamba_process_envvars(root_dir)
  overlay[["XDG_CACHE_HOME"]] <- micromamba_cache_dir(root_dir)
  overlay[["TMP"]] <- micromamba_tmp_dir(tmp_dir)
  conda_args <- as.character(conda_args)
  moves_home <- isTRUE(identical(conda_cmd, "env")) &&
    isTRUE(conda_args[1L] %in% c("list", "remove"))
  if (
    isTRUE(identical(conda_cmd, "create")) &&
      isFALSE("--dry-run" %in% conda_args)
  ) {
    moves_home <- isFALSE(micromamba_create_keeps_home(specs))
  }
  if (isTRUE(moves_home)) {
    home_var <- if (isTRUE(is_windows())) "USERPROFILE" else "HOME"
    overlay[[home_var]] <- as.character(fs::path(root_dir, "home"))
    # On macOS, pip keeps its cache in `~/Library/Caches/pip`, which the
    # moved home would put under `<root>/home`, where `clean_cache()` does
    # not look. Keep it in the user's cache, as with the real home. On
    # Linux, `XDG_CACHE_HOME` above places it; on Windows, pip finds
    # `%LOCALAPPDATA%` through the Known Folder, not `USERPROFILE`.
    if (
      isTRUE(identical(conda_cmd, "create")) &&
        isTRUE(is_macos()) &&
        identical(Sys.getenv("PIP_CACHE_DIR", unset = ""), "")
    ) {
      overlay[["PIP_CACHE_DIR"]] <- as.character(fs::path(
        micromamba_user_home(),
        "Library",
        "Caches",
        "pip"
      ))
    }
  }
  if (isTRUE(identical(conda_cmd, "run"))) {
    overlay[["PATH"]] <- micromamba_run_path()
    # `micromamba run` starts the `Rscript` that records an activation.
    overlay <- c(overlay, as.list(internal_rscript_vars()))
  }
  if (isTRUE(conda_cmd %in% c("create", "install"))) {
    overlay <- c(overlay, micromamba_pip_install_vars())
  }
  if (isTRUE(identical(conda_cmd, "list"))) {
    overlay <- c(overlay, micromamba_pip_inspect_vars())
  }
  return(overlay)
}

#' The pip and uv variables of `micromamba create` and `micromamba install`
#'
#' micromamba installs the `pip:` section of an environment file with the
#' environment's `pip`, or with `uv` when the file lists it. Both read the
#' user's settings, which could send the packages elsewhere or stop the
#' install, and `create_env()` still succeeded without them.
#'
#' `PIP_USER` and `PIP_REQUIRE_VIRTUALENV` are `"false"`, and
#' `PIP_REQUIRE_VENV`, `PIP_TARGET`, `PIP_PREFIX` and `PIP_ROOT` are
#' removed, for every child (see `python_isolation_envvars()`, decisions
#' D22 and D23), as are the other Python
#' variables. Here, in addition, `VIRTUAL_ENV` and `VIRTUAL_ENV_PROMPT` are
#' removed, whatever their value: uv installed into the virtual environment
#' of `VIRTUAL_ENV`. The commands of the run family keep a `VIRTUAL_ENV`
#' that names no virtual environment (see `undo_host_venv()`).
#'
#' The settings of the package index, the credentials, the certificates
#' and the proxy (`PIP_INDEX_URL`, `PIP_EXTRA_INDEX_URL`, `PIP_CERT`,
#' `PIP_CONFIG_FILE`, `UV_INDEX_URL`, ...) reach pip and uv unchanged.
#'
#' @returns A named list for the `overlay` of `build_child_env()`: an `NA`
#'   entry removes the variable.
#'
#' @keywords internal
#' @noRd
micromamba_pip_install_vars <- function() {
  return(list(
    `VIRTUAL_ENV` = NA_character_,
    `VIRTUAL_ENV_PROMPT` = NA_character_
  ))
}

#' The pip variables of `micromamba list`
#'
#' `list` runs `python -m pip inspect` in the environment for its PyPI
#' packages (see `read_pypi_package_records()`). pip reads no index for
#' it, so it reads no configuration file at all: `PIP_CONFIG_FILE` is the
#' null device (`os.devnull` of Python: `/dev/null`, on Windows `nul`),
#' which pip reads as "no configuration files". `PIP_USER` is `"false"`,
#' and `PIP_PATH` and `PIP_LOCAL` are removed: they restricted what
#' `inspect` reported. The working directory of `list` is its temporary
#' directory (see `native_cmd()`), so a `pip` package in the working
#' directory of R never runs in place of the environment's pip.
#'
#' @param on_windows Logical. Whether to use the Windows null device.
#'
#' @returns A named list for the `overlay` of `build_child_env()`.
#'
#' @keywords internal
#' @noRd
micromamba_pip_inspect_vars <- function(on_windows = is_windows()) {
  return(list(
    `PIP_CONFIG_FILE` = if (isTRUE(on_windows)) "nul" else "/dev/null",
    `PIP_USER` = "false",
    `PIP_PATH` = NA_character_,
    `PIP_LOCAL` = NA_character_
  ))
}

#' Variables of the `Rscript` processes of `condathis` itself
#'
#' `condathis` starts R's own `Rscript` to record an activation (see
#' `resolve_micromamba_activation_envvars()`) and to measure R's startup
#' (see `r_startup_env_vars()`). They get no `R_*` variable of the session
#' (see `undo_r_startup_env()`), so their R falls back to its default user
#' library. Some installations of R create that directory at every start:
#' the base profile of R installed by rig does, also with `--vanilla`. So
#' these processes get `R_LIBS_USER = "NULL"`, which R reads as no user
#' library, and they write nothing to the user's home. They load no package
#' of the user.
#'
#' @returns A named character vector.
#'
#' @keywords internal
#' @noRd
internal_rscript_vars <- function() {
  return(c(R_LIBS_USER = "NULL"))
}

#' The `PATH` of the processes that record an activation
#'
#' The activation of an environment is recorded by an `Rscript` started
#' through `micromamba run`, and diffed against the same `Rscript` started
#' directly (see `resolve_micromamba_activation_envvars()`). Both get this
#' `PATH`, which only these internal processes need. Directories it adds
#' are left out of the directories the activation adds, so the commands of
#' `run()` get the child's `PATH` with the activation's directories only.
#'
#' * Linux and macOS: `micromamba run` activates the environment with its
#'   shell hook, which runs `basename` (`mamba.sh` of libmamba). Without it
#'   on `PATH` (for example a `PATH` with only `sh`), the activation fails
#'   silently, and the dump records no activation at all. Then the first of
#'   `/usr/bin` and `/bin` that has `basename` is appended.
#' * Windows: the binary directories of R's own Conda prefix are appended.
#'   They are not on the `PATH` of a command (see `host_env_prefixes()`),
#'   but Windows has no `rpath`, and an R of a Conda environment loads its
#'   DLLs from them.
#'
#' The child's `PATH` is the session's without the activation of the R
#' session (see `isolate_host_env()`): this value replaces the `PATH` of
#' `build_child_env()`, and the session's own `PATH` would put the binary
#' directories of R's own environments back.
#'
#' @param session_path Character string, the `PATH` of the child before
#'   this change. Defaults to `isolated_session_path()`.
#' @param on_windows Logical. Whether to apply the Windows rule.
#' @param system_dirs Character vector, the directories to look in for
#'   `basename`.
#' @param r_prefix Character string, the Conda prefix that R runs from, or
#'   `NULL` (see `condathis_r_prefix()`). Used on Windows only.
#'
#' @returns A character string, or `NULL` when nothing needs to change.
#'
#' @keywords internal
#' @noRd
micromamba_run_path <- function(
  session_path = isolated_session_path(),
  on_windows = is_windows(),
  system_dirs = c("/usr/bin", "/bin"),
  r_prefix = if (isTRUE(on_windows)) condathis_r_prefix()
) {
  if (isTRUE(on_windows)) {
    if (isFALSE(rlang::is_string(r_prefix)) || isFALSE(nzchar(r_prefix))) {
      return(NULL)
    }
    entries <- strsplit(session_path %||% "", ";", fixed = TRUE)[[1L]]
    r_dirs <- as.character(env_bin_search_dirs(r_prefix, on_windows = TRUE))
    r_dirs <- r_dirs[
      !(path_entry_key(r_dirs, on_windows = TRUE) %in%
        path_entry_key(entries, on_windows = TRUE))
    ]
    if (identical(length(r_dirs), 0L)) {
      return(NULL)
    }
    return(paste(c(entries, r_dirs), collapse = ";"))
  }
  found <- find_command_on_path(
    "basename",
    path = session_path,
    on_windows = FALSE
  )
  if (isFALSE(is.null(found))) {
    return(NULL)
  }
  with_basename <- system_dirs[file.exists(fs::path(system_dirs, "basename"))]
  if (identical(length(with_basename), 0L)) {
    return(NULL)
  }
  return(paste(
    c(
      strsplit(session_path %||% "", ":", fixed = TRUE)[[1L]],
      with_basename[[1L]]
    ),
    collapse = ":"
  ))
}

#' Whether `micromamba create` must keep the user's home
#'
#' `micromamba_cmd_overlay()` gives `create` the home `<root>/home`, so
#' that micromamba does not add the environment to the user's
#' `~/.conda/environments.txt`. The home (`HOME`, on Windows `USERPROFILE`)
#' is also where micromamba reads saved credentials, and where it expands
#' `~`. Checked in the sources of micromamba 2.10.0:
#'
#' * `~/.mamba/auth/authentication.json` (`micromamba auth login`) and the
#'   `*.token` files of `~/.continuum/anaconda-client/tokens`
#'   (`Context::load_authentication_info()`), and `~/.netrc` (on Windows
#'   also `_netrc`), which libcurl reads for every download
#'   (`CURLOPT_NETRC`; on Windows only when `HOME` is unset, and then from
#'   `USERPROFILE`). When any of them exists, the home is kept, and the
#'   environment is registered as before.
#' * `~` at the start of a channel, an environment file path or a package
#'   path. `condathis` expands these itself, with the same home (see
#'   `micromamba_expand_home()`). It cannot rewrite an environment file,
#'   so a file that names the home (`~/`, `$HOME`, `%USERPROFILE%`) keeps
#'   it.
#' * micromamba runs `pip`, or `uv` when the file lists it, with its own
#'   environment for the `pip:` section of an environment file and for the
#'   pip packages of a lock file (`manager: pip` in a conda-lock file,
#'   `pipPackages` in a mambajs `.json` lock file). Such a file keeps the
#'   home only when pip or uv would read a file from it (see
#'   `micromamba_pip_needs_home()`). `.netrc` is already covered above.
#'
#' The `pre-link` and `post-link` scripts of packages see `<root>/home` as
#' their home. The environment variables of the session, such as `NETRC`,
#' `REQUESTS_CA_BUNDLE` and the proxy variables, are not changed.
#'
#' @param specs List of the other arguments of `micromamba create`, as
#'   `micromamba_cmd_overlay()` gets them.
#' @param home Character string, micromamba's home (see
#'   `micromamba_user_home()`).
#'
#' @returns `TRUE` when the real home must be kept, else `FALSE`.
#'
#' @keywords internal
#' @noRd
micromamba_create_keeps_home <- function(
  specs,
  home = micromamba_user_home()
) {
  credential_files <- fs::path(
    home,
    c(fs::path(".mamba", "auth", "authentication.json"), ".netrc", "_netrc")
  )
  if (isTRUE(any(fs::file_exists(credential_files)))) {
    return(TRUE)
  }
  tokens_dir <- fs::path(home, ".continuum", "anaconda-client", "tokens")
  if (
    isTRUE(fs::dir_exists(tokens_dir)) &&
      isTRUE(length(fs::dir_ls(tokens_dir, glob = "*.token")) > 0L)
  ) {
    return(TRUE)
  }
  args <- as.character(unlist(specs))
  file_index <- which(args == "-f")
  for (env_file in args[file_index + 1L]) {
    if (isTRUE(micromamba_env_file_needs_home(env_file, home = home))) {
      return(TRUE)
    }
  }
  return(FALSE)
}

#' Whether an environment file needs micromamba's real home
#'
#' See `micromamba_create_keeps_home()`. The check is a text search, and
#' errs on the side of keeping the home: any home-relative path (`~/`) and
#' any home variable (`$HOME`, `${HOME}`, `%USERPROFILE%`, ...) keep it. Any
#' `pip:` key, any pip package manager of a conda-lock file and any
#' `pipPackages` key of a mambajs lock file (`env_lockfile_mambajs.cpp` of
#' libmamba 2.10.0) keep it when `micromamba_pip_needs_home()` says so. A
#' file that cannot be read keeps it too.
#'
#' @param env_file Character string, the path of the file.
#' @param home Character string, micromamba's home.
#'
#' @returns Logical scalar.
#'
#' @keywords internal
#' @noRd
micromamba_env_file_needs_home <- function(
  env_file,
  home = micromamba_user_home()
) {
  text <- tryCatch(
    suppressWarnings(readLines(env_file, warn = FALSE)),
    error = function(e) NULL
  )
  if (is.null(text)) {
    return(TRUE)
  }
  home_vars <- "(HOME|USERPROFILE|HOMEDRIVE|HOMEPATH)"
  # micromamba expands `$VAR`, `${VAR}` and, on Windows, `%VAR%` in the
  # channels of a YAML file.
  names_home <- grepl(
    paste0("~[/\\\\]|\\$\\{?", home_vars, "\\b"),
    text,
    useBytes = TRUE
  ) |
    grepl(
      paste0("%", home_vars, "%"),
      text,
      ignore.case = TRUE,
      useBytes = TRUE
    )
  if (isTRUE(any(names_home))) {
    return(TRUE)
  }
  if (isFALSE(env_file_runs_pip(text))) {
    return(FALSE)
  }
  return(isTRUE(micromamba_pip_needs_home(home = home)))
}

#' Whether micromamba runs pip or uv for an environment file
#'
#' A text search, which errs on the side of `TRUE`: any `pip:` key, any
#' pip package manager of a conda-lock file and any `pipPackages` key of a
#' mambajs lock file (`env_lockfile_mambajs.cpp` of libmamba 2.10.0).
#'
#' @param text Character vector, the lines of the file.
#'
#' @returns Logical scalar.
#'
#' @keywords internal
#' @noRd
env_file_runs_pip <- function(text) {
  runs_pip <- grepl(
    paste0(
      "pip[\"']?[[:space:]]*:|",
      "pipPackages[\"']?[[:space:]]*:|",
      "manager[\"']?[[:space:]]*:[[:space:]]*[\"']?pip"
    ),
    text,
    ignore.case = TRUE,
    useBytes = TRUE
  )
  return(isTRUE(any(runs_pip)))
}

#' Whether pip or uv would read a file from micromamba's home
#'
#' micromamba installs the pip packages of an environment file with `pip`,
#' or with `uv` when the file lists `uv`. With the home `<root>/home`, both
#' would miss the files below. These are the user files that depend on the
#' home (`HOME`, on Windows `USERPROFILE`), as pip 26.2
#' (`pip/_internal/configuration.py`, `pip/_internal/utils/appdirs.py`,
#' `pip/_internal/network/auth.py`) and uv 0.13 (`docs/reference/storage.md`,
#' `docs/concepts/authentication/http.md`) read them:
#'
#' * pip configuration: the legacy `~/.pip/pip.conf` (on Windows
#'   `~\pip\pip.ini`), and the user configuration directory: on Linux
#'   `$XDG_CONFIG_HOME/pip/pip.conf`, else `~/.config/pip/pip.conf`; on
#'   macOS `~/Library/Application Support/pip/pip.conf` when that
#'   directory exists, else `~/.config/pip/pip.conf` (pip ignores
#'   `XDG_CONFIG_HOME` there).
#' * uv configuration: `$XDG_CONFIG_HOME/uv/uv.toml`, else
#'   `~/.config/uv/uv.toml` (Linux and macOS).
#' * uv credentials (`uv auth login`): `$XDG_DATA_HOME/uv/credentials/
#'   credentials.toml`, else under `~/.local/share` (Linux and macOS).
#' * A `keyring` program on `PATH`: pip asks it for credentials, and its
#'   backends and configuration can live in the home.
#'
#' A path under `XDG_CONFIG_HOME` or `XDG_DATA_HOME` does not depend on the
#' home, and neither do the Windows `%APPDATA%` locations of pip and uv
#' (both resolve the Known Folder, not `USERPROFILE`). `.netrc` and `NETRC`
#' are covered by `micromamba_create_keeps_home()`.
#'
#' @param home Character string, micromamba's home.
#' @param on_windows,on_macos Logical. The platform rules to apply.
#' @param keyring Character string, the path of a `keyring` program on
#'   `PATH`, or `""`.
#'
#' @returns Logical scalar.
#'
#' @keywords internal
#' @noRd
micromamba_pip_needs_home <- function(
  home,
  on_windows = is_windows(),
  on_macos = is_macos(),
  keyring = Sys.which("keyring")
) {
  if (isTRUE(nzchar(keyring))) {
    return(TRUE)
  }
  if (isTRUE(on_windows)) {
    return(isTRUE(fs::file_exists(fs::path(home, "pip", "pip.ini"))))
  }
  xdg_config <- Sys.getenv("XDG_CONFIG_HOME", unset = "")
  xdg_data <- Sys.getenv("XDG_DATA_HOME", unset = "")
  files <- fs::path(home, ".pip", "pip.conf")
  if (isTRUE(on_macos)) {
    files <- c(
      files,
      fs::path(home, "Library", "Application Support", "pip", "pip.conf"),
      fs::path(home, ".config", "pip", "pip.conf")
    )
  } else if (identical(xdg_config, "")) {
    files <- c(files, fs::path(home, ".config", "pip", "pip.conf"))
  }
  if (identical(xdg_config, "")) {
    files <- c(files, fs::path(home, ".config", "uv", "uv.toml"))
  }
  if (identical(xdg_data, "")) {
    files <- c(
      files,
      fs::path(home, ".local", "share", "uv", "credentials", "credentials.toml")
    )
  }
  return(isTRUE(any(fs::file_exists(files))))
}

#' The home directory that micromamba uses
#'
#' `HOME`, else the home of the user's account, and on Windows
#' `USERPROFILE`, else `HOMEDRIVE` and `HOMEPATH`, as libmamba's
#' `user_home_dir()`.
#'
#' @returns Character string.
#'
#' @keywords internal
#' @noRd
micromamba_user_home <- function() {
  if (isTRUE(is_windows())) {
    home <- Sys.getenv("USERPROFILE", unset = "")
    if (isFALSE(nzchar(home))) {
      home <- paste0(Sys.getenv("HOMEDRIVE"), Sys.getenv("HOMEPATH"))
    }
    return(home)
  }
  home <- Sys.getenv("HOME", unset = "")
  if (isFALSE(nzchar(home))) {
    home <- as.character(fs::path_home())
  }
  return(home)
}

#' Expand `~` as micromamba does
#'
#' `~` alone, or followed by `/` (on Windows also by `\\`), becomes the
#' home of `micromamba_user_home()`; anything else, `~user` included, is
#' kept, as libmamba's `expand_home()` keeps it. `micromamba create` can run
#' with another home (see `micromamba_create_keeps_home()`), so
#' `condathis` expands the channels, package paths and environment file
#' path it passes.
#'
#' @param x Character vector.
#' @param home Character string, the home.
#'
#' @returns `x`, with `~` expanded.
#'
#' @keywords internal
#' @noRd
micromamba_expand_home <- function(x, home = micromamba_user_home()) {
  x <- as.character(x)
  if (identical(length(x), 0L)) {
    return(x)
  }
  prefix_pattern <- if (isTRUE(is_windows())) "^~([/\\\\]|$)" else "^~(/|$)"
  at_home <- !is.na(x) & grepl(prefix_pattern, x)
  x[at_home] <- paste0(home, substring(x[at_home], 2L))
  return(x)
}

#' The variables that every micromamba process of `condathis` gets
#'
#' `MAMBA_ROOT_PREFIX`, set to the root, so that micromamba resolves no
#' default root when it starts (see `micromamba_cmd_overlay()`).
#' `native_cmd()` gives it every command through `micromamba_cmd_overlay()`,
#' and `get_micromamba_version()` gives it the `--version` call.
#'
#' @param root_dir Character string with the micromamba root. The
#'   directory need not exist: micromamba neither checks nor creates it.
#'
#' @returns A named list. Does no file system access.
#'
#' @keywords internal
#' @noRd
micromamba_process_envvars <- function(root_dir) {
  return(list(`MAMBA_ROOT_PREFIX` = as.character(root_dir)))
}

#' The user cache directory of micromamba's own commands
#'
#' `<root>/cache`, the `XDG_CACHE_HOME` that `micromamba_cmd_overlay()`
#' gives every command. micromamba keeps its sharded repodata cache in
#' `conda/pkgs/cache/shards` under it, and on Linux the pip of an
#' environment file its cache in `pip`. `clean_cache()` deletes it.
#'
#' @param root_dir Character string with the micromamba root.
#'
#' @returns A character string. Does no file system access.
#'
#' @keywords internal
#' @noRd
micromamba_cache_dir <- function(root_dir) {
  return(as.character(fs::path(root_dir, "cache")))
}

#' The `TMP` directory of micromamba's own commands
#'
#' On Windows, `<tmp_dir>\mamba-tmp`, the `TMP` that
#' `micromamba_cmd_overlay()` gives every command, spelled with the
#' separator of `tmp_dir` (`tempfile()` gives backslashes on Windows).
#'
#' @param tmp_dir Character string, the `TMPDIR` of the command, or `NULL`.
#'
#' @returns A character string, or `NULL` on other OSs and when `tmp_dir`
#'   is `NULL`. Does no file system access.
#'
#' @keywords internal
#' @noRd
micromamba_tmp_dir <- function(tmp_dir) {
  if (isFALSE(is_windows()) || is.null(tmp_dir)) {
    return(NULL)
  }
  tmp_dir <- as.character(tmp_dir)
  sep <- if (grepl("\\", tmp_dir, fixed = TRUE)) "\\" else "/"
  return(file.path(tmp_dir, "mamba-tmp", fsep = sep))
}

#' Write the micromamba configuration file of the `condathis` root
#'
#' Two settings: `pkgs_dirs`, pinned to `<root>/pkgs`, and
#' `shortcuts: false`. On Windows, micromamba otherwise adds a Start Menu
#' shortcut for each `Menu/*.json` file of a package it links (such as
#' `spyder`), in the Programs known folder, which Windows finds under
#' `USERPROFILE`, not in the root. The file is rewritten only when its
#' content would change, through a temporary file and a rename, so
#' concurrent `condathis` processes never read a partial file.
#'
#' @param root_dir Character string. The `condathis` root directory.
#'
#' @returns The path of the configuration file.
#'
#' @keywords internal
#' @noRd
ensure_condathis_rc_file <- function(root_dir) {
  rc_path <- fs::path(root_dir, "condathis-micromamba.yaml")
  yaml_quote <- function(x) {
    paste0("'", gsub("'", "''", as.character(x), fixed = TRUE), "'")
  }
  content <- c(
    "# Written by condathis. Changes are overwritten.",
    "pkgs_dirs:",
    paste0("  - ", yaml_quote(fs::path(root_dir, "pkgs"))),
    "shortcuts: false"
  )
  current <- if (isTRUE(fs::file_exists(rc_path))) {
    tryCatch(readLines(rc_path, warn = FALSE), error = function(e) NULL)
  }
  if (isFALSE(identical(current, content))) {
    if (isFALSE(fs::dir_exists(root_dir))) {
      fs::dir_create(root_dir)
    }
    tmp_path <- fs::path(
      root_dir,
      paste0(".condathis-micromamba-", Sys.getpid(), ".yaml.tmp")
    )
    writeLines(content, tmp_path)
    file.rename(tmp_path, rc_path)
    if (isTRUE(fs::file_exists(tmp_path))) {
      try(fs::file_delete(tmp_path), silent = TRUE)
    }
  }
  return(rc_path)
}

#' Whether `native_cmd()` echoes the output of micromamba
#'
#' Management commands pass `micromamba_quiet_args` to hide micromamba's own
#' output. It still prints progress to stdout, so that is captured but not
#' echoed, as with the `--quiet` flag it replaced. Only `conda_args` is
#' checked: the positional arguments are package specs, or for
#' `micromamba run` the command it starts, and a `--log-level error` there
#' belongs to that command.
#'
#' @param output Logical. The `output` flag of `parse_strategy_verbose()`.
#' @param conda_args Character vector. The micromamba options passed by
#'   `condathis`.
#' @param stderr The standard error target. Output is not echoed when
#'   stderr is redirected: to a file path, or with `"2>&1"`.
#' @param encoding Character string. Binary streams are never echoed: they
#'   have no terminal representation.
#'
#' @returns Logical scalar.
#'
#' @keywords internal
#' @noRd
native_cmd_echo <- function(output, conda_args, stderr, encoding) {
  # `NULL %in% x` is `logical(0)`: a discarded stderr keeps the echo.
  stderr_to_file <- isFALSE(stderr %in% c("|", ""))
  return(
    isTRUE(output) &&
      isFALSE(stderr_to_file) &&
      isFALSE(has_arg_sequence(conda_args, micromamba_quiet_args)) &&
      isFALSE(identical(encoding, "binary"))
  )
}

#' Check whether `args` contains `seq` as consecutive elements
#'
#' @keywords internal
#' @noRd
has_arg_sequence <- function(args, seq) {
  args <- as.character(unlist(args))
  n <- length(seq)
  if (length(args) < n) {
    return(FALSE)
  }
  for (i in seq_len(length(args) - n + 1L)) {
    if (identical(args[i:(i + n - 1L)], seq)) {
      return(TRUE)
    }
  }
  return(FALSE)
}
