#' Parse verbosity strategy
#'
#' Converts a verbosity setting into normalized flags used by command runners.
#'
#' @param verbose Character, logical, or parsed verbosity list.
#'   Supported character values are `"output"`, `"silent"`, `"cmd"`,
#'   `"spinner"`, and `"full"`.
#'
#' @returns A named list with execution flags:
#'   `cmd`, `output`, `quiet_flag`, `internal_verbose`, `spinner_flag`,
#'   and `strategy`.
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
  )
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
    verbose <- rlang::arg_match(
      verbose,
      error_call = rlang::caller_env(n = 2L)
    )
  }

  verbose_flags_list <- base::switch(
    EXPR = verbose,
    silent = list(
      cmd = FALSE,
      output = FALSE,
      quiet_flag = "--quiet",
      internal_verbose = "silent",
      spinner_flag = FALSE
    ),
    cmd = list(
      cmd = TRUE,
      output = FALSE,
      quiet_flag = "--quiet",
      internal_verbose = "spinner",
      spinner_flag = rlang::is_interactive()
    ),
    output = list(
      cmd = FALSE,
      output = TRUE,
      quiet_flag = "--quiet",
      internal_verbose = "spinner",
      spinner_flag = rlang::is_interactive()
    ),
    spinner = list(
      cmd = FALSE,
      output = FALSE,
      quiet_flag = "--quiet",
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
