#' Compare a Version String Against a Conda VersionSpec Constraint
#'
#' Checks whether a version string satisfies a Conda MatchSpec version
#' constraint string. The output is compatible with
#' `libmambapy.specs.VersionSpec.parse(spec).contains(Version.parse(version))`.
#'
#' @details
#' This function implements the full Conda version comparison algorithm
#' following the libmamba specification:
#'
#' - **Operators:** `==`, `!=`, `>`, `>=`, `<`, `<=`, `=` (starts-with/fuzzy),
#'   `~=` (compatible release), `*` (free/any).
#' - **Compound expressions:** `,` for AND (higher precedence), `|` for OR
#'   (lower precedence), and parentheses for grouping.
#' - **Fuzzy matching:** `=1.2` matches any version starting with `1.2`
#'   (e.g., `1.2.3`, `1.2.0`). `==1.2.*` and `=1.2.*` also work.
#' - **Compatible release:** `~=1.4.2` is equivalent to `>=1.4.2,=1.4.*`.
#' - **Globs after an operator:** `>=1.3.*` is `>=1.3`, as in micromamba.
#'   Any other `*` after `>=` (`>=1.3*`, `>=1.3.*.*`), a glob after `>`,
#'   `<`, `<=` or `~=`, a `*` that is not a trailing glob (`1.*.5`,
#'   `1.3.*.*`), `!=1.3*`, `=1.3*`, `~=1`, an operator with no version
#'   (`>=*`, the `>=` of `>=,<2`), a missing operand (`>=1.3,`) or
#'   parenthesis, and a version that micromamba rejects (`>==1.3`) are not
#'   compared: micromamba and conda read them differently, so such a spec
#'   is never satisfied (see `version_spec_is_compared()`).
#' - **Epoch:** Optional `N!` prefix (e.g., `1!2.0`).
#' - **Version atoms:** Segments split by `.`/`-`/`_`, with atoms of alternating
#'   digit/letter runs. Special ordering: `dev < _ < regular < "" < post`.
#'
#' @param version_string A character string containing the version to check
#'   (e.g., `"1.26.4"`, `"2025b"`).
#' @param spec_string A character string containing the VersionSpec constraint
#'   (e.g., `">=1.8,<2.0"`, `"=1.2.*"`, `"~=1.4.2"`).
#'
#' @returns A logical scalar: `TRUE` if the version satisfies the constraint,
#'   `FALSE` otherwise.
#'
#' @examples
#' version_spec_contains("1.26.4", ">=1.8,<2.0")
#' version_spec_contains("1.2.3", "=1.2")
#' version_spec_contains("2025b", ">=2025a,<2026")
#' version_spec_contains("1.0", "~=1.0")
#'
#' @keywords internal
#' @noRd
version_spec_contains <- function(version_string, spec_string) {
  if (
    rlang::is_null(version_string) ||
      !is.character(version_string) ||
      !identical(length(version_string), 1L)
  ) {
    condathis_abort(
      message = c(
        `x` = "{.arg version_string} must be a single character string."
      ),
      class = c(
        "condathis_version_spec_contains_invalid_input",
        "condathis_invalid_arg"
      )
    )
  }
  if (
    rlang::is_null(spec_string) ||
      !is.character(spec_string) ||
      !identical(length(spec_string), 1L)
  ) {
    condathis_abort(
      message = c(
        `x` = "{.arg spec_string} must be a single character string."
      ),
      class = c(
        "condathis_version_spec_contains_invalid_input",
        "condathis_invalid_arg"
      )
    )
  }

  parsed_ver <- vs_parse_ver(version_string)
  spec_tree <- vs_parse_spec_expr(spec_string)
  # One uncompared predicate makes the whole spec uncompared, also in an
  # OR: `">1.3.*|<1"` is never satisfied.
  if (isTRUE(vs_has_uncompared(spec_tree))) {
    return(FALSE)
  }
  return(vs_eval_spec(spec_tree, parsed_ver))
}

#' Can a VersionSpec be compared?
#'
#' A spec with a glob after `>`, `<`, `<=` or `~=`, a `*` after `>=` other
#' than one trailing `.*`, a `*` that is not a trailing glob, `!=` with a
#' `*` but no `.*`, `=` with a `*` but no `.*`, `~=` with a one-part
#' version, an operator with no version, a missing operand or parenthesis,
#' or a version that micromamba rejects, is not compared:
#' `version_spec_contains()` never reports it as satisfied (see
#' `vs_parse_predicate()` and `vs_parse_primary_expr()`).
#'
#' @param spec_string A character string containing the VersionSpec.
#'
#' @returns `TRUE` or `FALSE`.
#'
#' @keywords internal
#' @noRd
version_spec_is_compared <- function(spec_string) {
  return(isFALSE(vs_has_uncompared(vs_parse_spec_expr(spec_string))))
}

#' Does a VersionSpec AST have an uncompared predicate?
#'
#' @param node An AST node (from `vs_parse_spec_expr`).
#' @returns Logical scalar.
#'
#' @keywords internal
#' @noRd
vs_has_uncompared <- function(node) {
  if (identical(node$type, "predicate")) {
    return(identical(node$op, "uncompared"))
  }
  return(any(vapply(node$children, vs_has_uncompared, logical(1L))))
}

#' Is a string a version that micromamba accepts?
#'
#' An optional epoch (`1!`), then parts of letters and digits separated by
#' `.`, `_` or `-`, and an optional local version after `+` of the same
#' form. Anything else is not compared: micromamba rejects most of it
#' (`1..2`, `1.3.0+`, `!`), and reads the rest, such as a trailing `.` in
#' `>=1.3.`, its own way.
#'
#' @param x A character string: a version without operator or glob.
#'
#' @returns `TRUE` or `FALSE`.
#'
#' @keywords internal
#' @noRd
vs_is_version_string <- function(x) {
  part <- "[0-9A-Za-z]+([._-][0-9A-Za-z]+)*"
  return(isTRUE(grepl(paste0("^([0-9]+!)?", part, "(\\+", part, ")?$"), x)))
}


# =============================================================================
# Internal: Version parsing
# =============================================================================

#' Parse a version string into epoch, segments, and local parts
#'
#' Handles the format `[epoch!]main[+local]`.
#'
#' @param str A version string (e.g., `"1!2.3.4+local1"`).
#' @returns A list with `epoch` (integer), `segments` (list of atom lists),
#'   and `local` (list of atom lists).
#'
#' @keywords internal
#' @noRd
vs_parse_ver <- function(str) {
  str <- trimws(str)

  # Parse epoch

  epoch <- 0
  bang_pos <- regexpr("!", str, fixed = TRUE)
  if (isTRUE(as.integer(bang_pos) > 0L)) {
    epoch_str <- substring(str, 1L, as.integer(bang_pos) - 1L)
    epoch <- suppressWarnings(as.numeric(epoch_str))
    if (is.na(epoch)) {
      epoch <- 0
    }
    str <- substring(str, as.integer(bang_pos) + 1L)
  }

  # Parse local
  local_parts <- list()
  plus_pos <- regexpr("+", str, fixed = TRUE)
  if (isTRUE(as.integer(plus_pos) > 0L)) {
    local_str <- substring(str, as.integer(plus_pos) + 1L)
    str <- substring(str, 1L, as.integer(plus_pos) - 1L)
    local_parts <- vs_parse_ver_parts(local_str)
  }

  # Parse main segments
  segments <- vs_parse_ver_parts(str)

  return(list(
    epoch = epoch,
    segments = segments,
    local = local_parts
  ))
}


#' Split a version part by delimiters and parse each segment
#'
#' Delimiters are `.`, `-`, and `_`.
#'
#' @param str A version part string (e.g., `"1.2.3rc1"`).
#' @returns A list of segments, where each segment is a list of
#'   `list(num, lit)` atoms.
#'
#' @keywords internal
#' @noRd
vs_parse_ver_parts <- function(str) {
  if (rlang::is_null(str) || identical(str, "")) {
    return(list())
  }

  # Split by . - or _ (the delimiters)
  # Note: dash must be at start or end of character class
  parts <- strsplit(str, "[._-]")[[1L]]

  return(lapply(parts, vs_parse_ver_segment))
}


#' Parse a single version segment into atoms
#'
#' Alternates between digit runs (parsed as doubles) and letter runs
#' (lowercased). If the segment starts with letters, an implicit leading
#' zero is prepended.
#'
#' @param str A single segment string (e.g., `"3rc1"`, `"beta15"`).
#' @returns A list of `list(num, lit)` atoms.
#'
#' @keywords internal
#' @noRd
vs_parse_ver_segment <- function(str) {
  if (rlang::is_null(str) || identical(str, "")) {
    return(list(list(num = 0, lit = "")))
  }

  atoms <- list()
  pos <- 1L
  n <- nchar(str)
  chars <- strsplit(str, "")[[1L]]

  # If starts with a letter, prepend implicit zero
  if (isTRUE(grepl("^[A-Za-z]", str))) {
    # Consume the letter run
    end <- pos
    while (isTRUE(end <= n) && isTRUE(grepl("[A-Za-z]", chars[end]))) {
      end <- end + 1L
    }
    lit_val <- tolower(substring(str, pos, end - 1L))
    atoms <- c(atoms, list(list(num = 0, lit = lit_val)))
    pos <- end
  }

  while (isTRUE(pos <= n)) {
    atom_start <- pos
    # Consume digit run
    digit_start <- pos
    while (isTRUE(pos <= n) && isTRUE(grepl("[0-9]", chars[pos]))) {
      pos <- pos + 1L
    }
    num_str <- substring(str, digit_start, pos - 1L)
    # Doubles, not integers: libmamba stores numerals as `size_t`, and
    # timestamp-style versions (`0.0.20240101123456`) exceed R's integer
    # range. `as.integer()` turned them into `NA` (with a warning), and `NA`
    # numerals compared as equal to anything. Doubles are exact to 2^53.
    num_val <- if (identical(num_str, "")) 0 else as.numeric(num_str)

    # Consume letter run
    lit_start <- pos
    while (isTRUE(pos <= n) && isTRUE(grepl("[A-Za-z]", chars[pos]))) {
      pos <- pos + 1L
    }
    lit_val <- tolower(substring(str, lit_start, pos - 1L))

    # Neither a digit nor a letter, such as `*`: one literal atom, so the
    # loop always moves on. It looped forever on `"1.3.*"` before.
    if (identical(pos, atom_start)) {
      lit_val <- chars[pos]
      pos <- pos + 1L
    }

    atoms <- c(atoms, list(list(num = num_val, lit = lit_val)))
  }

  if (identical(length(atoms), 0L)) {
    return(list(list(num = 0, lit = "")))
  }

  return(atoms)
}


# =============================================================================
# Internal: Version comparison
# =============================================================================

#' Get priority ordering for a version literal string
#'
#' Ordering: `"*"` (-3) < `"dev"` (-2) < `"_"` (-1) < regular (0)
#'            < `""` (1) < `"post"` (2)
#'
#' @param lit A literal string.
#' @returns An integer priority value.
#'
#' @keywords internal
#' @noRd
vs_lit_priority <- function(lit) {
  if (identical(lit, "*")) {
    return(-3L)
  }
  if (identical(lit, "dev")) {
    return(-2L)
  }
  if (identical(lit, "_")) {
    return(-1L)
  }
  if (identical(lit, "")) {
    return(1L)
  }
  if (identical(lit, "post")) {
    return(2L)
  }
  return(0L)
}


#' Compare two version atoms
#'
#' @param a A `list(num, lit)` atom.
#' @param b A `list(num, lit)` atom.
#' @returns `-1L`, `0L`, or `1L`.
#'
#' @keywords internal
#' @noRd
vs_cmp_atoms <- function(a, b) {
  # Compare numerals first
  if (isTRUE(a$num < b$num)) {
    return(-1L)
  }
  if (isTRUE(a$num > b$num)) {
    return(1L)
  }

  # Numerals equal, compare literals by priority

  pa <- vs_lit_priority(a$lit)
  pb <- vs_lit_priority(b$lit)

  if (isTRUE(pa < pb)) {
    return(-1L)
  }
  if (isTRUE(pa > pb)) {
    return(1L)
  }

  # Same priority class: if both are regular strings (priority 0),
  # compare lexicographically
  if (identical(pa, 0L)) {
    if (isTRUE(a$lit < b$lit)) {
      return(-1L)
    }
    if (isTRUE(a$lit > b$lit)) {
      return(1L)
    }
  }

  return(0L)
}


#' Compare two version segments (lists of atoms)
#'
#' Lexicographic comparison with padding using default atom `(0, "")`.
#'
#' @param sa A list of atoms (one segment).
#' @param sb A list of atoms (one segment).
#' @returns `-1L`, `0L`, or `1L`.
#'
#' @keywords internal
#' @noRd
vs_cmp_segments <- function(sa, sb) {
  default_atom <- list(num = 0, lit = "")
  len <- max(length(sa), length(sb))

  for (i in seq_len(len)) {
    atom_a <- if (isTRUE(i <= length(sa))) sa[[i]] else default_atom
    atom_b <- if (isTRUE(i <= length(sb))) sb[[i]] else default_atom
    cmp <- vs_cmp_atoms(atom_a, atom_b)
    if (!identical(cmp, 0L)) {
      return(cmp)
    }
  }

  return(0L)
}


#' Compare two lists of segments (CommonVersion comparison)
#'
#' Lexicographic comparison with padding using default segment `[(0, "")]`.
#'
#' @param pa A list of segments.
#' @param pb A list of segments.
#' @returns `-1L`, `0L`, or `1L`.
#'
#' @keywords internal
#' @noRd
vs_cmp_parts <- function(pa, pb) {
  default_segment <- list(list(num = 0, lit = ""))
  len <- max(length(pa), length(pb))

  if (identical(len, 0L)) {
    return(0L)
  }

  for (i in seq_len(len)) {
    seg_a <- if (isTRUE(i <= length(pa))) pa[[i]] else default_segment
    seg_b <- if (isTRUE(i <= length(pb))) pb[[i]] else default_segment
    cmp <- vs_cmp_segments(seg_a, seg_b)
    if (!identical(cmp, 0L)) {
      return(cmp)
    }
  }

  return(0L)
}


#' Compare two fully parsed versions
#'
#' Compares epoch, then main segments, then local segments.
#'
#' @param va A parsed version (from `vs_parse_ver`).
#' @param vb A parsed version (from `vs_parse_ver`).
#' @returns `-1L`, `0L`, or `1L`.
#'
#' @keywords internal
#' @noRd
vs_cmp_versions <- function(va, vb) {
  # Compare epoch
  if (isTRUE(va$epoch < vb$epoch)) {
    return(-1L)
  }
  if (isTRUE(va$epoch > vb$epoch)) {
    return(1L)
  }

  # Compare main segments
  main_cmp <- vs_cmp_parts(va$segments, vb$segments)
  if (!identical(main_cmp, 0L)) {
    return(main_cmp)
  }

  # Compare local segments
  return(vs_cmp_parts(va$local, vb$local))
}


# =============================================================================
# Internal: Operator predicates
# =============================================================================

#' Check if version starts with a reference prefix
#'
#' The version `v` "starts with" `ref` if:
#' - Epochs are equal.
#' - Each segment in `ref` matches the corresponding segment in `v`
#'   (with atom-level prefix matching: if the ref atom's literal is empty,
#'   only the numeral needs to match).
#' - If `ref` has fewer segments than `v`, the extra segments in `v` can be
#'   anything.
#' - If `ref` has a local part, the main versions must be exactly equal,
#'   then the local is prefix-matched.
#'
#' @param v Parsed version (candidate).
#' @param ref Parsed version (prefix/reference).
#' @returns Logical.
#'
#' @keywords internal
#' @noRd
vs_ver_starts_with <- function(v, ref) {
  # Epochs must be equal
  if (!identical(v$epoch, ref$epoch)) {
    return(FALSE)
  }

  # If ref has a local part, main versions must be exactly equal
  if (isTRUE(length(ref$local) > 0L)) {
    main_cmp <- vs_cmp_parts(v$segments, ref$segments)
    if (!identical(main_cmp, 0L)) {
      return(FALSE)
    }
    return(vs_parts_starts_with(v$local, ref$local))
  }

  # Otherwise, prefix-match on main segments
  return(vs_parts_starts_with(v$segments, ref$segments))
}


#' Check if a list of segments starts with a reference prefix
#'
#' @param candidate_parts List of segments from the candidate version.
#' @param prefix_parts List of segments from the prefix/reference version.
#' @returns Logical.
#'
#' @keywords internal
#' @noRd
vs_parts_starts_with <- function(candidate_parts, prefix_parts) {
  if (identical(length(prefix_parts), 0L)) {
    return(TRUE)
  }

  # Match each prefix segment against the candidate segment. Like libmamba,
  # pad a shorter candidate with the default (0,""). A default prefix segment
  # [(0,"")] matches any candidate segment that equals (0,"") after padding.

  for (i in seq_along(prefix_parts)) {
    ref_seg <- prefix_parts[[i]]
    cand_seg <- if (isTRUE(i <= length(candidate_parts))) {
      candidate_parts[[i]]
    } else {
      list(list(num = 0, lit = ""))
    }
    if (isFALSE(vs_segment_starts_with(cand_seg, ref_seg))) {
      return(FALSE)
    }
  }

  return(TRUE)
}


#' Check if a candidate segment starts with a reference segment
#'
#' Atom-level prefix matching: if the ref atom's literal is empty,
#' only the numeral needs to match (the candidate's literal can be anything).
#'
#' @param cand_seg Candidate segment atom list.
#' @param ref_seg Reference segment atom list.
#'
#' @returns Logical.
#'
#' @keywords internal
#' @noRd
vs_segment_starts_with <- function(cand_seg, ref_seg) {
  default_atom <- list(num = 0, lit = "")

  for (i in seq_along(ref_seg)) {
    ref_atom <- ref_seg[[i]]
    cand_atom <- if (isTRUE(i <= length(cand_seg))) {
      cand_seg[[i]]
    } else {
      default_atom
    }

    # Compare numerals
    if (!identical(cand_atom$num, ref_atom$num)) {
      return(FALSE)
    }

    # If ref literal is empty (priority 1 = ""), only numeral needs to match
    if (identical(ref_atom$lit, "")) {
      next
    }

    # Otherwise, literals must match exactly
    if (!identical(cand_atom$lit, ref_atom$lit)) {
      return(FALSE)
    }
  }

  return(TRUE)
}


#' Check compatible release constraint
#'
#' `~=X.Y.Z` means `>= X.Y.Z` AND the first N-1 segments match
#' (where N is the number of segments in the reference version).
#'
#' @param v Parsed version (candidate).
#' @param ref Parsed version (reference).
#' @returns Logical.
#'
#' @keywords internal
#' @noRd
vs_ver_compatible_with <- function(v, ref) {
  # Epochs must be equal
  if (!identical(v$epoch, ref$epoch)) {
    return(FALSE)
  }

  # Must be >= ref
  cmp <- vs_cmp_versions(v, ref)
  if (identical(cmp, -1L)) {
    return(FALSE)
  }

  # The level is max(number_of_segments, 1) - 1

  n_segments <- max(length(ref$segments), 1L)
  level <- n_segments - 1L

  if (identical(level, 0L)) {
    # Only need >= (no prefix constraint when there's only one segment)
    return(TRUE)
  }

  # First `level` segments must be identical
  for (i in seq_len(level)) {
    ref_seg <- if (isTRUE(i <= length(ref$segments))) {
      ref$segments[[i]]
    } else {
      list(list(num = 0, lit = ""))
    }
    cand_seg <- if (isTRUE(i <= length(v$segments))) {
      v$segments[[i]]
    } else {
      list(list(num = 0, lit = ""))
    }
    seg_cmp <- vs_cmp_segments(cand_seg, ref_seg)
    if (!identical(seg_cmp, 0L)) {
      return(FALSE)
    }
  }

  return(TRUE)
}


# =============================================================================
# Internal: VersionSpec expression parsing and evaluation
# =============================================================================

#' Parse a VersionSpec string into an expression tree (AST)
#'
#' Handles compound expressions with `,` (AND), `|` (OR), and parentheses.
#' OR (`|`) has higher precedence (binds tighter) than AND (`,`),
#' matching libmamba's `InfixParser` with `std::less<BoolOperator>`.
#'
#' The AST uses list nodes:
#' - `list(type = "and", children = list(...))`
#' - `list(type = "or", children = list(...))`
#' - `list(type = "predicate", op = "...", ver = parsed_version)`
#'
#' @param spec_str A VersionSpec string (e.g., `">=1.8,<2.0|==3.0"`).
#' @returns An AST node (list).
#'
#' @keywords internal
#' @noRd
vs_parse_spec_expr <- function(spec_str) {
  spec_str <- trimws(spec_str)

  # Handle free interval
  if (
    identical(spec_str, "") ||
      identical(spec_str, "*") ||
      identical(spec_str, "=*") ||
      identical(spec_str, "==*")
  ) {
    return(list(type = "predicate", op = "free", ver = NULL))
  }

  # Tokenize
  tokens <- vs_tokenize_spec(spec_str)

  # Parse expression from tokens
  env <- new.env(parent = emptyenv())
  env$tokens <- tokens
  env$pos <- 1L

  result <- vs_parse_and_expr(env)
  # Tokens left over, as after the `)` of `>=1.3)`: not compared.
  if (isTRUE(env$pos <= length(env$tokens))) {
    return(list(type = "predicate", op = "uncompared", ver = NULL))
  }
  return(result)
}


#' Tokenize a VersionSpec string
#'
#' Splits the string into predicate atoms and operators (`,`, `|`, `(`, `)`).
#'
#' @param str A VersionSpec string.
#' @returns A character vector of tokens.
#'
#' @keywords internal
#' @noRd
vs_tokenize_spec <- function(str) {
  tokens <- character(0L)
  pos <- 1L
  n <- nchar(str)
  chars <- strsplit(str, "")[[1L]]

  while (isTRUE(pos <= n)) {
    ch <- chars[pos]

    if (ch %in% c(",", "|", "(", ")")) {
      tokens <- c(tokens, ch)
      pos <- pos + 1L
    } else if (identical(ch, " ")) {
      # Skip whitespace
      pos <- pos + 1L
    } else {
      # Consume a predicate atom: everything until ,|()
      atom_start <- pos
      paren_depth <- 0L
      while (isTRUE(pos <= n)) {
        c2 <- chars[pos]
        if (identical(c2, "(")) {
          paren_depth <- paren_depth + 1L
          pos <- pos + 1L
        } else if (identical(c2, ")")) {
          if (identical(paren_depth, 0L)) {
            break
          }
          paren_depth <- paren_depth - 1L
          pos <- pos + 1L
        } else if (c2 %in% c(",", "|") && identical(paren_depth, 0L)) {
          break
        } else {
          pos <- pos + 1L
        }
      }
      atom <- trimws(substring(str, atom_start, pos - 1L))
      if (isTRUE(nchar(atom) > 0L)) {
        tokens <- c(tokens, atom)
      }
    }
  }

  return(tokens)
}


#' Parse an AND expression (lowest precedence, parsed at top level)
#'
#' @param env An environment with `tokens` and `pos`.
#' @returns An AST node.
#'
#' @keywords internal
#' @noRd
vs_parse_and_expr <- function(env) {
  left <- vs_parse_or_expr(env)

  children <- list(left)
  while (
    isTRUE(env$pos <= length(env$tokens)) &&
      identical(env$tokens[env$pos], ",")
  ) {
    env$pos <- env$pos + 1L
    right <- vs_parse_or_expr(env)
    children <- c(children, list(right))
  }

  if (identical(length(children), 1L)) {
    return(children[[1L]])
  }

  return(list(
    type = "and",
    children = children
  ))
}


#' Parse an OR expression (higher precedence than AND)
#'
#' @param env An environment with `tokens` and `pos`.
#' @returns An AST node.
#'
#' @keywords internal
#' @noRd
vs_parse_or_expr <- function(env) {
  left <- vs_parse_primary_expr(env)

  children <- list(left)
  while (
    isTRUE(env$pos <= length(env$tokens)) &&
      identical(env$tokens[env$pos], "|")
  ) {
    env$pos <- env$pos + 1L
    right <- vs_parse_primary_expr(env)
    children <- c(children, list(right))
  }

  if (identical(length(children), 1L)) {
    return(children[[1L]])
  }

  list(type = "or", children = children)
}


#' Parse a primary expression (atom or parenthesized group)
#'
#' @param env An environment with `tokens` and `pos`.
#' @returns An AST node.
#'
#' @keywords internal
#' @noRd
vs_parse_primary_expr <- function(env) {
  # A missing operand, as in `>=1.3,`, `>=1,,<2`, `|<2` or `()`, is not
  # compared: micromamba rejects it. A `,`, `|` or `)` is left for the
  # caller.
  uncompared <- list(type = "predicate", op = "uncompared", ver = NULL)
  if (isTRUE(env$pos > length(env$tokens))) {
    return(uncompared)
  }

  tok <- env$tokens[env$pos]
  if (isTRUE(tok %in% c(",", "|", ")"))) {
    return(uncompared)
  }

  if (identical(tok, "(")) {
    env$pos <- env$pos + 1L
    node <- vs_parse_and_expr(env)
    # Consume closing paren; without one, the group is not compared.
    if (
      isTRUE(env$pos <= length(env$tokens)) &&
        identical(env$tokens[env$pos], ")")
    ) {
      env$pos <- env$pos + 1L
    } else {
      return(uncompared)
    }
    return(node)
  }

  # It's a predicate atom
  env$pos <- env$pos + 1L
  vs_parse_predicate(tok)
}


#' Parse a single predicate atom into an AST leaf node
#'
#' Detects the operator prefix and parses the version reference.
#'
#' @param atom_str A predicate string (e.g., `">=1.8"`, `"=1.2.*"`, `"*"`).
#' @returns A list with `type = "predicate"`, `op`, and `ver`.
#'
#' @keywords internal
#' @noRd
vs_parse_predicate <- function(atom_str) {
  atom_str <- trimws(atom_str)

  # Free interval
  if (
    identical(atom_str, "") ||
      identical(atom_str, "*") ||
      identical(atom_str, "=*") ||
      identical(atom_str, "==*")
  ) {
    return(list(type = "predicate", op = "free", ver = NULL))
  }

  # A glob after a range operator: micromamba 2.9.0 and 2.10.0 read
  # `>=1.3.*` as `>=1.3`, but compare any other `*` after `>=`, as in
  # `>=1.3*` or `>=1.3.*.*`, as the lowest version, so pre-releases of 1.3
  # match too. `>1.3.*`, `<1.3.*`, `<=1.3.*` and `~=1.2.*` match no
  # version, while conda drops the glob. With no known answer, such a
  # predicate is "uncompared" and never satisfied. So is a `*` that is not
  # a trailing glob, as in `1.*.5`, `!=1.3*`, which micromamba reads as a
  # literal version (conda as "does not start with"), and an operator with
  # no version: micromamba reads `>=*` as any version and rejects the `>=`
  # of `>=,<2`. Also not compared: `=1.3*`, a glob without a dot after
  # `=`, which micromamba reads as 1.3 followed by more version parts (so
  # not 1.3 itself), `~=` with a one-part version (`~=1`), which matches no
  # version in micromamba, and a version that micromamba rejects, such as
  # `=1.3` after `>=` (`>==1.3`), `1.3.0+` or `!`.
  operator <- regmatches(
    atom_str,
    regexpr("^(>=|>|<=|<|~=|!=|==|=)", atom_str)
  )
  if (identical(length(operator), 0L)) {
    operator <- ""
  }
  ver_str <- trimws(substring(atom_str, nchar(operator) + 1L))
  if (identical(operator, ">=")) {
    ver_str <- sub("\\.\\*$", "", ver_str)
    atom_str <- paste0(">=", ver_str)
  }
  rest <- ver_str
  if (isTRUE(operator %in% c("==", ""))) {
    rest <- if (isTRUE(grepl("\\.\\*$", rest))) {
      sub("\\.\\*$", "", rest)
    } else {
      sub("\\*$", "", rest)
    }
  } else if (isTRUE(operator %in% c("=", "!="))) {
    rest <- sub("\\.\\*$", "", rest)
  }
  if (
    isTRUE(grepl("*", rest, fixed = TRUE)) ||
      isFALSE(vs_is_version_string(rest)) ||
      (identical(operator, "~=") &&
        isFALSE(grepl("[._-]", sub("\\+.*$", "", sub("^[0-9]+!", "", rest)))))
  ) {
    return(list(type = "predicate", op = "uncompared", ver = NULL))
  }

  # Detect operator prefix (order matters: longer prefixes first)
  if (isTRUE(startsWith(atom_str, ">="))) {
    ver_str <- substring(atom_str, 3L)
    return(list(
      type = "predicate",
      op = "greater_equal",
      ver = vs_parse_ver(ver_str)
    ))
  }
  if (isTRUE(startsWith(atom_str, ">"))) {
    ver_str <- substring(atom_str, 2L)
    return(list(
      type = "predicate",
      op = "greater",
      ver = vs_parse_ver(ver_str)
    ))
  }
  if (isTRUE(startsWith(atom_str, "<="))) {
    ver_str <- substring(atom_str, 3L)
    return(list(
      type = "predicate",
      op = "less_equal",
      ver = vs_parse_ver(ver_str)
    ))
  }
  if (isTRUE(startsWith(atom_str, "<"))) {
    ver_str <- substring(atom_str, 2L)
    return(list(
      type = "predicate",
      op = "less",
      ver = vs_parse_ver(ver_str)
    ))
  }
  if (isTRUE(startsWith(atom_str, "~="))) {
    ver_str <- substring(atom_str, 3L)
    return(list(
      type = "predicate",
      op = "compatible_with",
      ver = vs_parse_ver(ver_str)
    ))
  }
  if (isTRUE(startsWith(atom_str, "!="))) {
    ver_str <- substring(atom_str, 3L)
    # Check for glob suffix .* (a trailing * without the dot is uncompared)
    if (isTRUE(grepl("\\.\\*$", ver_str))) {
      cleaned <- sub("\\.\\*$", "", ver_str)
      return(list(
        type = "predicate",
        op = "not_starts_with",
        ver = vs_parse_ver(cleaned)
      ))
    }
    return(list(
      type = "predicate",
      op = "not_equal",
      ver = vs_parse_ver(ver_str)
    ))
  }
  if (isTRUE(startsWith(atom_str, "=="))) {
    ver_str <- substring(atom_str, 3L)
    # Check for glob suffix .* or trailing *
    if (isTRUE(grepl("\\.\\*$", ver_str))) {
      cleaned <- sub("\\.\\*$", "", ver_str)
      return(list(
        type = "predicate",
        op = "starts_with",
        ver = vs_parse_ver(cleaned)
      ))
    }
    if (isTRUE(grepl("\\*$", ver_str)) && !identical(ver_str, "*")) {
      cleaned <- sub("\\*$", "", ver_str)
      cleaned <- sub("\\.$", "", cleaned)
      return(list(
        type = "predicate",
        op = "starts_with",
        ver = vs_parse_ver(cleaned)
      ))
    }
    return(list(
      type = "predicate",
      op = "equal",
      ver = vs_parse_ver(ver_str)
    ))
  }
  if (isTRUE(startsWith(atom_str, "="))) {
    ver_str <- substring(atom_str, 2L)
    # Free if just "="
    if (identical(ver_str, "") || identical(ver_str, "*")) {
      return(list(type = "predicate", op = "free", ver = NULL))
    }
    # Strip trailing .* for starts_with
    ver_str <- sub("\\.\\*$", "", ver_str)
    # Strip trailing * (non-dot)
    if (isTRUE(grepl("\\*$", ver_str)) && !identical(ver_str, "*")) {
      ver_str <- sub("\\*$", "", ver_str)
      ver_str <- sub("\\.$", "", ver_str)
    }
    return(list(
      type = "predicate",
      op = "starts_with",
      ver = vs_parse_ver(ver_str)
    ))
  }

  # Bare version string (no operator prefix)
  # Check for trailing glob: .* or * -> starts_with
  if (isTRUE(grepl("\\.\\*$", atom_str))) {
    cleaned <- sub("\\.\\*$", "", atom_str)
    return(list(
      type = "predicate",
      op = "starts_with",
      ver = vs_parse_ver(cleaned)
    ))
  }
  if (isTRUE(grepl("\\*$", atom_str)) && !identical(atom_str, "*")) {
    cleaned <- sub("\\*$", "", atom_str)
    cleaned <- sub("\\.$", "", cleaned)
    return(list(
      type = "predicate",
      op = "starts_with",
      ver = vs_parse_ver(cleaned)
    ))
  }

  # Plain bare version -> exact match
  return(list(
    type = "predicate",
    op = "equal",
    ver = vs_parse_ver(atom_str)
  ))
}


#' Evaluate a VersionSpec AST against a parsed version
#'
#' @param node An AST node (from `vs_parse_spec_expr`).
#' @param parsed_ver A parsed version (from `vs_parse_ver`).
#' @returns Logical.
#'
#' @keywords internal
#' @noRd
vs_eval_spec <- function(node, parsed_ver) {
  if (identical(node$type, "predicate")) {
    return(vs_eval_predicate(node, parsed_ver))
  }

  if (identical(node$type, "and")) {
    for (child in node$children) {
      if (isFALSE(vs_eval_spec(child, parsed_ver))) {
        return(FALSE)
      }
    }
    return(TRUE)
  }

  if (identical(node$type, "or")) {
    for (child in node$children) {
      if (isTRUE(vs_eval_spec(child, parsed_ver))) {
        return(TRUE)
      }
    }
    return(FALSE)
  }

  # Unknown node type: unreachable
  return(FALSE)
}


#' Evaluate a single predicate against a parsed version
#'
#' @param pred A predicate node with `op` and `ver`.
#' @param parsed_ver A parsed version.
#' @returns Logical.
#'
#' @keywords internal
#' @noRd
vs_eval_predicate <- function(pred, parsed_ver) {
  op <- pred$op
  ref <- pred$ver

  if (identical(op, "free")) {
    return(TRUE)
  }
  if (identical(op, "uncompared")) {
    return(FALSE)
  }

  cmp <- vs_cmp_versions(parsed_ver, ref)

  return(switch(
    EXPR = op, # styler: off
    `equal` = identical(cmp, 0L),
    `not_equal` = !identical(cmp, 0L),
    `greater` = identical(cmp, 1L),
    `greater_equal` = !identical(cmp, -1L),
    `less` = identical(cmp, -1L),
    `less_equal` = !identical(cmp, 1L),
    `starts_with` = vs_ver_starts_with(parsed_ver, ref),
    `not_starts_with` = !vs_ver_starts_with(parsed_ver, ref),
    `compatible_with` = vs_ver_compatible_with(parsed_ver, ref),
    FALSE
  ))
}
