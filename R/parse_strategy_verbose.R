#' The valid values of `verbose`, in the canonical order
#'
#' The first value, `"output"`, is the default of the functions that act.
#'
#' @keywords internal
#' @noRd
condathis_verbose_values <- c("output", "silent", "cmd", "spinner", "full")

#' Validate and parse the `verbose` argument of an exported function
#'
#' Every exported function that takes `verbose` calls this with its other
#' argument checks, before its first backend call (rule R2):
#' `verbose_list <- parse_verbose_arg(verbose)`. It is the shared parser,
#' so its error has only the shared classes
#' `c("condathis_invalid_verbose", "condathis_invalid_arg",
#' "condathis_error")`, and the error names the user's call.
#'
#' Unlike `parse_strategy_verbose()`, it rejects a list: only internal
#' callers may pass an already-parsed list on.
#'
#' Pass `verbose_list$strategy` (one of the five strings) to a backend
#' generic (rule R4), and `verbose_list$internal_verbose` to internal
#' probes and nested calls.
#'
#' It also records the level for the rest of the call (see
#' `local_call_verbose()`).
#'
#' @param verbose The value of `verbose`: one of `"output"`, `"silent"`,
#'   `"cmd"`, `"spinner"`, `"full"`, or the unchanged default vector of
#'   choices; `TRUE` means `"output"` and `FALSE` means `"silent"`.
#' @param call Environment of the function the error is reported for.
#'   It must be the frame of that function, which is the default, because
#'   the recorded level is restored when that frame exits.
#'
#' @returns The list of `parse_strategy_verbose()`.
#'
#' @keywords internal
#' @noRd
parse_verbose_arg <- function(verbose, call = rlang::caller_env()) {
  if (isTRUE(is.list(verbose))) {
    condathis_abort(
      message = c(
        `x` = "{.arg verbose} must be one of {.or {.val {condathis_verbose_values}}}, not a list."
      ),
      class = c("condathis_invalid_verbose", "condathis_invalid_arg"),
      call = call
    )
  }
  verbose_list <- parse_strategy_verbose(verbose = verbose, call = call)
  local_call_verbose(verbose_list$strategy, frame = call)
  return(verbose_list)
}

#' The `verbose` level of the exported call that is running
#'
#' A package-level environment with one entry, `strategy`: the level that
#' the innermost running exported function was given, or `NULL` outside of
#' one. `parse_verbose_arg()` sets it with `local_call_verbose()`.
#'
#' @keywords internal
#' @noRd
condathis_call_verbose_state <- new.env(parent = emptyenv())

#' Record the `verbose` level of an exported call while it runs
#'
#' The internal probes of a call run silently, whatever its `verbose`, for
#' example the dry-run solves of `define_platform()` and the platform query
#' of `micromamba_native_platform()`. On macOS arm64 and Windows they are
#' the first micromamba commands of `create_env()`, so the automatic install
#' of micromamba happened in them, and their `"silent"` hid it. With the
#' level of the call recorded, `install_micromamba_for_command()` follows
#' the user's level instead of the probe's.
#'
#' @param strategy Character string, one of the five verbose values.
#' @param frame The frame of the exported function: the previous level is
#'   restored when it exits, also on an error, so nested calls and later
#'   calls see the right one.
#'
#' @returns `NULL`, invisibly.
#'
#' @keywords internal
#' @noRd
local_call_verbose <- function(strategy, frame = rlang::caller_env()) {
  previous <- condathis_call_verbose_state$strategy
  condathis_call_verbose_state$strategy <- strategy
  withr::defer(
    condathis_call_verbose_state$strategy <- previous,
    envir = frame
  )
  return(invisible(NULL))
}

#' The `verbose` level of the running exported call
#'
#' @returns Character string, one of the five verbose values, or `NULL`
#'   outside of an exported call (see `local_call_verbose()`).
#'
#' @keywords internal
#' @noRd
call_verbose <- function() {
  return(condathis_call_verbose_state$strategy)
}

#' Parse verbosity strategy
#'
#' Converts a verbosity setting into normalized flags used by command runners.
#' Exported functions call `parse_verbose_arg()` instead.
#'
#' @param verbose Character, logical, or parsed verbosity list.
#'   Supported character values are `"output"`, `"silent"`, `"cmd"`,
#'   `"spinner"`, and `"full"`. A list that has an `internal_verbose`
#'   element is returned unchanged.
#' @param call Environment of the function the error is reported for.
#'
#' @returns A named list with execution flags:
#'   `cmd`, `output`, `quiet_flag`, `internal_verbose`, `spinner_flag`,
#'   and `strategy`.
#'   `quiet_flag` holds the micromamba arguments that hide its own output
#'   below `"full"`, see `micromamba_quiet_args`.
#'   An invalid value aborts with class
#'   `c("condathis_invalid_verbose", "condathis_invalid_arg",
#'   "condathis_error")`.
#'
#' @keywords internal
#' @noRd
parse_strategy_verbose <- function(
  verbose = c(
    "output",
    "silent",
    "cmd",
    "spinner",
    "full"
  ),
  call = rlang::caller_env()
) {
  if (
    rlang::has_name(verbose, "internal_verbose") &&
      rlang::is_list(verbose)
  ) {
    return(verbose)
  }

  if (isTRUE(verbose)) {
    verbose <- "output"
  } else if (isFALSE(verbose)) {
    verbose <- "silent"
  } else {
    verbose <- arg_match_classed(
      verbose,
      values = condathis_verbose_values,
      class = "condathis_invalid_verbose",
      arg_name = "verbose",
      call = call
    )
  }

  verbose_flags_list <- base::switch(
    EXPR = verbose,
    silent = list(
      cmd = FALSE,
      output = FALSE,
      quiet_flag = micromamba_quiet_args,
      internal_verbose = "silent",
      spinner_flag = FALSE
    ),
    cmd = list(
      cmd = TRUE,
      output = FALSE,
      quiet_flag = micromamba_quiet_args,
      internal_verbose = "spinner",
      spinner_flag = rlang::is_interactive()
    ),
    output = list(
      cmd = FALSE,
      output = TRUE,
      quiet_flag = micromamba_quiet_args,
      internal_verbose = "spinner",
      spinner_flag = rlang::is_interactive()
    ),
    spinner = list(
      cmd = FALSE,
      output = FALSE,
      quiet_flag = micromamba_quiet_args,
      internal_verbose = "spinner",
      spinner_flag = rlang::is_interactive()
    ),
    full = list(
      cmd = TRUE,
      output = TRUE,
      quiet_flag = NULL,
      internal_verbose = "full",
      spinner_flag = rlang::is_interactive()
    )
  )

  verbose_flags_list$strategy <- verbose

  return(verbose_flags_list)
}

#' Micromamba arguments that hide its output but keep its errors
#'
#' `--quiet` also hid micromamba's error messages, so a failed
#' `create_env()` or `install_packages()` raised an error with no text.
#' `--log-level error` keeps error messages on stderr. `native_cmd()` does
#' not echo the progress output micromamba still prints to stdout.
#'
#' @keywords internal
#' @noRd
micromamba_quiet_args <- c("--log-level", "error")
