#' Parse a Conda MatchSpec String
#'
#' Parses a string representation of a Conda package specification into its
#' constituent parts following the CEP 29 MatchSpec query language
#' specification.
#' Output is compatible with `libmambapy.specs.MatchSpec`.
#'
#' @details
#' The output format matches `libmambapy.specs.MatchSpec` string representations
#' exactly, including Python-style `"None"`, `"set()"`, and `"{'plat'}"` strings
#' for set/optional fields.
#'
#' This implementation follows:
#'
#' - [Conda CEP 29](https://conda.org/learn/ceps/cep-0029/):
#'   The `MatchSpec` query language.
#' - [libmamba](https://github.com/mamba-org/mamba):
#'   at `libmamba/src/specs/match_spec.cpp`.
#'
#' @param spec_string A character string containing the `MatchSpec` text
#'   (e.g., `"numpy>=1.11"`, `"conda-forge::python=3.9"`).
#'
#' @returns A named list with 10 character string fields:
#'
#' - **formatted_spec**: Canonical string representation.
#' - **name**: Package name (`NameSpec`).
#' - **name_space**: Namespace (empty string if not set).
#' - **channel**: Channel string or `"None"`.
#' - **channel_location**: Channel location or `"None"`.
#' - **channel_platform_filters**: Platform filters as Python set string.
#' - **version**: Version specifier (e.g., `">=1.8"`, `"=*"` for free).
#' - **build_string**: Build string spec (e.g., `"py27_0"`, `"*"` for free).
#' - **platforms**: Platforms as Python set string or `"None"`.
#' - **track_features**: Track features as Python set string or `"None"`.
#'
#' @examples
#' condathis::parse_match_spec("conda-forge::numpy>=1.11")
#' condathis::parse_match_spec("bioconda::samtools=1.10[build=1]")
#' condathis::parse_match_spec("numpy=1.11.2=*nomkl*")
#'
#' @keywords internal
#' @noRd
parse_match_spec <- function(spec_string) {
  if (
    rlang::is_null(spec_string) ||
      !is.character(spec_string) ||
      !identical(length(spec_string), 1L)
  ) {
    cli::cli_abort(
      message = c(
        `x` = "The {.code MatchSpec} string must be a single character string."
      ),
      class = "condathis_parse_match_spec_invalid_input"
    )
  }

  raw_string <- spec_string

  # Strip comments: everything after " #" (including space)
  comment_pos <- as.integer(base::regexpr(" #", raw_string, fixed = TRUE))
  if (isTRUE(comment_pos > 0L)) {
    raw_string <- base::substring(raw_string, 1L, comment_pos - 1L)
  }

  # Strip whitespace
  raw_string <- trimws(raw_string)

  if (identical(raw_string, "")) {
    # Empty MatchSpec returns all-free spec
    return(ms_make_result(
      name = "*",
      name_space = "",
      channel_location = NULL,
      channel_platform_filters = NULL,
      version = "=*",
      build_string = "*",
      extra_platforms = NULL,
      extra = list()
    ))
  }

  # Normalize spaces after operators (libmamba does this)
  op_vector <- c(">=", "<=", "!=", "==", "~=", ">", "<", "=", ",")
  for (op_string in op_vector) {
    escaped_op <- gsub("([|.\\^$*+?(){}\\[\\]])", "\\\\\\1", op_string)
    bad_pattern <- paste0(escaped_op, " +")
    raw_string <- gsub(bad_pattern, op_string, raw_string, perl = TRUE)
  }

  raw_string <- trimws(raw_string)

  if (identical(raw_string, "")) {
    return(ms_make_result(
      name = "*",
      name_space = "",
      channel_location = NULL,
      channel_platform_filters = NULL,
      version = "=*",
      build_string = "*",
      extra_platforms = NULL,
      extra = list()
    ))
  }

  # Check for archive URL (ends with .tar.bz2 or .conda)
  if (isTRUE(grepl("\\.(tar\\.bz2|conda)$", raw_string))) {
    return(ms_parse_url(raw_string))
  }

  # Check for URL with MD5 hash fragment
  if (isTRUE(grepl("#[0-9a-fA-F]+$", raw_string))) {
    hash_match <- as.integer(base::regexpr("#[0-9a-fA-F]+$", raw_string))
    url_part <- base::substring(raw_string, 1L, hash_match - 1L)
    if (isTRUE(grepl("\\.(tar\\.bz2|conda)$", url_part))) {
      return(ms_parse_url(url_part))
    }
  }

  # 1. Split channel:namespace:spec
  cns <- ms_split_channel_namespace_spec(raw_string)
  channel_str <- cns$channel
  name_space <- cns$namespace
  remaining <- cns$spec

  # Parse channel if present
  channel_location <- NULL
  channel_pf <- NULL
  if (!rlang::is_null(channel_str) && nchar(channel_str) > 0L) {
    ch <- ms_parse_channel(channel_str)
    channel_location <- ch$location
    channel_pf <- ch$platform_filters
  }

  # 2. Parse bracket attributes from right to left
  bracket_result <- ms_rparse_brackets(remaining)
  remaining <- bracket_result$remaining
  attrs <- bracket_result$attributes

  # 3. Apply bracket attributes
  extra <- list()
  bracket_version <- NULL
  bracket_build <- NULL

  for (key in names(attrs)) {
    val <- attrs[[key]]
    lkey <- tolower(trimws(key))

    if (identical(lkey, "version")) {
      bracket_version <- val
    } else if (lkey %in% c("build", "build_string")) {
      bracket_build <- val
    } else if (lkey %in% c("channel", "url")) {
      if (rlang::is_null(channel_location)) {
        ch <- ms_parse_channel(val)
        channel_location <- ch$location
        channel_pf <- ch$platform_filters
      }
    } else if (identical(lkey, "subdir")) {
      # subdir sets platform filters
      new_pf <- ms_parse_platform_list(val)
      if (rlang::is_null(channel_location)) {
        # No channel yet: these become extra_platforms
        if (rlang::is_null(channel_pf) || identical(length(channel_pf), 0L)) {
          channel_pf <- new_pf
        }
      } else {
        # Channel exists: set platform filters if empty
        if (rlang::is_null(channel_pf) || identical(length(channel_pf), 0L)) {
          channel_pf <- new_pf
        }
      }
    } else if (identical(lkey, "namespace")) {
      if (identical(name_space, "")) {
        name_space <- val
      }
    } else if (identical(lkey, "build_number")) {
      extra$build_number <- val
    } else if (identical(lkey, "track_features")) {
      extra$track_features <- ms_split_features(val)
    } else if (lkey %in% c("fn", "filename")) {
      extra$filename <- val
    } else if (identical(lkey, "md5")) {
      extra$md5 <- val
    } else if (identical(lkey, "sha256")) {
      extra$sha256 <- val
    } else if (identical(lkey, "license")) {
      extra$license <- val
    } else if (identical(lkey, "license_family")) {
      extra$license_family <- val
    } else if (identical(lkey, "features")) {
      extra$features <- val
    } else if (identical(lkey, "optional")) {
      extra$optional <- TRUE
    }
  }

  # 4. Split name, version, build from remaining positional spec
  remaining <- trimws(remaining)
  nvb <- ms_split_name_version_build(remaining)

  pkg_name <- nvb$name
  pos_version <- nvb$version
  pos_build <- nvb$build

  if (identical(pkg_name, "")) {
    cli::cli_abort(
      message = c(
        `x` = "Invalid MatchSpec: Empty package name."
      ),
      class = "condathis_parse_match_spec_invalid_name"
    )
  }

  # 5. Set final values: bracket overrides positional, except name
  if (!rlang::is_null(bracket_version)) {
    final_version <- bracket_version
  } else {
    final_version <- pos_version
  }

  if (!rlang::is_null(bracket_build)) {
    final_build <- bracket_build
  } else {
    final_build <- pos_build
  }

  # Normalize version and build
  version_spec <- ms_normalize_version(final_version)
  build_spec <- ms_normalize_build(final_build)

  # Determine extra_platforms: if subdir was set without a channel, it goes

  # to extra_platforms
  extra_platforms <- NULL
  if (
    rlang::is_null(channel_location) &&
      !rlang::is_null(channel_pf) &&
      isTRUE(length(channel_pf) > 0L)
  ) {
    extra_platforms <- channel_pf
    channel_pf <- NULL
  }

  ms_make_result(
    name = pkg_name,
    name_space = name_space,
    channel_location = channel_location,
    channel_platform_filters = channel_pf,
    version = version_spec,
    build_string = build_spec,
    extra_platforms = extra_platforms,
    extra = extra
  )
}


# =============================================================================
# Internal: Result construction and formatting
# =============================================================================

#' Build the result list with canonical formatting
#'
#' @keywords internal
#' @noRd
ms_make_result <- function(
  name,
  name_space,
  channel_location,
  channel_platform_filters,
  version,
  build_string,
  extra_platforms,
  extra
) {
  # Format canonical string
  formatted_spec <- ms_format_canonical(
    name = name,
    name_space = name_space,
    channel_location = channel_location,
    channel_platform_filters = channel_platform_filters,
    version = version,
    build_string = build_string,
    extra_platforms = extra_platforms,
    extra = extra
  )

  # Format channel output
  if (!rlang::is_null(channel_location)) {
    pf <- channel_platform_filters
    if (rlang::is_null(pf)) {
      pf <- base::character(0L)
    }
    channel_str <- ms_format_channel_display(channel_location, pf)
    channel_location_str <- channel_location
    channel_pf_str <- ms_format_python_set(pf)
  } else {
    channel_str <- "None"
    channel_location_str <- "None"
    channel_pf_str <- "None"
  }

  # Determine platforms display
  if (
    !rlang::is_null(channel_location) &&
      !rlang::is_null(channel_platform_filters) &&
      isTRUE(length(channel_platform_filters) > 0L)
  ) {
    platforms_str <- ms_format_python_set(channel_platform_filters)
  } else if (
    !rlang::is_null(extra_platforms) &&
      isTRUE(length(extra_platforms) > 0L)
  ) {
    platforms_str <- ms_format_python_set(extra_platforms)
  } else {
    platforms_str <- "None"
  }

  # Format track_features
  # When ExtraMembers is allocated (md5, sha256, etc. are set),
  # track_features becomes set() instead of None
  has_extra_members <- !rlang::is_null(extra$md5) ||
    !rlang::is_null(extra$sha256) ||
    !rlang::is_null(extra$license) ||
    !rlang::is_null(extra$license_family) ||
    !rlang::is_null(extra$features) ||
    !rlang::is_null(extra$filename) ||
    isTRUE(extra$optional)

  if (
    !rlang::is_null(extra$track_features) &&
      isTRUE(length(extra$track_features) > 0L)
  ) {
    track_features_str <- ms_format_python_set(extra$track_features)
  } else if (has_extra_members) {
    track_features_str <- "set()"
  } else {
    track_features_str <- "None"
  }

  list(
    formatted_spec = formatted_spec,
    name = name,
    name_space = name_space,
    channel = channel_str,
    channel_location = channel_location_str,
    channel_platform_filters = channel_pf_str,
    version = version,
    build_string = build_string,
    platforms = platforms_str,
    track_features = track_features_str
  )
}


#' Format a Python-style set string
#'
#' @keywords internal
#' @noRd
ms_format_python_set <- function(items) {
  if (rlang::is_null(items) || identical(length(items), 0L)) {
    return("set()")
  }
  items <- sort(items)
  if (identical(length(items), 1L)) {
    return(paste0("{'", items, "'}"))
  }

  inner <- paste0("'", items, "'", collapse = ", ")
  paste0("{", inner, "}")
}


#' Format channel string with platform filters for display
#'
#' @keywords internal
#' @noRd
ms_format_channel_display <- function(location, platform_filters) {
  if (rlang::is_null(location)) {
    return("None")
  }
  if (
    !rlang::is_null(platform_filters) &&
      isTRUE(length(platform_filters) > 0L)
  ) {
    pf_str <- paste(sort(platform_filters), collapse = ",")
    return(paste0(location, "[", pf_str, "]"))
  }
  return(location)
}


# =============================================================================
# Internal: Canonical formatting (matches libmamba's fmt::formatter)
# =============================================================================

#' Generate canonical string representation matching libmamba
#'
#' @keywords internal
#' @noRd
ms_format_canonical <- function(
  name,
  name_space,
  channel_location,
  channel_platform_filters,
  version,
  build_string,
  extra_platforms,
  extra
) {
  out <- ""

  # Channel prefix: channel:namespace:name
  if (!rlang::is_null(channel_location)) {
    chan_str <- ms_format_channel_display(
      channel_location,
      channel_platform_filters
    )
    out <- paste0(out, chan_str, ":")
    if (!rlang::is_null(name_space)) {
      out <- paste0(out, name_space)
    }
    out <- paste0(out, ":")
  } else if (!rlang::is_null(name_space) && nchar(name_space) > 0L) {
    out <- paste0(out, name_space, ":")
  }

  # Name
  out <- paste0(out, name)

  # Determine complexity of version and build
  is_free_version <- rlang::is_null(version) ||
    identical(version, "") ||
    identical(version, "=*")
  is_free_build <- rlang::is_null(build_string) ||
    identical(build_string, "") ||
    identical(build_string, "*")
  is_exact_build <- !is_free_build && !grepl("\\*", build_string)

  is_complex_version <- ms_is_complex_version(version)
  is_complex_build <- !is_free_build && !is_exact_build

  if (!is_complex_version && !is_complex_build) {
    # Simple: write positionally
    if (!is_free_build) {
      out <- paste0(out, version, "=", build_string)
    } else if (!is_free_version) {
      out <- paste0(out, version)
    }
  }

  # Bracket attributes
  bracket_parts <- character(0L)

  if (is_complex_version || is_complex_build) {
    if (!is_free_version) {
      bracket_parts <- c(
        bracket_parts,
        paste0("version=\"", version, "\"")
      )
    }
    if (!is_free_build) {
      bracket_parts <- c(
        bracket_parts,
        paste0("build=\"", build_string, "\"")
      )
    }
  }

  if (!rlang::is_null(extra$build_number)) {
    bracket_parts <- c(
      bracket_parts,
      paste0("build_number=\"", extra$build_number, "\"")
    )
  }

  if (
    !rlang::is_null(extra$track_features) &&
      isTRUE(length(extra$track_features) > 0L)
  ) {
    tf_str <- paste(sort(extra$track_features), collapse = " ")
    bracket_parts <- c(
      bracket_parts,
      paste0("track_features=\"", tf_str, "\"")
    )
  }

  if (!rlang::is_null(extra$features) && nchar(extra$features) > 0L) {
    q <- ms_find_needed_quote(extra$features)
    bracket_parts <- c(
      bracket_parts,
      paste0("features=", q, extra$features, q)
    )
  }

  if (!rlang::is_null(extra$filename) && nchar(extra$filename) > 0L) {
    q <- ms_find_needed_quote(extra$filename)
    bracket_parts <- c(
      bracket_parts,
      paste0("fn=", q, extra$filename, q)
    )
  }

  if (!rlang::is_null(extra$md5) && nchar(extra$md5) > 0L) {
    bracket_parts <- c(bracket_parts, paste0("md5=", extra$md5))
  }

  if (!rlang::is_null(extra$sha256) && nchar(extra$sha256) > 0L) {
    bracket_parts <- c(bracket_parts, paste0("sha256=", extra$sha256))
  }

  if (!rlang::is_null(extra$license) && nchar(extra$license) > 0L) {
    bracket_parts <- c(bracket_parts, paste0("license=", extra$license))
  }

  if (
    !rlang::is_null(extra$license_family) && nchar(extra$license_family) > 0L
  ) {
    bracket_parts <- c(
      bracket_parts,
      paste0("license_family=", extra$license_family)
    )
  }

  if (isTRUE(extra$optional)) {
    bracket_parts <- c(bracket_parts, "optional")
  }

  if (length(bracket_parts) > 0L) {
    out <- paste0(out, "[", paste(bracket_parts, collapse = ","), "]")
  }

  return(out)
}


#' Check if a version spec is complex (expression_size > 1)
#'
#' @keywords internal
#' @noRd
ms_is_complex_version <- function(version) {
  if (
    rlang::is_null(version) ||
      identical(version, "") ||
      identical(version, "=*")
  ) {
    return(FALSE)
  }
  # Complex if it contains comma, pipe, or parentheses
  if (isTRUE(grepl("[,|()]", version))) {
    return(TRUE)
  }
  return(FALSE)
}


#' Find needed quote character for a value
#'
#' @keywords internal
#' @noRd
ms_find_needed_quote <- function(data) {
  if (isTRUE(grepl("[ =\"]", data))) {
    if (isTRUE(grepl("\"", data, fixed = TRUE))) {
      return("'")
    }
    return("\"")
  }
  return("")
}


# =============================================================================
# Internal: Channel/namespace/spec splitting
# =============================================================================

#' Split channel:namespace:spec using single colon separator
#'
#' Scans from right to left for `:` that is not inside brackets/quotes.
#'
#' In `conda-forge::numpy`, `::` means channel=`conda-forge`,
#' namespace=`` (empty), spec=`numpy`.
#'
#' In `conda-forge:ns:numpy`, channel=`conda-forge`, namespace=`ns`,
#' spec=`numpy`.
#'
#' @param str The full MatchSpec string
#' @returns list(channel, namespace, spec)
#'
#' @keywords internal
#' @noRd
ms_split_channel_namespace_spec <- function(str) {
  # Find rightmost colon not inside brackets/quotes
  spec_pos <- ms_rfind_colon_outside_brackets(str)

  if (rlang::is_null(spec_pos)) {
    # No colon found - entire string is the spec
    return(list(channel = NULL, namespace = "", spec = str))
  }

  spec_part <- substring(str, spec_pos + 1L)
  left_part <- substring(str, 1L, spec_pos - 1L)

  # Now find the next colon from right in the left part
  ns_pos <- ms_rfind_colon_outside_brackets(left_part)

  if (rlang::is_null(ns_pos)) {
    # Only one colon: left_part is namespace (per libmamba: first rfind gives
    # namespace when there's only one separator)
    return(list(channel = NULL, namespace = left_part, spec = spec_part))
  }

  # Two colons found: channel:namespace:spec
  channel_part <- substring(left_part, 1L, ns_pos - 1L)
  namespace_part <- substring(left_part, ns_pos + 1L)

  # If channel_part is empty, treat as no channel
  if (identical(channel_part, "")) {
    channel_part <- NULL
  }

  return(list(
    channel = channel_part,
    namespace = namespace_part,
    spec = spec_part
  ))
}


#' Find the rightmost colon not inside brackets or quotes
#'
#' @keywords internal
#' @noRd
ms_rfind_colon_outside_brackets <- function(str) {
  if (rlang::is_null(str) || identical(str, "")) {
    return(NULL)
  }

  chars <- strsplit(str, "")[[1]]
  n <- length(chars)
  depth <- 0L

  for (i in seq(n, 1L)) {
    ch <- chars[i]
    if (ch %in% c("]", ")")) {
      depth <- depth + 1L
    } else if (ch %in% c("[", "(")) {
      depth <- depth - 1L
    } else if (identical(ch, ":") && identical(depth, 0L)) {
      return(i)
    }
  }

  return(NULL)
}


# =============================================================================
# Internal: Channel parsing
# =============================================================================

#' Parse channel string into location and platform_filters
#'
#' Handles formats like:
#' - `"conda-forge"` -> location=`"conda-forge"`, filters=empty
#' - `"conda-forge/linux-64"` -> location=`"conda-forge"`, filters=`{"linux-64"}`
#' - `"conda-forge[linux-64]"` -> location=`"conda-forge"`, filters=`{"linux-64"}`
#' - `"*"` -> location=`"*"`, filters=empty
#'
#' @keywords internal
#' @noRd
ms_parse_channel <- function(str) {
  str <- trimws(str)

  if (identical(str, "") || identical(tolower(str), "<unknown>")) {
    return(list(location = "*", platform_filters = character(0L)))
  }

  # Check for bracket-style platform filters: "conda-forge[linux-64,noarch]"
  if (isTRUE(grepl("\\]$", str))) {
    bracket_start <- as.integer(base::regexpr("\\[", str))
    if (isTRUE(bracket_start > 0L)) {
      location <- trimws(base::substring(str, 1L, bracket_start - 1L))
      plat_str <- base::substring(str, bracket_start + 1L, nchar(str) - 1L)
      filters <- ms_parse_platform_list(plat_str)
      return(list(location = location, platform_filters = filters))
    }
  }

  # Check for slash-style platform: "conda-forge/linux-64"
  # Only if the part after the LAST slash is a known platform
  if (isTRUE(grepl("/", str, fixed = TRUE))) {
    slash_pos <- as.integer(base::regexpr("/[^/]+$", str))
    if (isTRUE(slash_pos > 0L)) {
      potential_plat <- base::substring(str, slash_pos + 1L)
      if (ms_is_known_platform(potential_plat)) {
        location <- base::substring(str, 1L, slash_pos - 1L)
        return(list(
          location = location,
          platform_filters = potential_plat
        ))
      }
    }
  }

  # Plain channel name or URL
  return(
    list(
      location = str,
      platform_filters = character(0L)
    )
  )
}


#' Parse a comma/pipe separated list of platforms
#'
#' @keywords internal
#' @noRd
ms_parse_platform_list <- function(str) {
  parts <- strsplit(str, "[,|;]")[[1]]
  parts <- trimws(parts)
  parts <- parts[nchar(parts) > 0L]
  tolower(parts)
}


#' Check if a string is a known conda platform/subdir
#'
#' @keywords internal
#' @noRd
ms_is_known_platform <- function(str) {
  known <- c(
    "noarch",
    "linux-32",
    "linux-64",
    "linux-aarch64",
    "linux-armv6l",
    "linux-armv7l",
    "linux-ppc64",
    "linux-ppc64le",
    "linux-s390x",
    "linux-riscv32",
    "linux-riscv64",
    "osx-64",
    "osx-arm64",
    "win-32",
    "win-64",
    "win-arm64",
    "zos-z"
  )
  tolower(str) %in% known
}


#' Split features string into a character vector
#'
#' @keywords internal
#' @noRd
ms_split_features <- function(str) {
  parts <- strsplit(str, "[ ,;]+")[[1]]
  parts <- trimws(parts)
  parts[nchar(parts) > 0L]
}


# =============================================================================
# Internal: Bracket attribute parsing
# =============================================================================

#' Parse and strip bracket attributes from right to left
#'
#' Handles both `[key=val,...]` and `(key=val,...)` sections.
#' Multiple bracket sections are parsed from right to left.
#'
#' @param str The spec string potentially containing brackets
#' @returns list(remaining, attributes)
#'
#' @keywords internal
#' @noRd
ms_rparse_brackets <- function(str) {
  attributes <- list()

  repeat {
    str <- trimws(str)
    if (isFALSE(nzchar(str))) {
      break
    }
    last_char <- substring(str, nchar(str))

    if (identical(last_char, "]")) {
      pos <- ms_rfind_matching_bracket(str, "[", "]")
      if (rlang::is_null(pos)) {
        break
      }
      bracket_content <- substring(str, pos + 1L, nchar(str) - 1L)
      str <- substring(str, 1L, pos - 1L)
      new_attrs <- ms_parse_bracket_content(bracket_content)
      for (key in names(new_attrs)) {
        if (rlang::is_null(attributes[[key]])) {
          attributes[[key]] <- new_attrs[[key]]
        }
      }
    } else if (identical(last_char, ")")) {
      pos <- ms_rfind_matching_bracket(str, "(", ")")
      if (rlang::is_null(pos)) {
        break
      }
      bracket_content <- substring(str, pos + 1L, nchar(str) - 1L)
      str <- substring(str, 1L, pos - 1L)
      new_attrs <- ms_parse_bracket_content(bracket_content)
      for (key in names(new_attrs)) {
        if (rlang::is_null(attributes[[key]])) {
          attributes[[key]] <- new_attrs[[key]]
        }
      }
    } else {
      break
    }
  }

  # Strip trailing "=" (handles "libblas=[build=*mkl]")
  str <- sub("=+$", "", str)

  list(remaining = trimws(str), attributes = attributes)
}


#' Find matching opening bracket from the end
#'
#' @keywords internal
#' @noRd
ms_rfind_matching_bracket <- function(str, open, close) {
  chars <- strsplit(str, "")[[1]]
  n <- length(chars)
  depth <- 0L

  for (i in seq(n, 1L)) {
    if (identical(chars[i], close)) {
      depth <- depth + 1L
    } else if (identical(chars[i], open)) {
      depth <- depth - 1L
      if (identical(depth, 0L)) {
        return(i)
      }
    }
  }
  return(NULL)
}


#' Parse bracket content into key=value pairs
#'
#' @keywords internal
#' @noRd
ms_parse_bracket_content <- function(content) {
  attrs <- list()

  pairs <- ms_split_bracket_pairs(content)

  for (pair in pairs) {
    pair <- trimws(pair)
    if (identical(pair, "")) {
      next
    }

    # Split on first "="
    eq_pos <- as.integer(base::regexpr("=", pair, fixed = TRUE))
    if (isTRUE(eq_pos > 0L)) {
      key <- trimws(base::substring(pair, 1L, eq_pos - 1L))
      val <- trimws(base::substring(pair, eq_pos + 1L))
      val <- ms_strip_quotes(val)
      attrs[[tolower(key)]] <- val
    } else {
      # Bare keyword like "optional"
      attrs[[tolower(pair)]] <- "true"
    }
  }

  return(attrs)
}


#' Split bracket content by commas, respecting quotes and parentheses
#'
#' @keywords internal
#' @noRd
ms_split_bracket_pairs <- function(str) {
  result <- character(0L)
  current <- ""
  in_single_quote <- FALSE
  in_double_quote <- FALSE
  paren_depth <- 0L

  chars <- strsplit(str, "")[[1]]
  for (ch in chars) {
    if (identical(ch, "'") && !in_double_quote) {
      in_single_quote <- !in_single_quote
      current <- paste0(current, ch)
    } else if (identical(ch, "\"") && !in_single_quote) {
      in_double_quote <- !in_double_quote
      current <- paste0(current, ch)
    } else if (identical(ch, "(") && !in_single_quote && !in_double_quote) {
      paren_depth <- paren_depth + 1L
      current <- paste0(current, ch)
    } else if (identical(ch, ")") && !in_single_quote && !in_double_quote) {
      paren_depth <- paren_depth - 1L
      current <- paste0(current, ch)
    } else if (
      identical(ch, ",") &&
        !in_single_quote &&
        !in_double_quote &&
        identical(paren_depth, 0L)
    ) {
      result <- c(result, current)
      current <- ""
    } else {
      current <- paste0(current, ch)
    }
  }

  if (isTRUE(nchar(current) > 0L)) {
    result <- c(result, current)
  }

  return(result)
}


#' Strip surrounding quotes from a string
#'
#' @keywords internal
#' @noRd
ms_strip_quotes <- function(str) {
  if (isTRUE(nchar(str) >= 2L)) {
    first <- substring(str, 1L, 1L)
    last <- substring(str, nchar(str))
    if (
      (identical(first, "'") && identical(last, "'")) ||
        (identical(first, "\"") && identical(last, "\""))
    ) {
      return(substring(str, 2L, nchar(str) - 1L))
    }
  }
  return(str)
}


# =============================================================================
# Internal: Name/version/build splitting
# =============================================================================

#' Split name, version, and build from spec string
#'
#' Follows libmamba's split_name_version_and_build logic.
#' Package name ends at first version separator character.
#'
#' @keywords internal
#' @noRd
ms_split_name_version_build <- function(str) {
  # base::browser()
  str <- trimws(str)

  if (identical(str, "")) {
    return(list(name = "", version = NULL, build = NULL))
  }

  # Find where package name ends: first char in " <>=!~"
  sep_pattern <- "[ <>=!~]"
  match_pos <- as.integer(base::regexpr(sep_pattern, str, perl = TRUE))

  if (identical(match_pos, -1L)) {
    return(list(name = str, version = NULL, build = NULL))
  }

  pkg_name <- base::substring(str, 1L, match_pos - 1L)
  ver_build_str <- base::substring(str, match_pos)

  vb <- ms_split_version_and_build(ver_build_str)

  list(name = pkg_name, version = vb$version, build = vb$build)
}


#' Split version and build string
#'
#' Follows libmamba's split_version_and_build exactly:
#' 1. Strip whitespace
#' 2. Strip trailing `=`
#' 3. Find last `=` or space position
#' 4. If last `=` is preceded by an operator char, it's not a build separator
#'
#' @keywords internal
#' @noRd
ms_split_version_and_build <- function(str) {
  str <- trimws(str)

  if (identical(str, "")) {
    return(list(version = NULL, build = NULL))
  }

  # Strip trailing = (handles faulty specs like "libblas=")
  str <- sub("=+$", "", str)

  if (identical(str, "")) {
    return(list(version = NULL, build = NULL))
  }

  # Find last position of space or =
  last_sp_eq <- ms_find_last_of(str, c(" ", "="))

  if (rlang::is_null(last_sp_eq) || isTRUE(last_sp_eq <= 1L)) {
    return(list(version = str, build = NULL))
  }

  # Find last = position
  last_eq <- ms_find_last_of(str, "=")

  if (rlang::is_null(last_eq)) {
    # No = found - check for space-separated build
    last_space <- ms_find_last_of(str, " ")
    if (!rlang::is_null(last_space)) {
      version_part <- trimws(base::substring(str, 1L, last_space - 1L))
      build_part <- base::substring(str, last_space + 1L)
      return(list(version = version_part, build = build_part))
    }
    return(list(version = str, build = NULL))
  }

  # Check char before last =
  prev_char <- base::substring(str, last_eq - 1L, last_eq - 1L)
  if (prev_char %in% c("=", "!", "|", ",", "<", ">", "~")) {
    # The = is part of an operator, not a build separator
    # Look for space-separated build:
    # Find first non-space after operator (version start)
    after_op <- base::substring(str, last_eq + 1L)
    version_start_pos <- as.integer(base::regexpr("[^ ]", after_op))
    if (isTRUE(version_start_pos > 0L)) {
      rest_after_version_start <- base::substring(after_op, version_start_pos)
      space_in_rest <- as.integer(
        base::regexpr(" ", rest_after_version_start, fixed = TRUE)
      )
      if (isTRUE(space_in_rest > 0L)) {
        # There's something after a space -> that's the build
        abs_space <- last_eq + version_start_pos - 1L + space_in_rest - 1L
        version_part <- trimws(base::substring(str, 1L, abs_space))
        build_start_pos <- abs_space + 1L
        build_part <- trimws(base::substring(str, build_start_pos))
        if (isTRUE(nchar(build_part) > 0L)) {
          return(list(version = version_part, build = build_part))
        }
      }
    }
    return(list(version = str, build = NULL))
  }

  # = is a build separator
  version_part <- base::substring(str, 1L, last_eq - 1L)
  build_part <- trimws(base::substring(str, last_eq + 1L))

  if (identical(build_part, "")) {
    return(list(version = version_part, build = NULL))
  }

  return(list(version = version_part, build = build_part))
}


#' Find last position of any character in chars within str
#'
#' @keywords internal
#' @noRd
ms_find_last_of <- function(str, chars) {
  n <- nchar(str)
  str_chars <- strsplit(str, "")[[1]]

  for (i in seq(n, 1L)) {
    if (str_chars[i] %in% chars) {
      return(i)
    }
  }
  return(NULL)
}


# =============================================================================
# Internal: Version normalization
# =============================================================================

#' Normalize version string to match libmamba VersionSpec representation
#'
#' CEP 29 semantics:
#' - Space-separated bare version is exact: `"1.8"` -> `"==1.8"`
#' - `"="` prefix is fuzzy: `"=1.8"` stays `"=1.8"`
#' - `"=="` prefix is exact: `"==1.8"` stays `"==1.8"`
#' - Trailing `".*"` on fuzzy versions is stripped: `"=1.8.*"` -> `"=1.8"`
#' - Trailing `"*"` with no dot: `"1.8*"` -> `"=1.8"` (fuzzy)
#' - `"*"` alone is free: `"=*"`
#'
#' @keywords internal
#' @noRd
ms_normalize_version <- function(version) {
  if (rlang::is_null(version) || identical(trimws(version), "")) {
    return("=*")
  }

  ver <- trimws(version)

  # Free version
  if (identical(ver, "*") || identical(ver, "=*")) {
    return("=*")
  }

  # Compound expression: contains comma or pipe
  # Must be handled before simple atom rules
  if (grepl("[,|]", ver)) {
    return(ms_normalize_compound_version(ver))
  }

  # Strip trailing .* from fuzzy versions: "=1.8.*" -> "=1.8"
  if (grepl("^=([^=])", ver) && grepl("\\.\\*$", ver)) {
    ver <- sub("\\.\\*$", "", ver)
    return(ver)
  }

  # Handle trailing * without dot on fuzzy: "=1.8*" -> "=1.8"
  if (grepl("^=([^=]).*[^.]\\*$", ver)) {
    ver <- sub("\\*$", "", ver)
    return(ver)
  }

  # Handle bare version with trailing .*: "1.8.*" -> "=1.8" (fuzzy)
  if (!grepl("^[<>=!~]", ver) && grepl("\\.\\*$", ver)) {
    ver <- sub("\\.\\*$", "", ver)
    return(paste0("=", ver))
  }

  # Handle bare version with trailing *: "1.8*" -> "=1.8" (fuzzy)
  if (!grepl("^[<>=!~]", ver) && grepl("\\*$", ver) && !identical(ver, "*")) {
    ver <- sub("\\*$", "", ver)
    # Remove trailing dot if present
    ver <- sub("\\.$", "", ver)
    return(paste0("=", ver))
  }

  # Bare version literal without any operator -> exact match
  if (!grepl("^[<>=!~,|()]", ver) && !grepl("\\*", ver)) {
    return(paste0("==", ver))
  }

  return(ver)
}


#' Normalize a compound version expression (contains , or |)
#'
#' Splits by comma (AND), then by pipe (OR) within each group.
#' Bare version atoms get == prefix. Pipe groups get parenthesized
#' when there are multiple AND groups.
#'
#'
#' @keywords internal
#' @noRd
ms_normalize_compound_version <- function(ver) {
  # Split by comma (top-level AND)
  and_groups <- strsplit(ver, ",")[[1]]
  n_and <- length(and_groups)

  normalized_groups <- vapply(
    and_groups,
    function(group) {
      group <- trimws(group)

      # Split by pipe (OR within group)
      or_atoms <- strsplit(group, "\\|")[[1]]
      or_atoms <- trimws(or_atoms)

      # Normalize each atom
      normalized_atoms <- vapply(
        or_atoms,
        function(atom) {
          ms_normalize_version_atom(atom)
        },
        character(1L),
        USE.NAMES = FALSE
      )

      or_result <- paste(normalized_atoms, collapse = "|")

      # Parenthesize if this OR group is part of a multi-AND expression
      if (isTRUE(n_and > 1L) && isTRUE(length(or_atoms) > 1L)) {
        or_result <- paste0("(", or_result, ")")
      }

      or_result
    },
    character(1L),
    USE.NAMES = FALSE
  )

  paste(normalized_groups, collapse = ",")
}


#' Normalize a single version atom (no comma or pipe)
#'
#' @keywords internal
#' @noRd
ms_normalize_version_atom <- function(atom) {
  atom <- trimws(atom)

  if (identical(atom, "") || identical(atom, "*")) {
    return("=*")
  }

  # Already has operator prefix -> return as-is
  if (grepl("^[<>=!~]", atom)) {
    # Strip trailing .* for fuzzy
    if (grepl("^=([^=])", atom) && grepl("\\.\\*$", atom)) {
      return(sub("\\.\\*$", "", atom))
    }
    return(atom)
  }

  # Bare version with trailing .*: "1.8.*" -> "=1.8"
  if (grepl("\\.\\*$", atom)) {
    return(paste0("=", sub("\\.\\*$", "", atom)))
  }

  # Bare version with trailing *: "1.8*" -> "=1.8"
  if (grepl("\\*$", atom)) {
    cleaned <- sub("\\*$", "", atom)
    cleaned <- sub("\\.$", "", cleaned)
    return(paste0("=", cleaned))
  }

  # Bare version literal -> exact match
  return(paste0("==", atom))
}


#' Normalize build string
#'
#' @keywords internal
#' @noRd
ms_normalize_build <- function(build) {
  if (rlang::is_null(build) || identical(trimws(build), "")) {
    return("*")
  }
  return(trimws(build))
}


# =============================================================================
# Internal: URL parsing
# =============================================================================

#' Parse a URL-style MatchSpec (archive URL)
#'
#' @keywords internal
#' @noRd
ms_parse_url <- function(url) {
  # Extract filename from URL
  parts <- strsplit(url, "/")[[1]]
  filename <- parts[length(parts)]

  # Strip archive extension
  pkg_str <- sub("\\.(tar\\.bz2|conda)$", "", filename)

  # Split by '-' from right: name-version-build
  last_dash <- ms_find_last_of(pkg_str, "-")
  if (rlang::is_null(last_dash)) {
    cli::cli_abort(
      message = c(
        `x` = "Invalid archive URL: cannot parse filename."
      ),
      class = "condathis_parse_match_spec_invalid_url"
    )
  }
  build_str <- substring(pkg_str, last_dash + 1L)
  rest <- substring(pkg_str, 1L, last_dash - 1L)

  second_last_dash <- ms_find_last_of(rest, "-")
  if (rlang::is_null(second_last_dash)) {
    cli::cli_abort(
      message = c(
        `x` = "Invalid archive URL: cannot parse name and version."
      ),
      class = "condathis_parse_match_spec_invalid_url"
    )
  }
  ver_str <- substring(rest, second_last_dash + 1L)
  name_str <- substring(rest, 1L, second_last_dash - 1L)

  # Parse channel from the URL prefix
  ch <- ms_parse_channel(url)

  ms_make_result(
    name = name_str,
    name_space = "",
    channel_location = ch$location,
    channel_platform_filters = ch$platform_filters,
    version = paste0("==", ver_str),
    build_string = build_str,
    extra_platforms = NULL,
    extra = list()
  )
}
