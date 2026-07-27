#' Run a command inside a Conda environment
#'
#' Executes a command in a Conda environment managed by `condathis`.
#' The command is run through `micromamba run` using the internal Conda root.
#'
#' @param cmd Character string with the command to execute.
#' @param ... Additional unnamed command arguments passed to `cmd`.
#' @param env_name Character string with the target environment name.
#'   Defaults to `"condathis-env"`.
#'   If the default environment does not exist, it is created automatically.
#'   A missing *custom* `env_name` is never created automatically — it
#'   fails instead, per `error` below.
#' @param method Character string with the backend execution strategy.
#'   Supported values are `"native"` and `"auto"`.
#'   Defaults to `"native"`.
#'   This argument is soft-deprecated and currently does not change behavior.
#' @param verbose Character string controlling console output.
#'   Supported values are `"output"`, `"silent"`, `"cmd"`, `"spinner"`,
#'   and `"full"`. Defaults to `"output"`.
#'   Logical values are accepted for backward compatibility:
#'   `TRUE` maps to `"output"` and `FALSE` maps to `"silent"`.
#' @param error Character string that controls error behavior.
#'   Supported values are `"cancel"` and `"continue"`.
#'   Defaults to `"cancel"`. Also controls what happens when `env_name` is
#'   a non-default environment that does not exist: `"cancel"` aborts with
#'   class `condathis_run_env_not_found`; `"continue"` returns a result
#'   with `status = 127` instead of running anything.
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
#'   set) when `stdin` is not `"|"`. Note: live stdout/stderr echoing,
#'   spinner, and timeout are not available when `input` triggers the
#'   writable-stdin code path.
#' @param binary Logical. Whether to capture stdout/stderr as raw vectors
#'   instead of decoding them as UTF-8 text. Defaults to `FALSE`. Since a
#'   process's stdout and stderr share a single encoding, both streams are
#'   returned raw when `TRUE`, even if only one of them actually carries
#'   binary data — check with `is.raw()` before treating either as text.
#'   Binary streams are never live-echoed to the console, regardless of
#'   `verbose`.
#' @param supervise Logical. Whether the process should be supervised by the
#'   `processx` supervisor for crash-safe cleanup — the process (and its
#'   descendants, with `cleanup_tree = TRUE`) is killed if the R session
#'   crashes. Defaults to `FALSE`.
#' @param cleanup_tree Logical. Whether to clean up the child process tree
#'   (not just the direct child) on crash/interrupt. Defaults to `FALSE`.
#' @param linux_pdeathsig Logical. On Linux, whether to send `SIGKILL` to the
#'   child process if the parent R process dies. Has no effect on other
#'   platforms. Defaults to `FALSE`.
#'
#' @returns A `condathis_result` S3 object (a classed list, still usable as
#'   a plain list) with `status`, `stdout`, `stderr`, `timeout`, `pid`,
#'   `cmd`, and `env_name`.
#'
#' @details
#' This function is the main execution entry point in `condathis`.
#' Use it to run CLI tools with reproducible dependencies isolated in Conda
#' environments.
#'
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   ## Create env
#'   create_env("bioconda::samtools", env_name = "samtools-env")
#'
#'   ## Run a command in a specific Conda environment
#'   samtools_res <- run(
#'     "samtools", "view",
#'     fs::path_package("condathis", "extdata", "example.bam"),
#'     env_name = "samtools-env",
#'     verbose = "silent"
#'   )
#'   parse_output(samtools_res)[1]
#'   #> [1] "SOLEXA-1GA-1_6_FC20ET7:6:92:473:531\t0\tchr1\t10156..."
#' })
#' }
#'
#' @seealso
#' \code{\link{install_micromamba}}, \code{\link{create_env}}
#'
#' @export
run <- function(
  cmd,
  ...,
  env_name = "condathis-env",
  method = c(
    "native",
    "auto"
  ),
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
  linux_pdeathsig = FALSE
) {
  rlang::check_dots_unnamed()
  rlang::check_required(cmd)
  if (rlang::is_null(cmd)) {
    cli::cli_abort(
      message = c(
        `x` = "{.field cmd} need to be a {.code character} string."
      ),
      class = "condathis_run_null_cmd"
    )
  }
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
  method <- rlang::arg_match(method)
  error <- rlang::arg_match(error)

  verbose_list <- parse_strategy_verbose(verbose = verbose)

  # Ignore linter warning. `error_var` is used by `rethrow_error_run()`
  # + env by accessing this function environment.
  if (identical(error, "cancel")) {
    error_var <- TRUE
  } else {
    error_var <- FALSE
  }

  method_to_use <- method

  if (isTRUE(method_to_use %in% c("native", "auto"))) {
    # Only the default environment is auto-created when missing (a
    # deliberate, documented convenience). A missing *custom* `env_name`
    # used to be silently papered over here too: this check only ever
    # tested for `"condathis-env"` specifically, regardless of the actual
    # `env_name` argument, so calling `run(cmd, env_name = "my-env")` when
    # `"my-env"` didn't exist would create an unrelated, empty
    # `"condathis-env"` as a side effect and then still fail — the
    # auto-create never actually helped the real target. (This
    # side-effect-creation existed to work around an old `micromamba`
    # requirement that the root prefix have *some* environment before
    # `micromamba run` would work at all; confirmed empirically that a
    # fresh install root with only a custom-named environment — never
    # touching `"condathis-env"` — runs commands in it correctly with the
    # current pinned `micromamba` version, so that workaround is no longer
    # needed.) A missing custom `env_name` now fails clearly instead:
    # aborts under `error = "cancel"`, matching `run_pipeline()`'s
    # `condathis_pipeline_env_not_found` behavior for the same situation;
    # reports a `status = 127` result under `error = "continue"`, without
    # ever creating anything.
    env_name_exists <- env_exists(
      env_name = env_name,
      verbose = verbose_list$internal_verbose
    )

    if (isFALSE(env_name_exists) && identical(env_name, "condathis-env")) {
      create_base_env(verbose = verbose_list$internal_verbose)
      env_name_exists <- TRUE
    }

    if (isFALSE(env_name_exists)) {
      if (isTRUE(error_var)) {
        cli::cli_abort(
          message = c(
            `x` = "Environment {.field {env_name}} does not exist.",
            `!` = "Create it with {.fn create_env} first."
          ),
          class = "condathis_run_env_not_found"
        )
      }
      px_res <- list(
        status = 127L,
        stdout = "",
        stderr = sprintf(
          "Conda environment '%s' does not exist.\n",
          env_name
        ),
        timeout = FALSE
      )
    } else {
      px_res <- rethrow_error_run(
        expr = {
          run_internal_native(
            cmd = cmd,
            ...,
            env_name = env_name,
            verbose = verbose_list,
            error = error,
            stdout = stdout,
            stderr = stderr,
            stdin = stdin,
            input = input,
            binary = binary,
            supervise = supervise,
            cleanup_tree = cleanup_tree,
            linux_pdeathsig = linux_pdeathsig
          )
        }
      )
    }
  }

  cmd_string <- paste(
    shQuote(as.character(c(cmd, unlist(list(...))))),
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
