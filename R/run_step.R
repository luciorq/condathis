#' Describe one command of a pipeline
#'
#' Builds one step for [run_pipeline()]. `run_step()` takes the same
#' command, arguments and `env_name` as [run()], but **it does not run
#' anything**. It only records the command, so [run_pipeline()] can start
#' every step together and connect them with pipes.
#'
#' `run_step()` checks arguments when it builds the step, so it reports a
#' mistake on the line that made it. Each invalid argument aborts with class
#' `condathis_run_step_invalid_<argument>`, for example
#' `condathis_run_step_invalid_cmd`, and with the shared classes
#' `condathis_invalid_<argument>` and `condathis_invalid_arg`.
#'
#' @param cmd Character string, the command to run: a single, non-empty
#'   string. Its arguments go in `...`.
#' @param ... Arguments of the command, unnamed, as in [run()]. Each
#'   element of a character, numeric or logical vector is one argument.
#'   `run_step()` drops `NULL` values and writes numbers in full, never in
#'   scientific notation: it stores `100000` as `"100000"`. `NA`, named
#'   arguments, and values that are not atomic vectors (for example lists)
#'   abort with class `condathis_run_step_invalid_args`.
#' @param env_name Character string with the environment the command runs
#'   in, or an environment given by [env_path()]. Defaults to `NULL`: the
#'   `env_name` of [run_pipeline()]. A name must follow the rules of the
#'   `env_name` argument of [run()]. Invalid values abort with class
#'   `condathis_invalid_env_name`.
#' @param method Character string naming the backend for this step, as the
#'   `method` of [run_pipeline()]. Defaults to `NULL`: the `method` of
#'   [run_pipeline()]. Steps that share an environment must agree on it.
#'   [run_pipeline()] checks whether the backend is registered when it runs,
#'   before it starts anything.
#' @param stderr Standard error target for this step, replacing the
#'   `stderr` of [run_pipeline()]: `"|"` to capture it, `NULL` to discard
#'   it, `""` to send it to the standard error of the R process, `"2>&1"`
#'   to send it to the standard output of the step (the next command, or
#'   the `stdout` target of [run_pipeline()] for the last step), or a file
#'   path. When not given, the step uses the `stderr` of [run_pipeline()].
#'
#' @returns An object of class `condathis_run_step`, for [run_pipeline()],
#'   which prints as the command line and its environment.
#'   [`c()`][c.condathis_run_step] combines steps into a list of steps of
#'   class `condathis_run_steps`, which [c()] extends again.
#'   `c(step_1, step_2)`, `c(c(step_1, step_2), step_3)` and
#'   `Reduce(c, steps)` all give a list for `run_pipeline(!!!steps)`. [c()]
#'   with a value that is not a step gives a plain list, as the default
#'   [c()] does.
#'
#' @examples
#' condathis::run_step(
#'   "pigz", "--decompress", "--stdout", "reads.fastq.gz",
#'   env_name = "pigz-env"
#' )
#' condathis::run_step(
#'   "rg", "--count", "^@read",
#'   env_name = condathis::env_path("/opt/envs/ripgrep")
#' )
#'
#' # Combine steps with `c()`, then pass them to `run_pipeline()` with `!!!`
#' steps <- c(
#'   condathis::run_step("seq", "1", "10"),
#'   condathis::run_step("head", "-n", "3")
#' )
#' steps
#'
#' @family commands
#'
#' @export
run_step <- function(
  cmd,
  ...,
  env_name = NULL,
  method = NULL,
  stderr
) {
  # The same checks and messages as `run()` and `run_bin()`, also for a
  # missing `cmd`. Named values in `...` are checked with the other
  # arguments, in `validate_run_step_object()`: `rlang::check_dots_unnamed()`
  # raised an error without the condathis classes.
  validate_cmd_arg(
    cmd,
    class = "condathis_run_step_invalid_cmd",
    call = rlang::current_env()
  )
  stderr_set <- isFALSE(missing(stderr))
  step <- new_run_step(
    cmd = cmd,
    # Converted to a character vector by `validate_run_step_object()`.
    args = list(...),
    env_name = env_name,
    method = method,
    stderr = if (isTRUE(stderr_set)) stderr,
    stderr_set = stderr_set
  )
  return(validate_run_step_object(step, call = rlang::current_env()))
}

#' Construct a `condathis_run_step` object
#'
#' @param cmd Character string.
#' @param args Character vector. In `run_step()`, the list of `...` values,
#'   before `validate_run_step_object()` converts it.
#' @param env_name `NULL`, a character string, or a `condathis_env_path`.
#' @param method `NULL` or a character string.
#' @param stderr The step's stderr target, when `stderr_set`.
#' @param stderr_set Logical. Whether the step replaces the pipeline's
#'   `stderr`. Needed because `NULL` is itself a target (discard).
#'
#' @keywords internal
#' @noRd
new_run_step <- function(
  cmd,
  args = character(0L),
  env_name = NULL,
  method = NULL,
  stderr = NULL,
  stderr_set = FALSE
) {
  return(structure(
    list(
      cmd = cmd,
      args = args,
      env_name = env_name,
      method = method,
      stderr = stderr,
      stderr_set = stderr_set
    ),
    class = "condathis_run_step"
  ))
}

#' Check the fields of a pipeline step
#'
#' Both `run_step()` and `run_pipeline()` check steps with this function. A
#' `condathis_run_step` object can also be built or edited by hand, so
#' `run_pipeline()` checks every step again before using it.
#'
#' With `index = NULL`, `x` comes from `run_step()`: its `args` is the list
#' of `...` values, converted here with `cmd_args_as_character()`, and each
#' invalid field is an error of the class `run_step()` documents for that
#' argument (`condathis_run_step_invalid_cmd`, `_invalid_args`,
#' `_invalid_env_name`, `_invalid_method`, `_invalid_stderr`), with the
#' shared classes of rule R1 (`condathis_invalid_<arg>`,
#' `condathis_invalid_arg`). Otherwise every invalid field is an error of
#' class `c("condathis_run_pipeline_invalid_step",
#' "condathis_pipeline_invalid_step", "condathis_invalid_arg")` that names
#' the step by its position; an invalid `env_name` also has
#' `condathis_invalid_env_name`.
#'
#' @param x A `condathis_run_step` object.
#' @param index Integer position of the step in the pipeline, or `NULL` for
#'   a step that `run_step()` is building.
#' @param call Calling environment, for the error.
#'
#' @returns `x`, with `args` converted to a character vector when
#'   `index = NULL`. Invisibly otherwise.
#'
#' @keywords internal
#' @noRd
validate_run_step_object <- function(
  x,
  index = NULL,
  call = rlang::caller_env()
) {
  from_run_step <- is.null(index)
  # The step classes of `run_pipeline()`: the new name, then the old one,
  # kept until 1.0.
  invalid_step_class <- c(
    "condathis_run_pipeline_invalid_step",
    "condathis_pipeline_invalid_step"
  )
  env_name_class <- if (isTRUE(from_run_step)) {
    arg_error_class("run_step", "env_name")
  } else {
    c(invalid_step_class, "condathis_invalid_env_name", "condathis_invalid_arg")
  }
  abort_bad <- function(field) {
    if (isTRUE(from_run_step)) {
      # `stderr_set` is not an argument: it records whether `stderr` was set.
      arg <- if (identical(field, "stderr_set")) "stderr" else field
      expected <- if (identical(arg, "cmd")) {
        "a single, non-empty character string"
      } else {
        "{.code NULL} or a single character string"
      }
      condathis_abort(
        message = c(
          `x` = paste0("{.arg ", arg, "} must be ", expected, ".")
        ),
        class = arg_error_class("run_step", arg),
        call = call
      )
    }
    condathis_abort(
      message = c(
        `x` = "Step {index} is a malformed {.cls condathis_run_step} object: invalid {.field {field}}.",
        `i` = "Build each step with {.fn run_step}."
      ),
      class = c(invalid_step_class, "condathis_invalid_arg"),
      call = call
    )
  }
  is_single_string <- function(value) {
    isTRUE(rlang::is_string(value)) && isFALSE(is.na(value))
  }
  if (isFALSE(is_single_string(x$cmd)) || isFALSE(nzchar(x$cmd))) {
    abort_bad("cmd")
  }
  if (isTRUE(from_run_step)) {
    # A named value aborts here, with a hint for a misspelled option, as in
    # `run()` and `run_bin()`.
    x$args <- cmd_args_as_character(
      x$args,
      class = "condathis_run_step_invalid_args",
      formal_names = names(formals(run_step)),
      call = call
    )
  } else if (isFALSE(is.character(x$args)) || isTRUE(anyNA(x$args))) {
    abort_bad("args")
  }
  if (isFALSE(is.null(x$env_name))) {
    if (isTRUE(is_env_path(x$env_name))) {
      validate_env_path_object(x$env_name, class = env_name_class, call = call)
    } else {
      validate_env_name(x$env_name, class = env_name_class, call = call)
    }
  }
  if (isFALSE(is.null(x$method)) && isFALSE(is_single_string(x$method))) {
    abort_bad("method")
  }
  if (isFALSE(rlang::is_bool(x$stderr_set))) {
    abort_bad("stderr_set")
  }
  if (
    isTRUE(x$stderr_set) &&
      isFALSE(is.null(x$stderr)) &&
      isFALSE(is_single_string(x$stderr))
  ) {
    abort_bad("stderr")
  }
  if (isTRUE(from_run_step)) {
    return(x)
  }
  return(invisible(x))
}

#' Is `x` a pipeline step?
#'
#' @keywords internal
#' @noRd
is_run_step <- function(x) {
  return(inherits(x, "condathis_run_step"))
}

#' Quote command words only where a shell would need it
#'
#' For display only, as in the "Running" line of `processx`.
#'
#' @param x Character vector of words.
#'
#' @returns Character vector.
#'
#' @keywords internal
#' @noRd
quote_cmd_words <- function(x) {
  x <- as.character(x)
  needs_quotes <- !nzchar(x) | grepl("[^A-Za-z0-9_./:=@%+,^-]", x)
  x[needs_quotes] <- shQuote(x[needs_quotes])
  return(x)
}

#' Display label of an `env_name` value
#'
#' @param env_name `NULL`, a character string, or a `condathis_env_path`.
#'
#' @returns Character string.
#'
#' @keywords internal
#' @noRd
env_name_label <- function(env_name) {
  if (is.null(env_name)) {
    return("pipeline default")
  }
  if (isTRUE(is_env_path(env_name))) {
    return(as.character(env_name$path))
  }
  return(as.character(env_name))
}

#' Combine pipeline steps into a list of steps
#'
#' `c()` on classed lists splices their fields into one list and drops the
#' class. For steps it returns a list of steps instead, of class
#' `condathis_run_steps`, so `run_pipeline(!!!c(step_1, step_2))` works.
#' Its own `c()` method keeps it that way: `c(c(step_1, step_2), step_3)`,
#' `c(step_1, c(step_2, step_3))` and `Reduce(c, steps)` give one flat list
#' of steps. Plain lists of steps are flattened into the result, and `NULL`
#' values are dropped, as by `c()`, so `c(step_1, if (gz) step_2)` works.
#'
#' Any other value gives a plain list, as the default `c()` does, and
#' [run_pipeline()] reports the values that are not steps. So
#' `do.call(run_pipeline, c(steps, list(verbose = "silent")))` works.
#'
#' `c()` dispatches on its first argument only: `c(steps, step)` with a
#' plain list or `NULL` as `steps` uses the default method and splits
#' `step` into its fields. Write `c(steps, list(step))` there, or start
#' from a step.
#'
#' @param ... `condathis_run_step` objects, lists of them, `NULL`, or other
#'   values.
#'
#' @returns A `condathis_run_steps` object (a list of `condathis_run_step`
#'   objects) when every value is a step, a list of steps or `NULL`.
#'   Otherwise the plain list that the default `c()` gives, with the steps
#'   as elements. `[` keeps the class, and `as.list()` removes it.
#'
#' @keywords internal
#' @export
c.condathis_run_step <- function(...) {
  return(combine_run_steps(...))
}

#' @rdname c.condathis_run_step
#' @export
c.condathis_run_steps <- function(...) {
  return(combine_run_steps(...))
}

#' @rdname c.condathis_run_step
#' @param x A `condathis_run_steps` object.
#' @param i Index of the steps to keep.
#' @export
`[.condathis_run_steps` <- function(x, i) {
  return(new_run_steps(unclass(x)[i]))
}

#' @rdname c.condathis_run_step
#' @export
as.list.condathis_run_steps <- function(x, ...) {
  return(unclass(x))
}

#' @export
format.condathis_run_steps <- function(x, ...) {
  n <- length(x)
  steps <- vapply(
    seq_len(n),
    function(i) {
      step <- x[[i]]
      text <- if (isTRUE(is_run_step(step))) {
        format(step, ...)
      } else {
        "<not a run_step>"
      }
      return(sprintf("[%d] %s", i, text))
    },
    character(1L)
  )
  return(c(
    sprintf("<run_steps> %d step%s", n, if (n == 1L) "" else "s"),
    steps
  ))
}

#' @export
print.condathis_run_steps <- function(x, ...) {
  cat(format(x, ...), sep = "\n")
  return(invisible(x))
}

#' Construct a `condathis_run_steps` object
#'
#' @param steps Unnamed list of `condathis_run_step` objects.
#'
#' @keywords internal
#' @noRd
new_run_steps <- function(steps = list()) {
  return(structure(unname(steps), class = "condathis_run_steps"))
}

#' Is `x` a list of pipeline steps?
#'
#' A `condathis_run_steps` object, or a plain list whose elements are all
#' steps (an empty list too).
#'
#' @keywords internal
#' @noRd
is_run_step_list <- function(x) {
  if (inherits(x, "condathis_run_steps")) {
    return(TRUE)
  }
  return(
    is.list(x) &&
      isFALSE(is.object(x)) &&
      isTRUE(all(vapply(x, is_run_step, logical(1L))))
  )
}

#' Combine steps and lists of steps into one list of steps
#'
#' Each step becomes a list of one step and each list of steps a plain
#' list, so the default `c()` joins them without splitting a step into its
#' fields. Other values go to the default `c()` as they are, and a named
#' option keeps its name: `do.call(run_pipeline, c(steps, list(verbose =
#' "silent")))` works, and `run_pipeline()` reports any value that is not
#' a step.
#'
#' @param ... Values given to `c()`.
#'
#' @returns A `condathis_run_steps` object when every element is a step,
#'   otherwise what the default `c()` returns.
#'
#' @keywords internal
#' @noRd
combine_run_steps <- function(...) {
  parts <- lapply(list(...), function(part) {
    if (isTRUE(is_run_step(part))) {
      return(list(part))
    }
    if (inherits(part, "condathis_run_steps")) {
      return(unclass(part))
    }
    return(part)
  })
  # The first part is now a plain list, so this uses the default method.
  combined <- do.call(c, parts)
  if (
    isTRUE(is.list(combined)) &&
      isTRUE(all(vapply(combined, is_run_step, logical(1L))))
  ) {
    return(new_run_steps(combined))
  }
  return(combined)
}

#' @export
format.condathis_run_step <- function(x, ...) {
  details <- paste0("env: ", env_name_label(x$env_name))
  if (isFALSE(is.null(x$method))) {
    details <- paste0(details, ", method: ", x$method)
  }
  return(sprintf(
    "<run_step> %s [%s]",
    paste(quote_cmd_words(hide_secrets(c(x$cmd, x$args))), collapse = " "),
    details
  ))
}

#' @export
print.condathis_run_step <- function(x, ...) {
  cat(format(x, ...), "\n", sep = "")
  return(invisible(x))
}
