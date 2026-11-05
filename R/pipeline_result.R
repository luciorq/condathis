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
#'   - `stdout`: Character string or raw vector with stdout, or `NA` for
#'     non-last processes.
#'   - `stderr`: Character string or raw vector with stderr.
#'   - `pid`: Integer process ID.
#' @param timeout Logical. Whether the pipeline was killed due to timeout.
#' @param status Integer scalar, the status of the whole pipeline. The
#'   default is `pipeline_status(statuses, timeout)`.
#' @param cmd Character string, the whole pipeline. The default is
#'   `pipeline_cmd(processes)`.
#'
#' @returns An object of class `"condathis_pipeline"`: a list with
#'   `status`, `statuses`, `processes`, `timeout` and `cmd`.
#'
#' @keywords internal
#' @noRd
new_condathis_pipeline <- function(
  statuses,
  processes,
  timeout = FALSE,
  status = pipeline_status(statuses, timeout),
  cmd = pipeline_cmd(processes)
) {
  stopifnot(is.integer(statuses))
  stopifnot(is.list(processes))
  stopifnot(is.logical(timeout))
  stopifnot(rlang::is_scalar_integer(status))
  stopifnot(rlang::is_scalar_character(cmd))

  structure(
    list(
      status = status,
      statuses = statuses,
      processes = processes,
      timeout = timeout,
      cmd = cmd
    ),
    class = "condathis_pipeline"
  )
}

#' Which stages of a pipeline failed
#'
#' A stage failed when its status is not `0`, not `NA`, and not an
#' upstream `SIGPIPE` (see `is_upstream_sigpipe()`). `error = "cancel"`,
#' the "Failed commands" lines of its error, and the `status` of the
#' result all use this rule.
#'
#' @param statuses Integer vector of exit statuses, one per stage.
#'
#' @returns Logical vector, one element per stage.
#'
#' @keywords internal
#' @noRd
is_failed_stage <- function(statuses) {
  n <- length(statuses)
  return(vapply(
    seq_len(n),
    function(i) {
      status <- statuses[[i]]
      return(
        isFALSE(is.na(status)) &&
          isFALSE(identical(as.integer(status), 0L)) &&
          isFALSE(is_upstream_sigpipe(status, i, n))
      )
    },
    logical(1L)
  ))
}

#' The status of a whole pipeline
#'
#' `-9` when the pipeline timed out, as for a timeout of `run()`.
#' Otherwise the status of the first stage that failed (see
#' `is_failed_stage()`), or `0` when none failed. So an upstream command
#' ended by a broken pipe, as in `seq 1 1000000 | head -n 1`, does not
#' make the pipeline fail. This is not a shell's rule: a shell gives the
#' status of the last command, and bash with `pipefail` the status of the
#' last command that failed.
#'
#' @param statuses Integer vector of exit statuses, one per stage.
#' @param timeout Logical. Whether the pipeline timed out.
#'
#' @returns Integer scalar.
#'
#' @keywords internal
#' @noRd
pipeline_status <- function(statuses, timeout = FALSE) {
  if (isTRUE(timeout)) {
    return(-9L)
  }
  failed <- which(is_failed_stage(statuses))
  if (isTRUE(length(failed) > 0L)) {
    return(as.integer(statuses[[failed[[1L]]]]))
  }
  return(0L)
}

#' The command line of a whole pipeline
#'
#' @param processes List of per-process results with a `cmd` element.
#'
#' @returns Character string: every `cmd`, joined with `" | "`.
#'   `NA_character_` when a process has no `cmd`.
#'
#' @keywords internal
#' @noRd
pipeline_cmd <- function(processes) {
  cmds <- vapply(
    processes,
    function(p) {
      cmd <- p[["cmd"]]
      if (isTRUE(rlang::is_string(cmd))) {
        return(cmd)
      }
      return(NA_character_)
    },
    character(1L)
  )
  if (isTRUE(anyNA(cmds))) {
    return(NA_character_)
  }
  return(paste(cmds, collapse = " | "))
}

#' Format an exit status for `format()`
#'
#' @param status Integer scalar, or `NULL`.
#'
#' @returns `"OK"` for `0`, otherwise `"exit: <status>"`.
#'
#' @keywords internal
#' @noRd
format_status_icon <- function(status) {
  if (identical(status, 0L)) {
    return("OK")
  }
  status_str <- if (is.null(status) || isTRUE(is.na(status))) {
    "NA"
  } else {
    as.character(status)
  }
  return(paste("exit:", status_str))
}

#' @export
format.condathis_pipeline <- function(x, ...) {
  n <- length(x$processes)
  lines <- c(
    sprintf("<condathis_pipeline (%d commands)>", n),
    sprintf("  status: %s", format_status_icon(x[["status"]])),
    ""
  )
  for (i in seq_along(x$processes)) {
    p <- x$processes[[i]]
    stdout_first_line <- stream_preview_line(p$stdout)
    stderr_first_line <- stream_preview_line(p$stderr)
    lines <- c(
      lines,
      sprintf("  [%d] %s (%s)", i, p$cmd, p$env_name),
      sprintf("       status: %s", format_status_icon(p$status))
    )
    if (!is.null(stdout_first_line)) {
      lines <- c(lines, sprintf("  stdout: %s", stdout_first_line))
    }
    if (!is.null(stderr_first_line)) {
      lines <- c(lines, sprintf("  stderr: %s", stderr_first_line))
    }
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
      status = x[["status"]],
      statuses = x[["statuses"]],
      timeout = x[["timeout"]],
      cmd = x[["cmd"]]
    ),
    x$processes
  )
}
