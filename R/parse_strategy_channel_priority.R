#' Parse channel priority strategy
#'
#' Maps a channel priority mode to `micromamba` command-line flags.
#'
#' @param channel_priority Character string with channel priority mode.
#'   Supported values are `"disabled"`, `"strict"`, and `"flexible"`.
#'   Defaults to `"disabled"`.
#'
#' @returns A character vector of command-line arguments.
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
