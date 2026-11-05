# Shared parameters of condathis functions

The parameters that many condathis functions share. Each function uses
`@inheritParams condathis-params` and keeps its own `@param` only where
the meaning differs.

## Arguments

- env_name:

  Character string with the environment name. It must be a plain
  directory name that is valid on Linux, macOS and Windows:

  - Not empty, and not `.` or `..`.

  - Not starting with `-`, and not ending with `.`.

  - Without path separators, `:`, `#`, whitespace, control characters or
    `<>"|?*`.

  - Not a Windows device name, such as `NUL` or `COM1` (see *Environment
    names* in
    [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)).

  Invalid values abort with class `condathis_invalid_env_name`.
  Functions that take only names reject an
  [`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md)
  value with class `condathis_env_path_read_only`.
  [`run()`](https://luciorq.github.io/condathis/reference/run.md),
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md),
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
  and
  [`run_step()`](https://luciorq.github.io/condathis/reference/run_step.md)
  accept one.

- method:

  Character string naming the backend. `"auto"` (the default) uses the
  backend that owns `env_name` when it exists, and otherwise the first
  available backend in `getOption("condathis.backend_priority")` order
  (see
  [condathis-options](https://luciorq.github.io/condathis/reference/condathis-options.md)).
  Any name from
  [`list_registered_backend_names()`](https://luciorq.github.io/condathis/reference/list_registered_backend_names.md)
  selects that backend, and `"micromamba"` is built in. The name of a
  backend whose package `condathis` knows, such as `"rattler"` of the
  `rattlerthis` package, also selects it. `condathis` loads the package
  on first use. It aborts with class `condathis_backend_not_installed`
  when the package is not installed. `"native"` is a deprecated alias
  for `"micromamba"` (warns once per session). If you name a backend
  other than the owner, functions that change the environment abort with
  class `condathis_backend_mismatch`. The others warn
  (`condathis_backend_mismatch_warning`) and use the owner. An
  environment found under several backends aborts with
  `condathis_backend_ambiguous_env` unless `method` names one of them.
  Invalid values abort with class `condathis_invalid_method`.

- verbose:

  Character string that controls the console output. One of:

  - `"output"`: show the output of the command and the messages of
    condathis.

  - `"silent"`: show nothing.

  - `"cmd"`: show the command line.

  - `"spinner"`: show only a spinner.

  - `"full"`: show the command line, the output, and the backend's own
    log.

  `TRUE` means `"output"` and `FALSE` means `"silent"`. Every level
  except `"silent"` shows a spinner in interactive sessions. Invalid
  values abort with class `condathis_invalid_verbose` (see
  [condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)).
  The default is shown in Usage.

  The command line shown, the `cmd` of a result and the messages of
  `condathis` show the password and the token of a URL as `*****`.
  `micromamba` does the same (`https://user:*****@host/channel`,
  `https://host/t/*****/channel`). The command still gets them.

- error:

  Character string that controls what happens when the command fails.
  With `"cancel"` (the default), `condathis` aborts with these classes:

  - A non-zero exit status: `condathis_<function>_status_error` (also
    `condathis_status_error`).

  - A timeout: `condathis_<function>_timeout_error` (also
    `condathis_timeout_error`).

  - A missing environment: `condathis_<function>_env_not_found` (also
    `condathis_env_not_found`).

  A problem with an
  [`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md)
  value also adds `condathis_env_path_not_found` or
  `condathis_env_path_not_conda_env`. A command that the backend fails
  to resolve (for example a failed activation) aborts with class
  `condathis_<function>_resolve_failed` (also
  `condathis_backend_error`). It keeps the condathis classes of the
  backend's error, such as `condathis_activation_dump_error`, and has
  that error as its parent. The status and timeout errors carry the
  fields `status`, `stdout`, `stderr` and `timeout`.

  With `"continue"`, `condathis` returns a result instead. Its exit
  status is the status of the command, 127 for a missing environment or
  a command that could not start, or -9 for a timeout.

  Invalid values abort with class `condathis_invalid_error`. See
  [condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)
  for all classes.
