#' Run a process while writing data to its standard input
#'
#' `processx::run()` accepts `stdin = "|"` but never exposes the resulting
#' input connection, so the child process blocks forever waiting for input.
#' This helper drives `processx::process$new()` directly. It writes `input`
#' (if any) to the stdin pipe and returns a `processx::run()`-shaped list
#' (`status`, `stdout`, `stderr`, `timeout`, `pid`).
#'
#' On non-zero exit with `error_on_status = TRUE`, it signals a condition of
#' class `"system_command_status_error"` with `status`, `stdout` and `stderr`
#' fields.
#' This is the `processx::run()` contract, so `rethrow_error_run()` handles
#' both identically. A missing executable throws directly from
#' `processx::process$new()` (classes `rlib_error_3_0`/`c_error`), which
#' `rethrow_error_run()` also handles.
#'
#' With `cleanup_tree = TRUE`, the process tree is killed when this
#' function returns, as in `processx::run()`: a daemon the command started
#' does not outlive the call. With `FALSE`, only a child that is still
#' running is killed.
#'
#' There is no live streaming of stdout/stderr and no spinner. On `timeout`
#' expiry the process is killed (`proc$kill()`), `status` is forced to `-9`
#' and `timeout = TRUE` is set. The `-9` sentinel is `condathis`-normalized:
#' the exit status of a killed process differs across platforms (for example
#' `2` on Windows). Gated by `error_on_status` like a regular non-zero exit,
#' a condition of class `"system_command_timeout_error"` is signaled instead
#' of `"system_command_status_error"`.
#'
#' `pump_process_io()` interleaves writing `input` with draining
#' stdout/stderr. This avoids two hazards. Writing once and closing
#' immediately truncates `input` larger than the OS pipe buffer. Draining
#' streams sequentially (or after `wait()`) deadlocks once output exceeds the
#' buffer. It also avoids `processx`'s `read_all_output()`/`read_all_error()`,
#' which mangle output into hex-string characters when `encoding = "binary"`.
#' Binary streams are never echoed to the console.
#'
#' @keywords internal
#' @noRd
run_process_with_input <- function(
  command,
  args = character(),
  input = NULL,
  stdout = "|",
  stderr = "|",
  echo_cmd = FALSE,
  echo = FALSE,
  env = NULL,
  wd = NULL,
  error_on_status = TRUE,
  cleanup_tree = FALSE,
  supervise = FALSE,
  linux_pdeathsig = FALSE,
  encoding = "utf-8",
  timeout = Inf
) {
  deadline <- if (isTRUE(is.finite(timeout))) {
    proc.time()[["elapsed"]] + timeout
  } else {
    Inf
  }

  proc <- processx::process$new(
    command = command,
    args = args,
    stdin = "|",
    stdout = stdout,
    stderr = stderr,
    env = env,
    wd = wd,
    echo_cmd = echo_cmd,
    supervise = supervise,
    cleanup_tree = cleanup_tree,
    encoding = encoding,
    linux_pdeathsig = processx_linux_pdeathsig(linux_pdeathsig)
  )
  # Kill the child if R leaves this function early (an error, an interrupt,
  # or `setTimeLimit()` firing while the pump polls). Without this the child
  # kept running until its `process` object was garbage collected.
  # With `cleanup_tree = TRUE`, the tree is killed on every exit, also after
  # the child has finished: a daemon it started must not outlive the call.
  # `processx::run()`, used when stdin is not writable, does the same.
  on.exit(
    tryCatch(
      if (isTRUE(cleanup_tree)) {
        proc$kill_tree()
      } else if (isTRUE(proc$is_alive())) {
        proc$kill()
      },
      error = function(e) NULL
    ),
    add = TRUE
  )

  is_binary <- identical(encoding, "binary")
  empty_stream <- if (isTRUE(is_binary)) raw(0L) else ""

  streams <- pump_process_io(
    proc,
    input = input,
    binary = is_binary,
    deadline = deadline
  )

  p_timeout <- isTRUE(streams$timeout)
  # pump_process_io() observes the deadline only through the streams it
  # watches. With stdout/stderr redirected to files (or closed by a child
  # that keeps running), it returns early. A bare `wait()` would then block
  # until the child exits, disabling `timeout` (`timeout = 2` waited out a
  # 100-second sleep). Enforce the remaining budget with a bounded wait.
  if (isFALSE(p_timeout) && isTRUE(is.finite(deadline)) && proc$is_alive()) {
    remaining_ms <- max(0, (deadline - proc.time()[["elapsed"]]) * 1000)
    wait_process_safely(proc, timeout = round(remaining_ms))
    if (proc$is_alive()) {
      p_timeout <- TRUE
    }
  }
  if (isTRUE(p_timeout)) {
    tryCatch(proc$kill(), error = function(e) NULL)
  }
  # Tolerates the Windows finalized-handle race. See wait_process_safely().
  wait_process_safely(proc)

  p_stdout <- if (is.null(streams$stdout)) empty_stream else streams$stdout
  p_stderr <- if (is.null(streams$stderr)) empty_stream else streams$stderr

  # Force a fixed sentinel on timeout. The raw exit status of a killed
  # process is an OS/`processx` detail: `-9` on Linux/macOS, `2` on Windows
  # for the identical `proc$kill()` call. `-9` is the cross-platform
  # contract for a timed-out `condathis_result`.
  if (isTRUE(p_timeout)) {
    p_status <- -9L
  } else {
    p_status <- exit_status_safely(proc)
  }
  p_pid <- proc$get_pid()

  # Never echo binary streams: raw bytes have no terminal representation.
  if (isTRUE(echo) && isFALSE(is_binary)) {
    if (nzchar(p_stdout)) {
      cat(p_stdout)
    }
    if (nzchar(p_stderr)) base::message(p_stderr, appendLF = FALSE)
  }

  p_res <- list(
    status = p_status,
    stdout = p_stdout,
    stderr = p_stderr,
    timeout = p_timeout,
    pid = p_pid
  )
  if (isTRUE(error_on_status)) {
    signal_process_failure(p_res, timeout = timeout, na_is_failure = FALSE)
  }

  return(p_res)
}

#' Validate the `input` argument of `run()`, `run_bin()` and `run_pipeline()`
#'
#' `input` must be `NULL`, a character vector, or a raw vector. Anything
#' else (for example a numeric vector) used to fail inside the write and was
#' silently treated as a broken pipe, so the process received no input.
#'
#' @param input The `input` argument.
#' @param class Character vector. The calling function's own classes, the
#'   most specific first, for example `arg_error_class("run", "input")`.
#'   `c("condathis_invalid_input", "condathis_invalid_arg")` is appended.
#' @param call Environment of the user-facing caller, for the error.
#'
#' @returns `input`, invisibly.
#'
#' @keywords internal
#' @noRd
validate_stdin_input <- function(
  input,
  class = "condathis_run_invalid_input",
  call = rlang::caller_env()
) {
  error_class <- unique(c(
    class,
    "condathis_invalid_input",
    "condathis_invalid_arg"
  ))
  if (
    isFALSE(is.null(input)) &&
      isFALSE(rlang::is_character(input)) &&
      isFALSE(is.raw(input))
  ) {
    condathis_abort(
      message = c(
        `x` = "{.arg input} must be a character or raw vector, not {.obj_type_friendly {input}}."
      ),
      class = error_class,
      call = call
    )
  }
  if (rlang::is_character(input) && anyNA(input)) {
    condathis_abort(
      message = c(`x` = "{.arg input} must not contain {.val {NA}}."),
      class = error_class,
      call = call
    )
  }
  return(invisible(input))
}

#' Validate `input` together with `stdin`
#'
#' `validate_stdin_input()`, then the rule that `input` needs
#' `stdin = "|"`: with any other `stdin`, the input would never be written.
#'
#' @param input The `input` argument.
#' @param stdin The `stdin` argument.
#' @param class Character vector, as in `validate_stdin_input()`.
#' @param call Environment of the user-facing caller, for the error.
#'
#' @returns `input`, invisibly.
#'
#' @keywords internal
#' @noRd
validate_input_with_stdin <- function(
  input,
  stdin,
  class,
  call = rlang::caller_env()
) {
  validate_stdin_input(input, class = class, call = call)
  if (isFALSE(is.null(input)) && isFALSE(identical(stdin, "|"))) {
    condathis_abort(
      message = c(
        `x` = "{.arg input} must be {.code NULL} unless {.arg stdin} is {.val |}."
      ),
      class = unique(c(
        class,
        "condathis_invalid_input",
        "condathis_invalid_arg"
      )),
      call = call
    )
  }
  return(invisible(input))
}

#' Convert `input` to what the process's stdin connection accepts
#'
#' Text mode leaves character input to `processx`, which joins the elements
#' with newlines and converts them to the connection encoding. In binary
#' mode that conversion fails (the connection encoding is `"binary"`), so
#' character input is joined the same way and converted to UTF-8 bytes here.
#'
#' @param input `NULL`, a character vector, or a raw vector.
#' @param binary Logical. Whether the process uses binary encoding.
#'
#' @returns `input`, or a raw vector in binary mode.
#'
#' @keywords internal
#' @noRd
normalize_stdin_input <- function(input, binary) {
  if (isTRUE(binary) && rlang::is_character(input)) {
    return(charToRaw(enc2utf8(paste(input, collapse = "\n"))))
  }
  return(input)
}
