#' Shared parameters of condathis functions
#'
#' The parameters that many condathis functions share. Each function uses
#' `@inheritParams condathis-params` and keeps its own `@param` only where
#' the meaning differs.
#'
#' @param env_name Character string with the environment name.
#'   It must be a plain directory name that is valid on Linux, macOS and
#'   Windows:
#'   * Not empty, and not `.` or `..`.
#'   * Not starting with `-`, and not ending with `.`.
#'   * Without path separators, `:`, `#`, whitespace, control characters or
#'     `<>"|?*`.
#'   * Not a Windows device name, such as `NUL` or `COM1` (see
#'     *Environment names* in [create_env()]).
#'
#'   Invalid values abort with class `condathis_invalid_env_name`.
#'   [run()], [run_bin()], [run_pipeline()] and [run_step()] also accept an
#'   [env_path()] value. The other functions reject it with class
#'   `condathis_env_path_read_only`.
#' @param method Character string naming the backend. `"auto"` (the
#'   default) uses the backend that owns `env_name` when it exists, and
#'   otherwise the first available backend in
#'   `getOption("condathis.backend_priority")` order (see
#'   [condathis-options]). Any name from [list_registered_backend_names()]
#'   selects that backend, and `"micromamba"` is built in. The name of a
#'   backend whose package `condathis` knows, such as `"rattler"` of the
#'   `rattlerthis` package, also selects it. `condathis` loads the package
#'   on first use. `"native"` is a deprecated alias for `"micromamba"`
#'   (warns once per session). The 0.1.4 default `c("native", "auto")` is
#'   read as `"native"`.
#'
#'   If you name a backend other than the owner, functions that change the
#'   environment abort. The others warn and use the owner. The classes:
#'   * `condathis_backend_not_installed`: the package of the named backend
#'     is not installed.
#'   * `condathis_backend_mismatch`: the named backend does not own the
#'     environment, and the function changes it.
#'   * `condathis_backend_mismatch_warning` (a warning): the same, for a
#'     function that does not change the environment.
#'   * `condathis_backend_ambiguous_env`: several backends have an
#'     environment of that name, and `method` names none of them.
#'   * `condathis_invalid_method`: an invalid value.
#' @param verbose Character string that controls the console output. One
#'   of:
#'   * `"output"`: show the output of the command and the messages of
#'     `condathis`.
#'   * `"silent"`: show nothing.
#'   * `"cmd"`: show the command line.
#'   * `"spinner"`: show only a spinner.
#'   * `"full"`: show the command line, the output, and the backend's own
#'     log.
#'
#'   `TRUE` means `"output"` and `FALSE` means `"silent"`. Every level
#'   except `"silent"` shows a spinner in interactive sessions. It also
#'   shows these messages and this warning when they occur (see
#'   [condathis-conditions]):
#'   * `condathis_micromamba_downloading` (a message): no usable
#'     `micromamba` was found, so it is downloaded. Queries, such as
#'     [list_envs()], never download it.
#'   * `condathis_env_lock_waiting` and `condathis_cache_lock_waiting`
#'     (messages): the call waits for another R session.
#'   * `condathis_install_micromamba_checksum_unavailable` (a warning): the
#'     checksum of the downloaded `micromamba` could not be checked.
#'
#'   Invalid values abort with class `condathis_invalid_verbose`. The
#'   default is shown in Usage.
#'
#'   The command line shown, the `cmd` of a result and the messages of
#'   `condathis` show the password and the token of a URL as `*****`.
#'   `micromamba` does the same (`https://user:*****@host/channel`,
#'   `https://host/t/*****/channel`). The command still gets them.
#' @param error Character string that controls what happens when the
#'   command fails. With `"cancel"` (the default), `condathis` aborts with
#'   these classes:
#'   * `condathis_<function>_status_error` (also `condathis_status_error`):
#'     a non-zero exit status.
#'   * `condathis_<function>_timeout_error` (also `condathis_timeout_error`):
#'     a timeout.
#'   * `condathis_<function>_env_not_found` (also `condathis_env_not_found`):
#'     a missing environment.
#'   * `condathis_<function>_resolve_failed` (also `condathis_backend_error`):
#'     the backend failed to resolve the command, for example in a failed
#'     activation. The error keeps the condathis classes of the backend's
#'     error, such as `condathis_activation_dump_error`, and has that error
#'     as its parent.
#'
#'   A problem with an [env_path()] value also adds
#'   `condathis_env_path_not_found` or `condathis_env_path_not_conda_env`.
#'   The status and timeout errors carry the fields `status`, `stdout`,
#'   `stderr` and `timeout`.
#'
#'   With `"continue"`, `condathis` returns a result instead. Its exit
#'   status is the status of the command, 127 for a missing environment or a
#'   command that could not start, or -9 for a timeout.
#'
#'   Invalid values abort with class `condathis_invalid_error`. See
#'   [condathis-conditions] for all classes.
#'
#' @name condathis-params
#' @keywords internal
NULL
