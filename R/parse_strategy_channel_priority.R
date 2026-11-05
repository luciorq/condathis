#' Parse channel priority strategy
#'
#' Maps a channel priority mode to `micromamba` command-line flags.
#'
#' @param channel_priority Character string with channel priority mode.
#'   Supported values are `"strict"`, `"flexible"`, and `"disabled"`.
#'   Defaults to `"strict"`.
#' @param class Character vector of the caller's own classes for an invalid
#'   value, or `NULL`. `c("condathis_invalid_channel_priority",
#'   "condathis_invalid_arg")` is appended.
#' @param call Environment of the function the error is reported for.
#'
#' @returns A character vector of command-line arguments.
#'
#' @keywords internal
#' @noRd
parse_strategy_channel_priority <- function(
  channel_priority = c("strict", "flexible", "disabled"),
  class = NULL,
  call = rlang::caller_env()
) {
  channel_priority <- arg_match_classed(
    channel_priority,
    values = c("strict", "flexible", "disabled"),
    class = c(class, "condathis_invalid_channel_priority"),
    arg_name = "channel_priority",
    call = call
  )

  channel_priority_args <- base::switch(
    EXPR = channel_priority,
    disabled = c("--no-channel-priority", "--channel-priority=0"),
    strict = c("--strict-channel-priority", "--channel-priority=2"),
    flexible = c("--channel-priority=1")
  )

  return(channel_priority_args)
}
