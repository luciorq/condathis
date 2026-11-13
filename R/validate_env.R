#' Check that an environment has the requested packages
#'
#' Checks that an environment exists, and that its installed packages
#' satisfy every package match spec. `validate_env()` is a query: it never
#' creates or changes an environment. With the micromamba backend, it
#' reports an environment that does not exist without starting a process
#' or installing micromamba.
#' When no micromamba binary is installed, the micromamba backend reads
#' the `envs` directory of its data directory and the package records in
#' `conda-meta/` instead. It never installs micromamba.
#'
#' It uses the same check as `create_env(overwrite = FALSE)`. A spec without
#' a channel must match a package from `channels`, or from any channel when
#' `channels` is `NULL` (the default). Given
#' `channels = c(channels, additional_channels)` of a `create_env()` call
#' (by default `"conda-forge"`), `validate_env()` gives the same answer as
#' that call, with two exceptions. They exist because `validate_env()` only
#' reads:
#' * When `method` names a backend that does not own the environment,
#'   `validate_env()` warns with class `condathis_backend_mismatch_warning`
#'   and checks the environment with its owner. `create_env()` aborts with
#'   class `condathis_backend_mismatch`.
#' * When a backend cannot tell whether the environment exists,
#'   `validate_env()` still lists its packages, and reports the listing's
#'   error if it fails. In that case, `create_env()` aborts with the class
#'   `condathis_backend_probe_failed`.
#'
#' @param ... Package match specs (MatchSpec strings), unnamed, as in
#'   [create_env()]: character strings or character vectors, in order.
#'   With no specs, `validate_env()` only checks that the environment
#'   exists. An installed package satisfies a spec when it matches the
#'   name, version, build string and channel of the spec, as *Existing
#'   environments* in [create_env()] describes. The name match ignores case:
#'   `"PyYAML"` matches `pyyaml`. A spec without a channel matches a package
#'   from `channels` (see below). A spec with a channel, such as
#'   `"conda-forge::zlib"`, matches only a package from that channel. A spec
#'   that is not compared, such as `"zlib[md5=...]"` or `"zlib<2.*"`, never
#'   counts as satisfied. A spec for a virtual package, whose name starts
#'   with `__` (`"__cuda=12"`, `"__unix"`), is not checked: it describes the
#'   host, and an environment never lists it.
#'   `packages = <specs>` still works, as in [create_env()], and
#'   `packages = NULL` only checks that the environment exists. It is
#'   deprecated. It warns once per session (class
#'   `condathis_deprecated_packages_arg`) when the call comes from the
#'   console, a script or the tests of the package that makes it. Calls
#'   made inside other packages do not warn.
#'
#'   Or one lock file, given by [env_definition()], such as
#'   `env_definition("conda-lock.yml")`, without package specs. Then the
#'   environment must have exactly the packages that the lock lists for its
#'   platform, as [create_env()] compares them (see *Existing environments*
#'   there): `platform` when it is given, else any platform of the lock.
#'   Only a lock whose packages the backend reports can be compared, such
#'   as an `@EXPLICIT`, conda-lock or mambajs file with micromamba. Any
#'   other file, such as `environment.yml`, or a lock that has no packages
#'   for `platform`, aborts with class
#'   `condathis_validate_env_unsupported_definition` (also
#'   `condathis_invalid_arg`), with either value of `error`. Package specs
#'   and a definition together, or two definitions, abort with class
#'   `condathis_validate_env_conflicting_args`.
#'
#'   These values abort with class
#'   `condathis_validate_env_invalid_packages`:
#'   * A named argument that `validate_env()` does not have. Names are
#'     never abbreviated.
#'   * A value that is not a character vector.
#'   * `NA` or `""`.
#'   * A file name that ends in `.yml`, `.yaml`, `.json` or `.lock`. Pass
#'     a lock file with [env_definition()].
#'
#'   These classes abort too:
#'   * `condathis_validate_env_positional_env_name`\cr
#'     `env_name` is not given, the specs are two or more unnamed
#'     arguments, and the last of them is one string that names an existing
#'     environment. Specs given with `packages =` or as one vector are never
#'     checked this way.
#'   * `condathis_parse_match_spec_invalid_name`\cr
#'     a spec that condathis cannot read, such as `"::"`.
#'   * `condathis_parse_match_spec_invalid_url`\cr
#'     the URL of a package file that condathis cannot read.
#'
#'   Both parse errors also have class `condathis_invalid_arg`. They abort
#'   with `error = "continue"` too.
#' @inheritParams condathis-params
#' @param channels `NULL` (the default) or a non-empty character vector of
#'   channel names or URLs. With `NULL`, a spec without a channel matches a
#'   package from any channel. Otherwise, a spec without a channel must
#'   match a package from one of `channels`, compared as in [create_env()].
#'   A spec with a channel ignores `channels`. When a package matches a
#'   spec but comes from a channel that is not in `channels`, the error
#'   names that channel. There is no
#'   `additional_channels`: put those channels in `channels`. Invalid values
#'   abort with class `condathis_validate_env_invalid_channels`.
#' @param platform `NULL` (the default) or a known conda platform name,
#'   such as `"linux-64"`, as `platform` of [create_env()] accepts.
#'   When given, the packages of the environment must be built for it
#'   (`noarch` packages match any platform). Other values abort with class
#'   `condathis_validate_env_invalid_platform`.
#' @param error Character string. What happens when the environment does not
#'   exist or does not have the requested packages: `"cancel"` (the default)
#'   aborts, and `"continue"` returns `FALSE`. A backend failure always
#'   aborts. Invalid values abort with class `condathis_invalid_error`.
#'
#' @returns `TRUE`, invisibly, when the environment exists and has every
#'   requested package.
#'   Otherwise, with `error = "cancel"`, it aborts with one of these
#'   classes:
#'   * `condathis_validate_env_env_not_found` (also
#'     `condathis_env_not_found`)\cr
#'     the environment does not exist.
#'   * `condathis_validate_env_unsatisfied`\cr
#'     a spec is not satisfied or the platform differs. The message lists
#'     each spec that is not satisfied.
#'
#'   With `error = "continue"`, it returns `FALSE` with two attributes.
#'   `reason` is one of `"env_not_found"`, `"platform_mismatch"` and
#'   `"unsatisfied"`. `unsatisfied` is a character vector of the specs that
#'   are not satisfied (every spec when the environment does not exist).
#'   `validate_env()` reports a platform mismatch before unsatisfied specs.
#'   For a lock file, `unsatisfied` lists the packages of the lock that the
#'   environment does not have, as `"<name>-<version>-<build>"`, and a
#'   third attribute, `unexpected`, lists the packages of the environment
#'   that the lock does not list.
#'
#'   A backend failure aborts with either value of `error`, with the class
#'   `condathis_validate_env_failed` (also `condathis_backend_error`).
#'
#' @family environments
#' @seealso [condathis-conditions] for every condition class.
#'
#' @examples
#' condathis::with_sandbox_dir({
#'   # A missing environment: FALSE, with the reason
#'   res <- condathis::validate_env(
#'     "polyglot",
#'     env_name = "no-such-env",
#'     error = "continue"
#'   )
#'   print(res)
#' })
#'
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   # A local channel shipped with condathis, with `polyglot`: a
#'   # dependency-free script that runs on Linux, macOS and Windows.
#'   channel <- system.file(
#'     "extdata", "polyglot-channel",
#'     package = "condathis"
#'   )
#'   condathis::create_env(
#'     "polyglot",
#'     env_name = "polyglot-env",
#'     channels = channel
#'   )
#'
#'   # TRUE, invisibly.
#'   condathis::validate_env("polyglot", env_name = "polyglot-env")
#'
#'   # Also TRUE: `polyglot` comes from `channel`, as `create_env()` with
#'   # the same channels requires.
#'   condathis::validate_env(
#'     "polyglot",
#'     env_name = "polyglot-env",
#'     channels = channel
#'   )
#'
#'   # FALSE, with the reason and the specs that are not satisfied.
#'   res <- condathis::validate_env(
#'     "polyglot>=2",
#'     env_name = "polyglot-env",
#'     error = "continue"
#'   )
#'   print(attr(res, "reason"))
#'   #> [1] "unsatisfied"
#'   attr(res, "unsatisfied")
#'   #> [1] "polyglot>=2"
#' })
#' }
#'
#' @export
validate_env <- function(
  ...,
  env_name = "condathis-env",
  method = "auto",
  verbose = "silent",
  channels = NULL,
  platform = NULL,
  error = c("cancel", "continue")
) {
  # The caller, for the soft deprecations of `packages =` and
  # `method = "native"` (see `is_direct_use()`).
  user_env <- rlang::caller_env()
  # Rule R2: every argument is checked before the first backend call.
  dots <- rlang::list2(...)
  # An `env_definition()` of a lock is compared by its records.
  split_dots <- split_env_definitions(dots)
  dots <- split_dots$dots
  packages <- collect_package_specs(
    dots,
    fn = "validate_env",
    user_env = user_env
  )
  validate_env_name(env_name, class = "condathis_validate_env_invalid_env_name")
  method <- validate_method_arg(method)
  verbose_list <- parse_verbose_arg(verbose)
  validate_channels_arg(
    channels,
    additional_channels = NULL,
    class = "condathis_validate_env_invalid_channels",
    allow_null = TRUE
  )
  validate_platform_arg(
    platform,
    class = arg_error_class("validate_env", "platform")
  )
  error <- arg_match_classed(
    error,
    values = c("cancel", "continue"),
    class = "condathis_invalid_error",
    arg_name = "error"
  )
  definition <- resolve_call_definition(
    split_dots$definitions,
    packages = packages,
    fn = "validate_env"
  )
  if (missing(env_name) && isTRUE(positional_env_name_possible(dots))) {
    abort_on_positional_env_name(packages, fn = "validate_env")
  }
  method <- resolve_method_alias(method, user_env = user_env)

  resolved <- resolve_backend(
    env_name = env_name,
    method = method,
    mutating = FALSE
  )
  # Before the environment is probed: a definition that cannot be compared
  # aborts also for a missing environment.
  lock_records <- NULL
  if (isFALSE(is.null(definition))) {
    lock_records <- validate_env_lock_records(
      resolved,
      definition = definition,
      platform = platform
    )
  }

  env_probe <- backend_probe_env(
    resolved$backend,
    env_name = env_name,
    verbose = "silent"
  )
  if (isFALSE(env_probe)) {
    if (identical(error, "cancel")) {
      abort_env_not_found(
        env_name,
        class = "condathis_validate_env_env_not_found"
      )
    }
    unsatisfied <- if (is.null(lock_records)) {
      packages
    } else {
      unique(package_dist_strings(lock_records))
    }
    return(validate_env_failure("env_not_found", unsatisfied = unsatisfied))
  }

  # A failed probe (`NA`, rule R5) is not read as "absent": the listing
  # either works, and the environment exists, or reports the real error.
  installed_pkgs_df <- NULL
  if (
    isTRUE(is.na(env_probe)) ||
      isFALSE(is.null(platform)) ||
      isTRUE(length(packages) > 0L) ||
      isFALSE(is.null(lock_records))
  ) {
    installed_pkgs_df <- list_env_packages_checked(
      backend = resolved$backend,
      backend_name = resolved$name,
      env_name = env_name,
      fn = "validate_env"
    )
  }
  check <- check_env_request(
    installed_pkgs_df = installed_pkgs_df,
    packages = packages,
    channels = channels,
    platform = platform
  )
  if (isFALSE(is.null(lock_records)) && isTRUE(check$satisfied)) {
    return(validate_env_lock(
      installed_pkgs_df,
      records = lock_records,
      platform = platform,
      definition = definition,
      env_name = env_name,
      error = error,
      verbose_list = verbose_list
    ))
  }

  if (isTRUE(check$satisfied)) {
    if (isTRUE(verbose_list$strategy %in% c("full", "output"))) {
      condathis_inform(
        message = c(
          `v` = "Environment {.field {env_name}} has the requested packages."
        )
      )
    }
    return(invisible(TRUE))
  }

  if (identical(error, "continue")) {
    return(validate_env_failure(check$reason, unsatisfied = check$unsatisfied))
  }
  unsatisfied <- check$unsatisfied
  uncompared <- check$uncompared
  uncompared_versions <- check$uncompared_versions
  uncompared_builds <- check$uncompared_builds
  other_channels <- check$other_channels
  env_platforms <- check$env_platforms
  problems <- character(0L)
  if (identical(check$reason, "platform_mismatch")) {
    problems <- c(
      problems,
      `x` = "It was built for platform {.val {env_platforms}}, not {.val {platform}}."
    )
  }
  problems <- c(problems, unsatisfied_spec_bullets(check))
  # When only the channel differs, the bullets above say what to pass.
  hint <- if (
    isFALSE(identical(check$reason, "platform_mismatch")) &&
      isTRUE(unsatisfied_only_by_channel(check))
  ) {
    character(0L)
  } else {
    c(
      `i` = "Use {.fn install_packages} to add packages, or {.code create_env(overwrite = TRUE)} to create it again."
    )
  }
  condathis_abort(
    message = c(
      `x` = "Environment {.field {env_name}} does not have the requested packages.",
      problems,
      hint
    ),
    class = "condathis_validate_env_unsatisfied"
  )
}

#' The `FALSE` value of `validate_env(error = "continue")`
#'
#' @param reason Character string: `"env_not_found"`, `"platform_mismatch"`
#'   or `"unsatisfied"`.
#' @param unsatisfied Character vector of the specs that are not satisfied.
#' @param unexpected `NULL`, or for a lock file the packages of the
#'   environment that the lock does not list.
#'
#' @returns `FALSE` with the attributes `reason` and `unsatisfied`, and
#'   `unexpected` when it is not `NULL`.
#'
#' @keywords internal
#' @noRd
validate_env_failure <- function(reason, unsatisfied, unexpected = NULL) {
  value <- structure(
    FALSE,
    reason = reason,
    unsatisfied = as.character(unsatisfied)
  )
  if (isFALSE(is.null(unexpected))) {
    attr(value, "unexpected") <- as.character(unexpected)
  }
  return(value)
}

#' The records that `validate_env()` compares an environment with
#'
#' Only a lock whose records the backend reports can be compared (see
#' `lock_records_comparable()`). A request, such as an environment YAML
#' file, depends on the channels and on the day.
#'
#' @param resolved The list from `resolve_backend()`.
#' @param definition A valid `condathis_env_definition` object.
#' @param platform `NULL` or the `platform` of `validate_env()`.
#' @param call Environment of the function the error is reported for.
#'
#' @returns The records of the lock: a data frame with `name`, `version`,
#'   `build_string` and `platform`, for `platform` when it is given. Aborts
#'   with class `condathis_validate_env_unsupported_definition` (also
#'   `condathis_invalid_arg`, and `condathis_backend_unsupported` when the
#'   backend cannot read the file).
#'
#' @keywords internal
#' @noRd
validate_env_lock_records <- function(
  resolved,
  definition,
  platform = NULL,
  call = rlang::caller_env()
) {
  description <- describe_definition(
    resolved$backend,
    definition = definition,
    platform = platform,
    generic = "backend_create_env",
    call = call
  )
  if (isFALSE(description$supported)) {
    abort_unsupported_definition(
      backend_name = resolved$name,
      definition = definition,
      reason = description$reason,
      fn = "validate_env",
      call = call
    )
  }
  target <- platform %||% NA_character_
  path <- definition$path
  listed <- setdiff(as.character(description$platforms), "noarch")
  if (
    identical(description$kind, "lock") &&
      isFALSE(is.null(platform)) &&
      isTRUE(length(listed) > 0L) &&
      isFALSE(platform %in% listed)
  ) {
    condathis_abort(
      message = c(
        `x` = "Lock file {.path {path}} has no packages for platform {.val {platform}}.",
        `i` = "It has packages for {.or {.val {listed}}}."
      ),
      class = c(
        "condathis_validate_env_unsupported_definition",
        "condathis_invalid_arg"
      ),
      call = call
    )
  }
  if (isTRUE(lock_records_comparable(description, target))) {
    records <- description$records
    if (isFALSE(is.null(platform))) {
      records <- lock_records_for(records, platform)
    }
    return(records)
  }
  reason <- if (identical(description$kind, "lock")) {
    "Backend {.field {resolved$name}} does not report the packages of lock file {.path {path}}."
  } else {
    "{.fn validate_env} compares an environment only with a lock file that lists its packages, such as an {.code @EXPLICIT} or conda-lock file, not with {.path {path}}."
  }
  condathis_abort(
    message = c(
      `x` = "Environment definition {.path {path}} cannot be compared with an environment.",
      `i` = reason,
      `i` = "Pass the package specs to check instead, or use {.code create_env(env_definition(...), overwrite = TRUE)} to create the environment again from the file."
    ),
    class = c(
      "condathis_validate_env_unsupported_definition",
      "condathis_invalid_arg"
    ),
    call = call
  )
}

#' The answer of `validate_env()` for a lock
#'
#' @param installed_pkgs_df Data frame from `list_env_packages_checked()`.
#' @param records The records from `validate_env_lock_records()`.
#' @param platform `NULL` or the `platform` of `validate_env()`.
#' @param definition The environment definition, for the message.
#' @param env_name Character string.
#' @param error `"cancel"` or `"continue"`.
#' @param verbose_list Parsed verbose list.
#' @param call Environment of the function the error is reported for.
#'
#' @returns `TRUE`, invisibly, when the environment has exactly the
#'   packages of the lock (see `compare_lock_records()`). Otherwise `FALSE`
#'   (see `validate_env_failure()`) or an abort with class
#'   `condathis_validate_env_unsatisfied`.
#'
#' @keywords internal
#' @noRd
validate_env_lock <- function(
  installed_pkgs_df,
  records,
  platform,
  definition,
  env_name,
  error,
  verbose_list,
  call = rlang::caller_env()
) {
  comparison <- compare_lock_records(
    installed_pkgs_df,
    records = records,
    target = platform %||% NA_character_
  )
  path <- definition$path
  if (isTRUE(comparison$satisfied)) {
    if (isTRUE(verbose_list$strategy %in% c("full", "output"))) {
      condathis_inform(
        message = c(
          `v` = "Environment {.field {env_name}} has the packages of lock file {.path {path}}."
        )
      )
    }
    return(invisible(TRUE))
  }
  if (identical(error, "continue")) {
    return(validate_env_failure(
      "unsatisfied",
      unsatisfied = comparison$missing,
      unexpected = comparison$unexpected
    ))
  }
  condathis_abort(
    message = c(
      `x` = "Environment {.field {env_name}} does not have the packages of lock file {.path {path}}.",
      lock_difference_bullets(comparison),
      `i` = "Use {.code create_env(env_definition(...), overwrite = TRUE)} to create it again from the lock file."
    ),
    class = "condathis_validate_env_unsatisfied",
    call = call
  )
}
