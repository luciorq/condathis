#' Pipeline result object
#'
#' @description
#' An S3 class representing the result of a pipeline execution.
#' Each process in the pipeline has its own entry with exit status,
#' stdout (last process only), stderr, and PID.
#'
#' @param statuses Integer vector of exit statuses, one per process.
#' @param processes List of per-process result lists, each containing:
#'   - `cmd`: Character string with the command and arguments.
#'   - `env_name`: Character string with the Conda environment name.
#'   - `status`: Integer exit status.
#'   - `stdout`: Character string with stdout, or `NA` for non-last processes.
#'   - `stderr`: Character string with stderr.
#'   - `pid`: Integer process ID.
#' @param timeout Logical. Whether the pipeline was killed due to timeout.
#'
#' @returns An object of class `"condathis_pipeline"`.
#'
#' @keywords internal
#' @noRd
new_condathis_pipeline <- function(statuses, processes, timeout = FALSE) {
  stopifnot(is.integer(statuses))
  stopifnot(is.list(processes))
  stopifnot(is.logical(timeout))

  structure(
    list(
      statuses = statuses,
      processes = processes,
      timeout = timeout
    ),
    class = "condathis_pipeline"
  )
}

#' @export
format.condathis_pipeline <- function(x, ...) {
  n <- length(x$processes)
  lines <- c(
    sprintf("<condathis_pipeline (%d commands)>", n),
    ""
  )
  for (i in seq_along(x$processes)) {
    p <- x$processes[[i]]
    status_str <- if (is.null(p$status)) "NA" else as.character(p$status)
    status_icon <- if (identical(p$status, 0L)) {
      "OK"
    } else {
      paste("exit:", status_str)
    }
    stdout_preview <- ""
    if (!is.na(p$stdout) && nzchar(p$stdout)) {
      first_line <- strsplit(p$stdout, "\n")[[1]][1]
      if (nchar(first_line) > 60) {
        first_line <- paste0(substr(first_line, 1, 57), "...")
      }
      stdout_preview <- sprintf("  stdout: %s", first_line)
    }
    stderr_preview <- ""
    if (nzchar(p$stderr)) {
      first_line <- strsplit(p$stderr, "\n")[[1]][1]
      if (nchar(first_line) > 60) {
        first_line <- paste0(substr(first_line, 1, 57), "...")
      }
      stderr_preview <- sprintf("  stderr: %s", first_line)
    }
    lines <- c(
      lines,
      sprintf("  [%d] %s (%s)", i, p$cmd, p$env_name),
      sprintf("       status: %s", status_icon)
    )
    if (nzchar(stdout_preview)) {
      lines <- c(lines, stdout_preview)
    }
    if (nzchar(stderr_preview)) lines <- c(lines, stderr_preview)
  }
  paste0(lines, collapse = "\n")
}

#' @export
print.condathis_pipeline <- function(x, ...) {
  cat(format(x, ...), "\n")
  invisible(x)
}

#' @export
as.list.condathis_pipeline <- function(x, ...) {
  c(
    list(
      statuses = x$statuses,
      timeout = x$timeout
    ),
    x$processes
  )
}
