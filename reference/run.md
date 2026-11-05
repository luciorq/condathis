# Run a command in a Conda environment

Runs a command line tool with a Conda environment activated. The command
gets the environment variables that the activation sets, including those
of the `activate.d` scripts of its packages. To run a program without
activation, use
[`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
with `activate = FALSE`.

## Usage

``` r
run(
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
  timeout = Inf
)
```

## Arguments

- cmd:

  Character string, the command to run: a single, non-empty string.
  Other values abort with class `condathis_invalid_cmd`. Pass the
  arguments of the command in `...`.

- ...:

  Arguments of the command, unnamed: character, numeric or logical
  vectors, each element one argument. `run()` drops `NULL` values. It
  writes numbers in full, never in scientific notation: `100000` is
  passed as `"100000"`. `NA`, named arguments, and values that are not
  atomic vectors (for example lists) abort with class
  `condathis_run_invalid_args`.

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
  value with class `condathis_env_path_read_only`. `run()`,
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

- stdout:

  Standard output target: `"|"` (the default) captures it in the result,
  a file path writes it to that file, and `NULL` discards it.

- stderr:

  Standard error target: `"|"` (the default) captures it in the result,
  a file path writes it to that file, and `NULL` discards it.

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

- timeout:

  Number of seconds the call may take, the activation of the environment
  included (see Details in `run()`). Defaults to `Inf` (no limit).
  `condathis` lowers a finite value above 2147483 (about 24.8 days) to
  that value. When the time is up, `condathis` kills the command, or
  does not start it when the activation took all the time.
  `error = "cancel"` then aborts, and `error = "continue"` returns a
  result with `status = -9` and `timeout = TRUE`. Values that are not a
  single, non-negative number abort with class
  `condathis_invalid_timeout`.

## Value

A `condathis_result` object, invisibly: a classed list with `status`,
`stdout`, `stderr`, `timeout`, `pid`, `cmd` and `env_name`, which prints
as a short summary. `status` is the exit status of the command. On Linux
and macOS, a command that a signal ends has status 128 plus the signal
number, as in a shell (143 for `SIGTERM`). `stdout` and `stderr` are
`NA` when that stream was not captured (a target other than `"|"`).
`pid` is the process ID of the command with `stdin = "|"`, and `NA`
otherwise. `cmd` is your command line, each part quoted, with the
credentials of URLs masked (see `verbose`). `env_name` is the
environment name, or the directory of an
[`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md).

## Details

`run()` activates the environment and starts the command itself. The
micromamba backend records the activation of an environment the first
time a command runs in it. That first command takes longer, and
`timeout` includes the activation. The backend reuses the activation
until the environment changes (its packages, `activate.d` scripts or
`env_vars.d` files). A change in the environment variables of the R
session also ends the reuse.

Arguments in `...` reach the command exactly as given on every platform.
No shell is involved. Characters such as `>`, `|`, `&`, `%`, `$`, `*`
and quotes have no special meaning. Shell builtins (for example `echo`
or `dir` on Windows) are not available as commands. To use shell
features, run a shell explicitly, as in `run("bash", "-c", "...")`. To
connect commands with pipes, use
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md).
One exception applies on Windows. Windows starts batch files (`.bat`,
`.cmd`) through `cmd.exe`, which parses their arguments again.

When `env_name` is the default `"condathis-env"` and that environment
does not exist, `run()` creates it, empty, with the backend that
`method` selects. `run()` never creates any other missing environment.
The call fails, as `error` describes.

The errors of a failed or timed-out command carry the fields `status`,
`stdout`, `stderr` and `timeout`. A handler does not need to parse the
message, as in
`tryCatch(run("false"), condathis_status_error = function(e) e$status)`.

## See also

[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
to create an environment,
[`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md)
for an environment created outside `condathis`, and
[condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)
for the condition classes.

Other commands:
[`parse_output()`](https://luciorq.github.io/condathis/reference/parse_output.md),
[`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md),
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md),
[`run_step()`](https://luciorq.github.io/condathis/reference/run_step.md)

## Examples

``` r
if (FALSE) { # \dontrun{
condathis::with_sandbox_dir({
  # A local channel shipped with condathis, with `polyglot`: a
  # dependency-free script that runs on Linux, macOS and Windows.
  channel <- system.file(
    "extdata", "polyglot-channel",
    package = "condathis"
  )
  create_env("polyglot", env_name = "polyglot-env", channels = channel)

  # Run its command, on any platform
  polyglot_res <- run(
    "polyglot",
    env_name = "polyglot-env",
    verbose = "silent"
  )
  print(parse_output(polyglot_res)[1])
  #> [1] "System detected: Linux/Unix"

  # `pigz` (conda-forge) has builds for Linux, macOS and Windows
  create_env("conda-forge::pigz", env_name = "pigz-env")

  # Decompress a FASTQ file shipped with condathis
  fastq_file <- fs::path_package(
    "condathis", "extdata", "sample1_L001_R1_001.fastq.gz"
  )
  pigz_res <- run(
    "pigz", "--decompress", "--stdout", fastq_file,
    env_name = "pigz-env",
    verbose = "silent"
  )
  print(parse_output(pigz_res)[1])
  #> [1] "@read1/gi|424037187|ref|NR_073460.1| Homo sapiens ribosome ..."
})
} # }
```
