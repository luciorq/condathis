#' Re-throw run errors with condathis classes
#'
#' @param expr Expression to evaluate.
#' @param env Environment used to evaluate `expr`.
#'   Defaults to `parent.frame()`.
#'
#' @returns The evaluated `expr` result when no captured error is present.
#'   For non-fatal modes, may return a synthesized process-like result list.
#'
#' @keywords internal
#' @noRd
rethrow_error_run <- function(expr, env = parent.frame()) {
  code <- base::substitute(expr = expr)
  err_cnd <- rlang::catch_cnd(
    expr = {
      px_res <- rlang::eval_bare(expr = code, env = env)
    },
    classes = c(
      "system_command_status_error",
      "system_command_timeout_error",
      "rlib_error_3_0",
      "c_error"
    )
  )
  is_timeout <- isTRUE(inherits(err_cnd, "system_command_timeout_error"))

  if (
    isFALSE(rlang::is_null(env[["stdin"]])) &&
      isFALSE(identical(env[["stdin"]], "|")) &&
      isFALSE(
        fs::is_file(env[["stdin"]]) &&
          fs::file_exists(env[["stdin"]])
      )
  ) {
    cli::cli_abort(
      message = c(
        `x` = "Argument {.code stdin} is not a file",
        `!` = "stdin: {.path {stdin}}"
      ),
      class = "condathis_run_stdin_error",
      .envir = env
    )
  }

  if (isFALSE(rlang::is_null(err_cnd)) && !isFALSE(env[["error_var"]])) {
    additional_lines <- NULL
    if (isTRUE("stderr" %in% names(err_cnd))) {
      additional_lines <- stream_display_lines(err_cnd[["stderr"]])
    }

    status_code <- NULL
    if (isFALSE("status" %in% names(err_cnd))) {
      status_code <- "127"
      additional_lines <- c("{cmd}: command not found", additional_lines)
    } else {
      status_code <- err_cnd[["status"]]
    }
    env[["status_code"]] <- status_code

    if (isTRUE(is_timeout)) {
      cli::cli_abort(
        message = c(
          `x` = "System command {.field {cmd}} timed out",
          `!` = "Timeout: {timeout} seconds",
          additional_lines
        ),
        class = "condathis_run_timeout_error",
        .envir = env
      )
    }

    cli::cli_abort(
      message = c(
        `x` = "System command {.field {cmd}} failed",
        `!` = "Status code: {status_code}",
        additional_lines
      ),
      class = "condathis_run_status_error",
      .envir = env
    )
  }

  if (isFALSE(exists("px_res"))) {
    if (isTRUE(rlang::is_null(err_cnd[["status"]]))) {
      status_code <- 127L
    } else {
      status_code <- err_cnd[["status"]]
    }

    if (isTRUE(is_timeout)) {
      stderr_msg <- sprintf(
        "Command timed out after %s seconds",
        env[["timeout"]]
      )
    } else if (
      isFALSE(rlang::is_null(err_cnd[["message"]])) &&
        isTRUE(stringr::str_detect(err_cnd[["message"]], "Native call to"))
    ) {
      if (isFALSE(rlang::is_null(env[["cmd"]]))) {
        cmd_str <- env[["cmd"]]
      }
      stderr_msg <- paste("System command", cmd_str, "not found", sep = " ")
    } else {
      stderr_msg <- "Unknown Error"
    }

    px_res <- list(
      status = status_code,
      stdout = "",
      stderr = stderr_msg,
      timeout = is_timeout
    )
  }

  # Normalized to a fixed sentinel here, in one place, regardless of how
  # `px_res` was produced above: `processx::run()` itself never throws on
  # timeout when `error_on_status = FALSE` (`error = "continue"`'s case) —
  # it returns normally with `status` set to whatever the OS reports for
  # the killed process, confirmed to differ across platforms (`-9` on
  # Linux/macOS, `2` on Windows for the identical `kill()`). `px_res$timeout`
  # is always reliably set by `processx::run()`/`run_process_with_input()`
  # either way, so it — not the raw status — is what `condathis` trusts.
  if (isTRUE(rlang::is_list(px_res)) && isTRUE(px_res$timeout)) {
    px_res$status <- -9L
  }

  return(px_res)
}
