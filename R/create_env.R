#' Create a Conda environment
#'
#' Creates a Conda environment from package specs or from an environment
#' file given by [env_definition()]. With `overwrite = FALSE` (the default),
#' `create_env()` never replaces an existing environment. It keeps the
#' environment when it already has the requested packages. Otherwise, it
#' aborts (see *Existing environments*).
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
#'
#'   Or one environment file, given by [env_definition()], such as
#'   `env_definition("environment.yml")`, without package specs. Package
#'   specs and a definition together, or two definitions, abort with class
#'   `condathis_create_env_conflicting_args`. A file that does not exist
#'   aborts with class `condathis_create_env_missing_env_file`. With
#'   `method = "auto"`, a new environment uses the first available backend
#'   in `condathis.backend_priority` order that does not say it cannot read
#'   the file. A file that the backend cannot read (any of them, with
#'   `"auto"`) aborts with class
#'   `condathis_create_env_unsupported_definition` (also
#'   `condathis_backend_unsupported`). See [env_definition()] for the
#'   formats, and for the rules of lock files. No backend applies the
#'   `variables:` of a YAML file: the commands that run in the environment
#'   do not get them.
#'
#'   Any other value aborts with class
#'   `condathis_create_env_invalid_packages`. Such values are:
#'   * A named argument that `create_env()` does not have. Names are never
#'     abbreviated: `env =` and `pack =` abort too. The error names the
#'     closest argument.
#'   * A value that is not a character vector.
#'   * `NA` or `""`.
#'   * A file name that ends in `.yml`, `.yaml`, `.json` or `.lock`. Pass
#'     it with [env_definition()].
#'
#'   `packages = <specs>` still works, and `packages = NULL` creates an
#'   empty environment. It is deprecated. It warns once per session (class
#'   `condathis_deprecated_packages_arg`) when the call comes from the
#'   console, a script or the tests of the package that makes it. Calls
#'   made inside other packages do not warn.
#'
#'   `create_env()` aborts with class
#'   `condathis_create_env_positional_env_name` when `env_name` is not
#'   given, the specs are two or more unnamed arguments, and the last of
#'   them is one string that names an existing environment. Name the
#'   argument, as in `env_name = "my-env"`. Specs given with `packages =`
#'   or as one vector are never checked this way.
#' @inheritParams condathis-params
#' @param channels A non-empty character vector of channel names or URLs,
#'   in priority order. For a package from another channel, either name the
#'   channel in the spec (`"bioconda::samtools"`) or add it here, as in
#'   `channels = c("conda-forge", "bioconda")`. Invalid values, such as
#'   `NULL`, `NA` or `""`, abort with class
#'   `condathis_create_env_invalid_channels`.
#'   condathis 0.1.4 also used `"bioconda"` by default. When `channels` is
#'   not given and the backend finds no package for a spec, the error says
#'   that the default changed.
#' @param additional_channels `NULL` (the default) or a non-empty character
#'   vector of channel names or URLs, used after `channels`. Invalid values
#'   abort with these classes:
#'   * `condathis_create_env_invalid_channels`
#'   * `condathis_invalid_additional_channels`
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
#'   happens when the package specs or the environment file cannot be
#'   installed for the native platform, dependencies included, but can for
#'   the emulated one. This works with every backend that can tell whether
#'   a request solves for a platform, micromamba included. A lock file is
#'   never solved (see [env_definition()]). On Apple Silicon,
#'   condathis uses `"osx-64"` when Rosetta 2 is available. With a backend
#'   that solves for `"win-arm64"`, condathis uses `"win-64"` through x64
#'   emulation. The `win-arm64` micromamba, which a native ARM64 R on
#'   Windows installs, is such a backend. [install_packages()] later
#'   installs packages for the platform that the environment was created
#'   for, given or emulated.
#'   For an existing environment, see *Existing environments*.
#' @param env_file `NULL` (the default) or the path of an environment
#'   file. Deprecated: pass `env_definition(<path>)` in `...` instead.
#'   `env_file = path` still works the same way. It warns once per session
#'   (class `condathis_deprecated_env_file_arg`) when the call comes from
#'   the console, a script or the tests of the package that makes it.
#'   Calls made inside other packages do not warn. `env_file` and an
#'   [env_definition()] together abort with class
#'   `condathis_create_env_conflicting_args`. A file that does not exist
#'   aborts with class `condathis_create_env_missing_env_file`. With a lock
#'   file, `channels`, `additional_channels` and `channel_priority` are
#'   ignored, as in 0.1.4.
#' @param overwrite `TRUE` or `FALSE` (the default).
#'   With `FALSE`, `create_env()` never replaces an existing environment.
#'   `create_env()` keeps the environment and runs nothing when it has every
#'   requested package (see *Existing environments*) or when no package is
#'   requested. For a lock file whose packages the backend reports, such as
#'   an `@EXPLICIT`, conda-lock or mambajs file with micromamba, it keeps the
#'   environment when it has exactly those packages (see *Existing
#'   environments*). It returns status 0.
#'   Otherwise, and always for an environment file that is solved, such as
#'   `environment.yml`, `create_env()` aborts with class
#'   `condathis_create_env_exists`. Use [install_packages()] to add
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
#'   `cmd` is the command line that the backend ran, or `NA` when the
#'   backend reports none. `cmd`, `stdout` and `stderr` are `NA` when
#'   nothing ran (an existing environment that already has the requested
#'   packages). `stdout`, `stderr` and `pid` are `NA` when the backend
#'   reports none, and `pid` always is with micromamba.
#'   A backend failure aborts with class `condathis_create_env_failed` (also
#'   `condathis_backend_error`), with the backend's error as the parent.
#'   micromamba runs the link scripts of packages (`pre-link` and
#'   `post-link`). A backend that does not, such as `"rattler"` of the
#'   `rattlerthis` package, makes `create_env()` warn. The warning names
#'   the packages, which may not work. Its classes are
#'   `condathis_link_scripts_skipped` and\cr
#'   `condathis_create_env_link_scripts_skipped`.
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
#' A package from another channel does not satisfy a spec without a
#' channel. An environment built with condathis 0.1.4, which also used
#' `"bioconda"` by default, can have such packages. The error then names
#' the channel of the package. Add that channel to `channels`, or name it
#' in the spec, as in `"bioconda::samtools"`.
#'
#' Specs for virtual packages, whose names start with `__`, such as
#' `"__cuda=12"`, `"__unix"` or `"__glibc>=2.17"`, are not compared. They
#' describe the host, not the environment, and are never installed. The
#' solver checked them when it created the environment. `create_env()` and
#' [install_packages()] still pass them to the backend.
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
#' A spec that condathis cannot read aborts with one of these classes, and
#' also with class `condathis_invalid_arg`:
#' * `condathis_parse_match_spec_invalid_name`: a spec such as `"::"`.
#' * `condathis_parse_match_spec_invalid_url`: the URL of a package file
#'   whose name is not `<name>-<version>-<build>`.
#'
#' For a new environment, only the backend reads the specs. A spec it
#' cannot read aborts with class `condathis_create_env_failed`.
#'
#' When `platform` is given, the platform of the installed packages must be
#' `platform` (`noarch` packages match any platform). A different platform
#' aborts with class `condathis_create_env_platform_mismatch`, and
#' `create_env()` keeps the environment. With `platform = NULL`, the
#' platform is not compared.
#'
#' A lock file is compared by its packages, not by specs. The environment
#' must have exactly the packages that the lock lists for its platform (see
#' [env_definition()]): the same names, versions and build strings, none
#' missing and none more. Packages that pip installed are left out. A
#' difference aborts with class `condathis_create_env_exists`, and the
#' message names a few of the packages that differ. An environment file
#' that is solved, such as `environment.yml`, or a lock whose packages the
#' backend does not report, is never compared: an existing environment
#' aborts with class `condathis_create_env_exists`.
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
  # The caller, for the soft deprecations of `packages =`, `env_file =` and
  # `method = "native"` (see `is_direct_use()`).
  user_env <- rlang::caller_env()
  # For the hint about the 0.1.4 default channels (see
  # `with_default_channels_hint()`).
  default_channels <- missing(channels)
  # A lock names the channel of each package: these abort with one.
  channel_args_given <- c(
    channels = !missing(channels),
    additional_channels = !missing(additional_channels),
    channel_priority = !missing(channel_priority)
  )
  # Rule R2: every argument is checked before the first backend call, so an
  # invalid value never installs micromamba or starts a process.
  dots <- rlang::list2(...)
  # `env_definition()` objects in `...` are not package specs.
  split_dots <- split_env_definitions(dots)
  dots <- split_dots$dots
  packages <- collect_package_specs(
    dots,
    fn = "create_env",
    user_env = user_env
  )
  validate_env_name(
    env_name,
    class = c(
      "condathis_create_env_invalid_env_name",
      "condathis_create_invalid_env_name"
    )
  )
  method <- validate_method_arg(method)
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
  # The deprecated `env_file =` keeps the behaviour of 0.1.4: the channels
  # given with a lock file are ignored, as the backend ignores them.
  if (isFALSE(is.null(env_file))) {
    channel_args_given[] <- FALSE
  }
  # From here on, `env_file` is the path of the definition, for the
  # internal functions and the backend.
  definition <- resolve_create_definition(
    definitions = split_dots$definitions,
    env_file = env_file,
    packages = packages,
    user_env = user_env
  )
  env_file <- if (isFALSE(is.null(definition))) definition$path
  if (missing(env_name) && isTRUE(positional_env_name_possible(dots))) {
    abort_on_positional_env_name(packages, fn = "create_env")
  }
  method <- resolve_method_alias(method, user_env = user_env)

  # The backend says what it makes of a definition before anything is
  # locked, moved or solved (rule R2): one it cannot read, or a lock for
  # another platform, aborts here. With `method = "auto"`, a new
  # environment goes to the first backend that does not refuse the
  # definition (see `create_definition_routing()`).
  routing <- create_definition_routing(definition, platform = platform)
  described <- NULL
  if (isFALSE(is.null(definition))) {
    pre_resolved <- resolve_backend(
      env_name = env_name,
      method = method,
      mutating = TRUE,
      accept = routing$accept,
      on_refused = routing$on_refused
    )
    described <- describe_create_definition(
      pre_resolved,
      description = routing$describe(pre_resolved$backend, pre_resolved$name),
      definition = definition,
      platform = platform,
      channel_args_given = channel_args_given,
      verbose = verbose_list$strategy
    )
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
    mutating = TRUE,
    accept = routing$accept,
    on_refused = routing$on_refused
  )
  # Another session created the environment with another backend in
  # between: ask that backend.
  if (
    isFALSE(is.null(described)) &&
      isFALSE(identical(described$backend_name, resolved$name))
  ) {
    described <- describe_create_definition(
      resolved,
      description = routing$describe(resolved$backend, resolved$name),
      definition = definition,
      platform = platform,
      channel_args_given = channel_args_given,
      verbose = verbose_list$strategy
    )
  }
  is_lock <- identical(described$description$kind, "lock")
  # The `definition` argument goes only to a backend function that takes
  # it (see `backend_call()`).
  create_optional <- if (isFALSE(is.null(definition))) {
    list(definition = definition)
  } else {
    list()
  }

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
      definition = definition,
      described = described,
      verbose_list = verbose_list
    )
    return(invisible(result))
  }

  packages <- if (isTRUE(length(packages) > 0L)) packages
  # The front end chooses the platform for every backend: a given one, or
  # an emulated one when the request does not solve for the native
  # platform (see define_platform()). The probes are backend calls of this
  # create, so their errors have its classes.
  # A solver error for a spec that is on none of the channels gets a hint
  # about the default channels, which changed in 0.2.0 (see
  # `with_default_channels_hint()`). Not for `env_file`: it names its own
  # channels.
  hint_packages <- if (is.null(env_file)) packages
  # A lock was given its platform by describe_create_definition(): a dry
  # run says nothing about it.
  platform <- if (isTRUE(is_lock)) {
    described$lock$platform
  } else {
    with_default_channels_hint(
      with_backend_errors(
        resolve_create_platform(
          resolved$backend,
          packages = packages,
          platform = platform,
          channels = channels,
          channel_priority = channel_priority,
          additional_channels = additional_channels,
          verbose = verbose_list$strategy,
          env_file = env_file,
          definition = definition
        ),
        fn = "create_env",
        backend_name = resolved$name,
        action = paste0("create environment '", env_name, "'")
      ),
      fn = "create_env",
      packages = hint_packages,
      channels = c(channels, additional_channels),
      default_channels = default_channels
    )
  }
  # The backend gets a free environment directory: an existing environment
  # is moved aside first, and moved back when the create fails (see
  # with_env_dir_replacement()). The result is read inside, so a non-zero
  # status also restores the old environment, and a failed environment
  # gets no marker.
  env_lock_before_change(env_lock, cache_lock)
  created <- with_default_channels_hint(
    with_backend_errors(
      with_env_dir_replacement(
        resolved$backend,
        env_name = env_name,
        expr = {
          px_res <- backend_call(
            "backend_create_env",
            resolved$backend,
            packages = packages,
            env_file = env_file,
            env_name = env_name,
            channels = channels,
            channel_priority = channel_priority,
            additional_channels = additional_channels,
            platform = platform,
            overwrite = overwrite,
            verbose = verbose_list$strategy,
            .optional = create_optional
          )
          created_result <- list(
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
          # Inside, so a failed check restores the old environment.
          if (isTRUE(is_lock)) {
            check_lock_installed(
              resolved$backend,
              env_name = env_name,
              definition = definition,
              records = described$description$records,
              target = described$lock$target
            )
          }
          created_result
        }
      ),
      fn = "create_env",
      backend_name = resolved$name,
      action = paste0("create environment '", env_name, "'")
    ),
    fn = "create_env",
    packages = hint_packages,
    channels = c(channels, additional_channels),
    default_channels = default_channels
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

#' Validate the deprecated `env_file` argument of `create_env()`
#'
#' The existence check runs here, not only in the backend: the
#' already-satisfied shortcut does not call the backend, and must not let a
#' mistyped `env_file` pass. It runs before the deprecation warning (see
#' `resolve_create_definition()`), so an invalid value aborts without one.
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

#' The environment definition of a `create_env()` call
#'
#' Checks the [env_definition()] objects of `...` and the deprecated
#' `env_file`, which becomes `env_definition(env_file)`, so both take the
#' same path from here on.
#'
#' @param definitions List of the `condathis_env_definition` objects of
#'   `...` (see `split_env_definitions()`).
#' @param env_file `NULL` or the checked value of `env_file`.
#' @param packages Character vector, the package specs of the call.
#' @param user_env The caller of `create_env()`, for the soft deprecation
#'   of `env_file` (see `is_direct_use()`).
#' @param call Environment of the function the error is reported for.
#'
#' @returns `NULL` when the call has no definition. Otherwise a valid
#'   `condathis_env_definition` object whose file exists. Aborts with class
#'   `condathis_create_env_conflicting_args` for two definitions, for a
#'   definition and `env_file`, and for a definition and package specs.
#'
#' @keywords internal
#' @noRd
resolve_create_definition <- function(
  definitions,
  env_file,
  packages,
  user_env = NULL,
  call = rlang::caller_env()
) {
  conflicting_class <- c(
    "condathis_create_env_conflicting_args",
    "condathis_invalid_arg"
  )
  if (isTRUE(length(definitions) > 1L)) {
    # micromamba used the last of several lock files and the first of
    # several explicit files.
    condathis_abort(
      message = c(
        `x` = "{.fn create_env} takes at most one {.fn env_definition}, not {length(definitions)}."
      ),
      class = conflicting_class,
      call = call
    )
  }
  if (isTRUE(length(definitions) > 0L) && isFALSE(is.null(env_file))) {
    condathis_abort(
      message = c(
        `x` = "Use either {.fn env_definition} in {.arg ...} or {.arg env_file}, not both."
      ),
      class = conflicting_class,
      call = call
    )
  }
  if (
    isTRUE(length(packages) > 0L) &&
      (isTRUE(length(definitions) > 0L) || isFALSE(is.null(env_file)))
  ) {
    # micromamba merges the specs into an environment YAML file or a list
    # of specs, and drops them for an `@EXPLICIT` or lock file.
    message <- if (is.null(env_file)) {
      spec <- packages[[length(packages)]]
      c(
        `x` = "Use either package specs in {.arg ...} or {.fn env_definition}, not both.",
        `i` = "If {.val {spec}} is an environment name, name its argument: {.code env_name = \"{spec}\"}."
      )
    } else {
      c(`x` = "Use either package specs in {.arg ...} or {.arg env_file}, not both.")
    }
    condathis_abort(message = message, class = conflicting_class, call = call)
  }
  if (isFALSE(is.null(env_file))) {
    condathis_deprecate_soft(
      id = "deprecated_env_file_arg",
      message = c(
        `!` = "The {.arg env_file} argument of {.fn create_env} is deprecated.",
        `i` = "Pass the file with {.fn env_definition} instead, as in {.code create_env(env_definition(\"environment.yml\"), env_name = \"my-env\")}."
      ),
      class = "condathis_deprecated_env_file_arg",
      user_env = user_env
    )
    definition <- new_env_definition(normalize_definition_path(env_file))
    return(check_env_definition_exists(definition, arg = "env_file", call = call))
  }
  if (identical(length(definitions), 0L)) {
    return(NULL)
  }
  definition <- validate_env_definition_object(definitions[[1L]], call = call)
  return(check_env_definition_exists(definition, call = call))
}

#' The backend routing of `create_env()` for an environment definition
#'
#' `describe()` asks a backend what it makes of the definition, once per
#' backend in the call (see `describe_definition()`). `accept()` and
#' `on_refused()` are for `resolve_backend()`: with `method = "auto"`, a new
#' environment skips an available backend that says it cannot read the
#' definition (`supported = FALSE`), as the routing of an environment given
#' by [env_path()] skips a backend that cannot run it. `NA` counts as
#' "can read". When every available backend refuses it, `create_env()`
#' aborts with `condathis_create_env_unsupported_definition`, naming the
#' backends it tried and their reasons.
#'
#' @param definition `NULL` or a valid `condathis_env_definition` object.
#' @param platform `NULL` or the requested platform.
#' @param call Environment of the function the error is reported for.
#'
#' @returns A list with the functions `describe`, `accept` and
#'   `on_refused`. The last two are `NULL` without a definition.
#'
#' @keywords internal
#' @noRd
create_definition_routing <- function(
  definition,
  platform = NULL,
  call = rlang::caller_env()
) {
  if (is.null(definition)) {
    return(list(describe = NULL, accept = NULL, on_refused = NULL))
  }
  cache <- new.env(parent = emptyenv())
  describe <- function(backend, backend_name) {
    if (is.null(cache[[backend_name]])) {
      cache[[backend_name]] <- describe_definition(
        backend,
        definition = definition,
        platform = platform,
        generic = "backend_create_env",
        call = call
      )
    }
    return(cache[[backend_name]])
  }
  accept <- function(backend, backend_name) {
    description <- describe(backend, backend_name)
    if (isFALSE(description$supported)) {
      return(description$reason)
    }
    return(TRUE)
  }
  on_refused <- function(refused) {
    abort_no_backend_for_definition(
      definition,
      refused = refused,
      fn = "create_env",
      call = call
    )
  }
  return(list(describe = describe, accept = accept, on_refused = on_refused))
}

#' Apply the rules of `create_env()` to what a backend makes of a definition
#'
#' Called by `create_env()` before it locks, moves or solves anything. A
#' description with `supported = FALSE` aborts: the backend was given by
#' `method`, or it already has the environment (see
#' `create_definition_routing()`). For a lock, the platform is chosen here
#' (see `choose_lock_platform()`), and `channels`, `additional_channels`
#' and `channel_priority` must not have been given.
#'
#' @param resolved The list from `resolve_backend()`.
#' @param description The description of the definition by that backend
#'   (see `describe_definition()`).
#' @param definition A valid `condathis_env_definition` object.
#' @param platform `NULL` or the requested platform.
#' @param channel_args_given Named logical vector: whether `channels`,
#'   `additional_channels` and `channel_priority` were given.
#' @param verbose Character string, the verbose strategy, for the emulation
#'   message.
#' @param call Environment of the function the error is reported for.
#'
#' @returns A list with `backend_name`, `description` (see
#'   `validate_definition_description()`) and `lock`: `NULL` for a
#'   request, else the list from `choose_lock_platform()`.
#'
#' @keywords internal
#' @noRd
describe_create_definition <- function(
  resolved,
  description,
  definition,
  platform,
  channel_args_given,
  verbose = "silent",
  call = rlang::caller_env()
) {
  backend <- resolved$backend
  if (isFALSE(description$supported)) {
    abort_unsupported_definition(
      backend_name = resolved$name,
      definition = definition,
      reason = description$reason,
      fn = "create_env",
      call = call
    )
  }
  lock <- NULL
  if (identical(description$kind, "lock")) {
    given <- names(channel_args_given)[channel_args_given]
    if (isTRUE(length(given) > 0L)) {
      condathis_abort(
        message = c(
          `x` = "{.arg {given}} cannot be given with a lock file.",
          `i` = "A lock file names the channel of each package, and is installed without a solve. Leave {.arg {given}} out."
        ),
        class = c(
          "condathis_create_env_conflicting_args",
          "condathis_invalid_arg"
        ),
        call = call
      )
    }
    lock <- choose_lock_platform(
      backend,
      definition = definition,
      platforms = description$platforms,
      platform = platform,
      verbose = verbose,
      call = call
    )
  }
  return(list(
    backend_name = resolved$name,
    description = description,
    lock = lock
  ))
}

#' Choose the platform of an environment created from a lock
#'
#' A lock has packages for the platforms it lists, and no solve can tell
#' whether it installs elsewhere: micromamba then creates an empty
#' environment from a conda-lock file, with exit status 0. So the platform is, in this order:
#' `platform` when it is given, the native platform of the backend, or the
#' emulated platform of `define_platform()`, each only when the lock lists
#' it. `noarch` is not a platform here. A lock that lists no platform, or a
#' backend that cannot tell its native platform, leaves the choice to the
#' backend, and `check_lock_installed()` catches an empty environment.
#'
#' @param backend An already-resolved backend object.
#' @param definition A `condathis_env_definition` object, for the message.
#' @param platforms `NULL` or the platforms of the lock.
#' @param platform `NULL` or the requested platform.
#' @param verbose Character string, the verbose strategy.
#' @param call Environment of the function the error is reported for.
#'
#' @returns A list with `platform` (the platform for the backend, `NULL`
#'   for its native one) and `target` (the platform whose records the
#'   environment gets, or `NA` when unknown). Aborts with
#'   `c("condathis_create_env_platform_not_locked",
#'   "condathis_create_env_platform_mismatch",
#'   "condathis_create_platform_mismatch", "condathis_error")`.
#'
#' @keywords internal
#' @noRd
choose_lock_platform <- function(
  backend,
  definition,
  platforms,
  platform = NULL,
  verbose = "silent",
  call = rlang::caller_env()
) {
  listed <- setdiff(as.character(platforms), "noarch")
  if (identical(length(listed), 0L)) {
    return(list(platform = platform, target = platform %||% NA_character_))
  }
  path <- definition$path
  not_locked <- function(target, bullets) {
    condathis_abort(
      message = c(
        `x` = "Lock file {.path {path}} has no packages for platform {.val {target}}.",
        `i` = "It has packages for {.or {.val {listed}}}.",
        bullets
      ),
      class = c(
        "condathis_create_env_platform_not_locked",
        "condathis_create_env_platform_mismatch",
        "condathis_create_platform_mismatch"
      ),
      call = call
    )
  }
  if (isFALSE(is.null(platform))) {
    if (isTRUE(platform %in% listed)) {
      return(list(platform = platform, target = platform))
    }
    not_locked(
      platform,
      c(`i` = "Pass one of them as {.arg platform}, or use a lock file for {.val {platform}}.")
    )
  }
  native <- backend_native_platform_checked(backend, call = call)
  if (isTRUE(is.na(native))) {
    return(list(platform = NULL, target = NA_character_))
  }
  if (isTRUE(native %in% listed)) {
    return(list(platform = NULL, target = native))
  }
  emulated <- NULL
  if (
    identical(get_sys_arch(), "Darwin-arm64") &&
      isTRUE("osx-64" %in% listed) &&
      isTRUE(is_rosetta_running())
  ) {
    emulated <- "osx-64"
  } else if (
    isTRUE(is_windows()) &&
      identical(native, "win-arm64") &&
      isTRUE("win-64" %in% listed)
  ) {
    emulated <- "win-64"
  }
  if (isFALSE(is.null(emulated))) {
    if (isFALSE(identical(verbose, "silent"))) {
      condathis_inform(c(
        `i` = if (identical(emulated, "osx-64")) {
          "Using {.field Rosetta 2} emulation."
        } else {
          "Using {.field x64} emulation for {.val win-64} packages."
        }
      ))
    }
    return(list(platform = emulated, target = emulated))
  }
  not_locked(
    native,
    c(`i` = "Use a lock file for {.val {native}}, or pass a platform it lists as {.arg platform} when this system can run it.")
  )
}

#' Abort when a lock gave an empty environment
#'
#' micromamba creates an empty environment, with exit status 0, from a
#' lock whose packages it does not select: a conda-lock file whose name
#' does not end in `-lock.yml`, or a conda-lock file without packages for
#' the platform. Called
#' inside the replacement of the environment directory, so the failure
#' restores an environment that `overwrite = TRUE` replaced.
#'
#' @param backend An already-resolved backend object.
#' @param env_name Character string.
#' @param definition A `condathis_env_definition` object, for the message.
#' @param records `NULL` or the data frame of the description.
#' @param target `NA` or the platform whose records count.
#'
#' @returns `NULL`, invisibly, when the lock lists no package for `target`
#'   or the environment has packages. Aborts otherwise.
#'
#' @keywords internal
#' @noRd
check_lock_installed <- function(
  backend,
  env_name,
  definition,
  records,
  target = NA_character_
) {
  if (is.null(records) || identical(NROW(records), 0L)) {
    return(invisible(NULL))
  }
  record_platforms <- as.character(records[["platform"]])
  expected <- is.na(record_platforms) |
    isTRUE(is.na(target)) |
    record_platforms %in% c(target, "noarch")
  n_expected <- sum(expected)
  if (identical(n_expected, 0L)) {
    return(invisible(NULL))
  }
  installed <- backend_list_packages_checked(
    backend,
    env_name = env_name,
    verbose = "silent"
  )
  if (isTRUE(NROW(installed) > 0L)) {
    return(invisible(NULL))
  }
  path <- definition$path
  condathis_abort(
    message = c(
      `x` = "Lock file {.path {path}} lists {n_expected} package{?s}, but the new environment {.field {env_name}} has none.",
      `i` = "The backend did not install the packages of the lock file."
    ),
    call = NULL
  )
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
#' Specs for virtual packages (names that start with `__`, such as
#' `"__cuda=12"` or `"__unix"`) are left out: they constrain the host, not
#' the environment, and the package listing never has them. The solver
#' checked them when it created the environment.
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
#'   * `other_channels`: the specs of `unsatisfied` that an installed
#'     package satisfies, but from a channel that is not in `channels` (see
#'     `specs_from_other_channels()`). A data frame with zero rows when
#'     there are none or `channels` is `NULL`. Packages from `pypi` are
#'     left out.
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
  packages <- as.character(packages)
  packages <- packages[!is_virtual_package_spec(packages)]
  unsatisfied <- character(0L)
  if (isTRUE(length(packages) > 0L)) {
    satisfied <- packages_satisfied_by(
      packages = packages,
      installed_pkgs_df = installed_pkgs_df,
      channels = channels
    )
    unsatisfied <- packages[!satisfied]
  }
  other_channels <- specs_from_other_channels(
    unsatisfied = unsatisfied,
    installed_pkgs_df = installed_pkgs_df,
    channels = channels
  )
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
    env_platforms = env_platforms,
    other_channels = other_channels
  ))
}

#' Which specs name a virtual package?
#'
#' A virtual package (`__cuda`, `__glibc`, `__unix`, `__osx`, `__win`,
#' ...) describes the host. The solver checks a spec for one against the
#' host, and never installs it, so the package listing of an environment
#' never has it.
#'
#' @param packages Character vector of package MatchSpec strings.
#'
#' @returns A logical vector with one value per spec: `TRUE` when the name
#'   of the spec starts with `__`. A spec that `parse_match_spec()` cannot
#'   read aborts with its classes, as the satisfaction check does.
#'
#' @keywords internal
#' @noRd
is_virtual_package_spec <- function(packages) {
  return(vapply(
    as.character(packages),
    function(spec_str) {
      name <- parse_match_spec(spec_str)[["name"]]
      return(isTRUE(rlang::is_string(name)) && isTRUE(startsWith(name, "__")))
    },
    logical(1L),
    USE.NAMES = FALSE
  ))
}

#' Unsatisfied specs that a package from another channel satisfies
#'
#' An environment that condathis 0.1.4 built with its default channels
#' `c("conda-forge", "bioconda")` has bioconda packages. Requested again
#' with the 0.2.0 default `"conda-forge"`, a spec such as `"samtools"` is
#' not satisfied, because the channel is part of the request. This finds
#' those specs, so the error can name the channel instead of only
#' suggesting `overwrite = TRUE`, which fails when the package is not on
#' the requested channels.
#'
#' @param unsatisfied Character vector of unsatisfied specs.
#' @param installed_pkgs_df Data frame from `list_env_packages_checked()`,
#'   or `NULL`.
#' @param channels Character vector of requested channels, or `NULL`.
#'
#' @returns A data frame with the character columns `spec`, `name` (the
#'   installed name), `channel` (the installed channel, as
#'   `normalize_channel_name()` gives it) and `spec_hint`
#'   (`"<channel>::<name>"`, or `NA` when the channel is a URL or a path).
#'   One row for each spec without a channel that an installed package
#'   satisfies when the channel is not compared. Zero rows when `channels`
#'   is `NULL`.
#'
#' @keywords internal
#' @noRd
specs_from_other_channels <- function(
  unsatisfied,
  installed_pkgs_df,
  channels
) {
  rows <- list()
  if (
    isFALSE(is.null(channels)) &&
      isFALSE(is.null(installed_pkgs_df)) &&
      isTRUE(length(unsatisfied) > 0L)
  ) {
    for (spec_str in as.character(unsatisfied)) {
      ms <- parse_match_spec(spec_str)
      location <- ms[["channel_location"]]
      has_channel <- isFALSE(is.null(location)) &&
        isFALSE(is.na(location)) &&
        isTRUE(nzchar(location)) &&
        isFALSE(identical(location, "None"))
      if (isTRUE(has_channel)) {
        next
      }
      if (
        isFALSE(spec_satisfied_by(
          spec_str = spec_str,
          installed_pkgs_df = installed_pkgs_df,
          requested_channels = NULL
        ))
      ) {
        next
      }
      # The row that `spec_satisfied_by()` compared: the first by name.
      installed <- installed_pkgs_df[
        tolower(installed_pkgs_df[["name"]]) %in% tolower(ms[["name"]]),
        ,
        drop = FALSE
      ][1L, , drop = FALSE]
      name <- as.character(installed[["name"]])
      channel <- normalize_channel_name(
        as.character(installed[["channel"]] %||% "")
      )
      # A package that pip installed is listed with the channel `pypi`,
      # which is not a Conda channel: neither `channels` nor a spec can
      # name it.
      if (isFALSE(isTRUE(nzchar(channel))) || identical(channel, "pypi")) {
        next
      }
      # A channel name, such as `bioconda` or `pkgs/main`, also works in a
      # spec. A URL (`host.org/path` once normalized) or a local path is
      # only suggested for `channels`.
      is_name <- grepl(
        "^[A-Za-z0-9_][A-Za-z0-9_-]*(/[A-Za-z0-9_.-]+)*$",
        channel
      )
      rows[[length(rows) + 1L]] <- data.frame(
        spec = spec_str,
        name = name,
        channel = channel,
        spec_hint = if (isTRUE(is_name)) {
          paste0(channel, "::", name)
        } else {
          NA_character_
        },
        stringsAsFactors = FALSE
      )
    }
  }
  if (identical(length(rows), 0L)) {
    return(data.frame(
      spec = character(0L),
      name = character(0L),
      channel = character(0L),
      spec_hint = character(0L),
      stringsAsFactors = FALSE
    ))
  }
  result <- do.call(rbind, rows)
  rownames(result) <- NULL
  return(result)
}

#' Message bullets for the specs that `check_env_request()` rejected
#'
#' @param check The list from `check_env_request()`.
#'
#' @returns A named character vector of `cli` bullets: one that lists the
#'   unsatisfied specs, and one more for each kind of constraint that is
#'   not compared (bracket keys, versions, build strings). Then, for the
#'   specs that a package from another channel satisfies, one bullet each
#'   that names that channel, and one hint. Empty when every spec is
#'   satisfied. The bullets refer to the variables `unsatisfied`,
#'   `uncompared`, `uncompared_versions`, `uncompared_builds` and
#'   `other_channels`, so the caller must define them before it formats the
#'   message.
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
  n_other <- NROW(check$other_channels)
  if (isTRUE(n_other > 0L)) {
    for (i in seq_len(n_other)) {
      bullets <- c(
        bullets,
        `x` = sprintf(
          "{.val {other_channels$name[[%d]]}} is installed from {.val {other_channels$channel[[%d]]}}, which is not in {.arg channels}.",
          i,
          i
        )
      )
    }
    hint <- if (isTRUE(all(is.na(check$other_channels$spec_hint)))) {
      "Add {.or {.val {unique(other_channels$channel)}}} to {.arg channels}."
    } else {
      "Add {.or {.val {unique(other_channels$channel)}}} to {.arg channels}, or name the channel in the spec, as in {.val {other_channels$spec_hint[!is.na(other_channels$spec_hint)]}}."
    }
    bullets <- c(bullets, `i` = hint)
  }
  return(bullets)
}

#' Are all unsatisfied specs explained by the channel of a package?
#'
#' Then `overwrite = TRUE` with the same channels does not help: the
#' package is not on them.
#'
#' @param check The list from `check_env_request()`.
#'
#' @returns `TRUE` or `FALSE`.
#'
#' @keywords internal
#' @noRd
unsatisfied_only_by_channel <- function(check) {
  return(
    isTRUE(length(check$unsatisfied) > 0L) &&
      isTRUE(all(check$unsatisfied %in% check$other_channels$spec))
  )
}

#' Evaluate a backend call, and add the default-channels hint to its error
#'
#' condathis 0.1.4 used `c("conda-forge", "bioconda")` by default, and
#' 0.2.0 uses only `"conda-forge"`. Calls that relied on the old default
#' for a bioconda package now fail in the solver with "does not exist".
#' When the caller did not pass `channels`, `"bioconda"` is not among the
#' channels, and the backend's error says that a requested spec without a
#' channel was not found, this adds a bullet that says so (see
#' `default_channels_hint()`). Any other error passes unchanged.
#'
#' @param expr The backend call, usually a `with_backend_errors()` call.
#' @param fn Character string, the exported function name. Only an error
#'   with class `condathis_<fn>_failed` gets the bullet.
#' @param packages Character vector of the requested specs, or `NULL`.
#' @param channels Character vector, `channels` and `additional_channels`.
#' @param default_channels `TRUE` when the caller did not pass `channels`.
#'
#' @returns The value of `expr`.
#'
#' @keywords internal
#' @noRd
with_default_channels_hint <- function(
  expr,
  fn,
  packages,
  channels,
  default_channels
) {
  if (isFALSE(default_channels) || identical(length(packages), 0L)) {
    return(expr)
  }
  failed_class <- paste0("condathis_", fn, "_failed")
  return(withCallingHandlers(
    expr,
    error = function(cnd) {
      if (
        isFALSE(inherits(cnd, failed_class)) ||
          isTRUE(cnd[["condathis_default_channels_hint"]])
      ) {
        return(invisible(NULL))
      }
      hint <- default_channels_hint(
        cnd,
        packages = packages,
        channels = channels
      )
      if (identical(length(hint), 0L)) {
        return(invisible(NULL))
      }
      # rlang keeps the bullets after the first one in `body`, and prints
      # them before the parent's message.
      if (is.null(cnd[["body"]]) || is.character(cnd[["body"]])) {
        cnd[["body"]] <- c(cnd[["body"]], hint)
      } else {
        cnd[["message"]] <- c(cnd[["message"]], hint)
      }
      cnd[["condathis_default_channels_hint"]] <- TRUE
      stop(cnd)
    }
  ))
}

#' The default-channels hint for a backend error
#'
#' @param cnd The error of a failed create or install.
#' @param packages Character vector of the requested specs.
#' @param channels Character vector, `channels` and `additional_channels`.
#'
#' @returns A named character vector with one formatted `i` bullet, or
#'   `character(0)` when `"bioconda"` is among `channels`, or when the error
#'   does not say that a requested spec without a channel was not found
#'   (see `missing_spec_names()`).
#'
#' @keywords internal
#' @noRd
default_channels_hint <- function(cnd, packages, channels) {
  if (isTRUE("bioconda" %in% requested_channel_names(channels))) {
    return(character(0L))
  }
  missing_names <- missing_spec_names(cnd)
  if (identical(length(missing_names), 0L)) {
    return(character(0L))
  }
  packages <- as.character(packages)
  # Specs without a channel only: a spec such as `"bioconda::samtools"`
  # already names its channel. A spec that cannot be read is left out.
  spec_names <- vapply(
    packages,
    function(spec_str) {
      ms <- tryCatch(parse_match_spec(spec_str), error = function(e) NULL)
      location <- ms[["channel_location"]]
      has_channel <- isFALSE(is.null(location)) &&
        isFALSE(is.na(location)) &&
        isTRUE(nzchar(location)) &&
        isFALSE(identical(location, "None"))
      if (is.null(ms) || isTRUE(has_channel)) {
        return(NA_character_)
      }
      return(tolower(as.character(ms[["name"]])))
    },
    character(1L),
    USE.NAMES = FALSE
  )
  specs <- packages[!is.na(spec_names) & spec_names %in% missing_names]
  if (identical(length(specs), 0L)) {
    return(character(0L))
  }
  bioconda_specs <- paste0("bioconda::", specs)
  hint <- cli::format_inline(
    "Since condathis 0.2.0, the default {.arg channels} is only {.val conda-forge}, without {.val bioconda}. If {.val {specs}} {?is a/are} bioconda package{?s}, name the channel in the spec{?s}, as in {.val {bioconda_specs}}, or pass {.code channels = c(\"conda-forge\", \"bioconda\")}."
  )
  return(c(`i` = hint))
}

#' The package names that a backend's error says were not found
#'
#' Reads the messages of `cnd` and of its parents, and their `stderr`
#' fields, for the text that each backend gives for a requested package
#' that is on none of the channels:
#' * micromamba 2: `"samtools =1.17 * does not exist (perhaps a typo or a
#'   missing channel)."`. A missing dependency reads `"which does not exist
#'   (perhaps a missing channel)"`, and does not count.
#' * rattler (resolvo): `"No candidates were found for samtools *."`.
#' Other text gives no names, so no hint.
#'
#' @param cnd An error condition.
#'
#' @returns Character vector of unique package names, in lower case,
#'   possibly empty.
#'
#' @keywords internal
#' @noRd
missing_spec_names <- function(cnd) {
  texts <- character(0L)
  depth <- 0L
  while (isTRUE(inherits(cnd, "condition")) && isTRUE(depth < 20L)) {
    texts <- c(texts, as.character(cnd[["message"]]))
    if (isTRUE(rlang::is_string(cnd[["stderr"]]))) {
      texts <- c(texts, cnd[["stderr"]])
    }
    cnd <- cnd[["parent"]]
    depth <- depth + 1L
  }
  text <- paste(texts[!is.na(texts)], collapse = "\n")
  name_pattern <- "([A-Za-z0-9_][A-Za-z0-9_.+-]*)"
  patterns <- c(
    paste0(
      "(?:^|\\s)",
      name_pattern,
      " [^\\n]*?does not exist \\(perhaps a typo or a missing channel\\)"
    ),
    paste0("No candidates were found for ", name_pattern)
  )
  found <- unlist(lapply(patterns, function(pattern) {
    matches <- regmatches(text, gregexpr(pattern, text, perl = TRUE))[[1L]]
    return(sub(pattern, "\\1", matches, perl = TRUE))
  }))
  return(unique(tolower(found)))
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
#' with its own class, also for an environment definition.
#'
#' A lock whose records the backend reported (see
#' `lock_records_comparable()`) is compared with the packages of the
#' environment: the environment is kept when it has exactly those packages
#' (see `compare_lock_records()`). Any other definition is never compared,
#' and aborts.
#'
#' @param backend An already-resolved backend object.
#' @param backend_name Character string, the registered backend name.
#' @param env_name Character string with the environment name.
#' @param packages Character vector of requested specs, possibly empty.
#' @param channels Character vector, `channels` and `additional_channels`.
#' @param platform `NULL` or the requested platform.
#' @param definition `NULL` or the environment definition of the call.
#' @param described `NULL` or the list from `describe_create_definition()`.
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
  definition = NULL,
  described = NULL,
  verbose_list,
  call = rlang::caller_env()
) {
  lock_target <- described$lock$target %||% NA_character_
  compare_lock <- isFALSE(is.null(definition)) &&
    isTRUE(lock_records_comparable(described$description, lock_target))
  # Each listing starts a process with micromamba, so list only when there
  # is something to compare.
  installed_pkgs_df <- NULL
  if (
    isFALSE(is.null(platform)) ||
      isTRUE(length(packages) > 0L) ||
      isTRUE(compare_lock)
  ) {
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
  if (isTRUE(compare_lock)) {
    comparison <- compare_lock_records(
      installed_pkgs_df,
      records = described$description$records,
      target = lock_target
    )
    path <- definition$path
    if (isFALSE(comparison$satisfied)) {
      condathis_abort(
        message = c(
          `x` = "Environment {.field {env_name}} exists and does not have the packages of lock file {.path {path}}.",
          lock_difference_bullets(comparison),
          `i` = "Use {.code overwrite = TRUE} to create it again from the lock file."
        ),
        class = "condathis_create_env_exists",
        call = call
      )
    }
    if (isTRUE(verbose_list$strategy %in% c("full", "output"))) {
      condathis_inform(
        message = c(
          `i` = "Environment {.field {env_name}} already has the packages of lock file {.path {path}}."
        )
      )
    }
    return(new_backend_result(
      NULL,
      fn = "create_env",
      backend_name = backend_name,
      env_name = env_name,
      call = call
    ))
  }
  if (isFALSE(is.null(definition))) {
    # A request depends on the channels and on the day, and a lock without
    # records cannot be compared: they never count as satisfied.
    message <- c(
      `x` = "Environment {.field {env_name}} already exists.",
      `i` = if (identical(described$description$kind, "lock")) {
        "It is not compared with a lock file whose packages the backend does not report."
      } else {
        "An existing environment is compared only with a lock file, not with an environment file that is solved."
      },
      env_request_hint
    )
    condathis_abort(
      message = message,
      class = "condathis_create_env_exists",
      call = call
    )
  }
  unsatisfied <- check$unsatisfied
  uncompared <- check$uncompared
  uncompared_versions <- check$uncompared_versions
  uncompared_builds <- check$uncompared_builds
  other_channels <- check$other_channels
  if (isFALSE(check$satisfied)) {
    # When only the channel differs, `overwrite = TRUE` with the same
    # channels fails: the package is not on them.
    hint <- if (isTRUE(unsatisfied_only_by_channel(check))) {
      character(0L)
    } else {
      env_request_hint
    }
    condathis_abort(
      message = c(
        `x` = "Environment {.field {env_name}} exists and does not have the requested packages.",
        unsatisfied_spec_bullets(check),
        hint
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
