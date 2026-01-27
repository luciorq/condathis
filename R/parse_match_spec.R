#' Parse a Conda MatchSpec String
#'
#' Parses a string representation of a Conda package specification into its
#' constituent parts (channel, name, version, build, etc.).
#'
#' This implementation follows the libmamba MatchSpec parser specification.
#' See: https://github.com/mamba-org/mamba/blob/main/libmamba/src/specs/match_spec.cpp
#'
#' @param spec_string A character string containing the MatchSpec
#' (e.g., "numpy>=1.11", "conda-forge::python=3.9").
#'
#' @returns A named list containing `channel`, `subdir`, `namespace`, `name`, `version`, `version_min`, `version_max`, and `build`.
#'         Empty fields are returned as NULL.
#'
#' @export
parse_match_spec <- function(spec_string) {
  if (rlang::is_null(spec_string) || identical(spec_string, "")) {
    cli::cli_abort(
      message = c(
        `x` = "MatchSpec string cannot be empty."
      ),
      class = "condathis_parse_match_spec_empty_string"
    )
  }

  # Initialize default structure
  match_spec_list <- list(
    channel = NULL,
    subdir = NULL,
    namespace = NULL,
    name = NULL,
    version = NULL,
    version_min = NULL,
    version_max = NULL,
    build = NULL
  )

  # Trim whitespace
  raw_spec <- trimws(spec_string)

  if (identical(raw_spec, "")) {
    cli::cli_abort(
      message = c(
        `x` = "MatchSpec string cannot be empty."
      ),
      class = "condathis_parse_match_spec_empty_string"
    )
  }

  # Remove comments (everything after " #")
  if (grepl(" #", raw_spec, fixed = TRUE)) {
    raw_spec <- sub(" #.*$", "", raw_spec)
  }

  # 1. Split channel::namespace::spec
  # We look for "::" from right to left
  split_result <- .split_channel_namespace_spec(raw_spec)
  match_spec_list$channel <- split_result$channel
  match_spec_list$namespace <- split_result$namespace
  remaining_spec <- split_result$spec

  # Handle channel/subdir format (e.g., "conda-forge/linux-64")
  if (
    !rlang::is_null(match_spec_list$channel) &&
      grepl("/", match_spec_list$channel, fixed = TRUE)
  ) {
    chan_sub <- strsplit(match_spec_list$channel, "/", fixed = TRUE)[[1]]
    match_spec_list$channel <- chan_sub[1]
    match_spec_list$subdir <- chan_sub[2]
  }

  # 2. Parse bracket attributes [key=val, ...] backwards
  bracket_result <- .parse_bracket_attributes(remaining_spec)
  remaining_spec <- bracket_result$remaining

  # Apply bracket attributes
  for (key in names(bracket_result$attributes)) {
    val <- bracket_result$attributes[[key]]
    if (key == "build" || key == "build_string") {
      if (rlang::is_null(match_spec_list$build)) {
        match_spec_list$build <- val
      }
    } else if (key == "version") {
      if (rlang::is_null(match_spec_list$version)) {
        match_spec_list$version <- val
      }
    } else if (key == "channel" || key == "url") {
      if (rlang::is_null(match_spec_list$channel)) {
        match_spec_list$channel <- val
      }
    } else if (key == "subdir") {
      if (rlang::is_null(match_spec_list$subdir)) {
        match_spec_list$subdir <- val
      }
    }
  }

  # 3. Split name, version, and build from remaining string
  name_ver_build <- .split_name_version_build(remaining_spec)

  if (identical(name_ver_build$name, "")) {
    cli::cli_abort(
      message = c(
        `x` = "Invalid MatchSpec: Empty package name."
      ),
      class = "condathis_parse_match_spec_invalid_name"
    )
  }

  match_spec_list$name <- name_ver_build$name

  # Only set version if not already set from brackets

  if (
    rlang::is_null(match_spec_list$version) &&
      !rlang::is_null(name_ver_build$version) &&
      name_ver_build$version != ""
  ) {
    match_spec_list$version <- name_ver_build$version
  }

  # Only set build if not already set from brackets
  if (
    rlang::is_null(match_spec_list$build) &&
      !rlang::is_null(name_ver_build$build) &&
      name_ver_build$build != ""
  ) {
    match_spec_list$build <- name_ver_build$build
  }

  # 4. Calculate version_min and version_max
  if (!rlang::is_null(match_spec_list$version)) {
    bounds <- .calculate_version_bounds(match_spec_list$version)
    match_spec_list$version_min <- bounds$min
    match_spec_list$version_max <- bounds$max
  }

  return(match_spec_list)
}

#' Split channel, namespace, and spec from a MatchSpec string
#'
#' Looks for "::" separators from right to left to split:
#' - channel::namespace::spec
#' - channel::spec (namespace is channel)
#' - spec (no channel/namespace)
#'
#' @param str The MatchSpec string
#' @returns list(channel=..., namespace=..., spec=...)
#' @keywords internal
#' @noRd
.split_channel_namespace_spec <- function(str) {
  channel <- NULL
  namespace <- NULL
  spec <- str

  # Find the rightmost "::"
  if (grepl("::", str, fixed = TRUE)) {
    # Split by "::" - we need to handle multiple "::" from right to left
    parts <- strsplit(str, "::", fixed = TRUE)[[1]]

    if (length(parts) == 2) {
      # channel::spec
      channel <- parts[1]
      spec <- parts[2]
    } else if (length(parts) >= 3) {
      # channel:namespace::spec or channel/subdir:namespace::spec
      # The last part is always the spec
      spec <- parts[length(parts)]

      # Check if first part contains ":" for namespace
      left_side <- paste(parts[-length(parts)], collapse = "::")

      if (
        grepl(":", left_side, fixed = TRUE) &&
          !grepl("://", left_side, fixed = TRUE)
      ) {
        # Has namespace separator (but not URL)
        ns_parts <- strsplit(left_side, ":", fixed = TRUE)[[1]]
        channel <- ns_parts[1]
        namespace <- paste(ns_parts[-1], collapse = ":")
      } else {
        channel <- left_side
      }
    }
  }

  list(channel = channel, namespace = namespace, spec = spec)
}

#' Parse bracket attributes from a MatchSpec string
#'
#' Parses attributes in brackets (e.g., `[key=val, ...]`) from right to left.
#' Handles both square brackets and parentheses as per libmamba.
#'
#' @param str The string potentially containing brackets
#' @returns list(remaining=..., attributes=list(...))
#' @keywords internal
#' @noRd
.parse_bracket_attributes <- function(str) {
  attributes <- list()

  # Process brackets from right to left
  # Handle both [] and ()
  while (grepl("\\[[^\\[\\]]*\\]$|\\([^\\(\\)]*\\)$", str, perl = TRUE)) {
    # Extract bracket content
    if (grepl("\\]$", str)) {
      # Square brackets
      match <- regexpr("\\[([^\\[\\]]*)\\]$", str, perl = TRUE)
      if (match > 0) {
        bracket_content <- sub(".*\\[([^\\[\\]]*)\\]$", "\\1", str, perl = TRUE)
        str <- sub("\\[[^\\[\\]]*\\]$", "", str, perl = TRUE)
      }
    } else if (grepl("\\)$", str)) {
      # Parentheses
      match <- regexpr("\\(([^\\(\\)]*)\\)$", str, perl = TRUE)
      if (match > 0) {
        bracket_content <- sub(".*\\(([^\\(\\)]*)\\)$", "\\1", str, perl = TRUE)
        str <- sub("\\([^\\(\\)]*\\)$", "", str, perl = TRUE)
      }
    } else {
      break
    }

    # Parse key=value pairs
    pairs <- strsplit(bracket_content, ",", fixed = TRUE)[[1]]
    for (pair in pairs) {
      pair <- trimws(pair)
      if (grepl("=", pair, fixed = TRUE)) {
        kv <- strsplit(pair, "=", fixed = TRUE)[[1]]
        key <- tolower(trimws(kv[1]))
        val <- trimws(paste(kv[-1], collapse = "="))
        # Remove quotes
        val <- gsub("^['\"]|['\"]$", "", val)

        # Only set if not already set (first value wins when parsing right-to-left)
        if (rlang::is_null(attributes[[key]])) {
          attributes[[key]] <- val
        }
      } else if (nchar(pair) > 0) {
        # Boolean attribute (e.g., "optional")
        key <- tolower(pair)
        if (rlang::is_null(attributes[[key]])) {
          attributes[[key]] <- "true"
        }
      }
    }
  }

  # Strip trailing "=" which handles faulty specs like "libblas=[build=*mkl]"
  str <- sub("=+$", "", str)

  list(remaining = trimws(str), attributes = attributes)
}

#' Split name, version, and build from a spec string
#'
#' Handles formats like:
#' - "numpy" -> name only
#' - "numpy 1.8" -> name + version (space separated)
#' - "numpy>=1.8" -> name + version (operator attached)
#' - "numpy 1.8.1 py27_0" -> name + version + build (space separated)
#' - "numpy=1.8.1=py27_0" -> name + version + build (= separated)
#'
#' @param str The spec string
#' @returns list(name=..., version=..., build=...)
#' @keywords internal
#' @noRd
.split_name_version_build <- function(str) {
  str <- trimws(str)

  if (identical(str, "")) {
    return(list(name = "", version = NULL, build = NULL))
  }

  # Find where the package name ends
  # Package name ends at first version separator: space, <, >, =, !
  version_sep_pattern <- "[ <>=!]"
  match <- regexpr(version_sep_pattern, str, perl = TRUE)

  if (match == -1) {
    # No version separator, entire string is package name
    return(list(name = str, version = NULL, build = NULL))
  }

  pkg_name <- substring(str, 1, match - 1)
  version_and_build <- trimws(substring(str, match))

  # Split version and build
  ver_build <- .split_version_and_build(version_and_build)

  list(name = pkg_name, version = ver_build$version, build = ver_build$build)
}

#' Split version and build from a version+build string
#'
#' Follows libmamba's split_version_and_build logic:
#' - Strip trailing "="
#' - Handle space-separated version and build: ">=1.0 py27_0"
#' - Handle "="-separated version and build: "=1.8.1=py27_0"
#'
#' @param str The version+build string
#' @returns list(version=..., build=...)
#' @keywords internal
#' @noRd
.split_version_and_build <- function(str) {
  str <- trimws(str)

  # Strip trailing "=" (handles faulty specs like "libblas=[build=*mkl]")
  # But NOT if the version is just "=*" which means any version
  if (!grepl("^=\\*$", str)) {
    str <- sub("=+$", "", str)
  }

  if (identical(str, "") || rlang::is_null(str)) {
    return(list(version = NULL, build = NULL))
  }

  # Find last space or last "=" that's not part of an operator
  # First check for space-separated version and build

  # Find last "=" position
  last_eq_pos <- .find_last_build_separator(str)

  if (!rlang::is_null(last_eq_pos)) {
    # Check if the character before "=" is an operator character
    if (last_eq_pos > 1) {
      prev_char <- substring(str, last_eq_pos - 1, last_eq_pos - 1)
      if (prev_char %in% c("=", "!", "|", ",", "<", ">", "~")) {
        # This "=" is part of an operator, look for space-separated build
        space_result <- .split_by_trailing_space(str)
        return(space_result)
      }
    }

    # The "=" is a build separator
    version <- substring(str, 1, last_eq_pos - 1)
    build <- substring(str, last_eq_pos + 1)

    # Handle case where build is empty
    if (identical(trimws(build), "")) {
      return(list(version = version, build = NULL))
    }

    # Check if the "build" is actually just "*" for wildcard version like "=*"
    # In this case, the whole thing is the version, not version + build
    if (identical(version, "") && identical(trimws(build), "*")) {
      return(list(version = str, build = NULL))
    }

    return(list(version = version, build = trimws(build)))
  }

  # Check for space-separated version and build
  space_result <- .split_by_trailing_space(str)
  return(space_result)
}

#' Find the last "=" that could be a build separator
#'
#' Returns the position of the last "=" that is not part of an operator
#' (==, !=, <=, >=, ~=)
#'
#' @param str The string to search
#' @returns Position of the "=" or NULL
#' @keywords internal
#' @noRd
.find_last_build_separator <- function(str) {
  # Find all "=" positions
  eq_positions <- gregexpr("=", str, fixed = TRUE)[[1]]

  if (identical(eq_positions[1], -1L)) {
    return(NULL)
  }

  # Check from right to left for a standalone "="
  for (i in rev(seq_along(eq_positions))) {
    pos <- eq_positions[i]

    # Check character before
    if (pos > 1) {
      prev_char <- substring(str, pos - 1, pos - 1)
      if (prev_char %in% c("=", "!", "<", ">", "~")) {
        next
      }
    }

    # Check character after
    if (pos < nchar(str)) {
      next_char <- substring(str, pos + 1, pos + 1)
      if (next_char == "=") {
        next
      }
    }

    return(pos)
  }

  return(NULL)
}

#' Split version and build by trailing space
#'
#' @param str The string to split
#' @returns list(version=..., build=...)
#' @keywords internal
#' @noRd
.split_by_trailing_space <- function(str) {
  # Find the last space
  last_space <- .find_last_space_before_build(str)

  if (!rlang::is_null(last_space)) {
    version <- trimws(substring(str, 1, last_space - 1))
    build <- trimws(substring(str, last_space + 1))

    # Check if potential build contains version operators
    # If it does, it's part of the version, not a build
    if (grepl("[<>!=]", build)) {
      return(list(version = str, build = NULL))
    }

    return(list(version = version, build = build))
  }

  return(list(version = str, build = NULL))
}

#' Find the last space that separates version from build
#'
#' @param str The string to search
#' @returns Position of the space or NULL
#' @keywords internal
#' @noRd
.find_last_space_before_build <- function(str) {
  # Find all space positions
  space_positions <- gregexpr(" ", str, fixed = TRUE)[[1]]

  if (identical(space_positions[1], -1L)) {
    return(NULL)
  }

  # Return the last space position
  return(space_positions[length(space_positions)])
}

#' Calculate Version Min and Max
#'
#' Extracts the minimum and maximum version bounds from a version string.
#'
#' @param version_str The version string
#' @returns list(min=..., max=...)
#' @keywords internal
#' @noRd
.calculate_version_bounds <- function(version_str) {
  min_ver <- NULL
  max_ver <- NULL

  if (rlang::is_null(version_str) || identical(version_str, "")) {
    return(list(min = NULL, max = NULL))
  }

  # Handle free version spec
  if (version_str == "*" || version_str == "=*") {
    return(list(min = NULL, max = NULL))
  }

  # Check if this is an OR expression (|) - these don't have simple bounds
  if (grepl("\\|", version_str)) {
    return(list(min = NULL, max = NULL))
  }

  # Split version string into individual clauses
  # Need to handle cases like ">=1.8,<2" (comma-separated) and ">=1.8<2" (not separated)
  clauses <- .split_version_clauses(version_str)

  for (clause in clauses) {
    clause <- trimws(clause)
    if (identical(clause, "")) {
      next
    }

    # Parse operator and version from clause
    parsed <- .parse_version_clause(clause)
    op <- parsed$operator
    ver <- parsed$version

    if (rlang::is_null(ver) || identical(ver, "") || identical(ver, "*")) {
      next
    }

    if (!rlang::is_null(op)) {
      if (op %in% c(">=", ">")) {
        # Min bound
        if (rlang::is_null(min_ver) || ver > min_ver) {
          min_ver <- ver
        }
      } else if (op %in% c("<=", "<")) {
        # Max bound
        if (rlang::is_null(max_ver) || ver < max_ver) {
          max_ver <- ver
        }
      } else if (op %in% c("==", "=")) {
        # Exact match - set both min and max
        # Remove trailing "*" for exact matches like "=1.8*"
        clean_ver <- sub("\\*$", "", ver)
        if (grepl("\\*", clause) || grepl("\\*", ver)) {
          # Fuzzy match with glob - only set min
          min_ver <- clean_ver
        } else {
          min_ver <- clean_ver
          max_ver <- clean_ver
        }
        break
      }
    } else {
      # No operator - could be exact version or glob
      clean_ver <- sub("\\*$", "", ver)
      if (grepl("\\*", clause)) {
        # Glob - only min bound
        if (!identical(clean_ver, "")) {
          min_ver <- clean_ver
        }
      } else {
        # Exact version
        min_ver <- ver
        max_ver <- ver
        break
      }
    }
  }

  list(min = min_ver, max = max_ver)
}

#' Split version string into individual clauses
#'
#' Handles both comma-separated (>=1.8,<2) and non-separated (>=1.8<2) formats.
#'
#' @param version_str The version string
#' @returns Character vector of clauses
#' @keywords internal
#' @noRd
.split_version_clauses <- function(version_str) {
  # First try comma separation
  if (grepl(",", version_str, fixed = TRUE)) {
    return(strsplit(version_str, ",", fixed = TRUE)[[1]])
  }

  # Split by operators (keeping the operator with the following version)
  # Pattern matches operator followed by version
  # e.g., ">=1.8<2" -> [">=1.8", "<2"]
  pattern <- "(?=>=|<=|==|!=|~=|(?<!>)(?<!<)(?<!!)(?<!~)(?<!=)>|(?<!>)(?<!<)(?<!!)(?<!~)(?<!=)<)"

  # Simpler approach: find all operator+version pairs
  op_pattern <- "(>=|<=|==|!=|~=|>(?!=)|<(?!=)|=(?!=))([^<>=!]+)"
  matches <- gregexpr(op_pattern, version_str, perl = TRUE)

  if (matches[[1]][1] == -1) {
    # No operators found, return as-is
    return(version_str)
  }

  # Extract all matches
  result <- regmatches(version_str, matches)[[1]]

  # If no result but there's content, check if it's a bare version
  if (length(result) == 0) {
    return(version_str)
  }

  return(result)
}

#' Parse a single version clause
#'
#' Extracts operator and version from a clause like ">=1.8", "<2", "1.8*"
#'
#' @param clause The version clause
#' @returns list(operator=..., version=...)
#' @keywords internal
#' @noRd
.parse_version_clause <- function(clause) {
  clause <- trimws(clause)

  # Match operators: >=, <=, ==, !=, ~=, >, <, =
  op_pattern <- "^(>=|<=|==|!=|~=|>|<|=)"
  match <- regexpr(op_pattern, clause, perl = TRUE)

  if (match > 0) {
    op_len <- attr(match, "match.length")
    op <- substring(clause, 1, op_len)
    ver <- trimws(substring(clause, op_len + 1))
    return(list(operator = op, version = ver))
  }

  # No operator
  return(list(operator = NULL, version = clause))
}
