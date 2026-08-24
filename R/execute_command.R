#' Spawn a process, with or without writable stdin
#'
#' The single place `condathis` actually starts a child process. Both
#' execution paths converge here so that `timeout`, `supervise`,
#' `cleanup_tree`, `linux_pdeathsig`, `encoding` and the echo/spinner
#' behaviour are wired identically no matter which backend resolved the
#' command — the `"micromamba"` path (via `native_cmd()`, which spawns
#' `micromamba run ...`) and any other backend's path (via
#' `run_internal_backend()`, which spawns the resolved command directly).
#'
#' The split is `processx`'s, not `condathis`'s: `processx::run()` accepts
#' `stdin = "|"` but never exposes the resulting connection, so writing to a
#' child's stdin needs `processx::process$new()` driven by hand — see
#' `run_process_with_input()` for that half and the hazards it avoids.
#'
#' @param command Character string with the executable to spawn.
#' @param args Character vector of arguments.
#' @param wd Working directory for the child process, or `NULL` to inherit.
#' @param env Environment variables for the child. `NULL` inherits the
#'   current environment unchanged; `c("current", NAME = "value", ...)` is
#'   `processx`'s idiom for "inherit, then override these".
#' @param spinner Logical, whether to show a spinner while waiting. Ignored
#'   on the writable-stdin path, which has no live streaming.
#' @param echo_cmd Logical, whether to print the command before running it.
#' @param echo Logical, whether to echo the child's stdout/stderr.
#' @param stdout,stderr,stdin Stream targets, as in `processx::run()`.
#' @param input Character or raw vector written to stdin when `stdin = "|"`.
#' @param error_on_status Logical, whether a non-zero exit signals.
#' @param cleanup_tree,supervise,linux_pdeathsig Process-cleanup options,
#'   passed through unchanged.
#' @param encoding `"utf-8"` or `"binary"`.
#' @param timeout Numeric seconds, or `Inf`.
#'
#' @returns A `processx::run()`-shaped list: `status`, `stdout`, `stderr`,
#'   `timeout`, and (on the writable-stdin path) `pid`.
#'
#' @keywords internal
#' @noRd
execute_command <- function(
  command,
  args = character(0L),
  wd = NULL,
  env = NULL,
  spinner = FALSE,
  echo_cmd = FALSE,
  echo = FALSE,
  stdout = "|",
  stderr = "|",
  stdin = NULL,
  input = NULL,
  error_on_status = TRUE,
  cleanup_tree = FALSE,
  supervise = FALSE,
  linux_pdeathsig = FALSE,
  encoding = "utf-8",
  timeout = Inf
) {
  if (identical(stdin, "|")) {
    return(run_process_with_input(
      command = command,
      args = args,
      input = input,
      stdout = stdout,
      stderr = stderr,
      echo_cmd = echo_cmd,
      echo = echo,
      env = env,
      wd = wd,
      error_on_status = error_on_status,
      cleanup_tree = cleanup_tree,
      supervise = supervise,
      linux_pdeathsig = linux_pdeathsig,
      encoding = encoding,
      timeout = timeout
    ))
  }
  return(processx::run(
    command = command,
    args = args,
    wd = wd,
    env = env,
    spinner = spinner,
    echo_cmd = echo_cmd,
    echo = echo,
    stdout = stdout,
    stdout_line_callback = NULL,
    stderr = stderr,
    stderr_line_callback = NULL,
    stdin = stdin,
    error_on_status = error_on_status,
    cleanup_tree = cleanup_tree,
    encoding = encoding,
    linux_pdeathsig = linux_pdeathsig,
    supervise = supervise,
    timeout = timeout
  ))
}
