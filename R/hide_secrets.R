#' Hide the credentials of URLs in text
#'
#' A channel URL can carry a token (`https://host/t/<token>/channel`) or a
#' login (`https://user:password@host/channel`). micromamba hides both in
#' what it prints (`hide_secrets()` in libmamba's `util.cpp`), and so does
#' every text that `condathis` prints or returns: the command lines it
#' echoes, the `cmd` of its results, its messages, warnings and errors, and
#' the channels of `list_packages()` and of an environment's history. The
#' command that runs still gets the credentials.
#'
#' The rule is the one of rattlerthis (`hide_secrets()` in
#' `src/rust/src/secrets.rs`), so both backends hide the same text:
#'
#' * Every `/t/<token>` becomes `/t/*****`. A token is what libmamba's
#'   `is_token()` (`conda_url.cpp`) takes for one: at least two characters,
#'   letters, digits and `-`, with `_` allowed in the first two (user names
#'   on anaconda.org). A token that is hidden already (`*****`, or rattler's
#'   `********`) counts too, so hiding twice changes nothing.
#' * The password of every `<scheme>://user:password@host` becomes
#'   `*****`. The login is the part after `://` up to the first `/`, white
#'   space or one of `()[]<>"'`` ` ``,`; the password runs from its first
#'   `:` to its last `@`. A login without a password (`user@host`) is kept,
#'   as micromamba keeps it.
#'
#' @param x A character vector. Any other value is returned as it is.
#'
#' @returns `x`, with the same attributes (names included), and `NA` kept.
#'
#' @keywords internal
#' @noRd
hide_secrets <- function(x) {
  if (isFALSE(is.character(x)) || identical(length(x), 0L)) {
    return(x)
  }
  todo <- which(
    !is.na(x) &
      (grepl("/t/", x, fixed = TRUE, useBytes = TRUE) |
        grepl("://", x, fixed = TRUE, useBytes = TRUE))
  )
  for (i in todo) {
    x[[i]] <- hide_secrets_string(x[[i]])
  }
  return(x)
}

#' Hide the credentials of the URLs in one string
#'
#' See `hide_secrets()`. Text that is not valid UTF-8 is read as bytes.
#'
#' @param text Character string, not `NA`.
#'
#' @returns Character string.
#'
#' @keywords internal
#' @noRd
hide_secrets_string <- function(text) {
  text <- enc2utf8(text)
  use_bytes <- isFALSE(validUTF8(text))
  if (isTRUE(use_bytes)) {
    Encoding(text) <- "bytes"
  }
  # `/t/` and the longest run of token characters after it, as rattlerthis
  # scans it: `_` only in the first two places, `*` anywhere.
  text <- replace_matches(
    text,
    pattern = "/t/[*A-Za-z0-9_-]{0,2}[*A-Za-z0-9-]*",
    use_bytes = use_bytes,
    replace = function(found) {
      token <- substring(found, 4L)
      is_token <- grepl("^[*]+$", token) ||
        (nchar(token, type = "bytes") >= 2L &&
          isFALSE(grepl("*", token, fixed = TRUE)))
      if (isTRUE(is_token)) {
        return("/t/*****")
      }
      return(found)
    }
  )
  # `://` and the login part of the URL after it. `(*UCP)` makes `\s` any
  # white space, as Rust's `char::is_whitespace()`.
  text <- replace_matches(
    text,
    pattern = paste0(
      if (isFALSE(use_bytes)) "(*UCP)",
      "://[^/\\s()\\[\\]<>\"'`,]*"
    ),
    use_bytes = use_bytes,
    replace = function(found) {
      login <- substring(found, 4L)
      at <- gregexpr("@", login, fixed = TRUE)[[1L]]
      if (identical(as.integer(at[[1L]]), -1L)) {
        return(found)
      }
      at <- at[[length(at)]]
      colon <- regexpr(":", substr(login, 1L, at - 1L), fixed = TRUE)
      if (identical(as.integer(colon), -1L)) {
        return(found)
      }
      return(paste0(
        "://",
        substr(login, 1L, colon),
        "*****",
        substring(login, at)
      ))
    }
  )
  if (isTRUE(use_bytes)) {
    Encoding(text) <- "unknown"
  }
  return(text)
}

#' Replace each match of a pattern with a function of it
#'
#' @param text Character string.
#' @param pattern Character string, a PCRE pattern.
#' @param use_bytes Logical, whether to match bytes.
#' @param replace Function of one match (a character string) that returns
#'   its replacement.
#'
#' @returns Character string.
#'
#' @keywords internal
#' @noRd
replace_matches <- function(text, pattern, use_bytes, replace) {
  matches <- gregexpr(pattern, text, perl = TRUE, useBytes = use_bytes)
  if (identical(as.integer(matches[[1L]][[1L]]), -1L)) {
    return(text)
  }
  found <- regmatches(text, matches)[[1L]]
  replaced <- vapply(found, replace, character(1L), USE.NAMES = FALSE)
  if (isTRUE(identical(found, replaced))) {
    return(text)
  }
  regmatches(text, matches) <- list(replaced)
  return(text)
}

#' A command line as `condathis` reports it
#'
#' Each word quoted with `shQuote()` and the credentials of URLs hidden
#' (see `hide_secrets()`): the `cmd` of the results of `native_cmd()`, the
#' run family and every backend.
#'
#' @param words Character vector, the program and its arguments.
#'
#' @returns Character string.
#'
#' @keywords internal
#' @noRd
format_cmd_line <- function(words) {
  return(paste(
    shQuote(hide_secrets(as.character(words))),
    collapse = " "
  ))
}

#' Print the "Running" line of a command
#'
#' The line that `processx` prints with `echo_cmd = TRUE` (its
#' `do_echo_cmd()`), with the credentials of URLs hidden (see
#' `hide_secrets()`): words without characters that a shell reads are not
#' quoted, and the line is wrapped at the console width, with ` \` at the
#' end of each wrapped line.
#'
#' @param command Character string, the program.
#' @param args Character vector of its arguments.
#'
#' @returns `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
echo_command_line <- function(command, args = character(0L)) {
  words <- hide_secrets(as.character(c("Running", command, args)))
  plain <- grepl("^[-a-zA-Z0-9/_\\.]*$", words)
  words[!plain] <- shQuote(words[!plain])
  width <- getOption("width", 80L) - 3L
  lines <- character(0L)
  line <- NULL
  line_width <- 0L
  for (word in words) {
    word_width <- nchar(word, type = "width")
    if (is.null(line)) {
      line <- word
      line_width <- word_width
    } else if (line_width + 1L + word_width <= width) {
      line <- paste(line, word)
      line_width <- line_width + 1L + word_width
    } else {
      lines <- c(lines, line)
      line <- paste0("  ", word)
      line_width <- 2L + word_width
    }
  }
  lines <- c(lines, line)
  n_lines <- length(lines)
  if (n_lines > 1L) {
    lines[-n_lines] <- paste0(lines[-n_lines], " \\")
  }
  cat(lines, sep = "\n")
  return(invisible(NULL))
}
