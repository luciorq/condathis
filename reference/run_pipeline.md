# Run a pipeline of commands connected with pipes

Executes a sequence of commands where each command's standard output is
piped as standard input to the next command (like a Unix shell
pipeline). Data flows directly between child processes via kernel-level
pipes, the parent R process only sees the output of the final command.

Each command in the pipeline can run in a **different** Conda
environment. Commands that do not specify an environment use the default
`env_name`.

## Usage

``` r
run_pipeline(
  cmds,
  stdout = "|",
  stderr = "|",
  stdin = NULL,
  input = NULL,
  binary = FALSE,
  error = c("cancel", "continue"),
  env_name = "condathis-env",
  supervise = TRUE,
  cleanup_tree = TRUE,
  linux_pdeathsig = FALSE,
  activate = TRUE,
  timeout = Inf
)
```

## Arguments

- cmds:

  A list of command specifications. Each element is either:

  - A character vector: `c("cmd", "arg1", ...)`. Runs in the default
    `env_name`.

  - A named list with `cmd` (character vector) and, optionally,
    `env_name` (character string) to specify a per-command environment,
    `stderr` to override the top-level `stderr` target for this command,
    and `stdout` to override the top-level `stdout` target, only allowed
    on the **last** command, since every other command's standard output
    is always piped to the next command.

- stdout:

  Standard output target for the **last** process. `"|"` (default)
  captures output in the result. Use a file path to redirect to a file,
  or `NULL` to discard. Can be overridden per-command for the last
  command only (see `cmds`).

- stderr:

  Standard error target for **all** processes. `"|"` (default) captures
  stderr per-process. Use a file path to redirect all stderr to a file,
  or `NULL` to discard. Can be overridden per-command (see `cmds`).

- stdin:

  Standard input source for the **first** process. `NULL` (default)
  discards input. Provide a file path to redirect file contents as
  stdin, or `"|"` to write `input` to the first process.

- input:

  Character or raw vector written to the first process's standard input
  when `stdin = "|"`. Defaults to `NULL`. Ignored (and must not be set)
  when `stdin` is not `"|"`.

- binary:

  Logical. Whether to capture every process's stderr, and the last
  process's stdout, as raw vectors instead of decoding them as UTF-8
  text. Defaults to `FALSE`. Applies to the whole pipeline; there is no
  per-command override.

- error:

  Character string controlling error behavior. Supported values are
  `"cancel"` and `"continue"`. Defaults to `"cancel"`.

- env_name:

  Character string with the default Conda environment name for commands
  that do not specify their own. Defaults to `"condathis-env"`.

- supervise:

  Logical. Whether each process should be supervised by the `processx`
  supervisor for crash-safe cleanup. Defaults to `TRUE` (unlike
  [`run()`](https://luciorq.github.io/condathis/reference/run.md)/[`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md),
  which default to `FALSE`) since a pipeline manages multiple
  concurrently connected processes.

- cleanup_tree:

  Logical. Whether to clean up each process's child tree on
  crash/interrupt. Defaults to `TRUE`.

- linux_pdeathsig:

  Logical. On Linux, whether to send `SIGKILL` to each child process if
  the parent R process dies. Has no effect on other platforms. Defaults
  to `FALSE`.

- activate:

  Logical. Whether to resolve each command's environment via
  `get_micromamba_activation_envvars()`, a real `micromamba run`
  activation (including package `activate.d` hook scripts), cached per
  `env_name`. Defaults to `TRUE`. Set to `FALSE` to use the original,
  faster hand-rolled activation (`get_activation_envvars()`: a fixed set
  of `CONDA_*`/`MAMBA_*` variables, no `activate.d` execution). The
  first pipeline call touching a given `env_name` with `activate = TRUE`
  pays for two extra subprocess spawns to resolve it; repeat calls for
  the same, unchanged environment hit the cache.

- timeout:

  Numeric. Maximum number of seconds to let the whole pipeline run
  before every process in it is killed. Defaults to `Inf` (no limit, the
  previous behavior). Applies to the pipeline as a whole (a single
  shared deadline across every command), not per-command. On expiry,
  every still-running process is killed (`status = -9`, matching
  [`processx::run()`](http://processx.r-lib.org/reference/run.md)'s own
  convention) and, gated by `error` exactly like a non-zero exit status,
  `error = "cancel"` aborts with class
  `condathis_pipeline_timeout_error` while `error = "continue"` returns
  normally with `result$timeout` (and each killed process's own
  `timeout`) set to `TRUE`.

## Value

A `condathis_pipeline` S3 object with per-process results:

- statuses:

  Integer vector of exit statuses, one per command.

- processes:

  List of per-process `condathis_result` objects (the same class
  [`run()`](https://luciorq.github.io/condathis/reference/run.md)/[`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
  return), each with `cmd`, `env_name`, `status`, `stdout` (`NA` for
  non-last processes), `stderr`, `pid`, and `timeout` (`TRUE` for
  whichever process(es) were still running when the pipeline's `timeout`
  expired, `FALSE` otherwise).
  [`format()`](https://rdrr.io/r/base/format.html)/[`print()`](https://rdrr.io/r/base/print.html)
  work directly on an individual `processes[[i]]`, not just on the whole
  pipeline result.

- timeout:

  Logical. Whether the pipeline timed out.

## See also

[`run`](https://luciorq.github.io/condathis/reference/run.md) for
single-command execution,
[`run_bin`](https://luciorq.github.io/condathis/reference/run_bin.md)
for direct binary execution.

## Examples

``` r
if (FALSE) { # \dontrun{
condathis::with_sandbox_dir({
  # `ripgrep` (the `rg` binary) is used here instead of GNU `grep`: a
  # single package name that installs and runs the same way on every
  # platform `condathis` supports, unlike `grep`, which on Windows only
  # exists under the "m2-" (MSYS2) prefix on conda-forge.
  #
  # `samtools` (bioconda) has no Windows build on any channel, so this
  # specific example only runs on Linux/macOS regardless — there's no
  # portable substitute that still demonstrates a real bioinformatics
  # CLI operating on the packaged BAM file below.
  create_env("bioconda::samtools", env_name = "samtools-env")
  create_env("conda-forge::ripgrep", env_name = "ripgrep-env")

  # Pipeline with per-command environments
  res <- run_pipeline(
    list(
      list(
        cmd = c(
          "samtools", "view", "-H",
          fs::path_package("condathis", "extdata", "example.bam")
        ),
        env_name = "samtools-env"
      ),
      list(
        cmd = c("rg", "@SQ"),
        env_name = "ripgrep-env"
      )
    )
  )
  print(res)
})
} # }
```
