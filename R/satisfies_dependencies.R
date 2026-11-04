#' Check whether dependencies are already satisfied
#'
#' Compares requested package specs with installed packages in an environment.
#'
#' @param pkg_str_vector Character vector of package MatchSpec strings.
#' @param env_name Character string with the environment name.
#' @param verbose Character string passed to `list_packages()`.
#'   Defaults to `"silent"`.
#' @param backend An already-resolved backend object, or `NULL` (default)
#'   to call the public, multi-backend `list_packages()`. Pass a resolved
#'   backend to avoid a second backend resolution. Its listing is checked
#'   with `backend_list_packages_checked()`.
#' @param channels Character vector of requested channels, or `NULL` to
#'   skip the channel check for specs without a channel.
#'
#' @returns A logical vector with one value per input specification.
#'
#' @keywords internal
#' @noRd
satisfies_dependencies <- function(
  pkg_str_vector,
  env_name,
  verbose = "silent",
  backend = NULL,
  channels = NULL
) {
  pkg_str_vector <- as.character(pkg_str_vector)
  if (isTRUE(length(pkg_str_vector) == 0L)) {
    return(logical(0L))
  }
  installed_pkgs_df <- if (rlang::is_null(backend)) {
    list_packages(env_name = env_name, verbose = verbose)
  } else {
    backend_list_packages_checked(
      backend,
      env_name = env_name,
      verbose = verbose
    )
  }
  requested_channels <- if (isFALSE(rlang::is_null(channels))) {
    requested_channel_names(channels)
  }
  output_vector <- vector(mode = "logical", length = length(pkg_str_vector))
  for (i in seq_along(pkg_str_vector)) {
    output_vector[i] <- spec_satisfied_by(
      spec_str = pkg_str_vector[i],
      installed_pkgs_df = installed_pkgs_df,
      requested_channels = requested_channels
    )
  }

  return(output_vector)
}

#' Is one MatchSpec satisfied by an installed package?
#'
#' Checks every field the solver would honor, not only the version:
#' the build string (see `build_string_matches()`), the channel named in
#' the spec, and, for a spec without a channel, the requested `channels`.
#' Checking only the name
#' and version made `create_env()` report success without installing
#' anything for requests such as `"numpy=1.26=*mkl*"` or
#' `"bioconda::samtools"`.
#'
#' Package names compare without case, as in libmamba: micromamba installs
#' `zlib` for the spec `"ZLIB"`. Of the bracket constraints, `version`,
#' `build`, `build_string`, `channel` and `build_number` are compared (see
#' `compared_bracket_keys`). A spec with any other bracket key (`md5`,
#' `sha256`, `subdir`, `url`, ...) is never satisfied, because the package
#' listing does not have those fields. With decision D4, an unsatisfied spec
#' makes `create_env(overwrite = FALSE)` abort on an existing environment,
#' so a false "not satisfied" breaks a repeated, identical call.
#'
#' @param spec_str Character string with one MatchSpec.
#' @param installed_pkgs_df Data frame from `list_packages()`.
#' @param requested_channels Channel names from `requested_channel_names()`,
#'   or `NULL` to skip the channel check for specs without a channel.
#'
#' @returns Logical scalar.
#'
#' @keywords internal
#' @noRd
spec_satisfied_by <- function(spec_str, installed_pkgs_df, requested_channels) {
  ms <- parse_match_spec(spec_str)
  bracket_attrs <- match_spec_bracket_attrs(spec_str)
  if (isFALSE(all(names(bracket_attrs) %in% compared_bracket_keys))) {
    return(FALSE)
  }
  # `[[` and not `$`: on a tibble, `$` warns for a missing column, and on a
  # data frame or a list it matches a partial name.
  installed <- installed_pkgs_df[
    tolower(installed_pkgs_df[["name"]]) %in% tolower(ms[["name"]]),
    ,
    drop = FALSE
  ]
  if (isFALSE(nrow(installed) > 0L)) {
    return(FALSE)
  }
  installed <- installed[1L, , drop = FALSE]
  if (
    isFALSE(isTRUE(version_spec_contains(
      version_string = as.character(installed[["version"]]),
      spec_string = ms[["version"]]
    )))
  ) {
    return(FALSE)
  }
  is_set <- function(x) {
    isFALSE(is.null(x)) &&
      isFALSE(is.na(x)) &&
      nzchar(x) &&
      !identical(x, "None")
  }
  if (is_set(ms[["build_string"]])) {
    installed_build <- as.character(installed[["build_string"]] %||% "")
    if (isFALSE(build_string_matches(ms[["build_string"]], installed_build))) {
      return(FALSE)
    }
  }
  if (isFALSE(is.null(bracket_attrs[["build_number"]]))) {
    if (
      isFALSE(build_number_spec_contains(
        build_number = installed[["build_number"]],
        spec_string = bracket_attrs[["build_number"]]
      ))
    ) {
      return(FALSE)
    }
  }
  installed_channel <- normalize_channel_name(installed[["channel"]] %||% "")
  if (is_set(ms[["channel_location"]])) {
    if (
      isFALSE(
        installed_channel %in% requested_channel_names(ms[["channel_location"]])
      )
    ) {
      return(FALSE)
    }
  } else if (isFALSE(rlang::is_null(requested_channels))) {
    if (isFALSE(installed_channel %in% requested_channels)) {
      return(FALSE)
    }
  }
  return(TRUE)
}

#' Does an installed build string match the build string of a spec?
#'
#' Only a build string of letters, digits, `_`, `.` and `*` is compared,
#' with `*` as its only wildcard and `.` as itself, as conda and rattler
#' read it. micromamba also matches any character at a `.`, so a match
#' here is a match for all three. A build string with any other character
#' is not compared and never matches (see
#' `specs_with_uncompared_builds()`): micromamba reads `?+()[]{}|\^$` as a
#' regular expression in its own dialect (and rejects `a((b`), rattler
#' reads `?` and `[...]` as glob wildcards when there is a `*`, and a
#' `^...$` regular expression has a different dialect in each of them.
#' `utils::glob2rx()` was used before: it read `?` as a wildcard, `+` as a
#' regular expression, and failed on `((`.
#'
#' @param pattern Character string. The build string of the spec.
#' @param build Character string. The installed build string.
#'
#' @returns `TRUE` or `FALSE`.
#'
#' @keywords internal
#' @noRd
build_string_matches <- function(pattern, build) {
  if (isFALSE(build_string_is_compared(pattern))) {
    return(FALSE)
  }
  regex <- gsub("[*]+", "*", pattern)
  regex <- gsub(".", "\\.", regex, fixed = TRUE)
  regex <- gsub("*", ".*", regex, fixed = TRUE)
  matched <- tryCatch(
    grepl(paste0("^", regex, "$"), build),
    error = function(e) FALSE,
    warning = function(w) FALSE
  )
  return(isTRUE(matched))
}

#' Is a build string compared?
#'
#' @param pattern Character string. The build string of a spec.
#'
#' @returns `TRUE` when it has only letters, digits, `_`, `.` and `*` (see
#'   `build_string_matches()`).
#'
#' @keywords internal
#' @noRd
build_string_is_compared <- function(pattern) {
  return(isTRUE(grepl("^[A-Za-z0-9_.*]*$", pattern)))
}

#' Bracket keys that `spec_satisfied_by()` compares
#'
#' `parse_match_spec()` moves `version`, `build`, `build_string` and
#' `channel` into the fields that `spec_satisfied_by()` compares, and
#' `build_number` is compared with the `build_number` column of the
#' listing. `url` is not here: `parse_match_spec()` reads it as a channel,
#' but in conda it is the URL of one package file.
#'
#' @keywords internal
#' @noRd
compared_bracket_keys <- c(
  "version",
  "build",
  "build_string",
  "channel",
  "build_number"
)

#' Specs with bracket constraints that are not compared
#'
#' @param packages Character vector of package MatchSpec strings.
#'
#' @returns The specs of `packages` with a bracket key that is not in
#'   `compared_bracket_keys`, or with a `build_number` that has `==`, which
#'   micromamba rejects. Such a spec never counts as satisfied.
#'
#' @keywords internal
#' @noRd
specs_with_uncompared_brackets <- function(packages) {
  packages <- as.character(packages)
  uncompared <- vapply(
    packages,
    function(spec_str) {
      attrs <- match_spec_bracket_attrs(spec_str)
      # micromamba rejects `==` for a build number.
      build_number <- gsub("[[:space:]]+", "", attrs[["build_number"]] %||% "")
      return(
        isFALSE(all(names(attrs) %in% compared_bracket_keys)) ||
          isTRUE(startsWith(build_number, "=="))
      )
    },
    logical(1L),
    USE.NAMES = FALSE
  )
  return(packages[uncompared])
}

#' Specs with a build string that is not compared
#'
#' A build string with a character other than a letter, a digit, `_`, `.`
#' and `*` (see `build_string_is_compared()`). conda, rattler and
#' micromamba read them differently, so such a spec never counts as
#' satisfied.
#'
#' @param packages Character vector of package MatchSpec strings.
#'
#' @returns The specs of `packages` with such a build string.
#'
#' @keywords internal
#' @noRd
specs_with_uncompared_builds <- function(packages) {
  packages <- as.character(packages)
  uncompared <- vapply(
    packages,
    function(spec_str) {
      build <- parse_match_spec(spec_str)[["build_string"]]
      return(
        rlang::is_string(build) &&
          isFALSE(identical(build, "None")) &&
          isFALSE(build_string_is_compared(build))
      )
    },
    logical(1L),
    USE.NAMES = FALSE
  )
  return(packages[uncompared])
}

#' Specs with a version that is not compared
#'
#' A `*` after `>=` other than one trailing `.*`, a glob after `>`, `<`,
#' `<=` or `~=`, a `*` that is not a trailing glob (`1.*.5`), `!=1.3*`,
#' `=1.3*`, `~=1`, an operator with no version, a missing operand or
#' parenthesis, and a version that micromamba rejects (see
#' `version_spec_is_compared()`). micromamba and conda read them
#' differently, so such a spec never counts as satisfied.
#'
#' @param packages Character vector of package MatchSpec strings.
#'
#' @returns The specs of `packages` with such a version.
#'
#' @keywords internal
#' @noRd
specs_with_uncompared_versions <- function(packages) {
  packages <- as.character(packages)
  uncompared <- vapply(
    packages,
    function(spec_str) {
      version <- parse_match_spec(spec_str)[["version"]]
      return(
        rlang::is_string(version) && isFALSE(version_spec_is_compared(version))
      )
    },
    logical(1L),
    USE.NAMES = FALSE
  )
  return(packages[uncompared])
}

#' Does a build number satisfy a `build_number` bracket constraint?
#'
#' The constraint is a number with an optional operator (`=`, `!=`, `>`,
#' `>=`, `<`, `<=`), or `*` for any build number, as libmamba accepts.
#' micromamba 2.9.0 and 2.10.0 reject `==` (`"Invalid build number
#' operator"`), so it never matches.
#'
#' @param build_number The installed build number: a single integer, or a
#'   value that converts to one.
#' @param spec_string Character string, the value of `build_number=` in the
#'   spec.
#'
#' @returns `TRUE` or `FALSE`. `FALSE` when the constraint cannot be read or
#'   the build number is missing.
#'
#' @keywords internal
#' @noRd
build_number_spec_contains <- function(build_number, spec_string) {
  spec_string <- gsub("[[:space:]]+", "", as.character(spec_string))
  if (identical(spec_string, "*")) {
    return(TRUE)
  }
  parts <- regmatches(
    spec_string,
    regexec("^(!=|>=|<=|=|>|<)?([0-9]+)$", spec_string)
  )[[1L]]
  installed <- suppressWarnings(as.numeric(as.character(build_number)))
  if (
    isFALSE(identical(length(parts), 3L)) ||
      isFALSE(identical(length(installed), 1L)) ||
      isTRUE(is.na(installed))
  ) {
    return(FALSE)
  }
  operator <- parts[[2L]]
  required <- as.numeric(parts[[3L]])
  result <- switch(
    operator,
    `!=` = installed != required,
    `>=` = installed >= required,
    `<=` = installed <= required,
    `>` = installed > required,
    `<` = installed < required,
    installed == required
  )
  return(isTRUE(result))
}

#' Reduce channel names and URLs to a comparable name
#'
#' micromamba reports a channel on `conda.anaconda.org` by name, and any
#' other channel by URL. Other backends can report every channel by URL.
#' The rules:
#' * Trailing slashes and a platform filter are dropped, as micromamba
#'   drops them: `"conda-forge/linux-64"`, `"conda-forge[linux-64]"` and
#'   `"file:///srv/chan/noarch"` name the channel without the platform.
#' * An `http(s)` URL loses its credentials: a user and password
#'   (`"https://user:pass@host/chan"`) and a token
#'   (`"https://host/t/<token>/chan"`). micromamba records the channel
#'   without them, and lists a token as `*****`.
#' * An `http(s)` URL on `conda.anaconda.org` becomes the path after the
#'   host: `"https://conda.anaconda.org/conda-forge/"` becomes
#'   `"conda-forge"`, and `"https://conda.anaconda.org/conda-forge/label/dev"`
#'   becomes `"conda-forge/label/dev"`. An `http(s)` URL under `pkgs/` on
#'   `repo.anaconda.com` also becomes its path, `"pkgs/main"`, as
#'   micromamba names the channels of `defaults`.
#' * Any other `http(s)` URL becomes `host/path`, with the host in lower
#'   case: `"https://repo.prefix.dev/my-org/channel"` becomes
#'   `"repo.prefix.dev/my-org/channel"`. So two hosts with the same last
#'   path component stay different.
#' * A `file://` URL or a local path becomes an absolute path, with `/`
#'   separators (see `local_channel_path()`). micromamba records a channel
#'   passed as a path (`"/srv/channels/my-channel"`, `"C:\\channels"`) as a
#'   `file://` URL. Two local channels with the same directory name in
#'   different places stay different. On Windows, where paths compare
#'   without case, the path is put in lower case after the last step.
#' * A channel name stays as it is.
#' * Last, every `/t/<word>` that `hide_secrets()` hides is hidden, in
#'   paths too: `"/srv/t/chan1/my-channel"` becomes
#'   `"/srv/t/*****/my-channel"`. micromamba 2.9.0 and later hide them in
#'   their JSON output (`micromamba list --json`), and condathis in the
#'   channels of the history and of `list_packages()`, so a recorded
#'   channel can have them hidden while the requested one does not. As
#'   they do, only a lower-case `/t/` counts, so `"C:\\data\\T\\a\\chan"`
#'   and `"C:\\data\\T\\b\\chan"` stay different.
#'
#' @param x Character vector of channel names or URLs.
#'
#' @returns Character vector.
#'
#' @keywords internal
#' @noRd
normalize_channel_name <- function(x) {
  x <- drop_channel_platform(as.character(x))
  is_http <- grepl("^https?://", x, ignore.case = TRUE)
  is_file <- grepl("^file://", x, ignore.case = TRUE)
  is_url <- grepl("^[A-Za-z][A-Za-z0-9+.-]*://", x)
  is_path <- !is_url &
    grepl("^(/|\\\\\\\\|~|\\.{1,2}([/\\\\]|$)|[A-Za-z]:[/\\\\])", x)

  # The token is hidden first, as micromamba lists it, and then a hidden
  # token (`t/*****`) is dropped: the plain and the hidden form of a URL
  # give one name, also for a token that `hide_secrets()` hides only up to
  # a `_` (`t/ab_cd` becomes `t/*****_cd`).
  host_path <- sub(
    "^https?://",
    "",
    hide_secrets(x[is_http]),
    ignore.case = TRUE
  )
  host_path <- sub("^[^/]*@", "", host_path)
  host <- tolower(sub("/.*$", "", host_path))
  path <- sub("^[^/]*/*", "", host_path)
  path <- sub("^t/[*]+(/+|$)", "", path)
  is_name <- (host == "conda.anaconda.org" & nzchar(path)) |
    (host == "repo.anaconda.com" & startsWith(path, "pkgs/"))
  x[is_http] <- ifelse(
    is_name,
    path,
    ifelse(nzchar(path), paste0(host, "/", path), host)
  )

  x[is_file] <- file_url_path(x[is_file])
  is_local <- is_file | is_path
  x[is_local] <- local_channel_path(x[is_local])
  # Hidden after `local_channel_path()`, which gives a path the form
  # micromamba records (absolute, `/` separators), so the hidden and the
  # plain form of a channel compare equal. So do two channels that differ
  # only inside a hidden part: the hidden form no longer tells them apart.
  # A Windows path is put in lower case only then, as micromamba and
  # condathis hide only a lower-case `/t/<word>`: an upper-case one
  # (`C:\T\a`) still tells two channels apart.
  x <- hide_secrets(x)
  if (isTRUE(is_windows())) {
    x[is_local] <- tolower(x[is_local])
  }
  return(x)
}

#' Channel names that requested channels stand for
#'
#' `normalize_channel_name()` of each channel. `"defaults"` also stands for
#' the channels micromamba resolves it to: `pkgs/main`, `pkgs/r` and, on
#' Windows, `pkgs/msys2` (added on every OS, where it matches nothing
#' else). micromamba lists their packages under those names, never as
#' `defaults`.
#'
#' @param channels Character vector of channel names or URLs.
#'
#' @returns Character vector of unique normalized names.
#'
#' @keywords internal
#' @noRd
requested_channel_names <- function(channels) {
  channels <- normalize_channel_name(channels)
  if (isTRUE("defaults" %in% channels)) {
    channels <- c(channels, "pkgs/main", "pkgs/r", "pkgs/msys2")
  }
  return(unique(channels))
}

#' Drop trailing slashes and a platform filter from channels
#'
#' As micromamba reads a channel: a `[platform, ...]` suffix, or a last
#' path component that is a known platform (`ms_is_known_platform()`),
#' filters the platforms and is not part of the channel.
#'
#' @param x Character vector of channel names, URLs or paths.
#'
#' @returns Character vector.
#'
#' @keywords internal
#' @noRd
drop_channel_platform <- function(x) {
  x <- sub("[/\\\\]+$", "", x)
  x <- sub("^(.+?)[[:space:]]*\\[[^]]*\\]$", "\\1", x, perl = TRUE)
  last_part <- sub("^.*[/\\\\]", "", x)
  has_platform <- grepl("[^/\\\\:][/\\\\]+[^/\\\\]+$", x) &
    ms_is_known_platform(last_part)
  x[has_platform] <- sub("[/\\\\]+[^/\\\\]+$", "", x[has_platform])
  return(sub("[/\\\\]+$", "", x))
}

#' The path of `file://` URLs
#'
#' Percent-encoded characters are decoded (`%20` is a space), and the `/`
#' before a Windows drive letter is dropped: `"file:///C:/chan"` gives
#' `"C:/chan"`. A URL with another host than `localhost` gives a UNC
#' path, `"//host/share/chan"`.
#'
#' @param x Character vector of `file://` URLs.
#'
#' @returns Character vector of paths.
#'
#' @keywords internal
#' @noRd
file_url_path <- function(x) {
  x <- sub("^file://", "", x, ignore.case = TRUE)
  x <- sub("^localhost/", "/", x, ignore.case = TRUE)
  x <- sub("^/([A-Za-z]:)", "\\1", x)
  is_unc <- !grepl("^(/|[A-Za-z]:)", x)
  x[is_unc] <- paste0("//", x[is_unc])
  return(vapply(
    x,
    function(path) {
      # A `%` that does not start an escape is kept as it is.
      if (
        isFALSE(grepl("%", path, fixed = TRUE)) ||
          isTRUE(grepl("%(?![0-9A-Fa-f]{2})", path, perl = TRUE))
      ) {
        return(path)
      }
      decoded <- utils::URLdecode(path)
      if (isTRUE(validUTF8(decoded))) {
        Encoding(decoded) <- "UTF-8"
      }
      return(decoded)
    },
    character(1L),
    USE.NAMES = FALSE
  ))
}

#' A local channel path as micromamba and rattler record it
#'
#' Both backends make the path absolute without reading the file system:
#' `~` is the home directory (`HOME`, or `USERPROFILE` on Windows), a
#' relative path is relative to the working directory, and `.` and `..`
#' are resolved by name, so a symbolic link is kept. The result has `/`
#' separators, and keeps the case of `x`, as both backends keep it.
#'
#' @param x Character vector of local paths.
#'
#' @returns Character vector of absolute paths.
#'
#' @keywords internal
#' @noRd
local_channel_path <- function(x) {
  x <- gsub("\\\\", "/", x)
  is_home <- grepl("^~(/|$)", x)
  if (isTRUE(any(is_home))) {
    home_var <- if (isTRUE(is_windows())) "USERPROFILE" else "HOME"
    home <- Sys.getenv(home_var, unset = "")
    if (isFALSE(nzchar(home))) {
      home <- path.expand("~")
    }
    x[is_home] <- paste0(gsub("\\\\", "/", home), substring(x[is_home], 2L))
  }
  is_relative <- !grepl("^(/|[A-Za-z]:/)", x)
  if (isTRUE(any(is_relative))) {
    wd <- gsub("\\\\", "/", getwd())
    x[is_relative] <- paste0(wd, "/", x[is_relative])
  }
  x <- as.character(fs::path_norm(x))
  return(x)
}
