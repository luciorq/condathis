#' Run a binary from a Conda environment
#'
#' `run_bin()` is superseded by [run()], which takes the same arguments
#' and runs the command the same way. `run_bin()` stays for code written
#' for earlier versions of `condathis`. Its errors have their own classes,
#' `condathis_run_bin_*`, which also carry the `condathis_run_*` classes
#' (see [condathis-conditions]).
#'
#' In `condathis` 0.1.4, `run_bin()` ran a program of the environment
#' without its activation. It now activates the environment, as [run()]
#' does. `activate = FALSE` gives the fixed activation of [run()].
#'
#' @inheritParams condathis-params
#' @inheritParams run
#' @param ... Arguments of the command, unnamed, as in [run()]. Values
#'   that [run()] rejects abort with class
#'   `condathis_run_bin_invalid_args`.
#'
#' @returns A `condathis_result` object, invisibly, as for [run()].
#'
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   channel <- system.file(
#'     "extdata", "polyglot-channel",
#'     package = "condathis"
#'   )
#'   condathis::create_env(
#'     "polyglot",
#'     env_name = "polyglot-env",
#'     channels = channel
#'   )
#'   # The same as condathis::run("polyglot", env_name = "polyglot-env")
#'   condathis::run_bin("polyglot", env_name = "polyglot-env")
#' })
#' }
#'
#' @seealso [run()].
#' @family commands
#'
#' @export
run_bin <- function(
  cmd,
  ...,
  env_name = "condathis-env",
  method = "auto",
  verbose = c(
    "output",
    "silent",
    "cmd",
    "spinner",
    "full"
  ),
  error = c("cancel", "continue"),
  stdout = "|",
  stderr = "|",
  stdin = NULL,
  input = NULL,
  binary = FALSE,
  supervise = FALSE,
  cleanup_tree = FALSE,
  linux_pdeathsig = FALSE,
  activate = TRUE,
  timeout = Inf
) {
  return(run_command(
    fn = "run_bin",
    cmd = cmd,
    args = list(...),
    formal_names = names(formals(run_bin)),
    env_name = env_name,
    method = method,
    verbose = verbose,
    error = error,
    stdout = stdout,
    stderr = stderr,
    stdin = stdin,
    input = input,
    binary = binary,
    supervise = supervise,
    cleanup_tree = cleanup_tree,
    linux_pdeathsig = linux_pdeathsig,
    activate = activate,
    timeout = timeout,
    user_env = rlang::caller_env(),
    call = rlang::current_env()
  ))
}
