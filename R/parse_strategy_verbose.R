#' Parse Verbosity Level Strategy
#'
#' @param strategy Character string specifying the verbosity level.
#' @keywords internal
#' @noRd
parse_strategy_verbose <- function(strategy) {
  if (isTRUE(strategy)) {
    strategy <- "full"
  }
  if (isFALSE(strategy)) {
    strategy <- "silent"
  }

  if (isTRUE(length(strategy) > 1L)) {
    strategy <- strategy[1]
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
