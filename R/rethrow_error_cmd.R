#' Re-throw command execution errors with condathis classes
#'
#' For the micromamba management commands (`create`, `install`, `remove`,
#' `env list`, `list`, `clean`). A failed command aborts with
#' `c("condathis_micromamba_status_error", "condathis_cmd_status_error",
#' "condathis_error")`. `condathis_cmd_status_error` is the old name, kept
#' until 1.0. The error carries the fields `status` (integer, `127` when
#' micromamba could not start) and `stderr`. The exported functions wrap it
#' as a backend failure (see `with_backend_errors()`).
#'
#' @param expr Expression to evaluate.
#' @param env Environment used to evaluate `expr`.
#'   Defaults to `parent.frame()`.
#'
#' @returns The evaluated `expr` result when no captured error is present.
#'   Otherwise aborts with a `condathis` error class.
#'
#' @keywords internal
#' @noRd
rethrow_error_cmd <- function(expr, env = parent.frame()) {
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

  if (isFALSE(rlang::is_null(err_cnd))) {
    additional_lines <- NULL
    if (isTRUE("stderr" %in% names(err_cnd))) {
      err_vector <- stringr::str_replace_all(
        stringr::str_replace_all(
          string = err_cnd[["stderr"]],
          pattern = stringr::fixed("{"),
          replacement = stringr::fixed("{{")
        ),
        pattern = stringr::fixed("}"),
        replacement = stringr::fixed("}}")
      )
      additional_lines <- stringr::str_split(
        string = stringr::str_trim(err_vector),
        pattern = stringr::regex("\\R"),
        simplify = FALSE
      )[[1]]
      # micromamba prefixes each log record with its level and source, and
      # repeats the error as a `critical` record.
      additional_lines <- stringr::str_remove(
        additional_lines,
        "^(critical|error|warning)\\s+libmamba\\s+"
      )
      additional_lines <- unique(additional_lines[nzchar(additional_lines)])
    }

    status_code <- NULL
    if (isFALSE("status" %in% names(err_cnd))) {
      status_code <- 127L
      additional_lines <- c("micromamba: command not found", additional_lines)
    } else {
      status_code <- as.integer(err_cnd[["status"]])
    }
    stderr_field <- err_cnd[["stderr"]]
    if (isFALSE(rlang::is_string(stderr_field))) {
      stderr_field <- NA_character_
    }

    env[["status_code"]] <- status_code
    # Without a header, an empty stderr gave an error with no text at all.
    condathis_abort(
      message = c(
        `x` = "{.code micromamba} failed with status code {status_code}.",
        rlang::set_names(additional_lines, rep(" ", length(additional_lines)))
      ),
      class = c(
        "condathis_micromamba_status_error",
        "condathis_cmd_status_error"
      ),
      status = status_code,
      stderr = stderr_field,
      call = env,
      .envir = env
    )
  }

  return(px_res)
}
