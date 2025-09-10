#' @keywords internal
#' @noRd
rethrow_error_run <- function(expr, env = parent.frame()) {
  code <- base::substitute(expr = expr)
  err_cnd <- rlang::catch_cnd(
    expr = {
      px_res <- rlang::eval_bare(expr = code, env = env)
    },
    classes = c("system_command_status_error", "rlib_error_3_0", "c_error")
  )

  if (
    isFALSE(rlang::is_null(env[["stdin"]])) &&
      isFALSE(identical(env[["stdin"]], "|"))
  ) {
    if (
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
  }

  if (isFALSE(is.null(err_cnd)) && !isFALSE(env[["error_var"]])) {
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
    }

    status_code <- NULL
    if (isFALSE("status" %in% names(err_cnd))) {
      status_code <- "127"
      additional_lines <- c("{cmd}: command not found", additional_lines)
    } else {
      status_code <- err_cnd[["status"]]
    }
    env[["status_code"]] <- status_code

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
    if (isTRUE(is.null(err_cnd[["status"]]))) {
      status_code <- 127L
    } else {
      status_code <- err_cnd[["status"]]
    }

    if (
      isFALSE(is.null(err_cnd[["message"]])) &&
        isTRUE(stringr::str_detect(err_cnd[["message"]], "Native call to"))
    ) {
      if (isFALSE(is.null(env[["cmd"]]))) {
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
      timeout = FALSE
    )
  }

  return(px_res)
}
