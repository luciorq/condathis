#' Choose the platform of a new environment
#'
#' `create_env()` calls it before `backend_create_env()`, for every
#' backend: the front end chooses the platform, and the backend only builds
#' the environment for it. See `define_platform()`.
#'
#' @param backend An already-resolved backend object.
#' @param packages,platform,channels,channel_priority,additional_channels,verbose,env_file
#'   As in `define_platform()`.
#' @param call Environment of the function that an invalid value of the
#'   backend is reported for.
#'
#' @returns A platform (subdir) name, or `NULL` for the native platform of
#'   the backend.
#'
#' @keywords internal
#' @noRd
resolve_create_platform <- function(
  backend,
  packages,
  platform,
  channels,
  channel_priority,
  additional_channels,
  verbose = "silent",
  env_file = NULL,
  call = rlang::caller_env()
) {
  # An empty environment solves for every platform: nothing to choose.
  if (rlang::is_null(packages) && rlang::is_null(env_file)) {
    return(platform)
  }
  # The caller's verbose level, so the emulation messages show; the solves
  # of define_platform() always run silently.
  return(define_platform(
    backend,
    packages = packages,
    platform = platform,
    channels = channels,
    channel_priority = channel_priority,
    additional_channels = additional_channels,
    verbose = verbose,
    env_file = env_file,
    call = call
  ))
}

#' Choose the platform of an install into an existing environment
#'
#' An environment created for another platform (`platform`, or the
#' emulation fallback of `define_platform()`) got packages for the native
#' platform of the backend: two platforms in one environment. So the
#' install solves for the platform of the environment (see
#' `env_platform()`), and `install_packages()` passes it to
#' `backend_install()`, for every backend. An environment with neither a
#' recorded platform nor packages other than `noarch` ones, such as the
#' empty `"condathis-env"` that `install_packages()` creates, gets the
#' emulation fallback of `create_env()` instead. Nothing is recorded for
#' it: after the install, its package records give the platform. Only
#' where that fallback exists (see `has_platform_fallback()`) are the
#' package records read: elsewhere every environment without a recorded
#' platform has the native platform of its backend, and reading the
#' records of an environment of 200 packages took about half a second.
#'
#' @param backend An already-resolved backend object.
#' @param env_dir Character string, the directory of the environment.
#' @param packages Character vector of package MatchSpec strings.
#' @param channels,channel_priority,additional_channels,verbose As in
#'   `define_platform()`.
#' @param call Environment of the function that an invalid value of the
#'   backend is reported for.
#'
#' @returns A platform (subdir) name, or `NULL` when the backend solves for
#'   its native platform. `NULL` also when `env_dir` does not exist: the
#'   backend then reports the missing environment.
#'
#' @keywords internal
#' @noRd
resolve_install_platform <- function(
  backend,
  env_dir,
  packages,
  channels,
  channel_priority,
  additional_channels,
  verbose = "silent",
  call = rlang::caller_env()
) {
  if (isFALSE(fs::dir_exists(env_dir))) {
    return(NULL)
  }
  can_fall_back <- has_platform_fallback()
  recorded_platform <- env_platform(env_dir, read_records = can_fall_back)
  if (isFALSE(rlang::is_null(recorded_platform))) {
    return(recorded_platform)
  }
  # Packages of several platforms, or of an unknown one: no fallback.
  # `noarch` packages work on every platform, as in an empty environment.
  if (
    isFALSE(can_fall_back) ||
      isTRUE(env_has_platform_packages(env_dir))
  ) {
    return(NULL)
  }
  return(define_platform(
    backend,
    packages = packages,
    platform = NULL,
    channels = channels,
    channel_priority = channel_priority,
    additional_channels = additional_channels,
    verbose = verbose,
    call = call
  ))
}

#' Choose an emulated platform when a request does not solve natively
#'
#' The emulation fallback of `create_env()`, and of `install_packages()`
#' into an environment that has neither a recorded platform nor packages
#' other than `noarch` ones (see `resolve_install_platform()`), for every
#' backend. Two fallbacks exist, and both ask `backend_can_solve()` about
#' the whole request, first for the native platform and then, only when
#' that does not solve, for the emulated one: on Apple Silicon, `osx-64`
#' when Rosetta 2 is running; when the backend solves for `win-arm64` (see
#' `backend_native_platform()`), `win-64`, through the x64 emulation of
#' Windows 11 on ARM. The emulated platform is used only when the request
#' solves for it. A backend without these two functions gets `NA` from
#' both defaults, and so never an emulated platform.
#'
#' @param backend An already-resolved backend object.
#' @param packages Character vector of package MatchSpec strings, or `NULL`
#'   when `env_file` is given.
#' @param platform Character string with a user-specified platform.
#'   Defaults to `NULL`. A given platform is used as is: nothing is solved.
#' @param channels Character vector with channel names.
#'   Defaults to `"conda-forge"`.
#' @param channel_priority Character string with channel priority mode.
#'   Supported values are `"strict"`, `"flexible"`, and `"disabled"`.
#'   Defaults to `"strict"`.
#' @param additional_channels Character vector of additional channels.
#'   Defaults to `NULL`.
#' @param verbose Character string, the `verbose` value of the call that
#'   creates the environment or installs into it. It controls only the
#'   emulation messages: `"silent"` (the default) hides them. The solves
#'   never print anything (`backend_can_solve()` takes no `verbose`). So
#'   the caller must pass its own `verbose`, not `"silent"`, or the
#'   messages are never shown.
#' @param env_file `NULL` (the default) or the path of an environment file.
#'   When given, it is solved instead of `packages`.
#' @param call Environment of the function that an invalid value of the
#'   backend is reported for.
#'
#' @returns A platform (subdir) name: `platform` when it is given, or the
#'   emulated platform. `NULL` when the backend solves for its native
#'   platform.
#'
#' @keywords internal
#' @noRd
define_platform <- function(
  backend,
  packages,
  platform = NULL,
  channels = "conda-forge",
  channel_priority = c("strict", "flexible", "disabled"),
  additional_channels = NULL,
  verbose = "silent",
  env_file = NULL,
  call = rlang::caller_env()
) {
  if (isFALSE(rlang::is_null(platform))) {
    return(platform)
  }
  # An empty request, for an empty environment, solves for every platform.
  if (rlang::is_null(env_file) && identical(length(packages), 0L)) {
    return(NULL)
  }
  chosen_platform <- NULL
  # `"silent"` means no output at all, also for these messages.
  show_messages <- isFALSE(identical(
    parse_strategy_verbose(verbose = verbose)$strategy,
    "silent"
  ))
  # A solve of the whole request, not a search per spec: a `noarch` spec,
  # such as `r-ggplot2`, exists for every platform, also for one where its
  # dependency `r-base` has no build. A result of `NA` is a failure that is
  # not about the packages, such as a missing channel: no fallback, so the
  # create or install reports the backend's own error.
  solves_for <- function(target_platform) {
    return(backend_can_solve_checked(
      backend,
      packages = packages,
      env_file = env_file,
      channels = channels,
      channel_priority = channel_priority,
      additional_channels = additional_channels,
      platform = target_platform,
      call = call
    ))
  }

  if (identical(get_sys_arch(), "Darwin-arm64")) {
    if (isFALSE(solves_for("osx-arm64"))) {
      if (isTRUE(is_rosetta_running())) {
        rosetta_res <- solves_for("osx-64")
      } else {
        if (isTRUE(show_messages)) {
          # Not `{.arg packages}`: create_env() and install_packages() take
          # the specs in `...`. Not "is not available" either: specs that
          # conflict do not solve for any platform.
          condathis_inform(c(
            `x` = "The requested packages cannot be installed for {.val osx-arm64}.",
            `i` = "{.field Rosetta 2} is not enabled, so {.val osx-64} packages cannot be used."
          ))
        }
        rosetta_res <- FALSE
      }
      if (isTRUE(rosetta_res)) {
        if (isTRUE(show_messages)) {
          condathis_inform(c(
            `i` = "Using {.field Rosetta 2} emulation."
          ))
        }
        chosen_platform <- "osx-64"
      }
    }
  }

  # The backend solves for its own platform, which need not be the one of
  # R: see micromamba_native_platform().
  if (
    isTRUE(is_windows()) &&
      identical(
        backend_native_platform_checked(backend, call = call),
        "win-arm64"
      )
  ) {
    # conda-forge builds far fewer packages for win-arm64 than for win-64.
    # Windows 11 on ARM always has x64 emulation, and no older Windows on
    # ARM runs a supported R: unlike Rosetta 2, there is nothing to check.
    if (isFALSE(solves_for("win-arm64")) && isTRUE(solves_for("win-64"))) {
      if (isTRUE(show_messages)) {
        condathis_inform(c(
          `i` = "Using {.field x64} emulation for {.val win-64} packages."
        ))
      }
      chosen_platform <- "win-64"
    }
  }
  return(chosen_platform)
}

#' Can `define_platform()` fall back to an emulated platform here?
#'
#' Its two fallbacks run on Apple Silicon, and on Windows with a backend
#' that solves for `win-arm64`, which any R of an ARM64 PC can meet: the
#' `win-arm64` micromamba that another R installed (see
#' `micromamba_native_platform()`). So every Windows machine counts.
#' Elsewhere, an environment of a platform other than the native one of
#' its backend comes only from `create_env(platform = )`, and condathis
#' records that platform (see `env_platform()`), also for an empty
#' environment. Keep this in step with the branches of `define_platform()`.
#'
#' @returns Logical scalar. No process starts.
#'
#' @keywords internal
#' @noRd
has_platform_fallback <- function() {
  return(identical(get_sys_arch(), "Darwin-arm64") || isTRUE(is_windows()))
}

#' Platform of an environment
#'
#' The platform that later installs into the environment solve for. In
#' this order:
#' 1. The `platform` of the backend marker that `create_env()` writes (see
#'    `write_backend_marker()`), when a platform was given or chosen by the
#'    emulation fallback. Every backend.
#' 2. The `platform:` of the `.mambarc` of the environment. `micromamba
#'    create --platform <p>` writes it (micromamba 2.8 and 2.10 do), also
#'    for the environments of an older condathis without a marker
#'    platform. micromamba reads that file for later commands in the
#'    environment, but the `--rc-file` of `native_cmd()` keeps it from
#'    doing so, so condathis passes the platform itself.
#' 3. With `read_records`, the `subdir` of the package records in
#'    `conda-meta/`, without `noarch` (see `read_conda_package_records()`,
#'    which skips a record that cannot be read): for an environment created
#'    by another tool, or by `install_packages()` into an empty
#'    environment.
#'
#' @param env_dir Character string, the directory of the environment.
#' @param read_records Logical. `FALSE` reads only the marker and the
#'   `.mambarc`, for a system where every environment without a recorded
#'   platform has the native platform of its backend (see
#'   `resolve_install_platform()`). Defaults to `TRUE`.
#'
#' @returns The platform, such as `"win-64"`: the recorded one, or else the
#'   one that every package other than a `noarch` one has. `NULL` when no
#'   package has a platform other than `noarch`, or when the packages have
#'   several platforms: then the backend solves for its native platform,
#'   and condathis does not guess.
#'
#' @keywords internal
#' @noRd
env_platform <- function(env_dir, read_records = TRUE) {
  marker_platform <- read_backend_marker_platform(env_dir)
  if (isFALSE(rlang::is_null(marker_platform))) {
    return(marker_platform)
  }
  rc_path <- fs::path(env_dir, ".mambarc")
  rc_lines <- character(0L)
  if (isTRUE(fs::file_exists(rc_path))) {
    # micromamba writes the file without a final newline.
    rc_lines <- tryCatch(
      readLines(rc_path, warn = FALSE),
      error = function(e) character(0L)
    )
  }
  rc_platform <- stringr::str_match(
    rc_lines,
    "^platform:\\s*['\"]?([[:alnum:]_-]+)['\"]?\\s*$"
  )[, 2L]
  rc_platform <- rc_platform[!is.na(rc_platform)]
  if (isTRUE(length(rc_platform) > 0L)) {
    return(rc_platform[[length(rc_platform)]])
  }
  if (isFALSE(read_records)) {
    return(NULL)
  }

  records_df <- tryCatch(
    read_conda_package_records(
      env_dir = env_dir,
      env_name = fs::path_file(env_dir)
    ),
    condathis_env_not_found = function(cnd) list()
  )
  record_platforms <- env_package_platforms(records_df)
  if (identical(length(record_platforms), 1L)) {
    return(record_platforms)
  }
  return(NULL)
}

#' Does an environment have a package of a platform?
#'
#' @param env_dir Character string, the directory of the environment.
#'
#' @returns `TRUE` when `conda-meta/` holds a `*.json` package record whose
#'   `subdir` is not `"noarch"`, also one that cannot be read or has no
#'   `subdir`: a package of an unknown platform is installed. `FALSE` for
#'   an environment without packages, or with only `noarch` ones, which
#'   work on every platform. The records are read until the first that is
#'   not `noarch`.
#'
#' @keywords internal
#' @noRd
env_has_platform_packages <- function(env_dir) {
  meta_dir <- fs::path(env_dir, "conda-meta")
  if (isFALSE(fs::dir_exists(meta_dir))) {
    return(FALSE)
  }
  record_files <- fs::dir_ls(meta_dir, glob = "*.json", type = "file")
  for (record_file in record_files) {
    record <- tryCatch(
      jsonlite::read_json(record_file),
      error = function(e) NULL
    )
    record_subdir <- NULL
    if (isTRUE(is.list(record))) {
      record_subdir <- record[["subdir"]]
    }
    if (isFALSE(identical(record_subdir, "noarch"))) {
      return(TRUE)
    }
  }
  return(FALSE)
}

#' Is the Rosetta 2 daemon running?
#'
#' A separate function, so tests can give its answer on any OS.
#'
#' @returns `TRUE` when `pgrep oahd` finds the Rosetta 2 daemon.
#'
#' @keywords internal
#' @noRd
is_rosetta_running <- function() {
  px_res <- processx::run(
    command = Sys.which("pgrep"),
    args = "oahd",
    error_on_status = FALSE,
    spinner = FALSE,
    echo = FALSE,
    echo_cmd = FALSE
  )
  return(identical(px_res$status, 0L))
}

#' Platform of the micromamba binary in use
#'
#' micromamba solves for the platform of its own binary, not of R. Every R
#' of a user shares the managed binary, so on an ARM64 PC an x64 R can run
#' the `win-arm64` binary that a native ARM64 R installed, and a native
#' ARM64 R the `win-64` one of an x64 R. `define_platform()` asks on every
#' Windows machine, x64 included, for every `create_env()` with package
#' specs or an `env_file` and every install into an environment without
#' packages of a platform. So when `native_cmd()` runs the managed binary,
#' the answer is read from the `Machine` field of its PE header (see
#' `read_pe_machine()`), and no process starts. Otherwise, the answer is
#' the `platform` of `micromamba info --json`, from the binary that
#' `native_cmd()` runs: the one of `condathis.micromamba_path` or
#' `CONDATHIS_MICROMAMBA_PATH`, or one found after the managed binary (see
#' `get_best_micromamba_path()`), or else the managed binary, which
#' `native_cmd()` installs first, as for the first `create_env()` on a new
#' machine. A separate function, so tests can give its answer on any OS.
#'
#' @param umamba_path `NULL` (the default) for the binary that
#'   `native_cmd()` runs, as above, or the path of a micromamba binary: then
#'   only its PE header is read.
#'
#' @returns `"win-arm64"` for an ARM64 binary, `"win-64"` for an x64 one.
#'   For a given `umamba_path`, `NA` for anything else: a missing file, a
#'   file that is too short or not a PE file, or another machine type, such
#'   as the ELF and Mach-O binaries of Linux and macOS. For the binary in
#'   use, such as `"linux-64"` there, or `NA` when `micromamba info` gives
#'   no platform.
#'
#' @keywords internal
#' @noRd
micromamba_native_platform <- function(umamba_path = NULL) {
  if (rlang::is_null(umamba_path)) {
    # As in get_best_micromamba_path(), only the two overrides come before
    # the managed binary. A managed binary older than
    # `micromamba_minimum_version`, which native_cmd() passes over, is still
    # read: condathis installs only newer ones.
    user_opt <- getOption("condathis.micromamba_path", default = "")
    user_env <- Sys.getenv("CONDATHIS_MICROMAMBA_PATH", unset = "")
    if (isFALSE(isTRUE(nzchar(user_opt))) && isFALSE(nzchar(user_env))) {
      managed_platform <- micromamba_native_platform(micromamba_bin_path())
      if (isFALSE(is.na(managed_platform))) {
        return(managed_platform)
      }
    }
    # Installs micromamba when no binary is found, as the native_cmd() of
    # the create or install that follows would.
    px_res <- native_cmd(
      conda_cmd = "info",
      conda_args = "--json",
      verbose = "silent",
      error = "continue"
    )
    info_platform <- tryCatch(
      jsonlite::fromJSON(px_res$stdout, simplifyVector = FALSE)[["platform"]],
      error = function(e) NULL
    )
    if (isFALSE(rlang::is_string(info_platform))) {
      return(NA_character_)
    }
    return(info_platform)
  }
  pe_machine <- tryCatch(
    read_pe_machine(umamba_path),
    error = function(e) NA_integer_,
    warning = function(w) NA_integer_
  )
  if (isFALSE(rlang::is_scalar_integer(pe_machine)) || is.na(pe_machine)) {
    return(NA_character_)
  }
  # `IMAGE_FILE_MACHINE_ARM64` and `IMAGE_FILE_MACHINE_AMD64` of the PE
  # format.
  native_platform <- switch(
    sprintf("%04x", pe_machine),
    `aa64` = "win-arm64",
    `8664` = "win-64",
    NA_character_
  )
  return(native_platform)
}

#' The `backend_native_platform()` function of the micromamba backend
#'
#' @param backend The micromamba backend object.
#'
#' @returns The platform that micromamba solves for, from
#'   `micromamba_native_platform()`, or `NA`.
#'
#' @keywords internal
#' @noRd
micromamba_backend_native_platform <- function(backend) {
  return(micromamba_native_platform())
}

#' Read the `Machine` field of the PE header of a Windows executable
#'
#' A PE file starts with a 64-byte DOS header, `"MZ"` first. Its bytes
#' `0x3C` to `0x3F` give the little-endian offset of the `"PE\0\0"`
#' signature, and the two bytes after the signature are the `Machine`
#' field, also little-endian.
#'
#' @param path Character string, the path of the file.
#'
#' @returns An integer, such as `0xAA64` for ARM64 or `0x8664` for x64, or
#'   `NA_integer_` when `path` is not a file, is too short, or has no DOS
#'   header or PE signature where they belong.
#'
#' @keywords internal
#' @noRd
read_pe_machine <- function(path) {
  if (isFALSE(isTRUE(fs::is_file(path)))) {
    return(NA_integer_)
  }
  file_size <- file.size(path)
  if (isFALSE(isTRUE(file_size >= 64))) {
    return(NA_integer_)
  }
  dos_header <- readBin(path, what = "raw", n = 64L)
  if (isFALSE(identical(dos_header[1:2], charToRaw("MZ")))) {
    return(NA_integer_)
  }
  pe_offset <- readBin(
    dos_header[61:64],
    what = "integer",
    size = 4L,
    endian = "little"
  )
  # Signed: an offset past 2 GiB reads as negative.
  if (isFALSE(isTRUE(pe_offset >= 0L && pe_offset + 6 <= file_size))) {
    return(NA_integer_)
  }
  # One read from the start of the file, not `seek()`, which the R
  # documentation advises against on Windows.
  file_head <- readBin(path, what = "raw", n = pe_offset + 6)
  pe_header <- file_head[pe_offset + seq_len(6L)]
  if (isFALSE(identical(pe_header[1:4], as.raw(c(0x50, 0x45, 0x00, 0x00))))) {
    return(NA_integer_)
  }
  return(readBin(
    pe_header[5:6],
    what = "integer",
    size = 2L,
    signed = FALSE,
    endian = "little"
  ))
}
