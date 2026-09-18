#' Run a micromamba command with the native backend
#'
#' Executes `micromamba` under the managed Conda root used by `condathis`.
#'
#' @param conda_cmd Character string with a micromamba subcommand.
#' @param conda_args Character vector of command arguments.
#'   Defaults to `NULL`.
#' @param ... Additional unnamed command arguments appended after `conda_args`.
#' @param verbose Character string controlling console output.
#'   Supported values are `"output"`, `"silent"`, `"cmd"`, `"spinner"`,
#'   and `"full"`. Defaults to `"output"`.
#' @param error Character string that controls error behavior.
#'   Supported values are `"cancel"` and `"continue"`.
#'   Defaults to `"cancel"`.
#' @param stdout Standard output target.
#'   Defaults to `"|"`.
#' @param stderr Standard error target.
#'   Defaults to `"|"`.
#' @param stdin Standard input source.
#'   Defaults to `NULL`. Use `"|"` together with `input` for writable stdin.
#' @param input Character or raw vector written to the process's standard
#'   input when `stdin = "|"`. Defaults to `NULL`.
#' @param cleanup_tree Logical. Whether to clean up the child process tree
#'   after the process has finished. Defaults to `FALSE`.
#' @param encoding Character string. Assumed encoding for stdout/stderr.
#'   Defaults to `"utf-8"`. Use `"binary"` for raw byte output.
#' @param linux_pdeathsig Logical. On Linux, whether to send `SIGKILL` to the
#'   child process if the parent R process dies. Has no effect on other
#'   platforms. Defaults to `FALSE`.
#' @param supervise Logical. Whether the process should be supervised by the
#'   `processx` supervisor for crash-safe cleanup. Defaults to `FALSE`.
#' @param timeout Numeric. Maximum number of seconds to let the command run
#'   before it's killed. Defaults to `Inf` (no limit).
#'
#' @returns A process result list from `processx::run()` (or an equivalent
#'   list from `run_process_with_input()` when `stdin = "|"`).
#'
#' @keywords internal
#' @noRd
native_cmd <- function(
  conda_cmd,
  conda_args = NULL,
  ...,
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
  cleanup_tree = FALSE,
  encoding = "utf-8",
  linux_pdeathsig = FALSE,
  supervise = FALSE,
  timeout = Inf
) {
  rlang::check_required(conda_cmd)

  error <- rlang::arg_match(error)
  if (isTRUE(identical(error, "cancel"))) {
    error_var <- TRUE
  } else {
    error_var <- FALSE
  }

  rlang::check_dots_unnamed()

  verbose_list <- parse_strategy_verbose(verbose = verbose)

  verbose_output <- verbose_list$output
  if (isFALSE(stderr %in% c("|", ""))) {
    verbose_output <- FALSE
  }
  # Binary streams have no sensible terminal representation, never echo them.
  if (identical(encoding, "binary")) {
    verbose_output <- FALSE
  }

  # Try to find a valid micromamba from any known location
  umamba_bin_path <- get_best_micromamba_path()

  if (is.null(umamba_bin_path)) {
    # No valid micromamba found anywhere - install to internal path
    install_micromamba(force = TRUE, verbose = verbose_list$internal_verbose)
    umamba_bin_path <- micromamba_bin_path()
  }

  env_root_dir <- install_dir_for_backend(micromamba_backend())
  env_envs_dir <- fs::path(env_root_dir, "envs")
  umamba_bin_path <- base::normalizePath(umamba_bin_path, mustWork = FALSE)
  tmp_dir_path <- withr::local_tempdir(pattern = "mamba-tmp")

  cmd_args <- c(
    "--no-rc",
    "--no-env",
    "-r",
    env_root_dir,
    conda_cmd,
    conda_args,
    ...
  )

  # The child's environment block is constructed explicitly and passed as
  # a full `env =` replacement - the calling R session's own environment
  # is never touched. (This used to be a `withr::local_envvar()` scope the
  # child inherited, which mutated the session for the duration of the
  # call - most visibly `R_HOME = ""` corrupting parent-side `R.home()`
  # calls, the bug the load-time Rscript-path cache in
  # condathis-package.R was introduced to patch around.)
  child_env <- build_child_env(
    tmp_dir = tmp_dir_path,
    envs_dir = env_envs_dir
  )

  px_res <- execute_command(
    command = fs::path_real(umamba_bin_path),
    args = cmd_args,
    env = child_env,
    spinner = verbose_list$spinner_flag,
    echo_cmd = verbose_list$cmd,
    echo = verbose_output,
    stdout = stdout,
    stderr = stderr,
    stdin = stdin,
    input = input,
    error_on_status = error_var,
    cleanup_tree = cleanup_tree,
    supervise = supervise,
    linux_pdeathsig = linux_pdeathsig,
    encoding = encoding,
    timeout = timeout
  )

  return(invisible(px_res))
}
