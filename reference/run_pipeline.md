# Run a pipeline of commands connected with pipes

Runs commands connected with pipes, as `cmd1 | cmd2` in a shell. The
standard output of each command is the standard input of the next one.
The data flows between the processes through operating system pipes, not
through R. R gets the standard output of the last command and the
standard error of every command.

Describe each command with
[`run_step()`](https://luciorq.github.io/condathis/reference/run_step.md),
which takes the same command, arguments and `env_name` as
[`run()`](https://luciorq.github.io/condathis/reference/run.md). Each
command can run in a **different** Conda environment. Commands that do
not set an environment use the `env_name` of `run_pipeline()`.

## Usage

``` r
run_pipeline(
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
  supervise = TRUE,
  cleanup_tree = TRUE,
  linux_pdeathsig = FALSE,
  activate = TRUE,
  timeout = Inf
)
```

## Arguments

- ...:

  Two or more pipeline steps, built with
  [`run_step()`](https://luciorq.github.io/condathis/reference/run_step.md),
  in pipeline order. Splice in a list of steps, built with
  [`list()`](https://rdrr.io/r/base/list.html) or
  [`c()`](https://luciorq.github.io/condathis/reference/c.condathis_run_step.md),
  with `!!!`, as in `run_pipeline(!!!steps)`.
  [`c()`](https://rdrr.io/r/base/c.html) on steps gives a list of steps
  that later [`c()`](https://rdrr.io/r/base/c.html) calls extend, as in
  `c(c(step_1, step_2), step_3)`. To add a step to a plain list or to
  `NULL`, wrap it in [`list()`](https://rdrr.io/r/base/list.html), as in
  `c(steps, list(step))`. [`c()`](https://rdrr.io/r/base/c.html) with a
  plain list or `NULL` first splits a step into its fields. Any other
  value aborts with class `condathis_run_pipeline_invalid_step`, so name
  every option below in full. Fewer than two steps abort with class
  `condathis_run_pipeline_too_few_commands`.

- env_name:

  Character string with the default environment of the steps that do not
  set their own, or an environment given by
  [`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md).
  Defaults to `"condathis-env"`, which `run_pipeline()` creates (empty,
  with the backend that `method` selects) when it does not exist.
  `run_pipeline()` never creates any other missing environment and fails
  per `error`. A name must follow the rules of the `env_name` argument
  of [`run()`](https://luciorq.github.io/condathis/reference/run.md).
  Invalid values abort with class `condathis_invalid_env_name`.

- method:

  Character string naming the default backend of the steps that do not
  set their own `method` (see
  [`run_step()`](https://luciorq.github.io/condathis/reference/run_step.md)).
  `"auto"` (the default) uses the backend that owns each environment,
  and otherwise the first available backend in the order of the option
  `condathis.backend_priority` (see
  [condathis-options](https://luciorq.github.io/condathis/reference/condathis-options.md)).
  Any name from
  [`list_registered_backend_names()`](https://luciorq.github.io/condathis/reference/list_registered_backend_names.md)
  selects that backend. `"micromamba"` is built in. The name of a
  backend whose package condathis knows also selects it, such as
  `"rattler"` of the `rattlerthis` package. condathis loads that
  package. `"native"` is a deprecated alias for `"micromamba"` (it warns
  once per session). If you name a backend other than the owner of an
  environment, condathis warns and uses the owner. Steps that share an
  environment must agree on the backend. The classes:

  - `condathis_backend_not_installed`: the package of the named backend
    is not installed.

  - `condathis_backend_mismatch_warning` (a warning): the named backend
    does not own the environment.

  - `condathis_backend_ambiguous_env`: several backends have an
    environment of that name, and `method` names none of them. With
    `error = "continue"`, its steps get status 127.

  - `condathis_run_pipeline_conflicting_method`: steps that share an
    environment do not agree on the backend.

  - `condathis_invalid_method`: an invalid value.

- verbose:

  Character string that controls the console output. One of `"output"`,
  `"silent"`, `"cmd"`, `"spinner"` and `"full"`. Usage shows the
  default. `"output"` prints, while the pipeline runs, what it captures:
  the last command's standard output and every command's standard error,
  when their target is `"|"`. `"cmd"` prints the whole pipeline first.
  `"full"` does both. `"spinner"` shows only a spinner, and `"silent"`
  shows nothing. `TRUE` means `"output"` and `FALSE` means `"silent"`.
  Every level except `"silent"` shows a spinner in interactive sessions.
  It also shows these messages and this warning (see
  [condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)):

  - `condathis_micromamba_downloading` (a message): no usable
    `micromamba` was found, so it is downloaded.

  - `condathis_env_lock_waiting` and `condathis_cache_lock_waiting`
    (messages): the call waits for another R session.

  - `condathis_install_micromamba_checksum_unavailable` (a warning): the
    checksum of the downloaded `micromamba` could not be checked.

  Invalid values abort with class `condathis_invalid_verbose`.

- error:

  Character string that controls what happens when a command fails. With
  `"cancel"` (the default), `run_pipeline()` aborts with these classes:

  - `condathis_run_pipeline_status_error` (also
    `condathis_status_error`): a command exits with a non-zero status. A
    broken pipe can end a command that is not the last one: that does
    not count (see *Broken pipes*).

  - `condathis_run_pipeline_timeout_error` (also
    `condathis_timeout_error`): a timeout.

  - `condathis_run_pipeline_env_not_found` (also
    `condathis_env_not_found`): a step environment does not exist. For
    an
    [`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md),
    the error also has `condathis_env_path_not_found` or
    `condathis_env_path_not_conda_env`.

  - `condathis_backend_ambiguous_env`: a step environment is found under
    several backends (see `method`).

  - `condathis_run_pipeline_resolve_failed` (also
    `condathis_backend_error`): the backend fails to resolve a command,
    for example because an `activate.d` script of the environment fails.
    The error keeps the condathis classes of the backend's error, for
    example `condathis_micromamba_status_error`, and has that error as
    its parent.

  - `condathis_backend_resolve_run_invalid`: a backend package gives an
    invalid command description (a bug in that package).

  The status and timeout errors carry the fields `status`, `stdout`,
  `stderr` and `timeout`, as the errors of
  [`run()`](https://luciorq.github.io/condathis/reference/run.md) do.
  They also carry `result` (the `condathis_pipeline` object that
  `error = "continue"` returns) and `statuses`. With `"continue"`,
  `run_pipeline()` returns the result instead. Every step in an
  environment that does not exist or is found under several backends
  gets status 127, with the reason in its `stderr`. So does every
  command that cannot be resolved or started. The other steps still run.
  A timeout gives status -9. Invalid values abort with class
  `condathis_invalid_error`. See
  [condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)
  for all classes.

- stdout:

  Standard output target of the **last** command: `"|"` (the default)
  captures it in the result, a file path writes it to that file, `""`
  sends it to the standard output of the R process, and `NULL` discards
  it. The standard output of every other command goes to the next
  command.

- stderr:

  Standard error target for **all** processes. `"|"` (the default)
  captures each command's standard error in its result. A file path
  writes them all to that file, in command order once the pipeline
  finishes. `NULL` discards them. `""` sends them to the standard error
  of the R process. `"2>&1"` sends the standard error of each command to
  its standard output: to the next command, and for the last command to
  the `stdout` target. The `stderr` argument of
  [`run_step()`](https://luciorq.github.io/condathis/reference/run_step.md)
  replaces it for one command.

- stdin:

  Standard input source of the **first** command: `NULL` (the default)
  for no input, the path of an existing file to read, or `"|"` to write
  `input` to it.

- input:

  Character or raw vector written to the standard input of the first
  command, as in
  [`run()`](https://luciorq.github.io/condathis/reference/run.md). Must
  be `NULL` (the default) unless `stdin = "|"`. Other values abort with
  class `condathis_invalid_input`.

- binary:

  Logical. Whether to return raw vectors, not UTF-8 text, for the
  standard error of every command and the standard output of the last
  one. Defaults to `FALSE`. It applies to the whole pipeline. There is
  no per-command setting.

- supervise:

  Logical. Whether the `processx` supervisor watches each process: when
  the R session ends, even by a crash, the supervisor kills it. Defaults
  to `TRUE`, unlike in
  [`run()`](https://luciorq.github.io/condathis/reference/run.md) and
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md),
  since a pipeline starts several connected processes. Ignored on
  Windows, where supervised pipelines hang.

- cleanup_tree:

  Logical. Whether to kill the process tree of each command, processes
  that it started in the background included. R kills the tree when it
  frees the process object of the command, at a garbage collection after
  the pipeline finishes. Defaults to `TRUE`, so that no command outlives
  the pipeline, unlike in
  [`run()`](https://luciorq.github.io/condathis/reference/run.md) and
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md),
  where a daemon that a command starts keeps running.

- linux_pdeathsig:

  Logical. On Linux, whether each command gets `SIGTERM` when the R
  session ends, even by a crash. Ignored on other platforms. Defaults to
  `FALSE`.

- activate:

  Logical. `TRUE` (the default) runs each command with the activation of
  its environment, as
  [`run()`](https://luciorq.github.io/condathis/reference/run.md) does.
  `FALSE` sets a fixed set of variables instead, without `activate.d`
  scripts (see
  [condathis-options](https://luciorq.github.io/condathis/reference/condathis-options.md)).
  Each command runs in the working directory of the R session, unless
  the activation of a backend gives another one.

- timeout:

  Number of seconds the whole pipeline may take, the activations of the
  environments included: one deadline for all commands, not one per
  command. Defaults to `Inf` (no limit). `run_pipeline()` lowers a
  finite value above 2147483 (about 24.8 days) to that value. When the
  time is up, `run_pipeline()` kills every command still running (status
  -9 and `timeout = TRUE` in its result). It does not start a command
  whose activation took the rest of the time, and counts it as killed.
  `error = "cancel"` then aborts with class
  `condathis_run_pipeline_timeout_error`, and `error = "continue"`
  returns the result, with `timeout = TRUE`. Values that are not a
  single, non-negative number abort with class
  `condathis_invalid_timeout`.

## Value

A `condathis_pipeline` object, invisibly, which prints as a short
summary and which
[`parse_output()`](https://luciorq.github.io/condathis/reference/parse_output.md)
reads. It is a classed list with:

- status:

  Integer. The status of the pipeline: -9 when it timed out, otherwise
  the status of the first command that failed, or 0. A broken pipe can
  end a command that is not the last one: that does not count (see
  *Broken pipes*).

- statuses:

  Integer vector, the exit status of each command. A command that a
  signal ends has the negative signal number, such as -13 for `SIGPIPE`.

- processes:

  List of `condathis_result` objects, one per command, with the fields
  of a [`run()`](https://luciorq.github.io/condathis/reference/run.md)
  result: `stdout` is `NA` for every command but the last, `env_name` is
  the environment name or the directory of an
  [`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md),
  and `timeout` is `TRUE` for the commands that the timeout killed.

- timeout:

  Logical. Whether the pipeline timed out.

- cmd:

  Character string. The command lines of the commands, each part quoted,
  joined with `" | "`.

## Broken pipes

A command that is not the last one ends as it would in a shell when it
writes again after the next command has exited. On Linux and macOS,
`SIGPIPE` kills it. Windows has no such signal. There, `run_pipeline()`
reads the pipe in place of the command that exited. It kills the writer
when more output comes after the pipe was empty for about one second in
total. It also kills the writer when more than 64 KiB comes, which is
what a Linux pipe holds. Output that was already in the pipe does not
count. Either way, the status of the writer is -13, and that is not a
failure. It does not make `error = "cancel"` abort, and it is not the
`status` of the result. So `seq 1 1000000 | head -n 1` has status 0.
Programs that handle `SIGPIPE` themselves, such as R and Python, exit
with their own status (R with 1, Python usually with 120), which counts
as a failure. A command that writes nothing more keeps running, on every
platform, and keeps its own status. On Windows, the reader that takes
the place of the exited command is a small `Rscript` process. When it
cannot start, the writer gets one second to exit on its own, and
`run_pipeline()` then kills it.

## See also

[`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md)
for an environment created outside `condathis`, and
[condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)
for the condition classes.

Other commands:
[`parse_output()`](https://luciorq.github.io/condathis/reference/parse_output.md),
[`run()`](https://luciorq.github.io/condathis/reference/run.md),
[`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md),
[`run_step()`](https://luciorq.github.io/condathis/reference/run_step.md)

## Examples

``` r
if (FALSE) { # \dontrun{
condathis::with_sandbox_dir({
  # `pigz` and `ripgrep` (the `rg` binary) come from conda-forge, which
  # builds both for Linux, macOS and Windows. `rg` is used here instead
  # of GNU `grep`, which conda-forge has for Windows only as an MSYS2
  # package (with the "m2-" prefix).
  create_env("conda-forge::pigz", env_name = "pigz-env")
  create_env("conda-forge::ripgrep", env_name = "ripgrep-env")

  # Pipeline with per-command environments: count the reads of a FASTQ
  # file shipped with condathis. In this file, the header line of each
  # read starts with "@read".
  fastq_file <- fs::path_package(
    "condathis", "extdata", "sample1_L001_R1_001.fastq.gz"
  )
  res <- run_pipeline(
    run_step(
      "pigz", "--decompress", "--stdout", fastq_file,
      env_name = "pigz-env"
    ),
    run_step("rg", "--count", "^@read", env_name = "ripgrep-env"),
    verbose = "silent"
  )
  print(parse_output(res))
  #> [1] "1086"

  # Steps are values: build a list of them, then splice it in with `!!!`
  steps <- list(
    run_step("rg", "--version", env_name = "ripgrep-env"),
    run_step("rg", "ripgrep", env_name = "ripgrep-env")
  )
  print(parse_output(run_pipeline(!!!steps, verbose = "silent")))
  #> [1] "ripgrep 15.2.0 (rev 78115297cd)"
})
} # }
```
