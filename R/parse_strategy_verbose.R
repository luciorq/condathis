#' Parse Verbosity Level Strategy
#'
#' This function parses the verbose string strategy and returns a list
#' indicating what types of output should be printed to the console.
#' This controls whether command output and/or messages should be shown.
#'
#' @param strategy Character string specifying the verbosity level.
#'
#' @return A list with logical elements indicating each type of output to show.
#'
#' @details
#' The types of output are:
#'
#' - `cmd`: Whether to show the command being executed.
#' - `output`: Whether to show the output from the command.
#' - `quiet_flag`: A flag passed to internal `micromammba` call.
#' - `internal_verbose`: A string indicating the verbosity level for internal
#'   functions.
#'
#' @keywords internal
#' @noRd
parse_strategy_verbose <- function(
  strategy = c(
    "output",
    "silent",
    "cmd",
    "full"
  )
) {
  if (isTRUE(length(strategy) > 1L)) {
    strategy <- strategy[1]
  }
  if (isTRUE(strategy)) {
    strategy <- "output"
  }
  if (isFALSE(strategy)) {
    strategy <- "silent"
  }
  verbose_flags <- switch(
    EXPR = strategy,
    silent = list(cmd = FALSE, output = FALSE),
    cmd = list(cmd = TRUE, output = FALSE),
    output = list(cmd = FALSE, output = TRUE),
    full = list(cmd = TRUE, output = TRUE),
    cli::cli_abort(
      message = c(
        `x` = 'Invalid `verbose` argument: {.code verbose = "{strategy}"}'
      ),
      class = "condathis_error_invalid_verbose"
    )
  )
  return(verbose_flags)
}
