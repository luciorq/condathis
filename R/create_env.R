#' Create a Conda environment
#'
#' Creates a Conda environment from package specs or from an environment
#' file. With `overwrite = FALSE` (the default), `create_env()` never replaces
#' an existing environment. It keeps the environment when it already has the
#' requested packages. Otherwise, it aborts (see *Existing environments*).
#'
#' With the micromamba backend, `create_env()` adds the new environment to
#' `~/.conda/environments.txt`, the registry that conda and mamba share.
#' It does so only when micromamba needs your home directory, for example
#' for channel credentials you saved there (see Details in
#' [get_install_dir()]).
#'
#' @param ... Package match specs (MatchSpec strings), unnamed: character
#'   strings or character vectors, in order. Examples: `"python=3.13"`,
#'   `"bioconda::fastqc==0.12.1"`. With no specs, `create_env()` creates an
#'   empty environment.
#'   Any other value aborts with class
#'   `condathis_create_env_invalid_packages`. Such values are:
#'   * A named argument that `create_env()` does not have. The error names
#'     the closest argument.
#'   * A value that is not a character vector.
#'   * `NA` or `""`.
#'   * A file name that ends in `.yml` or `.yaml`. Pass it as `env_file`.
#'
#'   `packages = <specs>` still works. It is deprecated and warns once per
#'   session (class `condathis_deprecated_packages_arg`).
#'   `create_env()` aborts with class
#'   `condathis_create_env_positional_env_name` when `env_name` is not given
#'   and the last of two or more specs names an existing environment. Name
#'   the argument, as in `env_name = "my-env"`.
#' @inheritParams condathis-params
#' @param channels A non-empty character vector of channel names or URLs,
#'   in priority order. For a package from another channel, either name the
#'   channel in the spec (`"bioconda::samtools"`) or add it here, as in
#'   `channels = c("conda-forge", "bioconda")`. Invalid values, such as
#'   `NULL`, `NA` or `""`, abort with class
#'   `condathis_create_env_invalid_channels`.
#' @param additional_channels `NULL` (the default) or a non-empty character
#'   vector of channel names or URLs, used after `channels`. Invalid values
#'   abort with class `condathis_create_env_invalid_channels` (also
#'   `condathis_invalid_additional_channels`).
#' @param channel_priority Channel priority mode: `"strict"` (the default),
#'   `"flexible"` or `"disabled"`. With `"strict"`, when several channels
#'   have a package, the solver uses only the builds from the first of them.
#'   This keeps the solution reproducible. The mamba documentation recommends
#'   this setting. Invalid values abort with class
#'   `condathis_create_env_invalid_channel_priority`.
#' @param platform `NULL` (the default) or the platform for the solver: a
#'   known conda platform (subdir) name in lower case, such as
#'   `"linux-64"`, `"linux-aarch64"`, `"osx-64"`, `"osx-arm64"`,
#'   `"win-64"`, `"win-arm64"` or `"emscripten-wasm32"`. Other values abort
#'   with class `condathis_create_env_invalid_platform` before anything
#'   runs. The message suggests a close name, such as `"linux-aarch64"`
#'   for `"linux-arm64"`. When the channels have no packages for a known
#'   platform, the backend fails. Then `create_env()` aborts with class
#'   `condathis_create_env_failed`.
#'   With `NULL`, condathis can fall back to an emulated platform. This
#'   happens when the package specs or the `env_file` cannot be installed
#'   for the native platform, dependencies included, but can for the
#'   emulated one. This works with every backend that can tell whether a
#'   request solves for a platform, micromamba included. On Apple Silicon,
#'   condathis uses `"osx-64"` when Rosetta 2 is available. With a backend
#'   that solves for `"win-arm64"`, condathis uses `"win-64"` through x64
#'   emulation. The `win-arm64` micromamba, which a native ARM64 R on
#'   Windows installs, is such a backend. [install_packages()] later
#'   installs packages for the platform that the environment was created
#'   for, given or emulated.
#'   For an existing environment, see *Existing environments*.
#' @param env_file `NULL` (the default) or the path of an environment YAML
#'   file. With the micromamba backend, condathis passes it to
#'   `micromamba create -f`. No backend applies the `variables:` of a YAML
#'   file: the commands that run in the environment do not get them. Do not
#'   use both package specs and `env_file`: that aborts with class
#'   `condathis_create_env_conflicting_args`. A file that does not exist
#'   aborts with class `condathis_create_env_missing_env_file`.
#' @param overwrite `TRUE` or `FALSE` (the default).
#'   With `FALSE`, `create_env()` never replaces an existing environment.
#'   `create_env()` keeps the environment and runs nothing when it has every
#'   requested package (see *Existing environments*) or when no package is
#'   requested. It returns status 0.
#'   Otherwise, and always when `env_file` is set, `create_env()` aborts with
#'   class `condathis_create_env_exists`. Use [install_packages()] to add
#'   packages to an existing environment. Use [validate_env()] to check one.
#'   With `TRUE`, `create_env()` creates the environment again from scratch,
#'   also when it exists or was built for another `platform`. When
#'   `create_env()` fails to create the new environment (a misspelled
#'   package, a download error), it keeps the existing one as it was. When it
#'   cannot move the existing one aside first (on Windows, while a program
#'   uses one of its files), it aborts with class
#'   `condathis_create_env_failed` and changes nothing.
#'   Invalid values abort with class `condathis_create_env_invalid_overwrite`.
#'
#' @returns A `condathis_result` object, invisibly: a classed list with
#'   `status`, `stdout`, `stderr`, `timeout`, `pid`, `cmd` and `env_name`.
#'   `cmd` is the command line that the backend ran. It is `NA` when the
#'   backend reports none or when nothing ran (an existing environment that
#'   already has the requested packages). `stdout`, `stderr` and `pid` are
#'   `NA` when the backend reports none, and `pid` always is with micromamba.
#'   A backend failure aborts with class `condathis_create_env_failed` (also
#'   `condathis_backend_error`), with the backend's error as the parent.
#'   micromamba runs the link scripts of packages (`pre-link` and
#'   `post-link`). A backend that does not, such as `"rattler"` of the
#'   `rattlerthis` package, makes `create_env()` warn with class
#'   `condathis_create_env_link_scripts_skipped` (also
#'   `condathis_link_scripts_skipped`). The warning names the packages,
#'   which may not work.
#'
#' @section Existing environments:
#' With `overwrite = FALSE`, `create_env()` compares an existing environment
#' with the request. [validate_env()] makes the same comparison.
#'
#' An installed package satisfies a spec when it matches the name, version,
#' build string and channel of the spec. The name match ignores case:
#' `"PyYAML"` matches `pyyaml`. A spec without a channel must match a
#' package from `channels` or `additional_channels`. The channel comparison
#' ignores credentials and platform subdirectories, and compares a local
#' channel by its absolute path. `"defaults"` matches the `pkgs/main` and
#' `pkgs/r` packages it installs. The comparison uses only these bracket
#' constraints: `version`, `build`, `build_number` and `channel`. `>=1.2.*`
#' is read as `>=1.2`, as micromamba does. A build string matches with `*`
#' as its only wildcard.
#'
#' A spec that condathis cannot compare, or that micromamba, rattler and
#' conda read differently, never counts as satisfied. `create_env()` then
#' aborts for it with class `condathis_create_env_exists`. These are specs
#' with:
#' * Another bracket constraint, such as `"zlib[md5=...]"`, or a group in
#'   parentheses at the end, such as `"zlib (>=1.2,<2)"` (read as bracket
#'   constraints).
#' * A version with `*` after `>`, `<`, `<=` or `~=` (`"zlib<2.*"`).
#' * A version with `*` in its middle (`"zlib=1.*.3"`, `"zlib=1.3.*.*"`), in
#'   `!=1.2*` or in `=1.2*`.
#' * A version with `*` after `>=`, other than a single `.*` at the end
#'   (`"zlib>=1.2*"`).
#' * `~=` with a one-part version (`"zlib~=1"`), an operator with no
#'   version (`"zlib>=*"`), a missing operand (`"zlib>=1.2,"`), a
#'   `build_number` with `==` (`"zlib[build_number='==0']"`), or a version
#'   that micromamba rejects (`"zlib>==1.2"`).
#' * A build string with a character other than a letter, a digit, `_`,
#'   `.` and `*`, such as a regular expression (`"zlib=1.3.1=^h4.*$"`) or
#'   `?`.
#'
#' A spec that condathis cannot read, such as `"::"`, aborts with class
#' `condathis_parse_match_spec_invalid_name`. The URL of a package file
#' whose name is not `<name>-<version>-<build>` aborts with class
#' `condathis_parse_match_spec_invalid_url`. Both errors also have class
#' `condathis_invalid_arg`. For a new environment, only the backend reads
#' the specs. A spec it cannot read aborts with class
#' `condathis_create_env_failed`.
#'
#' When `platform` is given, the platform of the installed packages must be
#' `platform` (`noarch` packages match any platform). A different platform
#' aborts with class `condathis_create_env_platform_mismatch`, and
#' `create_env()` keeps the environment. With `platform = NULL`, the
#' platform is not compared.
#'
#' @section Other R sessions:
#' Only one R session at a time changes an environment. [create_env()],
#' [install_packages()] and [remove_env()] hold a lock on the environment
#' name while they work, with every backend. A call for an environment that
#' another R session is changing waits until that session is done. After
#' two seconds, the call says so with a message of class
#' `condathis_env_lock_waiting`. `verbose = "silent"` hides this message.
#' Ctrl-C stops the wait. [clean_cache()] waits until no other R session
#' creates an environment or installs packages. Those calls wait while it
#' cleans. Each wait gives a message of class `condathis_cache_lock_waiting`.
#' A lock lasts only as long as its session, also when the session crashes
#' or is killed. The lock files are in the directory `locks` of the
#' condathis data directory (see [get_install_dir()]). Where files cannot be
#' locked, such as on some network file systems, the call goes on without
#' the lock. When it changes something, it warns once per session with class
#' `condathis_env_lock_unavailable`.
#'
#' @section Environment names:
#' An `env_name` cannot be a Windows device name, on any OS. These names are
#' `CON`, `PRN`, `AUX`, `NUL`, `CONIN$`, `CONOUT$`, `COM1` to `COM9` and
#' `LPT1` to `LPT9`, and `COM` or `LPT` followed by a superscript one, two
#' or three. The match ignores letter case and also applies with an
#' extension, such as `nul.txt`.
#'
#' @family environments
#' @seealso [condathis-conditions] for every condition class, and
#'   [condathis-options] for the options that choose the backend.
#'
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   # A local channel shipped with condathis, with `polyglot`: a
#'   # dependency-free script that runs on Linux, macOS and Windows.
#'   channel <- system.file(
#'     "extdata", "polyglot-channel",
#'     package = "condathis"
#'   )
#'
#'   # Create a Conda environment from that channel, without network access
#'   # once micromamba is installed.
#'   condathis::create_env(
#'     "polyglot",
#'     env_name = "polyglot-env",
#'     channels = channel
#'   )
#'
#'   # A second call keeps the environment: it already has `polyglot`.
#'   condathis::create_env(
#'     "polyglot",
#'     env_name = "polyglot-env",
#'     channels = channel
#'   )
#'
#'   # Create an empty environment.
#'   condathis::create_env(env_name = "empty-env")
#'
#'   # Create a Conda environment and install the CLI `fastqc` in it.
#'   # Explicitly using the channel `bioconda` and version `0.12.1`.
#'   condathis::create_env(
#'     "bioconda::fastqc==0.12.1",
#'     env_name = "fastqc-env",
#'     verbose = "output"
#'   )
#' })
#' }
#' @export
create_env <- function(
  ...,
  env_name = "condathis-env",
  method = "auto",
  verbose = c("output", "silent", "cmd", "spinner", "full"),
  channels = "conda-forge",
  additional_channels = NULL,
  channel_priority = c("strict", "flexible", "disabled"),
  platform = NULL,
  env_file = NULL,
  overwrite = FALSE
) {
  # Rule R2: every argument is checked before the first backend call, so an
  # invalid value never installs micromamba or starts a process.
  packages <- collect_package_specs(rlang::list2(...), fn = "create_env")
  validate_env_name(
    env_name,
    class = c(
      "condathis_create_env_invalid_env_name",
      "condathis_create_invalid_env_name"
    )
  )
  validate_method_arg(method)
  verbose_list <- parse_verbose_arg(verbose)
  validate_channels_arg(
    channels,
    additional_channels,
    class = "condathis_create_env_invalid_channels"
  )
  channel_priority <- arg_match_classed(
    channel_priority,
    values = c("strict", "flexible", "disabled"),
    class = c(
      "condathis_create_env_invalid_channel_priority",
      "condathis_invalid_channel_priority"
    ),
    arg_name = "channel_priority"
  )
  validate_platform_arg(
    platform,
    class = arg_error_class(
      "create_env",
      "platform",
      aliases = "condathis_create_invalid_platform_arg"
    )
  )
  validate_env_file_arg(env_file)
  validate_bool_arg(
    overwrite,
    class = arg_error_class(
      "create_env",
      "overwrite",
      aliases = "condathis_create_invalid_overwrite_arg"
    ),
    arg_name = "overwrite"
  )
  if (isTRUE(length(packages) > 0L) && isFALSE(is.null(env_file))) {
    # micromamba used the file and silently dropped the specs.
    condathis_abort(
      message = c(
        `x` = "Use either package specs in {.arg ...} or {.arg env_file}, not both."
      ),
      class = c(
        "condathis_create_env_conflicting_args",
        "condathis_invalid_arg"
      )
    )
  }
  if (missing(env_name)) {
    abort_on_positional_env_name(packages, fn = "create_env")
  }

  # One R session at a time changes an environment (see
  # `local_env_lock()`): everything from here on, the existence checks and
  # the set-aside and restore of an existing environment included, runs
  # under its lock. The package caches are held shared, so `clean_cache()`
  # in another session waits (see `local_cache_lock()`).
  env_lock <- local_env_lock(env_name, verbose = verbose_list$strategy)
  cache_lock <- local_cache_lock(verbose = verbose_list$strategy)

  resolved <- resolve_backend(
    env_name = env_name,
    method = method,
    mutating = TRUE
  )

  # Decision D4: `overwrite = FALSE` never replaces an environment, so
  # `backend_create_env()` gets only a missing environment, or
  # `overwrite = TRUE`.
  if (
    isFALSE(overwrite) &&
      isTRUE(env_exists_for_change(
        backend = resolved$backend,
        backend_name = resolved$name,
        env_name = env_name
      ))
  ) {
    result <- keep_existing_env(
      backend = resolved$backend,
      backend_name = resolved$name,
      env_name = env_name,
      packages = packages,
      channels = c(channels, additional_channels),
      platform = platform,
      env_file = env_file,
      verbose_list = verbose_list
    )
    return(invisible(result))
  }

  packages <- if (isTRUE(length(packages) > 0L)) packages
  # The front end chooses the platform for every backend: a given one, or
  # an emulated one when the request does not solve for the native
  # platform (see define_platform()). The probes are backend calls of this
  # create, so their errors have its classes.
  platform <- with_backend_errors(
    resolve_create_platform(
      resolved$backend,
      packages = packages,
      platform = platform,
      channels = channels,
      channel_priority = channel_priority,
      additional_channels = additional_channels,
      verbose = verbose_list$strategy,
      env_file = env_file
    ),
    fn = "create_env",
    backend_name = resolved$name,
    action = paste0("create environment '", env_name, "'")
  )
  # The backend gets a free environment directory: an existing environment
  # is moved aside first, and moved back when the create fails (see
  # with_env_dir_replacement()). The result is read inside, so a non-zero
  # status also restores the old environment, and a failed environment
  # gets no marker.
  env_lock_before_change(env_lock, cache_lock)
  created <- with_backend_errors(
    with_env_dir_replacement(
      resolved$backend,
      env_name = env_name,
      expr = {
        px_res <- backend_create_env(
          resolved$backend,
          packages = packages,
          env_file = env_file,
          env_name = env_name,
          channels = channels,
          channel_priority = channel_priority,
          additional_channels = additional_channels,
          platform = platform,
          overwrite = overwrite,
          verbose = verbose_list$strategy
        )
        list(
          result = new_backend_result(
            px_res,
            fn = "create_env",
            backend_name = resolved$name,
            env_name = env_name
          ),
          link_scripts = backend_link_scripts_skipped(
            px_res,
            fn = "create_env",
            backend_name = resolved$name
          )
        )
      }
    ),
    fn = "create_env",
    backend_name = resolved$name,
    action = paste0("create environment '", env_name, "'")
  )

  write_backend_marker(
    env_dir_for_backend(resolved$backend, env_name),
    resolved$name,
    platform = platform
  )

  if (isTRUE(verbose_list$strategy %in% c("full", "output"))) {
    condathis_inform(
      message = c(
        `v` = "Environment {.field {env_name}} successfully created."
      )
    )
  }
  warn_link_scripts_skipped(
    created$link_scripts,
    fn = "create_env",
    backend_name = resolved$name,
    env_name = env_name
  )
  return(invisible(created$result))
}

#' Conda platforms (subdirs) that `validate_platform_arg()` accepts
#'
#' The platforms that conda, micromamba 2.10.0 (`KnownPlatform` in
#' `libmamba/include/mamba/specs/platform.hpp`) and rattler 0.52.1
#' (`rattler_conda_types::Platform`) name. micromamba also solves for
#' other subdirs, as a "dynamic" platform, but a misspelled name such as
#' `"linux-arm64"` then fails late with "does not exist", and rattler
#' rejects names it does not know. conda accepts only its known subdirs
#' too.
#'
#' @keywords internal
#' @noRd
known_platforms <- c(
  "noarch",
  "linux-32",
  "linux-64",
  "linux-aarch64",
  "linux-armv6l",
  "linux-armv7l",
  "linux-loongarch64",
  "linux-ppc",
  "linux-ppc64",
  "linux-ppc64le",
  "linux-riscv32",
  "linux-riscv64",
  "linux-s390x",
  "osx-64",
  "osx-arm64",
  "win-32",
  "win-64",
  "win-arm64",
  "freebsd-32",
  "freebsd-64",
  "freebsd-arm64",
  "android-32",
  "android-64",
  "android-aarch64",
  "android-armv7a",
  "ios-arm64",
  "iossimulator-64",
  "iossimulator-arm64",
  "emscripten-wasm32",
  "emscripten-wasm64",
  "wasi-wasm32",
  "zos-z"
)

#' The conda platform a common other spelling of a platform stands for
#'
#' Other tools name architectures differently (`arm64` and `aarch64`,
#' `x86_64`, `amd64` and `x64`), so `"linux-arm64"` means
#' `"linux-aarch64"` and `"osx-aarch64"` means `"osx-arm64"`. Edit
#' distance alone suggests `"linux-armv6l"` for `"linux-arm64"`.
#'
#' @param platform A single string.
#'
#' @returns The name in `known_platforms`, or `character(0)`.
#'
#' @keywords internal
#' @noRd
platform_alias <- function(platform) {
  pattern <- "^([a-z]+)[-_]([a-z0-9_]+)$"
  lowered <- tolower(platform)
  if (isFALSE(grepl(pattern, lowered))) {
    return(character(0L))
  }
  parts <- c(sub(pattern, "\\1", lowered), sub(pattern, "\\2", lowered))
  os <- switch(
    parts[[1L]],
    darwin = ,
    macos = "osx",
    windows = "win",
    parts[[1L]]
  )
  arch <- switch(
    parts[[2L]],
    arm64 = ,
    aarch64 = if (identical(os, "linux")) "aarch64" else "arm64",
    x86_64 = ,
    amd64 = ,
    x64 = "64",
    x86 = ,
    i386 = ,
    i686 = "32",
    parts[[2L]]
  )
  candidate <- paste0(os, "-", arch)
  if (isTRUE(candidate %in% known_platforms)) {
    return(candidate)
  }
  return(character(0L))
}

#' Validate a `platform` argument
#'
#' Rule R2: the check runs before any backend call, so a misspelled
#' platform never installs micromamba or starts a process. Only the names
#' in `known_platforms` are accepted. Whether the channels have packages
#' for the platform is up to the backend.
#'
#' @param platform The value of `platform`.
#' @param class Character vector, usually `arg_error_class(fn, "platform")`.
#'   `"condathis_invalid_arg"` is kept or appended.
#' @param call Environment of the function the error is reported for.
#'
#' @returns `platform`, invisibly, when it is `NULL` or one of
#'   `known_platforms`. Aborts otherwise, with the closest names of
#'   `known_platforms` in the message.
#'
#' @keywords internal
#' @noRd
validate_platform_arg <- function(platform, class, call = rlang::caller_env()) {
  if (
    is.null(platform) ||
      (isTRUE(rlang::is_string(platform)) &&
        isTRUE(platform %in% known_platforms))
  ) {
    return(invisible(platform))
  }
  is_text <- isTRUE(rlang::is_string(platform)) && isTRUE(nzchar(platform))
  message <- if (isTRUE(is_text)) {
    c(
      `x` = "{.arg platform} must be {.code NULL} or a known conda platform name, not {.val {platform}}."
    )
  } else {
    c(
      `x` = "{.arg platform} must be {.code NULL} or a single, non-empty character string, not {.obj_type_friendly {platform}}."
    )
  }
  suggestion <- if (isTRUE(is_text)) {
    alias <- platform_alias(platform)
    if (isTRUE(length(alias) > 0L)) {
      alias
    } else {
      closest_names(platform, known_platforms)
    }
  } else {
    character(0L)
  }
  if (isTRUE(length(suggestion) > 0L)) {
    message <- c(message, `i` = "Did you mean {.or {.val {suggestion}}}?")
  }
  examples <- c("linux-64", "linux-aarch64", "osx-64", "osx-arm64", "win-64")
  message <- c(
    message,
    `i` = "Known platforms are lower case, such as {.or {.val {examples}}}."
  )
  condathis_abort(
    message = message,
    class = unique(c(class, "condathis_invalid_arg")),
    call = call
  )
}

#' Validate the `env_file` argument of `create_env()`
#'
#' The existence check runs here, not only in the backend: the
#' already-satisfied shortcut does not call the backend, and must not let a
#' mistyped `env_file` pass.
#'
#' @param env_file The value of `env_file`.
#' @param call Environment of the function the error is reported for.
#'
#' @returns `env_file`, invisibly, when it is `NULL` or the path of an
#'   existing file. Aborts otherwise.
#'
#' @keywords internal
#' @noRd
validate_env_file_arg <- function(env_file, call = rlang::caller_env()) {
  if (is.null(env_file)) {
    return(invisible(env_file))
  }
  if (isFALSE(rlang::is_string(env_file)) || isFALSE(nzchar(env_file))) {
    condathis_abort(
      message = c(
        `x` = "{.arg env_file} must be {.code NULL} or a single, non-empty character string, not {.obj_type_friendly {env_file}}."
      ),
      class = arg_error_class("create_env", "env_file"),
      call = call
    )
  }
  if (isFALSE(fs::file_exists(env_file))) {
    condathis_abort(
      message = c(`x` = "{.arg env_file} {.path {env_file}} does not exist."),
      class = c(
        "condathis_create_env_missing_env_file",
        "condathis_create_missing_env_file",
        "condathis_invalid_env_file",
        "condathis_invalid_arg"
      ),
      call = call
    )
  }
  return(invisible(env_file))
}

#' Whether an environment exists, for a function that changes it
#'
#' Rule R5: a backend that cannot tell whether the environment exists
#' aborts. Read as "absent", the environment would be created again, which
#' replaces an existing one.
#'
#' @param backend An already-resolved backend object.
#' @param backend_name Character string, the registered backend name.
#' @param env_name Character string with the environment name.
#' @param call Environment of the function the error is reported for.
#'
#' @returns `TRUE` or `FALSE`. Aborts with
#'   `c("condathis_backend_probe_failed", "condathis_backend_error", <the
#'   condathis_* classes of the probe's error>, "condathis_error")` when the
#'   probe fails.
#'
#' @keywords internal
#' @noRd
env_exists_for_change <- function(
  backend,
  backend_name,
  env_name,
  call = rlang::caller_env()
) {
  probe <- backend_probe_env(backend, env_name = env_name, verbose = "silent")
  if (isTRUE(is.na(probe))) {
    abort_env_probe_failed(
      attr(probe, "condition"),
      backend_name = backend_name,
      env_name = env_name,
      call = call
    )
  }
  return(isTRUE(probe))
}

#' The installed packages of an existing environment
#'
#' Calls `backend_list_packages()` with its return value checked, and
#' re-raises a backend error with the classes of rule R1.
#'
#' @param backend An already-resolved backend object.
#' @param backend_name Character string, the registered backend name.
#' @param env_name Character string with the environment name.
#' @param fn Character string, the exported function name, for the classes.
#' @param call Environment of the function the error is reported for.
#'
#' @returns A data frame with at least the columns `name`, `version`,
#'   `build_number`, `build_string`, `channel` and `platform`.
#'
#' @keywords internal
#' @noRd
list_env_packages_checked <- function(
  backend,
  backend_name,
  env_name,
  fn,
  call = rlang::caller_env()
) {
  return(with_backend_errors(
    backend_list_packages_checked(
      backend,
      env_name = env_name,
      verbose = "silent"
    ),
    fn = fn,
    backend_name = backend_name,
    action = paste0("list the packages of environment '", env_name, "'"),
    call = call
  ))
}

#' Compare an existing environment with a request
#'
#' The one satisfaction check. `create_env(overwrite = FALSE)` and
#' `validate_env()` both call it, each with its own `channels`:
#' `create_env()` passes its `channels` and `additional_channels`, never
#' `NULL`, and `validate_env()` passes its `channels`, `NULL` by default.
#' So the two give the same answer when `validate_env()` gets
#' `c(channels, additional_channels)` of the `create_env()` call.
#'
#' @param installed_pkgs_df Data frame from `list_env_packages_checked()`.
#'   It may be `NULL` only when `packages` is empty and `platform` is
#'   `NULL`: then there is nothing to compare.
#' @param packages Character vector of requested package specs, possibly
#'   empty.
#' @param channels Character vector of requested channels, or `NULL`. A spec
#'   without a channel is satisfied only by a package from one of them;
#'   with `NULL`, by a package from any channel.
#' @param platform `NULL`, or the requested platform. The packages of the
#'   environment, without `noarch` ones, must all be built for it.
#'
#' @returns A list:
#'   * `satisfied`: `TRUE` or `FALSE`.
#'   * `reason`: `NA` when satisfied, `"platform_mismatch"` when the
#'     environment was built for another platform, `"unsatisfied"` when a
#'     spec is not satisfied. A platform mismatch comes first.
#'   * `unsatisfied`: character vector of the specs that are not
#'     satisfied, possibly empty.
#'   * `uncompared`: the specs of `unsatisfied` with a bracket constraint
#'     that is not compared, possibly empty. The error messages name them,
#'     because the environment may well have those packages.
#'   * `uncompared_versions`: the specs of `unsatisfied` with a version that
#'     is not compared (see `specs_with_uncompared_versions()`), possibly
#'     empty.
#'   * `uncompared_builds`: the specs of `unsatisfied` with a build string
#'     that is not compared (see `specs_with_uncompared_builds()`), possibly
#'     empty.
#'   * `env_platforms`: character vector of the platforms of the
#'     environment, without `noarch`; empty when `platform` is `NULL`.
#'
#' @keywords internal
#' @noRd
check_env_request <- function(
  installed_pkgs_df,
  packages,
  channels = NULL,
  platform = NULL
) {
  env_platforms <- character(0L)
  platform_mismatch <- FALSE
  if (isFALSE(is.null(platform))) {
    env_platforms <- env_package_platforms(installed_pkgs_df)
    platform_mismatch <- isTRUE(length(env_platforms) > 0L) &&
      isFALSE(all(env_platforms == platform))
  }
  unsatisfied <- character(0L)
  if (isTRUE(length(packages) > 0L)) {
    satisfied <- packages_satisfied_by(
      packages = packages,
      installed_pkgs_df = installed_pkgs_df,
      channels = channels
    )
    unsatisfied <- packages[!satisfied]
  }
  reason <- NA_character_
  if (isTRUE(platform_mismatch)) {
    reason <- "platform_mismatch"
  } else if (isTRUE(length(unsatisfied) > 0L)) {
    reason <- "unsatisfied"
  }
  return(list(
    satisfied = is.na(reason),
    reason = reason,
    unsatisfied = unsatisfied,
    uncompared = specs_with_uncompared_brackets(unsatisfied),
    uncompared_versions = specs_with_uncompared_versions(unsatisfied),
    uncompared_builds = specs_with_uncompared_builds(unsatisfied),
    env_platforms = env_platforms
  ))
}

#' Message bullets for the specs that `check_env_request()` rejected
#'
#' @param check The list from `check_env_request()`.
#'
#' @returns A named character vector of `cli` bullets: one that lists the
#'   unsatisfied specs, and one more for each kind of constraint that is
#'   not compared (bracket keys, versions, build strings). Empty when every
#'   spec is satisfied. The bullets refer to the variables `unsatisfied`,
#'   `uncompared`, `uncompared_versions` and `uncompared_builds`, so the
#'   caller must define them before it formats the message.
#'
#' @keywords internal
#' @noRd
unsatisfied_spec_bullets <- function(check) {
  bullets <- character(0L)
  if (isTRUE(length(check$unsatisfied) > 0L)) {
    bullets <- c(bullets, `x` = "Not satisfied: {.val {unsatisfied}}.")
  }
  if (isTRUE(length(check$uncompared) > 0L)) {
    bullets <- c(
      bullets,
      `i` = "Only the {.code version}, {.code build}, {.code build_number} (without {.code ==}) and {.code channel} bracket constraints are compared, so {.val {uncompared}} never count{?s/} as satisfied."
    )
  }
  if (isTRUE(length(check$uncompared_versions) > 0L)) {
    bullets <- c(
      bullets,
      # Examples, not bare operators: cli fails to parse `{.code <}`.
      `i` = "Versions such as {.code <2.*}, {.code >=1.2*}, {.code =1.2*}, {.code ~=1}, {.code 1.*.3} and {.code >=*} are not compared (micromamba and conda read them differently, or reject them), so {.val {uncompared_versions}} never count{?s/} as satisfied."
    )
  }
  if (isTRUE(length(check$uncompared_builds) > 0L)) {
    bullets <- c(
      bullets,
      `i` = "Build strings with characters other than letters, digits, {.code _}, {.code .} and {.code *}, such as {.code ^py3.*$} or {.code h?x_0}, are not compared (micromamba, rattler and conda read them differently), so {.val {uncompared_builds}} never count{?s/} as satisfied."
    )
  }
  return(bullets)
}

#' Hint bullets for an environment that does not have the requested packages
#'
#' @keywords internal
#' @noRd
env_request_hint <- c(
  `i` = "Use {.fn install_packages} to add packages, or {.code overwrite = TRUE} to create it again."
)

#' Keep an existing environment, or abort (decision D4)
#'
#' Called by `create_env()` when `env_name` exists and `overwrite = FALSE`.
#' The platform check comes first: a request for another platform aborts
#' with its own class, also for `env_file`.
#'
#' @param backend An already-resolved backend object.
#' @param backend_name Character string, the registered backend name.
#' @param env_name Character string with the environment name.
#' @param packages Character vector of requested specs, possibly empty.
#' @param channels Character vector, `channels` and `additional_channels`.
#' @param platform `NULL` or the requested platform.
#' @param env_file `NULL` or the path of an environment file.
#' @param verbose_list Parsed verbose list.
#' @param call Environment of the function the error is reported for.
#'
#' @returns A `condathis_result` with status `0L` and `cmd` `NA` when the
#'   environment has the requested packages. Aborts otherwise.
#'
#' @keywords internal
#' @noRd
keep_existing_env <- function(
  backend,
  backend_name,
  env_name,
  packages,
  channels,
  platform,
  env_file,
  verbose_list,
  call = rlang::caller_env()
) {
  # Each listing starts a process with micromamba, so list only when there
  # is something to compare.
  installed_pkgs_df <- NULL
  if (isFALSE(is.null(platform)) || isTRUE(length(packages) > 0L)) {
    installed_pkgs_df <- list_env_packages_checked(
      backend = backend,
      backend_name = backend_name,
      env_name = env_name,
      fn = "create_env",
      call = call
    )
  }
  check <- check_env_request(
    installed_pkgs_df = installed_pkgs_df,
    packages = packages,
    channels = channels,
    platform = platform
  )
  env_platforms <- check$env_platforms
  if (identical(check$reason, "platform_mismatch")) {
    condathis_abort(
      message = c(
        `x` = "Environment {.field {env_name}} exists and was built for platform {.val {env_platforms}}, not {.val {platform}}.",
        `i` = "Pass {.code overwrite = TRUE} to create it again for {.val {platform}}, or use another {.arg env_name}."
      ),
      class = c(
        "condathis_create_env_platform_mismatch",
        "condathis_create_platform_mismatch"
      ),
      call = call
    )
  }
  if (isFALSE(is.null(env_file))) {
    # An existing environment cannot be compared with the contents of a
    # file, so a file request never counts as satisfied.
    condathis_abort(
      message = c(
        `x` = "Environment {.field {env_name}} already exists.",
        `i` = "An existing environment is not compared with {.arg env_file}.",
        env_request_hint
      ),
      class = "condathis_create_env_exists",
      call = call
    )
  }
  unsatisfied <- check$unsatisfied
  uncompared <- check$uncompared
  uncompared_versions <- check$uncompared_versions
  uncompared_builds <- check$uncompared_builds
  if (isFALSE(check$satisfied)) {
    condathis_abort(
      message = c(
        `x` = "Environment {.field {env_name}} exists and does not have the requested packages.",
        unsatisfied_spec_bullets(check),
        env_request_hint
      ),
      class = "condathis_create_env_exists",
      call = call
    )
  }

  if (isTRUE(verbose_list$strategy %in% c("full", "output"))) {
    condathis_inform(
      message = c(
        `i` = "Environment {.field {env_name}} already has the requested packages."
      )
    )
  }
  # Nothing ran, so the result has no command line and no output.
  return(new_backend_result(
    NULL,
    fn = "create_env",
    backend_name = backend_name,
    env_name = env_name,
    call = call
  ))
}

#' Check every requested spec against an already-read package listing
#'
#' Same result as `satisfies_dependencies()`, which lists the packages
#' itself. `create_env()` already has the listing and must not start a
#' second `micromamba list --json`.
#'
#' @param packages Character vector of package MatchSpec strings.
#' @param installed_pkgs_df Data frame from `backend_list_packages()`.
#' @param channels Character vector of requested channels, or `NULL` to
#'   skip the channel check for specs without a channel. `create_env()`
#'   always passes its channels; `validate_env()` passes `NULL` unless it
#'   is given `channels`.
#'
#' @returns A logical vector with one value per spec.
#'
#' @keywords internal
#' @noRd
packages_satisfied_by <- function(packages, installed_pkgs_df, channels) {
  requested_channels <- if (isFALSE(rlang::is_null(channels))) {
    requested_channel_names(channels)
  }
  return(vapply(
    as.character(packages),
    function(spec_str) {
      return(spec_satisfied_by(
        spec_str = spec_str,
        installed_pkgs_df = installed_pkgs_df,
        requested_channels = requested_channels
      ))
    },
    logical(1L),
    USE.NAMES = FALSE
  ))
}

#' Platforms of the installed packages, without `noarch`
#'
#' The PyPI packages of a listing (channel `pypi`) are left out: their
#' platform is pip's, such as `linux-x86_64`, not a Conda platform.
#'
#' @param pkgs_df Data frame from `backend_list_packages()`.
#'
#' @returns Character vector of unique platforms. Empty when no package has
#'   a platform other than `noarch`, or when `pkgs_df` has no `platform`
#'   column.
#'
#' @keywords internal
#' @noRd
env_package_platforms <- function(pkgs_df) {
  if (isFALSE(is.null(pkgs_df[["channel"]]))) {
    pkgs_df <- pkgs_df[!pkgs_df[["channel"]] %in% "pypi", , drop = FALSE]
  }
  platforms <- as.character(pkgs_df[["platform"]])
  platforms <- platforms[!is.na(platforms) & nzchar(platforms)]
  return(unique(setdiff(platforms, "noarch")))
}
