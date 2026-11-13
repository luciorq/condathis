#' Validate the `cmd` argument of the run family
#'
#' A missing `cmd` aborts with `"{.arg cmd} is absent but must be
#' supplied."`. This also holds when the caller passes on its own missing
#' argument, as in `validate_cmd_arg(cmd, ...)` inside `run()`. Any value
#' that is not a single, non-`NA`, non-empty string aborts too.
#'
#' @param cmd The value of `cmd`.
#' @param class Character vector, the function's own classes, the most
#'   specific first, for example
#'   `c("condathis_run_invalid_cmd", "condathis_run_null_cmd")`.
#'   `c("condathis_invalid_cmd", "condathis_invalid_arg")` is appended.
#' @param call Environment of the function the error is reported for.
#'
#' @returns `cmd`, invisibly.
#'
#' @keywords internal
#' @noRd
validate_cmd_arg <- function(cmd, class, call = rlang::caller_env()) {
  error_class <- c(class, "condathis_invalid_cmd", "condathis_invalid_arg")
  if (missing(cmd)) {
    condathis_abort(
      message = c(`x` = "{.arg cmd} is absent but must be supplied."),
      class = error_class,
      call = call
    )
  }
  if (
    isFALSE(rlang::is_string(cmd)) || isTRUE(is.na(cmd)) || isFALSE(nzchar(cmd))
  ) {
    message <- c(
      `x` = "{.arg cmd} must be a single, non-empty character string, not {.obj_type_friendly {cmd}}."
    )
    if (isTRUE(is.character(cmd)) && isTRUE(length(cmd) > 1L)) {
      message <- c(
        message,
        `i` = "Pass the arguments of the command in {.arg ...}."
      )
    }
    condathis_abort(message = message, class = error_class, call = call)
  }
  return(invisible(cmd))
}

#' Validate a logical flag argument
#'
#' @param x The value of the argument.
#' @param class Character vector of classes, usually
#'   `arg_error_class(fn, "<arg>")`. `"condathis_invalid_arg"` is appended.
#' @param arg_name Character string, the argument name for the message. The
#'   default is the expression passed as `x`.
#' @param call Environment of the function the error is reported for.
#'
#' @returns `x`, invisibly, when it is `TRUE` or `FALSE`. Aborts otherwise,
#'   also for `NA` and for vectors.
#'
#' @keywords internal
#' @noRd
validate_bool_arg <- function(
  x,
  class,
  arg_name = rlang::caller_arg(x),
  call = rlang::caller_env()
) {
  if (isFALSE(rlang::is_bool(x))) {
    condathis_abort(
      message = c(
        `x` = "{.arg {arg_name}} must be {.code TRUE} or {.code FALSE}, not {.obj_type_friendly {x}}."
      ),
      class = c(class, "condathis_invalid_arg"),
      call = call
    )
  }
  return(invisible(x))
}

#' Largest timeout that a process wait accepts
#'
#' `processx` waits take an integer number of milliseconds, so a timeout
#' above `.Machine$integer.max %/% 1000` seconds (2147483 s, about 24.8
#' days) cannot be passed on.
#'
#' @returns Integer scalar, seconds.
#'
#' @keywords internal
#' @noRd
max_process_timeout_secs <- function() {
  return(.Machine$integer.max %/% 1000L)
}

#' Validate and normalize a `timeout` argument of the run family
#'
#' @param timeout The value of `timeout`. It must pass `is_timeout_value()`:
#'   a single, non-`NA`, non-negative number. `Inf` means no limit.
#' @param class Character vector of classes, usually
#'   `arg_error_class(fn, "timeout")`. `"condathis_invalid_arg"` is
#'   appended.
#' @param call Environment of the function the error is reported for.
#'
#' @returns A double: `min(timeout, 2147483)` for a finite value, `Inf`
#'   otherwise.
#'
#' @keywords internal
#' @noRd
validate_timeout_arg <- function(timeout, class, call = rlang::caller_env()) {
  if (isFALSE(is_timeout_value(timeout))) {
    condathis_abort(
      message = c(
        `x` = "{.arg timeout} must be a single, non-negative number of seconds, or {.code Inf}, not {.obj_type_friendly {timeout}}."
      ),
      class = c(class, "condathis_invalid_arg"),
      call = call
    )
  }
  if (isTRUE(is.finite(timeout))) {
    return(base::min(as.double(timeout), max_process_timeout_secs()))
  }
  return(Inf)
}

#' Validate a `stdout` or `stderr` target
#'
#' @param x The value of the argument: `NULL` (discard), `"|"` (capture),
#'   `""` (inherit), or a file path.
#' @param class Character vector of classes, usually
#'   `arg_error_class(fn, "stdout")`. `"condathis_invalid_arg"` is appended.
#' @param arg_name Character string, the argument name for the message.
#' @param call Environment of the function the error is reported for.
#'
#' @returns `x`, invisibly, when it is `NULL` or a single, non-`NA` string.
#'
#' @keywords internal
#' @noRd
validate_target_arg <- function(
  x,
  class,
  arg_name = rlang::caller_arg(x),
  call = rlang::caller_env()
) {
  if (isFALSE(is.null(x)) && isFALSE(rlang::is_string(x))) {
    condathis_abort(
      message = c(
        `x` = "{.arg {arg_name}} must be {.code NULL} or a single character string, not {.obj_type_friendly {x}}."
      ),
      class = c(class, "condathis_invalid_arg"),
      call = call
    )
  }
  return(invisible(x))
}

#' Validate a `stdin` argument
#'
#' @param stdin The value of `stdin`: `NULL` (no input), `"|"` (write
#'   `input`), or the path of an existing regular file.
#' @param class Character vector of classes, usually
#'   `arg_error_class(fn, "stdin")`. `"condathis_invalid_arg"` is appended.
#' @param call Environment of the function the error is reported for.
#'
#' @returns `stdin`, invisibly.
#'
#' @keywords internal
#' @noRd
validate_stdin_arg <- function(stdin, class, call = rlang::caller_env()) {
  if (is.null(stdin) || identical(stdin, "|")) {
    return(invisible(stdin))
  }
  if (isFALSE(rlang::is_string(stdin))) {
    condathis_abort(
      message = c(
        `x` = "{.arg stdin} must be {.code NULL}, {.val |}, or the path of a file, not {.obj_type_friendly {stdin}}."
      ),
      class = c(class, "condathis_invalid_arg"),
      call = call
    )
  }
  if (isFALSE(isTRUE(fs::is_file(stdin)))) {
    condathis_abort(
      message = c(
        `x` = "{.arg stdin} must be {.code NULL}, {.val |}, or the path of a file.",
        `i` = "{.path {stdin}} is not a file."
      ),
      class = c(class, "condathis_invalid_arg"),
      call = call
    )
  }
  return(invisible(stdin))
}

#' Validate the process arguments of the run family
#'
#' Checks, in this order: `stdout`, `stderr`, `stdin`, `supervise`,
#' `cleanup_tree`, `linux_pdeathsig`, `activate`, `timeout`. Call it with the
#' other argument checks, before `resolve_backend()` or any other side
#' effect (rule R2).
#'
#' Each error has the classes `arg_error_class(fn, "<arg>")`, for example
#' `c("condathis_run_bin_invalid_timeout", "condathis_invalid_timeout",
#' "condathis_invalid_arg", "condathis_error")`. For `stdin` of `run()` and
#' `run_bin()`, the old class `"condathis_run_stdin_error"` is kept after
#' the function class.
#'
#' @param fn Character string, the exported function name: `"run"`,
#'   `"run_bin"` or `"run_pipeline"`.
#' @param timeout,supervise,cleanup_tree,linux_pdeathsig,stdin,stdout,stderr
#'   The values of those arguments.
#' @param activate The value of `activate`. `run()` has none and keeps the
#'   default `TRUE`.
#' @param call Environment of the function the error is reported for.
#'
#' @returns `list(timeout = <normalized>)`, see `validate_timeout_arg()`.
#'
#' @keywords internal
#' @noRd
validate_run_args <- function(
  fn,
  timeout,
  supervise,
  cleanup_tree,
  linux_pdeathsig,
  stdin,
  stdout,
  stderr,
  activate = TRUE,
  call = rlang::caller_env()
) {
  validate_target_arg(
    stdout,
    class = arg_error_class(fn, "stdout"),
    arg_name = "stdout",
    call = call
  )
  validate_target_arg(
    stderr,
    class = arg_error_class(fn, "stderr"),
    arg_name = "stderr",
    call = call
  )
  stdin_aliases <- if (isTRUE(fn %in% c("run", "run_bin"))) {
    "condathis_run_stdin_error"
  }
  validate_stdin_arg(
    stdin,
    class = arg_error_class(fn, "stdin", aliases = stdin_aliases),
    call = call
  )
  validate_bool_arg(
    supervise,
    class = arg_error_class(fn, "supervise"),
    arg_name = "supervise",
    call = call
  )
  validate_bool_arg(
    cleanup_tree,
    class = arg_error_class(fn, "cleanup_tree"),
    arg_name = "cleanup_tree",
    call = call
  )
  validate_bool_arg(
    linux_pdeathsig,
    class = arg_error_class(fn, "linux_pdeathsig"),
    arg_name = "linux_pdeathsig",
    call = call
  )
  validate_bool_arg(
    activate,
    class = arg_error_class(fn, "activate"),
    arg_name = "activate",
    call = call
  )
  timeout <- validate_timeout_arg(
    timeout,
    class = arg_error_class(fn, "timeout"),
    call = call
  )
  return(list(timeout = timeout))
}

#' Describe a value for an error message
#'
#' `cli`'s `{.obj_type_friendly}`, formatted now. Braces are doubled, so
#' the text can go into a message that is interpolated again.
#'
#' @param x Any value.
#'
#' @returns Character string, for example `"a number"` or `"NULL"`.
#'
#' @keywords internal
#' @noRd
describe_value <- function(x) {
  text <- cli::ansi_strip(cli::format_inline("{.obj_type_friendly {x}}"))
  return(gsub("}", "}}", gsub("{", "{{", text, fixed = TRUE), fixed = TRUE))
}

#' Does a string look like the name of an environment file?
#'
#' A spec never ends in `.yml`, `.yaml`, `.json` or `.lock`, so such a
#' value is a file that belongs in `env_definition()`. This also covers
#' lock files such as `conda-lock.yml`, `ci-lock.yaml`, `env.json` and
#' `pixi.lock`.
#'
#' @param x Character vector.
#'
#' @returns A logical vector.
#'
#' @keywords internal
#' @noRd
is_env_file_name <- function(x) {
  return(grepl("\\.(ya?ml|json|lock)$", x, ignore.case = TRUE))
}

#' Describe why a value is not a vector of package specs
#'
#' @param x The value to check.
#'
#' @returns A verb phrase for a cli message, such as `"is a number"` or
#'   `"contains {.val {NA}}"`, or `NULL` when `x` is a character vector
#'   without `NA` or `""`.
#'
#' @keywords internal
#' @noRd
package_specs_problem <- function(x) {
  if (isTRUE(is_env_definition(x))) {
    return("is an environment definition from {.fn env_definition}")
  }
  if (isFALSE(is.character(x))) {
    return(paste("is", describe_value(x)))
  }
  if (isTRUE(anyNA(x))) {
    return("contains {.val {NA}}")
  }
  if (isFALSE(all(nzchar(x)))) {
    return("contains an empty string")
  }
  return(NULL)
}

#' Validate a vector of package specs
#'
#' For a value that holds package specs as one argument, for example the
#' deprecated `packages =` alias (see `collect_package_specs()`).
#'
#' @param packages The value to check.
#' @param allow_null Logical. Whether `NULL` and `character(0)` mean "no
#'   packages" (`TRUE`) or abort with `missing_class` (`FALSE`).
#' @param missing_class Character vector, classes for a missing value, and
#'   for `NULL` or `character(0)` when `allow_null` is `FALSE`.
#' @param invalid_class Character vector, classes for any other value that
#'   is not a character vector without `NA` or `""`.
#' @param arg_name Character string, the argument name for the message.
#' @param call Environment of the function the error is reported for.
#'
#' @returns An unnamed character vector of specs, `character(0)` for no
#'   packages. Both error classes get
#'   `c("condathis_invalid_packages", "condathis_invalid_arg")` appended.
#'
#' @keywords internal
#' @noRd
validate_packages_arg <- function(
  packages,
  allow_null,
  missing_class,
  invalid_class,
  arg_name = rlang::caller_arg(packages),
  call = rlang::caller_env()
) {
  shared <- c("condathis_invalid_packages", "condathis_invalid_arg")
  if (missing(packages)) {
    condathis_abort(
      message = c(`x` = "{.arg {arg_name}} is absent but must be supplied."),
      class = c(missing_class, shared),
      call = call
    )
  }
  if (is.null(packages) || identical(packages, character(0L))) {
    if (isTRUE(allow_null)) {
      return(character(0L))
    }
    condathis_abort(
      message = c(
        `x` = "{.arg {arg_name}} must contain at least one package spec."
      ),
      class = c(missing_class, shared),
      call = call
    )
  }
  problem <- package_specs_problem(packages)
  if (isFALSE(is.null(problem))) {
    condathis_abort(
      message = c(
        `x` = "{.arg {arg_name}} must be a character vector of package specs.",
        `x` = paste0("It ", problem, ".")
      ),
      class = c(invalid_class, shared),
      call = call
    )
  }
  return(unname(as.character(packages)))
}

#' Validate `channels` and `additional_channels`
#'
#' `channels` must be a non-empty character vector without `NA` or `""`,
#' or `NULL` when `allow_null` is `TRUE`. `additional_channels` must be
#' `NULL` or a non-empty character vector.
#'
#' @param channels,additional_channels The values of those arguments.
#' @param class Character vector, the function's own classes, for example
#'   `"condathis_create_env_invalid_channels"`. For `channels`,
#'   `c("condathis_invalid_channels", "condathis_invalid_arg")` is appended.
#'   For `additional_channels`, `c("condathis_invalid_additional_channels",
#'   "condathis_invalid_channels", "condathis_invalid_arg")`.
#' @param allow_null Logical. `TRUE` accepts `channels = NULL`, as
#'   `validate_env()` does, and the message says so.
#' @param call Environment of the function the error is reported for.
#'
#' @returns `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
validate_channels_arg <- function(
  channels,
  additional_channels,
  class,
  allow_null = FALSE,
  call = rlang::caller_env()
) {
  channel_problem <- function(x) {
    if (isTRUE(is.character(x)) && identical(length(x), 0L)) {
      return("is empty")
    }
    return(package_specs_problem(x))
  }
  problem <- if (isFALSE(isTRUE(allow_null) && is.null(channels))) {
    channel_problem(channels)
  }
  if (isFALSE(is.null(problem))) {
    expected <- if (isTRUE(allow_null)) {
      "{.code NULL} or a non-empty character vector of channel names or URLs"
    } else {
      "a non-empty character vector of channel names or URLs"
    }
    condathis_abort(
      message = c(
        `x` = paste0("{.arg channels} must be ", expected, "."),
        `x` = paste0("It ", problem, ".")
      ),
      class = c(class, "condathis_invalid_channels", "condathis_invalid_arg"),
      call = call
    )
  }
  if (isFALSE(is.null(additional_channels))) {
    problem <- channel_problem(additional_channels)
    if (isFALSE(is.null(problem))) {
      condathis_abort(
        message = c(
          `x` = "{.arg additional_channels} must be {.code NULL} or a non-empty character vector of channel names or URLs.",
          `x` = paste0("It ", problem, ".")
        ),
        class = c(
          class,
          "condathis_invalid_additional_channels",
          "condathis_invalid_channels",
          "condathis_invalid_arg"
        ),
        call = call
      )
    }
  }
  return(invisible(NULL))
}

#' Collect the package specs given in `...`
#'
#' The `...` of `create_env()`, `install_packages()` and `validate_env()`
#' holds only package match specs (decision D6). This function applies
#' every rule of D6 to those values:
#'
#' * Unnamed character strings and character vectors are specs. They are
#'   flattened in order: `("a", c("b", "c"))` gives `c("a", "b", "c")`.
#'   `character(0)` adds nothing.
#' * `packages = <specs>` is a deprecated alias. It is a soft deprecation
#'   (see `condathis_deprecate_soft()`): for direct use only, it warns once
#'   per session and per function, with class
#'   `c("condathis_deprecated_packages_arg", "condathis_warning")`.
#'   `packages = NULL` and `packages = character(0)` mean no specs.
#'   `packages =` together with unnamed specs aborts, and so does
#'   `packages =` given twice. When the other value is one string, the hint
#'   names it as `env_name =`, its 0.1.4 positional meaning, or for a
#'   file name (see `is_env_file_name()`) as `env_definition()`, the
#'   successor of the 0.1.4 positional `env_file`.
#' * Any other named value aborts: the name is a misspelled or unknown
#'   argument. The message names the closest formal of the caller, for
#'   example `chanels = ` gives "Did you mean `channels`?". A name that
#'   abbreviates `packages` (`package =`, `pack =`, `p =`) gets a hint to
#'   pass the specs unnamed: 0.1.4 matched such abbreviations.
#' * A value that is not a character vector (`NULL`, a number, a logical,
#'   a list, a factor), `NA` and `""` abort. A `NULL` before other
#'   unnamed values gets a hint that the arguments after the specs must be
#'   named, as in 0.1.4's positional `create_env("pkg", NULL, "env")`, and
#'   that a file goes in `env_definition()`. An `env_definition()` object
#'   aborts too: `create_env()`, `install_packages()` and `validate_env()`
#'   take the unnamed ones out of `...` before this function runs, so only
#'   a named one, such as `packages = env_definition(...)`, gets here. Its
#'   hint says to pass it unnamed.
#' * A spec that looks like a file name (see `is_env_file_name()`) aborts
#'   with a hint to pass it as `env_definition()`.
#' * No specs at all abort with `missing_class` when `allow_empty` is
#'   `FALSE`, unless they came from `packages = NULL` or
#'   `packages = character(0)`.
#'
#' Every error has the classes
#' `c("condathis_<fn>_invalid_packages", "condathis_invalid_packages",
#' "condathis_invalid_arg", "condathis_error")`; the no-specs error has
#' `missing_class` first instead.
#'
#' It does not check whether the last spec is the name of an existing
#' environment (an old positional `env_name`): call
#' `abort_on_positional_env_name()` for that, only when `env_name` was not
#' given.
#'
#' @param dots A list, `rlang::list2(...)` evaluated in the exported
#'   function. A list, not `...` itself, so that a user argument named like
#'   one of the formals of this helper cannot bind to it.
#' @param fn Character string, the exported function name, for the classes
#'   and messages.
#' @param allow_empty Logical. `FALSE` aborts when no spec is given.
#' @param missing_class Character vector, classes of the no-specs error.
#' @param formal_names Character vector, the formals of the exported
#'   function, used for the closest-formal hint. `NULL` (the default) reads
#'   them from the calling function.
#' @param user_env The environment the exported function was called from,
#'   `rlang::caller_env()` evaluated in the exported function, for the soft
#'   deprecation of `packages =` (see `is_direct_use()`). `NULL` counts as
#'   direct use.
#' @param call Environment of the function the error is reported for.
#'
#' @returns An unnamed character vector of specs, `character(0)` when none
#'   was given.
#'
#' @examples
#' \dontrun{
#' create_env <- function(..., env_name = "condathis-env") {
#'   user_env <- rlang::caller_env()
#'   dots <- rlang::list2(...)
#'   packages <- collect_package_specs(
#'     dots,
#'     fn = "create_env",
#'     user_env = user_env
#'   )
#' }
#' }
#'
#' @keywords internal
#' @noRd
collect_package_specs <- function(
  dots,
  fn,
  allow_empty = TRUE,
  missing_class = paste0("condathis_", fn, "_missing_packages"),
  formal_names = NULL,
  user_env = NULL,
  call = rlang::caller_env()
) {
  if (is.null(formal_names)) {
    caller <- rlang::caller_fn()
    formal_names <- if (is.function(caller)) names(formals(caller))
  }
  invalid_class <- c(
    paste0("condathis_", fn, "_invalid_packages"),
    "condathis_invalid_packages",
    "condathis_invalid_arg"
  )
  dot_names <- names(dots)
  if (is.null(dot_names)) {
    dot_names <- rep("", length(dots))
  }

  unknown_names <- setdiff(dot_names[nzchar(dot_names)], "packages")
  if (isTRUE(length(unknown_names) > 0L)) {
    bad_name <- unknown_names[[1L]]
    suggestion <- closest_names(bad_name, setdiff(formal_names, "..."))
    message <- c(`x` = "{.arg {bad_name}} is not an argument of {.fn {fn}}.")
    if (isTRUE(startsWith("packages", bad_name))) {
      # 0.1.4 matched an abbreviation of `packages`, unless it abbreviated
      # another formal too (`p` in create_env(), with `platform`).
      other_matches <- setdiff(formal_names, c("...", "packages"))
      other_matches <- other_matches[startsWith(other_matches, bad_name)]
      unnamed_hint <- "Pass package specs unnamed, before the named arguments: {.code {fn}(\"pkg\", env_name = \"my-env\")}."
      if (isTRUE(length(other_matches) > 0L)) {
        message <- c(
          message,
          `i` = "Did you mean {.or {.arg {other_matches}}}?",
          `i` = unnamed_hint
        )
      } else if (isTRUE(fn %in% c("create_env", "install_packages"))) {
        message <- c(
          message,
          `i` = "In condathis 0.1.4, {.arg {bad_name}} abbreviated {.arg packages}.",
          `i` = unnamed_hint
        )
      } else {
        message <- c(message, `i` = unnamed_hint)
      }
    } else if (
      identical(bad_name, "additional_channels") &&
        isTRUE("channels" %in% formal_names)
    ) {
      # validate_env() has one channel vector: the request of
      # create_env(channels = a, additional_channels = b) is c(a, b).
      message <- c(
        message,
        `i` = "Pass every channel in {.arg channels}: {.code channels = c(channels, additional_channels)} checks the channels of {.code create_env(channels = channels, additional_channels = additional_channels)}."
      )
    } else if (isTRUE(length(suggestion) > 0L)) {
      message <- c(message, `i` = "Did you mean {.or {.arg {suggestion}}}?")
    } else {
      message <- c(
        message,
        `i` = "Package specs in {.arg ...} must be unnamed."
      )
    }
    condathis_abort(message = message, class = invalid_class, call = call)
  }

  is_alias <- dot_names == "packages"
  specs <- character(0L)
  if (isTRUE(any(is_alias))) {
    if (isTRUE(sum(is_alias) > 1L)) {
      condathis_abort(
        message = c(`x` = "{.arg packages} must be given only once."),
        class = invalid_class,
        call = call
      )
    }
    if (isTRUE(any(!is_alias))) {
      hint <- c(`i` = "Pass every spec unnamed, before the other arguments.")
      extra <- dots[!is_alias]
      if (
        isTRUE(identical(length(extra), 1L)) &&
          isTRUE(rlang::is_string(extra[[1L]]))
      ) {
        # The 0.1.4 positional meaning of the value: `env_file` was the
        # second argument of create_env(), `env_name` the second of
        # install_packages().
        extra_value <- extra[[1L]]
        extra_hint <- if (
          isTRUE(is_env_file_name(extra_value)) &&
            isTRUE("env_file" %in% formal_names)
        ) {
          "If {.val {extra_value}} is an environment file, pass it as {.code env_definition(\"{extra_value}\")}."
        } else {
          "If {.val {extra_value}} is not a package spec, name its argument: {.code env_name = \"{extra_value}\"}."
        }
        hint <- c(`i` = extra_hint, hint)
      }
      condathis_abort(
        message = c(
          `x` = "Use either {.arg packages} or unnamed package specs, not both.",
          hint
        ),
        class = invalid_class,
        call = call
      )
    }
    condathis_deprecate_soft(
      id = paste0("deprecated_packages_arg_", fn),
      message = c(
        `!` = "The {.arg packages} argument of {.fn {fn}} is deprecated.",
        `i` = "Pass package specs unnamed, before the named arguments: {.code {fn}(\"pkg\", env_name = \"my-env\")}."
      ),
      class = "condathis_deprecated_packages_arg",
      user_env = user_env
    )
    alias_value <- dots[[which(is_alias)]]
    specs <- validate_packages_arg(
      alias_value,
      allow_null = TRUE,
      missing_class = missing_class,
      invalid_class = invalid_class,
      arg_name = "packages",
      call = call
    )
  } else {
    for (i in seq_along(dots)) {
      problem <- package_specs_problem(dots[[i]])
      if (isFALSE(is.null(problem))) {
        message <- c(
          `x` = "{.arg ...} must contain only package specs: character strings.",
          `x` = paste0("Element ", i, " ", problem, ".")
        )
        if (is.null(dots[[i]]) && isTRUE(i < length(dots))) {
          # 0.1.4's positional `create_env("pkg", NULL, "env")`.
          message <- c(
            message,
            `i` = "Arguments after the package specs must be named, as in {.code env_name = \"my-env\"}."
          )
          if (isTRUE("env_file" %in% formal_names)) {
            message <- c(
              message,
              `i` = "Pass an environment file with {.fn env_definition}, as in {.code create_env(env_definition(\"environment.yml\"), env_name = \"my-env\")}."
            )
          }
        } else if (is.null(dots[[i]]) && isTRUE(allow_empty)) {
          message <- c(
            message,
            `i` = "For no packages, pass no package specs."
          )
        } else if (isTRUE(is_env_definition(dots[[i]]))) {
          # The functions that take a definition take it unnamed only.
          message <- c(
            message,
            `i` = "Pass {.fn env_definition} unnamed, in {.arg ...}."
          )
        }
        condathis_abort(message = message, class = invalid_class, call = call)
      }
      specs <- c(specs, unname(as.character(dots[[i]])))
    }
  }

  file_like <- specs[is_env_file_name(specs)]
  if (isTRUE(length(file_like) > 0L)) {
    env_file_spec <- file_like[[1L]]
    # create_env(), install_packages() and validate_env() all take one.
    hint <- c(
      `i` = "Pass an environment file as {.code env_definition(\"{env_file_spec}\")}."
    )
    condathis_abort(
      message = c(
        `x` = "{.val {env_file_spec}} looks like an environment file, not a package spec.",
        hint
      ),
      class = invalid_class,
      call = call
    )
  }

  # Only an explicit `packages = NULL` or `character(0)` may be empty, as
  # in 0.1.4. No specs at all still abort.
  if (
    identical(length(specs), 0L) &&
      isFALSE(allow_empty) &&
      isFALSE(any(is_alias))
  ) {
    condathis_abort(
      message = c(
        `x` = "{.fn {fn}} needs at least one package spec in {.arg ...}.",
        `i` = "For example: {.code {fn}(\"pkg\", env_name = \"my-env\")}."
      ),
      class = c(
        missing_class,
        "condathis_invalid_packages",
        "condathis_invalid_arg"
      ),
      call = call
    )
  }
  return(unname(specs))
}
