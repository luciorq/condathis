#' Parse a Conda MatchSpec String
#'
#' Parses a string representation of a Conda package specification into its
#' constituent parts (channel, name, version, build, etc.).
#'
#' @param spec_string A character string containing the MatchSpec
#' (e.g., "numpy>=1.11", "conda-forge::python=3.9").
#'
#' @returns A named list containing `channel`, `subdir`, `namespace`, `name`, `version`, and `build`.
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

  # 1. Extract and process Bracketed Key-Values [key=val, ...]
  # We look for brackets at the end of the string
  bracket_regex <- "\\[(.*)\\]$"
  if (grepl(bracket_regex, spec_string)) {
    # Extract content inside brackets
    bracket_content <- sub(paste0(".*", bracket_regex), "\\1", spec_string)

    # Remove brackets from the main spec string for further processing
    package_string <- sub(bracket_regex, "", spec_string)

    # Parse the key-value pairs
    # Logic: Split by comma or space, but respect quotes if necessary.
    # For simplicity, we assume standard conda format: key=value
    pairs <- strsplit(bracket_content, "[,\\s]+", perl = TRUE)[[1]]
    for (pair in pairs) {
      if (grepl("=", pair)) {
        kv <- strsplit(pair, "=", fixed = TRUE)[[1]]
        key <- kv[1]
        # Remove quotes from value if present
        val <- gsub("^['\"]|['\"]$", "", kv[2])
        match_spec_list[[key]] <- val
      }
    }
  }

  # match_spec_list

  # 2. Process Channel and Namespace (:: separator)
  if (grepl("::", spec_string, fixed = TRUE)) {
    parts <- strsplit(spec_string, "::", fixed = TRUE)[[1]]
    left_side <- parts[1]
    right_side <- parts[2] # This is the package part

    # Handle Namespace (channel:namespace separator)
    # The canonical format is channel(/subdir):(namespace):name
    # But usually it appears as channel::name
    if (grepl(":", left_side)) {
      # This logic handles edge cases where namespace might be present
      # though it is rarely used in modern conda
      chan_parts <- strsplit(left_side, ":")[[1]]
      match_spec_list$channel <- chan_parts[1]
      match_spec_list$namespace <- chan_parts[2]
    } else {
      match_spec_list$channel <- left_side
    }

    # Handle Subdir (channel/subdir)
    if (
      !rlang::is_null(match_spec_list$channel) &&
        grepl("/", match_spec_list$channel)
    ) {
      chan_sub <- strsplit(match_spec_list$channel, "/")[[1]]
      match_spec_list$channel <- chan_sub[1]
      match_spec_list$subdir <- chan_sub[2]
    }

    spec <- right_side
  } else {
    spec <- spec_string
  }

  # 3. Parse Name
  # Name is required. It is the start of the remaining string.
  # It ends at the first space, operator (<, >, =, !), or end of string.
  # Regex: Starts with valid chars, stops before space or operator.
  name_regex <- "^([^\\s<>=!]+)"
  name_match <- regexpr(name_regex, spec, perl = TRUE)

  if (identical(name_match, -1L)) {
    cli::cli_abort(
      message = c(
        `x` = "Invalid MatchSpec: Could not identify package name."
      ),
      class = "condathis_parse_match_spec_invalid_name"
    )
  }

  match_spec_list$name <- regmatches(spec, name_match)

  # Check if name is just a wildcard
  if (identical(match_spec_list$name, "*")) {
    # If name is wildcard, keep it, but ensure we processed it correctly
    return(match_spec_list)
  }

  # 4. Process Version and Build (The "Tail")
  # Everything after the name is the version_build string
  tail <- substring(spec, attr(name_match, "match.length") + 1L)
  tail <- trimws(tail)

  if (isTRUE(nchar(tail) > 0L)) {
    # If we haven't already extracted version/build from brackets
    # (Bracket values take precedence, but we merge them at the end)

    # Parse the confusing tail string
    vb_parts <- .parse_version_plus_build(tail)

    # Only assign if not already set by brackets
    if (rlang::is_null(match_spec_list$version)) {
      match_spec_list$version <- vb_parts$version
    }
    if (rlang::is_null(match_spec_list$build)) {
      match_spec_list$build <- vb_parts$build
    }
  }

  # 5. Sanitize Version
  # Apply the fuzzy matching logic (e.g. =1.0 -> 1.0*)
  if (!rlang::is_null(match_spec_list$version)) {
    match_spec_list$version <- .sanitize_version_str(
      version_str = match_spec_list$version,
      build_str = match_spec_list$build
    )
  }

  return(match_spec_list)
}

#' Parse Version + Build string
#'
#' Handles the ambiguity between version specs and build strings.
#' e.g. ">=1.0 py36_0" -> version: ">=1.0", build: "py36_0"
#' e.g. "=1.0=py36_0" -> version: "1.0", build: "py36_0"
#'
#' @param text The string containing version and optionally build
#' @returns list(version=..., build=...)
#'
#' @keywords internal
#' @noRd
.parse_version_plus_build <- function(text) {
  version <- NULL
  build <- NULL

  # Case 1: "==1.2.3" or "=1.2.3" (Explicit strict equality or fuzzy)
  # If it looks like multiple parts separated by `=`, handle that.
  # Conda allows `pkg=1.0=build`
  if (grepl("=", text, fixed = TRUE) && !grepl("[<>]", text)) {
    # Split by `=` but we must respect `==`.
    # Actually, simpler approach: Normalize `==` to just a marker, then split.
    # But wait, `pkg==1.0` means exact. `pkg=1.0` means fuzzy.
    # Let's rely on tokenization by whitespace first, as that's safer for "V B" format.
  }

  # Normalize the string to make splitting easier
  # 1. Remove spaces around operators to keep version parts together
  #    e.g. "> 1.0" -> ">1.0"
  clean_text <- gsub("\\s*([<>!=]=?|[<>])\\s*", "\\1", text, perl = TRUE)

  # 2. Remove spaces around commas
  clean_text <- gsub("\\s*,\\s*", ",", clean_text)

  # 3. Split by whitespace
  tokens <- strsplit(clean_text, "\\s+")[[1]]

  if (identical(length(tokens), 1L)) {
    # Only one token. Is it version or build?
    # Usually it's version, unless it matches specific build patterns
    # or the user provided `pkg * build_string`.
    # However, standard assumption: if 1 arg, it's version.
    # BUT check for `version=build` syntax within the token (e.g. `=1.2=py36`)

    # Count equals that are NOT part of operators (>=, <=, ==, !=)
    # This is tricky with regex. Let's look for explicit internal `=` splitters.
    # Note: Conda's python `_parse_version_plus_build` handles `1.2.3=0`
    if (grepl("(?<![<>!])=(?!=)", tokens[1], perl = TRUE)) {
      # Split on the LAST equals sign that isn't `==`
      # This is a rough heuristic for `version=build`
      parts <- strsplit(tokens[1], "(?<![<>!])=(?!=)", perl = TRUE)[[1]]
      # If the string started with =, parts[1] is empty.
      # e.g. =1.2=py3 -> "", "1.2", "py3"

      parts <- parts[parts != ""] # Remove empty start if any

      if (length(parts) >= 2) {
        version <- paste(parts[1:(length(parts) - 1L)], collapse = "=")
        build <- parts[length(parts)]
        # Add back the leading = if the original text had it and we stripped it implicitly
        if (
          substr(text, 1L, 1L) == "=" &&
            substr(version, 1L, 1L) != "="
        ) {
          version <- paste0("=", version)
        }
      } else {
        version <- tokens[1]
      }
    } else {
      version <- tokens[1]
    }
  } else if (length(tokens) >= 2L) {
    # Two or more tokens.
    # Heuristic: The last token is the Build string, everything before is Version.
    # UNLESS the last token looks like a version constraint (has operators).

    last_token <- tail(tokens, 1)
    has_op <- grepl("[<>!=]", last_token)

    if (has_op) {
      # If the last part has operators, it's part of the version spec
      # e.g. "> 1.0 < 2.0"
      version <- paste(tokens, collapse = ",")
    } else {
      # Last part is likely build
      build <- last_token
      version <- paste(head(tokens, -1), collapse = ",")
    }
  }

  return(list(version = version, build = build))
}

#' Sanitize Version String
#'
#' Adapts the raw version string to Conda MatchSpec rules.
#' Handles `=1.0` -> `1.0*` transformation.
#'
#' @param version_str The raw version string
#' @param build_str The build string (can be NULL)
#' @returns Sanitized version string
#' @noRd
.sanitize_version_str <- function(version_str, build_str) {
  if (rlang::is_null(version_str) || identical(version_str, "")) {
    return(NULL)
  }

  # If it contains space, comma, or pipe, it is a complex spec (OR/AND),
  # generally we don't apply the fuzzy glob expansion to complex specs.
  if (grepl("[ ,|]", version_str)) {
    return(version_str)
  }

  # Check prefix
  has_double_eq <- substr(version_str, 1L, 2L) == "=="
  has_single_eq <- substr(version_str, 1L, 1L) == "=" && !has_double_eq

  # 1. "==" -> Exact match. Remove prefix, return.
  if (has_double_eq) {
    return(substring(version_str, 3L))
  }

  # 2. "=" -> Fuzzy match logic
  if (has_single_eq) {
    # Remove the "="
    v_clean <- substring(version_str, 2L)

    # If build is NULL, and the version does NOT end in *, treat as fuzzy
    if (rlang::is_null(build_str) && !grepl("\\*$", v_clean)) {
      return(paste0(v_clean, "*"))
    }

    return(v_clean)
  }

  # 3. No operator (e.g. "1.2.3")
  # In MatchSpec strings, "numpy 1.2" usually implies "numpy 1.2*" (fuzzy)
  # unless it has operators like >=.
  if (!grepl("[<>!=]", version_str)) {
    if (
      rlang::is_null(build_str) &&
        !grepl("\\*$", version_str)
    ) {
      # This is debated in Conda specs:
      # "foo 1.0" -> foo=1.0 -> 1.0*
      # But "foo >=1.0" -> >=1.0
      return(paste0(version_str, "*"))
    }
  }

  return(version_str)
}
