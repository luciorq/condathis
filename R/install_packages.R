#' Install packages in a Conda environment
#'
#' Installs packages into an existing environment.
#' `install_packages()` creates the default environment `"condathis-env"`,
#' empty, when it does not exist. Any other environment that does not exist
#' aborts with class `condathis_install_packages_env_not_found` (also
#' `condathis_env_not_found`). Create it with [create_env()] first.
#'
#' `install_packages()` installs packages for the platform of the
#' environment, with every backend. That platform is the one the environment
#' was created for (see `platform` in [create_env()]). Otherwise, on Apple
#' Silicon and on Windows, it is the platform of the environment's packages
#' that are not `noarch`.
#' An environment with no packages other than `noarch` ones, such as a new
#' `"condathis-env"`, gets the emulation fallback of [create_env()] instead.
#' Packages that cannot be installed for the native platform then use an
#' emulated platform, when they can be installed there. That platform is
#' `"osx-64"` on Apple Silicon when Rosetta 2 is running. On Windows with a
#' backend that solves for `"win-arm64"`, such as the `win-arm64`
#' micromamba, it is `"win-64"`. Later installs then use the same platform.
#'
#' @param ... Package match specs (MatchSpec strings) to install, unnamed:
#'   character strings or character vectors, in order. Examples:
#'   `"python=3.13"`, `"bioconda::samtools"`. At least one spec is required.
#'   No specs abort with class `condathis_install_packages_missing_packages`.
#'   Any other value aborts with class
#'   `condathis_install_packages_invalid_packages`. Such values are:
#'   * A named argument that `install_packages()` does not have. The error
#'     names the closest argument.
#'   * A value that is not a character vector.
#'   * `NA` or `""`.
#'   * A file name that ends in `.yml` or `.yaml`.
#'
#'   `packages = <specs>` still works. It is deprecated and warns once per
#'   session (class `condathis_deprecated_packages_arg`).
#'   `install_packages()` aborts with class
#'   `condathis_install_packages_positional_env_name` when `env_name` is not
#'   given and the last of two or more specs names an existing environment.
#'   Name the argument, as in `env_name = "my-env"`.
#'   A spec that the backend cannot read, such as `"::"`, aborts with class
#'   `condathis_install_packages_failed`. When the `conda-meta/history` of
#'   the environment records channels, condathis reads the specs first. Then
#'   such a spec aborts with class
#'   `condathis_parse_match_spec_invalid_name`. For the URL of a package
#'   file, the class is `condathis_parse_match_spec_invalid_url`. Both
#'   errors also have class `condathis_invalid_arg`.
#' @inheritParams condathis-params
#' @param channels A non-empty character vector of channel names or URLs,
#'   in priority order. For a package from another channel, either name the
#'   channel in the spec (`"bioconda::samtools"`) or add it here, as in
#'   `channels = c("conda-forge", "bioconda")`. Invalid values, such as
#'   `NULL`, `NA` or `""`, abort with class
#'   `condathis_install_packages_invalid_channels`.
#'   The `conda-meta/history` of the environment records the channels of its
#'   packages. When the call leaves out one of them, `install_packages()`
#'   warns with class `condathis_install_packages_missing_previous_channels`.
#'   Add that channel to `channels` or `additional_channels`. A channel
#'   named in a spec counts as included.
#' @param additional_channels `NULL` (the default) or a non-empty character
#'   vector of channel names or URLs, used after `channels`. Invalid values
#'   abort with class `condathis_install_packages_invalid_channels` (also
#'   `condathis_invalid_additional_channels`).
#' @param channel_priority Channel priority mode: `"strict"` (the default),
#'   `"flexible"` or `"disabled"`, as in [create_env()]. Invalid values
#'   abort with class `condathis_install_packages_invalid_channel_priority`.
#'
#' @returns A `condathis_result` object, invisibly: a classed list with
#'   `status`, `stdout`, `stderr`, `timeout`, `pid`, `cmd` and `env_name`.
#'   `cmd` is the command line that the backend ran, or `NA` when the
#'   backend reports none. `stdout`, `stderr` and `pid` are `NA` when the
#'   backend reports none, and `pid` always is with micromamba.
#'   A backend failure aborts with class `condathis_install_packages_failed`
#'   (also `condathis_backend_error`), with the backend's error as the
#'   parent.
#'   micromamba runs the link scripts of packages. A backend that does not
#'   makes `install_packages()` warn with class
#'   `condathis_install_packages_link_scripts_skipped` (also
#'   `condathis_link_scripts_skipped`). The warning names the packages.
#'
#' @inheritSection create_env Other R sessions
#'
#' @family environments
#' @seealso [condathis-conditions] for every condition class.
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
#'   # Install `polyglot` into an existing, empty environment.
#'   condathis::create_env(env_name = "my-env")
#'   condathis::install_packages(
#'     "polyglot",
#'     env_name = "my-env",
#'     channels = channel
#'   )
#'
#'   condathis::create_env(
#'     "bioconda::fastqc",
#'     env_name = "fastqc-env"
#'   )
#'   # Install the package `python` in the `fastqc-env` environment.
#'   # Keep unrelated tools in separate environments, so that their
#'   # dependencies cannot conflict.
#'   # `bioconda` is passed again, because `fastqc` came from it: leaving out
#'   # a channel the environment was built from warns. `conda-forge` comes
#'   # first: with strict channel priority, the first channel wins.
#'   condathis::install_packages(
#'     "python",
#'     env_name = "fastqc-env",
#'     channels = c("conda-forge", "bioconda")
#'   )
#' })
#' }
#'
#' @export
install_packages <- function(
  ...,
  env_name = "condathis-env",
  method = "auto",
  verbose = c("output", "silent", "cmd", "spinner", "full"),
  channels = "conda-forge",
  additional_channels = NULL,
  channel_priority = c("strict", "flexible", "disabled")
) {
  # Rule R2: every argument is checked before the first backend call.
  packages <- collect_package_specs(
    rlang::list2(...),
    fn = "install_packages",
    allow_empty = FALSE
  )
  validate_env_name(
    env_name,
    class = "condathis_install_packages_invalid_env_name"
  )
  validate_method_arg(method)
  verbose_list <- parse_verbose_arg(verbose)
  validate_channels_arg(
    channels,
    additional_channels,
    class = "condathis_install_packages_invalid_channels"
  )
  # Matched here, so the backend gets one string: before, it got "bogus" or
  # the whole default vector.
  channel_priority <- arg_match_classed(
    channel_priority,
    values = c("strict", "flexible", "disabled"),
    class = c(
      "condathis_install_packages_invalid_channel_priority",
      "condathis_invalid_channel_priority"
    ),
    arg_name = "channel_priority"
  )
  if (missing(env_name)) {
    abort_on_positional_env_name(packages, fn = "install_packages")
  }

  # One R session at a time changes an environment (see
  # `local_env_lock()`), so a removal or a replacement in another session
  # never runs in the middle of this install. The `create_env()` of a
  # missing default environment takes the same lock again. The package
  # caches are held shared (see `local_cache_lock()`).
  env_lock <- local_env_lock(env_name, verbose = verbose_list$strategy)
  cache_lock <- local_cache_lock(verbose = verbose_list$strategy)

  resolved <- resolve_backend(
    env_name = env_name,
    method = method,
    mutating = TRUE
  )

  # Decision D3: only the default environment is created. A failed probe
  # (`NA`, rule R5) is not read as "absent": the backend gets the call and
  # reports its own error.
  env_probe <- backend_probe_env(
    resolved$backend,
    env_name = env_name,
    verbose = "silent"
  )
  if (isFALSE(env_probe)) {
    if (isFALSE(identical(env_name, "condathis-env"))) {
      abort_env_not_found(
        env_name,
        class = "condathis_install_packages_env_not_found",
        hint = c(`i` = "Create it with {.fn create_env} first.")
      )
    }
    create_env(
      env_name = env_name,
      method = resolved$name,
      verbose = verbose_list$internal_verbose
    )
  }

  # The resolved backend's directory: `get_env_dir()` would resolve the
  # backend again and probe every backend.
  env_dir <- env_dir_for_backend(resolved$backend, env_name)
  # For every backend: one that writes no `conda-meta/history` gets no
  # warning.
  warn_on_missing_previous_channels(
    env_dir = env_dir,
    env_name = env_name,
    packages = packages,
    channels = c(channels, additional_channels)
  )
  # The platform of the environment, or the emulation fallback of
  # create_env() for one without packages of a platform. The caller's
  # verbose level, so the emulation messages show. The probes are backend
  # calls of this install, so their errors have its classes.
  platform <- with_backend_errors(
    resolve_install_platform(
      resolved$backend,
      env_dir = env_dir,
      packages = packages,
      channels = channels,
      channel_priority = channel_priority,
      additional_channels = additional_channels,
      verbose = verbose_list$strategy
    ),
    fn = "install_packages",
    backend_name = resolved$name,
    action = paste0("install packages in environment '", env_name, "'")
  )

  env_lock_before_change(env_lock, cache_lock)
  px_res <- with_backend_errors(
    backend_install(
      resolved$backend,
      packages = packages,
      env_name = env_name,
      channels = channels,
      channel_priority = channel_priority,
      additional_channels = additional_channels,
      platform = platform,
      verbose = verbose_list$strategy
    ),
    fn = "install_packages",
    backend_name = resolved$name,
    action = paste0("install packages in environment '", env_name, "'")
  )
  result <- new_backend_result(
    px_res,
    fn = "install_packages",
    backend_name = resolved$name,
    env_name = env_name
  )
  link_scripts <- backend_link_scripts_skipped(
    px_res,
    fn = "install_packages",
    backend_name = resolved$name
  )

  if (isTRUE(verbose_list$strategy %in% c("full", "output"))) {
    condathis_inform(
      message = c(
        `v` = "{cli::qty(packages)}Package{?s} {.field {packages}} successfully installed in environment {.field {env_name}}."
      )
    )
  }
  warn_link_scripts_skipped(
    link_scripts,
    fn = "install_packages",
    backend_name = resolved$name,
    env_name = env_name
  )
  return(invisible(result))
}

#' Warn when an install leaves out a channel the environment was built from
#'
#' Channels named inside the package specs (`"bioconda::samtools"`) count
#' as included, and channel URLs compare by channel path (see
#' `normalize_channel_name()`), so `"https://conda.anaconda.org/conda-forge"`
#' covers `"conda-forge"`, and `"defaults"` covers `"pkgs/main"` (see
#' `requested_channel_names()`).
#'
#' @param env_dir Character string, the directory of the environment.
#' @param env_name Character string with the environment name.
#' @param packages Character vector of package specs.
#' @param channels Character vector, `channels` and `additional_channels`.
#'
#' @returns `NULL`, invisibly. Warns with class
#'   `c("condathis_install_packages_missing_previous_channels",
#'   "condathis_install_missing_previous_channels", "condathis_warning")`.
#'
#' @keywords internal
#' @noRd
warn_on_missing_previous_channels <- function(
  env_dir,
  env_name,
  packages,
  channels
) {
  previous_channels <- get_env_history_channels(env_dir = env_dir)
  if (identical(length(previous_channels), 0L)) {
    return(invisible(NULL))
  }
  spec_channels <- vapply(
    as.character(packages),
    function(spec) {
      location <- parse_match_spec(spec)$channel_location
      if (is.null(location) || is.na(location) || identical(location, "None")) {
        return("")
      }
      return(location)
    },
    character(1L),
    USE.NAMES = FALSE
  )
  included_channels <- requested_channel_names(
    c(channels, spec_channels[nzchar(spec_channels)])
  )
  missing_channels <- previous_channels[
    !normalize_channel_name(previous_channels) %in% included_channels
  ]
  if (isTRUE(length(missing_channels) > 0L)) {
    condathis_warn(
      message = c(
        `!` = "Environment {.field {env_name}} was previously installed using channel{?s} {.field {missing_channels}}, not included in this call.",
        `i` = "Dependency resolution may differ from previous installs. Consider adding {.field {missing_channels}} to {.arg channels} or {.arg additional_channels}."
      ),
      class = c(
        "condathis_install_packages_missing_previous_channels",
        "condathis_install_missing_previous_channels"
      )
    )
  }
  return(invisible(NULL))
}
