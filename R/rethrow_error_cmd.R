#' @keywords internal
#' @noRd
rethrow_error_cmd <- function(expr, env = parent.frame()) {
  code <- base::substitute(expr = expr)
  err_cnd <- rlang::catch_cnd(
    expr = {
      px_res <- rlang::eval_bare(expr = code, env = env)
    },
    classes = c("system_command_status_error", "rlib_error_3_0", "c_error")
  )

  if (isFALSE(is.null(err_cnd))) {
    additional_lines <- NULL
    if (isTRUE("stderr" %in% names(err_cnd))) {
      additional_lines <- stringr::str_split(
        string = stringr::str_trim(err_cnd[["stderr"]]),
        pattern = stringr::regex("\\R"),
        simplify = FALSE
      )[[1]]
    }

    status_code <- NULL
    if (isFALSE("status" %in% names(err_cnd))) {
      status_code <- "127"
      additional_lines <- c("micromamba: command not found", additional_lines)
    } else {
      status_code <- err_cnd[["status"]]
    }

    env[["status_code"]] <- status_code
    cli::cli_abort(
      message = c(
        additional_lines
      ),
      class = "condathis_cmd_status_error",
      .envir = env
    )
  }

  return(px_res)
}
