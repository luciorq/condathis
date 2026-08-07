#' Run a binary without environment activation
#'
#' Executes a binary using files from a target Conda environment, but without
#' running environment activation scripts.
#' This is a lower-level execution mode than `run()`.
#'
#' @param cmd Character string with the command to execute.
#' @param ... Additional unnamed command arguments passed to `cmd`.
#' @param env_name Character string with the target environment name.
#'   Defaults to `"condathis-env"`.
#' @param verbose Character string controlling console output.
#'   Supported values are `"output"`, `"silent"`, `"cmd"`, `"spinner"`,
#'   and `"full"`. Defaults to `"output"`.
#' @param error Character string that controls error behavior.
#'   Supported values are `"cancel"` and `"continue"`.
#'   Defaults to `"cancel"`.
#' @param stdout Standard output target.
#'   Defaults to `"|"` (capture stdout in the returned object).
#'   Provide a file path to redirect stdout to a file.
#' @param stderr Standard error target.
#'   Defaults to `"|"` (capture stderr in the returned object).
#'   Provide a file path to redirect stderr to a file.
#' @param stdin Standard input source.
#'   Defaults to `NULL` (no stdin stream).
#'   Provide a file path to use file contents as stdin, or `"|"` to write
#'   `input` to the process.
#' @param input Character or raw vector written to the process's standard
#'   input when `stdin = "|"`. Defaults to `NULL`. Ignored (and must not be
#'   set) when `stdin` is not `"|"`. Note: live (real-time) stdout/stderr
#'   streaming and the spinner are not available when `input` triggers the
#'   writable-stdin code path; `timeout` still works.
#' @param binary Logical. Whether to capture stdout/stderr as raw vectors
#'   instead of decoding them as UTF-8 text. Defaults to `FALSE`. Since a
#'   process's stdout and stderr share a single encoding, both streams are
#'   returned raw when `TRUE`, even if only one of them actually carries
#'   binary data — check with `is.raw()` before treating either as text.
#'   Binary streams are never live-echoed to the console, regardless of
#'   `verbose`.
#' @param supervise Logical. Whether the process should be supervised by the
#'   `processx` supervisor for crash-safe cleanup. Defaults to `FALSE`.
#' @param cleanup_tree Logical. Whether to clean up the child process tree
#'   on crash/interrupt. Defaults to `FALSE`.
#' @param linux_pdeathsig Logical. On Linux, whether to send `SIGKILL` to the
#'   child process if the parent R process dies. Has no effect on other
#'   platforms. Defaults to `FALSE`.
#' @param timeout Numeric. Maximum number of seconds to let the command run
#'   before it's killed. Defaults to `Inf` (no limit, the previous
#'   behavior). On expiry, the process is killed, `timeout` is `TRUE` in the
#'   returned result, and `error = "cancel"` aborts with class
#'   `condathis_run_timeout_error` (`error = "continue"` returns normally
#'   with `status = -9`).
#' @param activate Logical. Whether to resolve and apply `env_name`'s real
#'   `micromamba run` activation (via `get_micromamba_activation_envvars()`,
#'   including any package `activate.d` hook scripts) as an environment
#'   overlay before running `cmd`. Defaults to `TRUE`. Silently skipped
#'   (`cmd` still runs, unactivated) when `env_name` does not exist, so
#'   `error = "continue"`-style fallback to a binary outside any managed
#'   environment keeps working. Set to `FALSE` to restore the original,
#'   activation-free `run_bin()` behavior — `cmd` still resolves against
#'   `env_name`'s `bin/` directory (falling back to `PATH`), but the child
#'   process otherwise inherits the caller's environment unmodified. This
#'   is the mechanism that makes `run_bin(activate = TRUE)` behave like
#'   `run()`, minus the different binary-resolution strategy: `run()`
#'   resolves `cmd` via the activated `PATH` inside a `micromamba run`
#'   wrapper, while `run_bin()` always resolves `cmd` itself beforehand.
#'
#' @returns A `condathis_result` S3 object (a classed list, still usable as
#'   a plain list) with `status`, `stdout`, `stderr`, `timeout`, `pid`,
#'   `cmd`, and `env_name`.
#'
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   # Create an environment with 'python' and 'ripgrep'. `coreutils`
#'   # (and other GNU tools like `grep`) aren't available for Windows on
#'   # conda-forge, so `ripgrep` is used here instead of e.g. `ls`/`grep` —
#'   # a single package name that installs and runs the same way on every
#'   # platform `condathis` supports.
#'   condathis::create_env(
#'     c("conda-forge::python", "conda-forge::ripgrep"),
#'     env_name = "my-env"
#'   )
#'
#'   # Run 'python' with a script in 'my-env' environment
#'   condathis::run_bin(
#'     "python", "-c", "import sys; print(sys.version)",
#'     env_name = "my-env"
#'   )
#'
#'   # Run the 'rg' (ripgrep) binary with additional arguments
#'   condathis::run_bin("rg", "--version", env_name = "my-env")
#' })
#' }
#'
#' @export
run_bin <- function(
  cmd,
  ...,
  env_name = "condathis-env",
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
  error <- rlang::arg_match(error)
  if (identical(error, "cancel")) {
    error_var <- TRUE
  } else {
    error_var <- FALSE
  }

  rlang::check_dots_unnamed()

  if (!is.null(input) && !identical(stdin, "|")) {
    cli::cli_abort(
      message = c(
        `x` = "{.field input} can only be used when {.field stdin} is {.val {\"|\"}}."
      ),
      class = "condathis_run_invalid_input"
    )
  }
  if (isFALSE(rlang::is_bool(binary))) {
    cli::cli_abort(
      message = c(
        `x` = "{.field binary} needs to be a single {.cls logical} value."
      ),
      class = "condathis_run_invalid_binary_arg"
    )
  }

  verbose_list <- parse_strategy_verbose(verbose = verbose)

  verbose_output <- verbose_list$output
  if (isFALSE(stderr %in% c("|", ""))) {
    verbose_output <- FALSE
  }
  encoding <- if (isTRUE(binary)) "binary" else "utf-8"
  # Binary streams have no sensible terminal representation, never echo them.
  if (isTRUE(binary)) {
    verbose_output <- FALSE
  }

  env_dir <- get_env_dir(env_name = env_name)
  # `<env_dir>/bin` only exists on Linux/macOS; Windows environments spread
  # binaries across `Library/mingw-w64/bin`, `Library/usr/bin`,
  # `Library/bin`, `Scripts`, and the prefix root itself (see
  # `resolve_env_bin_path()`). Falling straight back to `Sys.which(cmd)`
  # without searching those first would silently run whatever same-named
  # program happens to already be on the caller's ambient PATH instead of
  # this environment's own binary — defeating environment isolation (e.g.
  # resolving `sort` to Windows' own `System32/sort.exe` instead of the
  # environment's coreutils build).
  cmd_path <- resolve_env_bin_path(env_dir, cmd)

  if (is.null(cmd_path)) {
    cmd_path <- if (isTRUE(fs::file_exists(Sys.which(cmd)))) {
      normalizePath(Sys.which(cmd), mustWork = FALSE)
    } else {
      fs::path(env_dir, "bin", cmd)
    }
  }
  tmp_dir_path <- withr::local_tempdir(pattern = "condathis-tmp")
  withr::local_envvar(
    .new = get_clean_conda_envvars(tmp_dir = tmp_dir_path)
  )
  withr::local_path(
    new = as.list(env_bin_search_dirs(env_dir)),
    action = "prefix"
  )

  activation_env <- NULL
  if (isTRUE(activate) && fs::dir_exists(env_dir)) {
    activation_env <- c(
      "current",
      get_micromamba_activation_envvars(env_name = env_name)
    )
  }

  args_vector <- c(...)
  if (isTRUE(rlang::is_null(args_vector))) {
    args_vector <- character(length = 0L)
  }
  px_res <- rethrow_error_run(
    expr = {
      if (identical(stdin, "|")) {
        run_process_with_input(
          command = cmd_path,
          args = args_vector,
          input = input,
          stdout = stdout,
          stderr = stderr,
          echo_cmd = verbose_list$cmd,
          echo = verbose_output,
          env = activation_env,
          error_on_status = error_var,
          cleanup_tree = cleanup_tree,
          supervise = supervise,
          linux_pdeathsig = linux_pdeathsig,
          encoding = encoding,
          timeout = timeout
        )
      } else {
        processx::run(
          command = cmd_path,
          args = args_vector,
          spinner = verbose_list$spinner_flag,
          echo_cmd = verbose_list$cmd,
          echo = verbose_output,
          stdout = stdout,
          stderr = stderr,
          stdin = stdin,
          env = activation_env,
          error_on_status = error_var,
          cleanup_tree = cleanup_tree,
          supervise = supervise,
          linux_pdeathsig = linux_pdeathsig,
          encoding = encoding,
          timeout = timeout
        )
      }
    }
  )

  cmd_string <- paste(
    shQuote(as.character(c(cmd, args_vector))),
    collapse = " "
  )
  result <- new_condathis_result(
    status = px_res$status,
    stdout = px_res$stdout,
    stderr = px_res$stderr,
    timeout = if (is.null(px_res$timeout)) FALSE else px_res$timeout,
    pid = if (is.null(px_res$pid)) NA_integer_ else px_res$pid,
    cmd = cmd_string,
    env_name = env_name
  )
  return(invisible(result))
}
