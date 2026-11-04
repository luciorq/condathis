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
#' @param verbose The value of `verbose`: one of `"output"`, `"silent"`,
#'   `"cmd"`, `"spinner"`, `"full"`, or the unchanged default vector of
#'   choices; `TRUE` means `"output"` and `FALSE` means `"silent"`.
#' @param call Environment of the function the error is reported for.
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
  return(parse_strategy_verbose(verbose = verbose, call = call))
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
