#' Validate an `env_name` argument
#'
#' Shared check for `env_name` arguments: a single, non-missing, non-`NA`
#' character string that is a plain directory name. Every exported function
#' that accepts `env_name` uses it, so the same bad input is rejected the
#' same way everywhere. It does **not** check whether the environment
#' exists. See `env_exists()` for that.
#'
#' An environment given by `env_path()` is rejected with class
#' `condathis_env_path_read_only` (and `condathis_invalid_env_name`):
#' functions that accept one check for it before calling this.
#'
#' The environment directory is `<root>/envs/<env_name>`, and creating or
#' removing an environment can delete that directory. A name such as `""`,
#' `".."` or `"../x"` resolved to `<root>/envs`, `<root>` or a directory
#' outside the root, which `remove_env()` and `create_env()` then deleted.
#' On Windows, `"myenv."` resolved to the directory of `"myenv"`, which they
#' deleted too. Rejected names: empty, `.` and `..`, names starting with `-`
#' (read as a command-line option), names containing a path separator,
#' `:`, `#`, whitespace, control characters, or characters Windows forbids
#' in file names (`<>"|?*`), names ending with `.`, and Windows device names
#' (see `invalid_env_name_reason()`). The rules are the same on every OS, so
#' an environment name works on every OS.
#'
#' @param env_name The value to validate.
#' @param class Character vector. The calling function's own classes, the
#'   most specific first, so each call site keeps its documented class.
#'   Every error appends `c("condathis_invalid_env_name",
#'   "condathis_invalid_arg", "condathis_error")`.
#' @param call Calling environment, passed to `condathis_abort()` so the
#'   error is attributed to the public-facing caller, not this helper.
#'
#' @returns `env_name`, invisibly, when valid. Aborts otherwise.
#'
#' @keywords internal
#' @noRd
validate_env_name <- function(env_name, class, call = rlang::caller_env()) {
  error_class <- c(class, "condathis_invalid_env_name", "condathis_invalid_arg")
  if (missing(env_name)) {
    condathis_abort(
      message = c(`x` = "{.arg env_name} is absent but must be supplied."),
      class = error_class,
      call = call
    )
  }
  if (isTRUE(is_env_path(env_name))) {
    abort_env_path_read_only(class = error_class, call = call)
  }
  if (
    isFALSE(rlang::is_character(env_name)) ||
      isFALSE(identical(length(env_name), 1L)) ||
      is.na(env_name)
  ) {
    condathis_abort(
      message = c(
        `x` = "{.arg env_name} must be a single, non-missing character string, not {.obj_type_friendly {env_name}}."
      ),
      class = error_class,
      call = call
    )
  }
  reason <- invalid_env_name_reason(env_name)
  if (isFALSE(is.null(reason))) {
    condathis_abort(
      message = c(
        `x` = "{.arg env_name} {.val {env_name}} is not a valid environment name.",
        `x` = reason,
        `i` = "Use a plain directory name that is valid on Linux, macOS and Windows."
      ),
      class = error_class,
      call = call
    )
  }
  return(invisible(env_name))
}

#' Is `env_name` a plain, safe environment directory name?
#'
#' @param env_name The value to check.
#'
#' @returns Logical scalar.
#'
#' @keywords internal
#' @noRd
is_valid_env_name <- function(env_name) {
  return(is.null(invalid_env_name_reason(env_name)))
}

#' Why is `env_name` not a valid environment directory name?
#'
#' Windows drops trailing dots and spaces from path components, so
#' `<root>/envs/myenv.` opens `<root>/envs/myenv`. Windows also opens a
#' device for the names `CON`, `PRN`, `AUX`, `NUL`, `CONIN$`, `CONOUT$`,
#' `COM1` to `COM9` and `LPT1` to `LPT9`, in any letter case and with any
#' extension (`nul.txt`). Whitespace is already rejected anywhere in the
#' name, so a trailing space needs no separate rule.
#'
#' @param env_name The value to check.
#'
#' @returns A character string with a `cli` message bullet, or `NULL` when
#'   `env_name` is valid.
#'
#' @keywords internal
#' @noRd
invalid_env_name_reason <- function(env_name) {
  # `delete_stale_env_dir()` calls this on its own, as a last check before
  # a deletion, so it must not take `NA` for a valid name.
  if (isFALSE(rlang::is_string(env_name))) {
    return("It is not a single, non-missing character string.")
  }
  if (isFALSE(nzchar(env_name))) {
    return("It is empty.")
  }
  if (isTRUE(env_name %in% c(".", ".."))) {
    return("It is the current or the parent directory.")
  }
  if (isTRUE(startsWith(env_name, "-"))) {
    return("It starts with {.val -}, which is read as a command-line option.")
  }
  if (isTRUE(grepl("[/\\\\:#<>\"|?*[:space:][:cntrl:]]", env_name))) {
    return(paste(
      "It contains a path separator, {.val :}, {.val #}, whitespace,",
      "a control character, or one of {.val <>\"|?*}."
    ))
  }
  if (isTRUE(endsWith(env_name, "."))) {
    return("It ends with {.val .}, which Windows drops from directory names.")
  }
  if (isTRUE(is_windows_device_name(env_name))) {
    return(paste(
      "It is a Windows device name, such as {.val CON}, {.val NUL} or",
      "{.val COM1}, with or without an extension."
    ))
  }
  return(NULL)
}

#' Is `name` a Windows device name?
#'
#' Windows compares the part before the first dot, without trailing spaces
#' and in any letter case, so `"nul"`, `"NUL.txt"` and `"Com1.tar.gz"` all
#' open a device.
#'
#' @param name A single character string.
#'
#' @returns Logical scalar.
#'
#' @keywords internal
#' @noRd
is_windows_device_name <- function(name) {
  # The superscript digits one, two and three are device names too.
  digits <- c(as.character(1:9), "\u00b9", "\u00b2", "\u00b3")
  device_names <- c(
    "CON",
    "PRN",
    "AUX",
    "NUL",
    "CONIN$",
    "CONOUT$",
    paste0("COM", digits),
    paste0("LPT", digits)
  )
  stem <- sub(" +$", "", sub("\\..*$", "", name))
  return(isTRUE(toupper(stem) %in% device_names))
}
