#' Run a command in a Conda environment
#'
#' Runs a command line tool with a Conda environment activated. The command
#' gets the environment variables that the activation sets, including those
#' of the `activate.d` scripts of its packages. To run a program without
#' activation, use [run_bin()] with `activate = FALSE`.
#'
#' `run()` activates the environment and starts the command itself. The
#' micromamba backend records the activation of an environment the first
#' time a command runs in it. That first command takes longer, and `timeout`
#' includes the activation. The backend reuses the activation until the
#' environment changes (its packages, `activate.d` scripts or `env_vars.d`
#' files). A change in the environment variables of the R session also ends
#' the reuse.
#'
#' Arguments in `...` reach the command exactly as given on every platform.
#' No shell is involved. Characters such as `>`, `|`, `&`, `%`, `$`, `*` and
#' quotes have no special meaning. Shell builtins (for example `echo` or
#' `dir` on Windows) are not available as commands. To use shell features,
#' run a shell explicitly, as in `run("bash", "-c", "...")`. To connect
#' commands with pipes, use [run_pipeline()]. One exception applies on
#' Windows. Windows starts batch files (`.bat`, `.cmd`) through `cmd.exe`,
#' which parses their arguments again.
#'
#' When `env_name` is the default `"condathis-env"` and that environment
#' does not exist, `run()` creates it, empty, with the backend that `method`
#' selects. `run()` never creates any other missing environment. The call
#' fails, as `error` describes.
#'
#' The errors of a failed or timed-out command carry the fields `status`,
#' `stdout`, `stderr` and `timeout`. A handler does not need to parse the
#' message, as in
#' `tryCatch(run("false"), condathis_status_error = function(e) e$status)`.
#'
#' @inheritParams condathis-params
#' @param cmd Character string, the command to run: a single, non-empty
#'   string. Other values abort with class `condathis_invalid_cmd`. Pass the
#'   arguments of the command in `...`.
#' @param ... Arguments of the command, unnamed: character, numeric or
#'   logical vectors, each element one argument. `run()` drops `NULL`
#'   values. It writes numbers in full, never in scientific notation:
#'   `100000` is passed as `"100000"`. `NA`, named arguments, and values
#'   that are not atomic vectors (for example lists) abort with class
#'   `condathis_run_invalid_args`.
#' @param stdout Standard output target: `"|"` (the default) captures it in
#'   the result, a file path writes it to that file, and `NULL` discards it.
#' @param stderr Standard error target: `"|"` (the default) captures it in
#'   the result, a file path writes it to that file, and `NULL` discards it.
#' @param stdin Standard input source: `NULL` (the default) for no input,
#'   the path of an existing file to read, or `"|"` to write `input` to the
#'   command. Other values abort with class `condathis_invalid_stdin`.
#' @param input Character or raw vector written to the standard input of
#'   the command. `condathis` joins the elements of a character vector with
#'   line feeds and adds none after the last one. Must be `NULL` (the default)
#'   unless `stdin = "|"`. Other values abort with class
#'   `condathis_invalid_input`. With `stdin = "|"`, `condathis` shows the
#'   output when the command ends, not while it runs, and shows no spinner.
#' @param binary Logical. Whether to return `stdout` and `stderr` as raw
#'   vectors instead of decoding them as UTF-8 text. Defaults to `FALSE`. A
#'   process has one encoding for both streams, so with `TRUE` both are raw,
#'   even if only one of them carries binary data. Check with `is.raw()`
#'   before treating either as text. `condathis` never shows raw streams on
#'   the console, whatever `verbose` is. Values other than `TRUE` and `FALSE`
#'   abort with class `condathis_invalid_binary`.
#' @param supervise Logical. Whether the `processx` supervisor watches the
#'   process: when the R session ends, even by a crash, the supervisor kills
#'   it. Defaults to `FALSE`.
#' @param cleanup_tree Logical. Whether to kill the process tree of the
#'   command, its child processes included, when the command finishes, times
#'   out, or is interrupted. Defaults to `FALSE`, so that a daemon that the
#'   command starts keeps running after the command exits. On Windows, a
#'   daemon that keeps the captured standard output or error of the command
#'   open ends when R has read that output. This is a limit of `processx` on
#'   Windows, whatever `cleanup_tree` is. Send the output to files
#'   (`stdout`, `stderr`) to keep such a daemon running.
#' @param linux_pdeathsig Logical. On Linux, whether the command gets
#'   `SIGTERM` when the R session ends, even by a crash. Ignored on other
#'   platforms. Defaults to `FALSE`.
#' @param timeout Number of seconds the call may take, the activation of the
#'   environment included (see Details in [run()]). Defaults to `Inf` (no
#'   limit). `condathis` lowers a finite value above 2147483 (about 24.8
#'   days) to that value. When the time is up, `condathis` kills the
#'   command, or does not start it when the activation took all the time.
#'   `error = "cancel"` then aborts, and `error = "continue"` returns a
#'   result with `status = -9` and `timeout = TRUE`. Values that are not a
#'   single, non-negative number abort with class
#'   `condathis_invalid_timeout`.
#'
#' @returns A `condathis_result` object, invisibly: a classed list with
#'   `status`, `stdout`, `stderr`, `timeout`, `pid`, `cmd` and `env_name`,
#'   which prints as a short summary. `status` is the exit status of the
#'   command. On Linux and macOS, a command that a signal ends has status
#'   128 plus the signal number, as in a shell (143 for `SIGTERM`).
#'   `stdout` and `stderr` are `NA` when that stream was not captured (a
#'   target other than `"|"`). `pid` is the process ID of the command with
#'   `stdin = "|"`, and `NA` otherwise. `cmd` is your command line, each part
#'   quoted, with the credentials of URLs masked (see `verbose`). `env_name`
#'   is the environment name, or the directory of an [env_path()].
#'
#' @examples
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   # A local channel shipped with condathis, with `polyglot`: a
#'   # dependency-free script that runs on Linux, macOS and Windows.
#'   channel <- system.file(
#'     "extdata", "polyglot-channel",
#'     package = "condathis"
#'   )
#'   create_env("polyglot", env_name = "polyglot-env", channels = channel)
#'
#'   # Run its command, on any platform
#'   polyglot_res <- run(
#'     "polyglot",
#'     env_name = "polyglot-env",
#'     verbose = "silent"
#'   )
#'   print(parse_output(polyglot_res)[1])
#'   #> [1] "System detected: Linux/Unix"
#'
#'   # `pigz` (conda-forge) has builds for Linux, macOS and Windows
#'   create_env("conda-forge::pigz", env_name = "pigz-env")
#'
#'   # Decompress a FASTQ file shipped with condathis
#'   fastq_file <- fs::path_package(
#'     "condathis", "extdata", "sample1_L001_R1_001.fastq.gz"
#'   )
#'   pigz_res <- run(
#'     "pigz", "--decompress", "--stdout", fastq_file,
#'     env_name = "pigz-env",
#'     verbose = "silent"
#'   )
#'   print(parse_output(pigz_res)[1])
#'   #> [1] "@read1/gi|424037187|ref|NR_073460.1| Homo sapiens ribosome ..."
#' })
#' }
#'
#' @seealso [create_env()] to create an environment, [env_path()] for an
#'   environment created outside `condathis`, and [condathis-conditions]
#'   for the condition classes.
#' @family commands
#'
#' @export
run <- function(
  cmd,
  ...,
  env_name = "condathis-env",
  method = "auto",
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
  linux_pdeathsig = FALSE,
  timeout = Inf
) {
  # Every argument is checked before the first backend call or other side
  # effect (rule R2), so a bad value never creates `condathis-env` first.
  validate_cmd_arg(
    cmd,
    class = c("condathis_run_invalid_cmd", "condathis_run_null_cmd")
  )
  args <- cmd_args_as_character(
    list(...),
    class = "condathis_run_invalid_args",
    formal_names = names(formals(run)),
    named_class = dots_named_old_class
  )
  validate_input_with_stdin(
    input,
    stdin = stdin,
    class = arg_error_class("run", "input")
  )
  validate_bool_arg(
    binary,
    class = arg_error_class(
      "run",
      "binary",
      aliases = "condathis_run_invalid_binary_arg"
    ),
    arg_name = "binary"
  )
  env_name_class <- "condathis_run_invalid_env_name"
  if (isTRUE(is_env_path(env_name))) {
    validate_env_path_object(env_name, class = env_name_class)
  } else {
    validate_env_name(env_name, class = env_name_class)
  }
  error <- arg_match_classed(
    error,
    values = c("cancel", "continue"),
    class = "condathis_invalid_error",
    arg_name = "error"
  )
  verbose_list <- parse_verbose_arg(verbose)
  run_args <- validate_run_args(
    fn = "run",
    timeout = timeout,
    supervise = supervise,
    cleanup_tree = cleanup_tree,
    linux_pdeathsig = linux_pdeathsig,
    stdin = stdin,
    stdout = stdout,
    stderr = stderr
  )
  # `rethrow_error_run()` reads `timeout` from this frame for its message.
  timeout <- run_args$timeout
  validate_method_arg(method)

  # Ignore linter warning. `error_var` is used by `rethrow_error_run()`
  # + env by accessing this function environment.
  error_var <- identical(error, "cancel")

  # An environment given by `env_path()` has no name to look up: it skips
  # backend resolution and the default environment's auto-creation, and is
  # checked to be a Conda environment instead.
  env_path_stderr <- NULL
  env_dir <- NULL
  if (isTRUE(is_env_path(env_name))) {
    resolved <- resolve_env_path_target(
      env_name,
      method = method,
      class = env_name_class
    )
    env_dir <- resolved$env_dir
    env_label <- env_dir
    env_path_stderr <- check_env_path_usable(
      env_dir,
      error_var = error_var,
      class = "condathis_run_env_not_found"
    )
    env_name_exists <- is.null(env_path_stderr)
  } else {
    env_label <- env_name
    resolved <- resolve_backend(
      env_name = env_name,
      method = method,
      mutating = FALSE
    )

    # Use backend_probe_env(), not backend_has_env(): a failed listing
    # (transient lock, corrupt metadata, JSON error) gives NA, and NA must
    # not refuse an existing environment (rule R5). The command then runs,
    # and a missing environment fails with the backend's own error.
    env_name_exists <- backend_probe_env(
      resolved$backend,
      env_name,
      verbose = "silent"
    )
    if (isTRUE(is.na(env_name_exists))) {
      env_name_exists <- TRUE
    }

    # Only the default environment is created when it is missing (decision
    # D3), and with the backend this call resolved, so that it never ends
    # up under another backend than the one `method` names.
    if (isFALSE(env_name_exists) && identical(env_name, "condathis-env")) {
      create_base_env(
        method = resolved$name,
        verbose = verbose_list$internal_verbose
      )
      env_name_exists <- TRUE
    }
  }

  if (isFALSE(env_name_exists)) {
    # An unusable environment given by path has already aborted under
    # `error = "cancel"`, in `check_env_path_usable()`.
    if (isTRUE(error_var)) {
      abort_env_not_found(env_name, class = "condathis_run_env_not_found")
    }
    px_res <- list(
      status = 127L,
      stdout = "",
      stderr = env_path_stderr %||%
        sprintf("Conda environment '%s' does not exist.\n", env_name),
      timeout = FALSE
    )
  } else {
    # Every backend describes the invocation with `backend_resolve_run()`,
    # and condathis starts the command itself, so streaming, spinner,
    # timeout and supervise/cleanup_tree/linux_pdeathsig behave the same
    # for every backend and OS. For the micromamba backend, the activation
    # variables are those of a real `micromamba run` activation, cached per
    # environment (see `get_micromamba_activation_envvars()`).
    #
    # The command used to run through `micromamba run` on Linux and macOS.
    # Then what `activate.d` scripts printed was in the output, and the
    # command got micromamba's own
    # environment (`MAMBA_ROOT_PREFIX`, its `TMPDIR`), unlike `run_bin()`,
    # `run_pipeline()` and every other backend. On Windows, `micromamba run`
    # wraps the command in a temporary `.bat` script, so `cmd.exe` re-parses
    # every argument: `>`, `<`, `|` and `&` become redirections and command
    # separators, `^` and `%` are consumed, and newlines cannot be passed at
    # all.
    px_res <- rethrow_error_run(
      expr = {
        run_internal_backend(
          resolved$backend,
          cmd = cmd,
          args,
          env_name = env_label,
          env_dir = env_dir,
          verbose = verbose_list,
          error = error,
          stdout = stdout,
          stderr = stderr,
          stdin = stdin,
          input = input,
          binary = binary,
          supervise = supervise,
          cleanup_tree = cleanup_tree,
          linux_pdeathsig = linux_pdeathsig,
          timeout = timeout,
          backend_name = resolved$name,
          call = rlang::current_env()
        )
      },
      fn = "run"
    )
  }

  cmd_string <- format_cmd_line(c(cmd, args))
  result <- new_condathis_result(
    status = px_res$status,
    stdout = captured_or_na(px_res$stdout, target = stdout),
    stderr = captured_or_na(px_res$stderr, target = stderr),
    timeout = if (is.null(px_res$timeout)) FALSE else px_res$timeout,
    pid = if (is.null(px_res$pid)) NA_integer_ else px_res$pid,
    cmd = cmd_string,
    env_name = env_label
  )
  return(invisible(result))
}

#' Old classes of a named value in `...` of `run()` and `run_bin()`
#'
#' Before, `run()` and `run_bin()` called `rlang::check_dots_unnamed()`,
#' whose error has these classes. They stay on the error of
#' `cmd_args_as_character()`, after the condathis classes.
#'
#' @keywords internal
#' @noRd
dots_named_old_class <- c("rlib_error_dots_named", "rlib_error_dots")

#' Convert the command arguments of the `run()` family to a character vector
#'
#' `run()`, `run_bin()` and `run_step()` all convert their `...` values with
#' this function, so a value reaches the command the same way through each
#' of them.
#'
#' `as.character()` writes doubles from `1e5` on in scientific notation and
#' rounds them to 15 significant digits: `100000` became `"1e+05"`, which
#' `head -n` rejects. Doubles are written in fixed notation instead, with
#' the fewest digits (15 to 17) that read back as the same number. Integers,
#' logical values and character strings use `as.character()`. A value with
#' a class (a factor, a date) uses its own `as.character()` method.
#'
#' A named value aborts too. An argument after `...` must be named exactly,
#' so a misspelled option such as `verbos = "silent"` lands in `...`; the
#' error then names the closest formal of the caller.
#'
#' @param args List of the values given in `...`. `NULL` values are
#'   dropped.
#' @param class Character string. Condition class of the error, one per
#'   calling function. The error also has the classes
#'   `condathis_invalid_cmd_args` and `condathis_invalid_arg`.
#' @param formal_names Character vector, the formals of the calling
#'   function, for the hint of a named value. `NULL` gives no hint.
#' @param named_class Character vector of extra classes for the error of a
#'   named value only, after `condathis_error`. `run()` and `run_bin()`
#'   pass the classes of the error of `rlang::check_dots_unnamed()`, which
#'   they raised before, so old handlers still match.
#' @param call Calling environment, for the error.
#'
#' @returns An unnamed character vector.
#'
#' @keywords internal
#' @noRd
cmd_args_as_character <- function(
  args,
  class,
  formal_names = NULL,
  named_class = NULL,
  call = rlang::caller_env()
) {
  error_class <- c(class, "condathis_invalid_cmd_args", "condathis_invalid_arg")
  arg_names <- names(args)
  if (isTRUE(any(nzchar(arg_names)))) {
    bad_name <- arg_names[nzchar(arg_names)][[1L]]
    suggestion <- closest_names(bad_name, setdiff(formal_names, "..."))
    message <- c(
      `x` = "Command arguments in {.arg ...} must be unnamed, but {.arg {bad_name}} is named."
    )
    if (isTRUE(length(suggestion) > 0L)) {
      message <- c(message, `i` = "Did you mean {.or {.arg {suggestion}}}?")
    }
    condathis_abort(
      message = message,
      class = c(error_class, "condathis_error", named_class),
      call = call
    )
  }
  parts <- lapply(args, function(value) {
    if (is.null(value)) {
      return(character(0L))
    }
    if (isFALSE(is.atomic(value)) || isTRUE(anyNA(value))) {
      condathis_abort(
        message = c(
          `x` = "Command arguments in {.arg ...} must be non-missing strings or numbers."
        ),
        class = error_class,
        call = call
      )
    }
    if (isTRUE(is.double(value)) && isFALSE(is.object(value))) {
      return(format_cmd_double(value))
    }
    return(as.character(value))
  })
  return(unname(as.character(unlist(parts))))
}

#' Write doubles as command arguments
#'
#' Fixed notation, never scientific, with `.` as the decimal mark whatever
#' `options(OutDec)` says, and with the fewest significant digits (15 to 17)
#' that read back as the same number: `0.1` stays `"0.1"`, and `0.1 + 0.2`
#' is `"0.30000000000000004"`, not `"0.3"`.
#'
#' `scientific = FALSE` only adds a penalty of 100 characters to the
#' scientific form, so doubles below about `1e-310` still came out in
#' scientific notation. The penalty of 1000 characters is larger than the
#' widest fixed form of any double (about 340 characters).
#'
#' @param x Double vector without `NA`.
#'
#' @returns Character vector.
#'
#' @keywords internal
#' @noRd
format_cmd_double <- function(x) {
  return(vapply(
    x,
    function(value) {
      if (isFALSE(is.finite(value))) {
        return(as.character(value))
      }
      for (digits in 15L:17L) {
        text <- format(
          value,
          digits = digits,
          scientific = 1000L,
          trim = TRUE,
          decimal.mark = ".",
          big.mark = ""
        )
        if (isTRUE(identical(as.numeric(text), value))) {
          return(text)
        }
      }
      return(text)
    },
    character(1L),
    USE.NAMES = FALSE
  ))
}
