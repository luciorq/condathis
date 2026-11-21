# Run a binary from a Conda environment

`run_bin()` is superseded by
[`run()`](https://luciorq.github.io/condathis/reference/run.md), which
takes the same arguments and runs the command the same way. `run_bin()`
stays for code written for earlier versions of `condathis`. Its errors
have their own classes, `condathis_run_bin_*`, which also carry the
`condathis_run_*` classes (see
[condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)).

## Usage

``` r
run_bin(
  cmd,
  ...,
  env_name = "condathis-env",
  method = "auto",
  verbose = c("output", "silent", "cmd", "spinner", "full"),
  error = c("cancel", "continue"),
  stdout = "|",
  stderr = "|",
  stdin = NULL,
  input = NULL,
  binary = FALSE,
  supervise = FALSE,
  cleanup_tree = FALSE,
  linux_pdeathsig = FALSE,
  activate = TRUE,
  timeout = Inf
)
```

## Arguments

- cmd:

  Character string, the command to run: a single, non-empty string.
  Other values abort with class `condathis_invalid_cmd`. Pass the
  arguments of the command in `...`.

- ...:

  Arguments of the command, unnamed, as in
  [`run()`](https://luciorq.github.io/condathis/reference/run.md).
  Values that
  [`run()`](https://luciorq.github.io/condathis/reference/run.md)
  rejects abort with class `condathis_run_bin_invalid_args`.

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
  [`run()`](https://luciorq.github.io/condathis/reference/run.md),
  `run_bin()`,
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
  and
  [`run_step()`](https://luciorq.github.io/condathis/reference/run_step.md)
  also accept an
  [`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md)
  value. The other functions reject it with class
  `condathis_env_path_read_only`.

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
  on first use. `"native"` is a deprecated alias for `"micromamba"`
  (warns once per session). The 0.1.4 default `c("native", "auto")` is
  read as `"native"`.

  If you name a backend other than the owner, functions that change the
  environment abort. The others warn and use the owner. The classes:

  - `condathis_backend_not_installed`: the package of the named backend
    is not installed.

  - `condathis_backend_mismatch`: the named backend does not own the
    environment, and the function changes it.

  - `condathis_backend_mismatch_warning` (a warning): the same, for a
    function that does not change the environment.

  - `condathis_backend_ambiguous_env`: several backends have an
    environment of that name, and `method` names none of them.

  - `condathis_invalid_method`: an invalid value.

- verbose:

  Character string that controls the console output. One of:

  - `"output"`: show the output of the command and the messages of
    `condathis`.

  - `"silent"`: show nothing.

  - `"cmd"`: show the command line.

  - `"spinner"`: show only a spinner.

  - `"full"`: show the command line, the output, and the backend's own
    log.

  `TRUE` means `"output"` and `FALSE` means `"silent"`. Every level
  except `"silent"` shows a spinner in interactive sessions. It also
  shows these messages and this warning when they occur (see
  [condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)):

  - `condathis_micromamba_downloading` (a message): no usable
    `micromamba` was found, so it is downloaded. Queries, such as
    [`list_envs()`](https://luciorq.github.io/condathis/reference/list_envs.md),
    never download it.

  - `condathis_env_lock_waiting` and `condathis_cache_lock_waiting`
    (messages): the call waits for another R session.

  - `condathis_install_micromamba_checksum_unavailable` (a warning): the
    checksum of the downloaded `micromamba` could not be checked.

  Invalid values abort with class `condathis_invalid_verbose`. The
  default is shown in Usage.

  The command line shown, the `cmd` of a result and the messages of
  `condathis` show the password and the token of a URL as `*****`.
  `micromamba` does the same (`https://user:*****@host/channel`,
  `https://host/t/*****/channel`). The command still gets them.

- error:

  Character string that controls what happens when the command fails.
  With `"cancel"` (the default), `condathis` aborts with these classes:

  - `condathis_<function>_status_error` (also `condathis_status_error`):
    a non-zero exit status.

  - `condathis_<function>_timeout_error` (also
    `condathis_timeout_error`): a timeout.

  - `condathis_<function>_env_not_found` (also
    `condathis_env_not_found`): a missing environment.

  - `condathis_<function>_resolve_failed` (also
    `condathis_backend_error`): the backend failed to resolve the
    command, for example in a failed activation. The error keeps the
    condathis classes of the backend's error, such as
    `condathis_activation_dump_error`, and has that error as its parent.

  A problem with an
  [`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md)
  value also adds `condathis_env_path_not_found` or
  `condathis_env_path_not_conda_env`. The status and timeout errors
  carry the fields `status`, `stdout`, `stderr` and `timeout`.

  With `"continue"`, `condathis` returns a result instead. Its exit
  status is the status of the command, 127 for a missing environment or
  a command that could not start, or -9 for a timeout.

  Invalid values abort with class `condathis_invalid_error`. See
  [condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)
  for all classes.

- stdout:

  Standard output target: `"|"` (the default) captures it in the result,
  a file path writes it to that file, `""` sends it to the standard
  output of the R process, and `NULL` discards it.

- stderr:

  Standard error target: `"|"` (the default) captures it in the result,
  `"2>&1"` sends it to the standard output target, a file path writes it
  to that file, `""` sends it to the standard error of the R process,
  and `NULL` discards it.

- stdin:

  Standard input source: `NULL` (the default) for no input, the path of
  an existing file to read, or `"|"` to write `input` to the command.
  Other values abort with class `condathis_invalid_stdin`.

- input:

  Character or raw vector written to the standard input of the command.
  `condathis` joins the elements of a character vector with line feeds
  and adds none after the last one. Must be `NULL` (the default) unless
  `stdin = "|"`. Other values abort with class
  `condathis_invalid_input`. With `stdin = "|"`, `condathis` shows the
  output when the command ends, not while it runs, and shows no spinner.

- binary:

  Logical. Whether to return `stdout` and `stderr` as raw vectors
  instead of decoding them as UTF-8 text. Defaults to `FALSE`. A process
  has one encoding for both streams, so with `TRUE` both are raw, even
  if only one of them carries binary data. Check with
  [`is.raw()`](https://rdrr.io/r/base/raw.html) before treating either
  as text. `condathis` never shows raw streams on the console, whatever
  `verbose` is. Values other than `TRUE` and `FALSE` abort with class
  `condathis_invalid_binary`.

- supervise:

  Logical. Whether the `processx` supervisor watches the process: when
  the R session ends, even by a crash, the supervisor kills it. Defaults
  to `FALSE`.

- cleanup_tree:

  Logical. Whether to kill the process tree of the command, its child
  processes included, when the command finishes, times out, or is
  interrupted. Defaults to `FALSE`, so that a daemon that the command
  starts keeps running after the command exits. On Windows, a daemon
  that keeps the captured standard output or error of the command open
  ends when R has read that output. This is a limit of `processx` on
  Windows, whatever `cleanup_tree` is. Send the output to files
  (`stdout`, `stderr`) to keep such a daemon running.

- linux_pdeathsig:

  Logical. On Linux, whether the command gets `SIGTERM` when the R
  session ends, even by a crash. Ignored on other platforms. Defaults to
  `FALSE`.

- activate:

  Logical. Whether to run `cmd` with the activation of the backend.
  Defaults to `TRUE`: the backend activates the environment, with the
  `activate.d` scripts and `env_vars.d` files of its packages. An
  activation that fails is an error, as `error` describes. With `FALSE`,
  no backend code runs: `condathis` sets only `CONDA_PREFIX`,
  `CONDA_DEFAULT_ENV`, `CONDA_SHLVL` and `MAMBA_SHLVL` (both `1`), empty
  prompt modifiers, and the binary directories of the environment in
  front of `PATH` (see
  [condathis-options](https://luciorq.github.io/condathis/reference/condathis-options.md)).
  In both modes, the command gets the variables that `condathis` sets in
  every process it starts. Values other than `TRUE` and `FALSE` abort
  with class `condathis_invalid_activate`.

- timeout:

  Number of seconds the call may take, the activation of the environment
  included (see Details in
  [`run()`](https://luciorq.github.io/condathis/reference/run.md)).
  Defaults to `Inf` (no limit). `condathis` lowers a finite value above
  2147483 (about 24.8 days) to that value. When the time is up,
  `condathis` kills the command, or does not start it when the
  activation took all the time. `error = "cancel"` then aborts, and
  `error = "continue"` returns a result with `status = -9` and
  `timeout = TRUE`. Values that are not a single, non-negative number
  abort with class `condathis_invalid_timeout`.

## Value

A `condathis_result` object, invisibly, as for
[`run()`](https://luciorq.github.io/condathis/reference/run.md).

## Details

In `condathis` 0.1.4, `run_bin()` ran a program of the environment
without its activation. It now activates the environment, as
[`run()`](https://luciorq.github.io/condathis/reference/run.md) does.
`activate = FALSE` gives the fixed activation of
[`run()`](https://luciorq.github.io/condathis/reference/run.md).

## See also

[`run()`](https://luciorq.github.io/condathis/reference/run.md).

Other commands:
[`parse_output()`](https://luciorq.github.io/condathis/reference/parse_output.md),
[`run()`](https://luciorq.github.io/condathis/reference/run.md),
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md),
[`run_step()`](https://luciorq.github.io/condathis/reference/run_step.md)

## Examples

``` r
if (FALSE) { # \dontrun{
condathis::with_sandbox_dir({
  channel <- system.file(
    "extdata", "polyglot-channel",
    package = "condathis"
  )
  condathis::create_env(
    "polyglot",
    env_name = "polyglot-env",
    channels = channel
  )
  # The same as condathis::run("polyglot", env_name = "polyglot-env")
  condathis::run_bin("polyglot", env_name = "polyglot-env")
})
} # }
```
