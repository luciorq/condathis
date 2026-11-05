# Run a command inside a Conda environment

Executes a command in a Conda environment managed by `condathis`. The
command is run through `micromamba run` using the internal Conda root.

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

  Character string with the command to execute.

- ...:

  Additional unnamed command arguments passed to `cmd`.

- env_name:

  Character string with the target environment name. Defaults to
  `"condathis-env"`. If the default environment does not exist, it is
  created automatically. A missing *custom* `env_name` is never created
  automatically - it fails instead, per `error` below.

- method:

  Character string naming the backend to use. Defaults to `"auto"`
  (resolve automatically: the environment's own owning backend if it
  already exists). `"micromamba"` is the only backend registered today -
  and the only one `run()` can actually execute through so far.
  `"native"` is a deprecated alias for `"micromamba"` (warns once per
  session).

- verbose:

  Character string controlling console output. Supported values are
  `"output"`, `"silent"`, `"cmd"`, `"spinner"`, and `"full"`. Defaults
  to `"output"`. Logical values are accepted for backward compatibility:
  `TRUE` maps to `"output"` and `FALSE` maps to `"silent"`.

- error:

  Character string that controls error behavior. Supported values are
  `"cancel"` and `"continue"`. Defaults to `"cancel"`. Also controls
  what happens when `env_name` is a non-default environment that does
  not exist: `"cancel"` aborts with class `condathis_run_env_not_found`;
  `"continue"` returns a result with `status = 127` instead of running
  anything.

- stdout:

  Standard output target. Defaults to `"|"` (capture stdout in the
  returned object). Provide a file path to redirect stdout to a file.

- stderr:

  Standard error target. Defaults to `"|"` (capture stderr in the
  returned object). Provide a file path to redirect stderr to a file.

- stdin:

  Standard input source. Defaults to `NULL` (no stdin stream). Provide a
  file path to use file contents as stdin, or `"|"` to write `input` to
  the process.

- input:

  Character or raw vector written to the process's standard input when
  `stdin = "|"`. Defaults to `NULL`. Ignored (and must not be set) when
  `stdin` is not `"|"`. Note: live (real-time) stdout/stderr streaming
  and the spinner are not available when `input` triggers the
  writable-stdin code path; `timeout` still works.

- binary:

  Logical. Whether to capture stdout/stderr as raw vectors instead of
  decoding them as UTF-8 text. Defaults to `FALSE`. Since a process's
  stdout and stderr share a single encoding, both streams are returned
  raw when `TRUE`, even if only one of them actually carries binary
  data - check with [`is.raw()`](https://rdrr.io/r/base/raw.html) before
  treating either as text. Binary streams are never live-echoed to the
  console, regardless of `verbose`.

- supervise:

  Logical. Whether the process should be supervised by the `processx`
  supervisor for crash-safe cleanup - the process (and its descendants,
  with `cleanup_tree = TRUE`) is killed if the R session crashes.
  Defaults to `FALSE`.

- cleanup_tree:

  Logical. Whether to clean up the child process tree (not just the
  direct child) on crash/interrupt. Defaults to `FALSE`.

- linux_pdeathsig:

  Logical. On Linux, whether to send `SIGKILL` to the child process if
  the parent R process dies. Has no effect on other platforms. Defaults
  to `FALSE`.

- timeout:

  Numeric. Maximum number of seconds to let the command run before it's
  killed. Defaults to `Inf` (no limit, the previous behavior). On
  expiry, the process is killed, `timeout` is `TRUE` in the returned
  result, and `error = "cancel"` aborts with class
  `condathis_run_timeout_error` (`error = "continue"` returns normally
  with `status = -9`).

## Value

A `condathis_result` S3 object (a classed list, still usable as a plain
list) with `status`, `stdout`, `stderr`, `timeout`, `pid`, `cmd`, and
`env_name`.

## Details

This function is the main execution entry point in `condathis`. Use it
to run CLI tools with reproducible dependencies isolated in Conda
environments.

## See also

[`install_micromamba`](https://luciorq.github.io/condathis/reference/install_micromamba.md),
[`create_env`](https://luciorq.github.io/condathis/reference/create_env.md)

## Examples

``` r
if (FALSE) { # \dontrun{
condathis::with_sandbox_dir({
  ## Create env
  ## `samtools` (bioconda) has no Windows build on any channel, so this
  ## specific example only runs on Linux/macOS - unlike most `condathis`
  ## examples, there's no portable substitute that still demonstrates a
  ## real bioinformatics CLI operating on the packaged BAM file below.
  create_env("bioconda::samtools", env_name = "samtools-env")

  ## Run a command in a specific Conda environment
  samtools_res <- run(
    "samtools", "view",
    fs::path_package("condathis", "extdata", "example.bam"),
    env_name = "samtools-env",
    verbose = "silent"
  )
  parse_output(samtools_res)[1]
  #> [1] "SOLEXA-1GA-1_6_FC20ET7:6:92:473:531\t0\tchr1\t10156..."
})
} # }
```
