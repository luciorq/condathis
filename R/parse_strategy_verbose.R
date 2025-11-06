#' Parse Verbosity Level Strategy
#'
#' This function parses the verbose string strategy and returns a list
#' indicating what types of output should be printed to the console.
#' This controls whether command output and/or messages should be shown.
#'
#' @param verbose Character string specifying the verbosity level.
#'
#' @returns A list with logical elements indicating each type of output to show.
#'
#' @details
#' The output contains types of output are:
#'
#' - `cmd`: Whether to show the command being executed.
#' - `output`: Whether to show the output from the command.
#' - `quiet_flag`: A flag passed to internal `micromammba` call.
#' - `internal_verbose`: A string indicating the verbosity level for internal
#'   functions.
#' - `spinner`: Whether to show a spinner animation for commands.
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
      error_call = rlang::caller_env(n = 2)
    )
  }

  verbose_flags_list <- switch(
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
