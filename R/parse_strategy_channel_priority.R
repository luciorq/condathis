#' Parse Channel Priority Strategy
#'
#' This function parses the channel priority strategy and returns
#' the appropriate command-line arguments for `micromamba`.
#'
#' @param channel_priority Character string specifying the channel priority
#' strategy.
#'
#' @returns A character vector of command-line arguments used by internal
#' `micromamba` calls.
#'
#' @keywords internal
#' @noRd
parse_strategy_channel_priority <- function(
  channel_priority = c(
    "disabled",
    "strict",
    "flexible"
  )
) {
  channel_priority <- rlang::arg_match(
    channel_priority,
    error_call = rlang::caller_env(n = 1L)
  )

  channel_priority_args <- base::switch(
    EXPR = channel_priority,
    disabled = c("--no-channel-priority", "--channel-priority=0"),
    strict = c("--strict-channel-priority", "--channel-priority=2"),
    flexible = c("--channel-priority=1")
  )

  return(channel_priority_args)
}
