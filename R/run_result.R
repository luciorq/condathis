#' Run result object
#'
#' @description
#' An S3 class representing the result of `run()` or `run_bin()`. It is a
#' plain list under the hood - `$status`, `$stdout`, `$stderr`, and
#' `$timeout` are always present and work exactly as they did when `run()`/
#' `run_bin()` returned an unclassed `processx::run()` result list - with a
#' `print()`/`format()` method and `pid`/`cmd`/`env_name` metadata added,
#' mirroring `condathis_pipeline`'s per-process result shape.
#'
#' @param status Integer exit status.
#' @param stdout Character string or raw vector with stdout, or `NA` if not
#'   captured.
#' @param stderr Character string or raw vector with stderr, or `NA` if not
#'   captured.
#' @param timeout Logical. Whether the process was killed due to timeout.
#' @param pid Integer process ID, or `NA_integer_` when unavailable.
#' @param cmd Character string with the command and arguments.
#' @param env_name Character string with the Conda environment name.
#'
#' @returns An object of class `"condathis_result"`.
#'
#' @keywords internal
#' @noRd
new_condathis_result <- function(
  status,
  stdout,
  stderr,
  timeout = FALSE,
  pid = NA_integer_,
  cmd = NA_character_,
  env_name = NA_character_
) {
  structure(
    list(
      status = status,
      stdout = stdout,
      stderr = stderr,
      timeout = timeout,
      pid = pid,
      cmd = cmd,
      env_name = env_name
    ),
    class = "condathis_result"
  )
}

#' @export
format.condathis_result <- function(x, ...) {
  status_str <- if (is.na(x$status)) "NA" else as.character(x$status)
  status_icon <- if (identical(x$status, 0L)) {
    "OK"
  } else {
    paste("exit:", status_str)
  }

  lines <- c(
    sprintf("<condathis_result> %s (%s)", x$cmd, x$env_name),
    sprintf("  status: %s", status_icon)
  )
  if (!is.null(x$pid) && !is.na(x$pid)) {
    lines <- c(lines, sprintf("  pid: %d", x$pid))
  }
  stdout_preview <- stream_preview_line(x$stdout)
  if (!is.null(stdout_preview)) {
    lines <- c(lines, sprintf("  stdout: %s", stdout_preview))
  }
  stderr_preview <- stream_preview_line(x$stderr)
  if (!is.null(stderr_preview)) {
    lines <- c(lines, sprintf("  stderr: %s", stderr_preview))
  }
  paste0(lines, collapse = "\n")
}

#' @export
print.condathis_result <- function(x, ...) {
  cat(format(x, ...), "\n")
  invisible(x)
}

#' @export
as.list.condathis_result <- function(x, ...) {
  unclass(x)
}
