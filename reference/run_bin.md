# Run a binary without environment activation

Executes a binary using files from a target Conda environment, but
without running environment activation scripts. This is a lower-level
execution mode than
[`run()`](https://luciorq.github.io/condathis/reference/run.md).

## Usage

``` r
run_bin(
  cmd,
  ...,
  env_name = "condathis-env",
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

  Character string with the command to execute.

- ...:

  Additional unnamed command arguments passed to `cmd`.

- env_name:

  Character string with the target environment name. Defaults to
  `"condathis-env"`.

- verbose:

  Character string controlling console output. Supported values are
  `"output"`, `"silent"`, `"cmd"`, `"spinner"`, and `"full"`. Defaults
  to `"output"`.

- error:

  Character string that controls error behavior. Supported values are
  `"cancel"` and `"continue"`. Defaults to `"cancel"`.

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
  raw when `TRUE`, even if only one of them actually carries binary data
  — check with [`is.raw()`](https://rdrr.io/r/base/raw.html) before
  treating either as text. Binary streams are never live-echoed to the
  console, regardless of `verbose`.

- supervise:

  Logical. Whether the process should be supervised by the `processx`
  supervisor for crash-safe cleanup. Defaults to `FALSE`.

- cleanup_tree:

  Logical. Whether to clean up the child process tree on
  crash/interrupt. Defaults to `FALSE`.

- linux_pdeathsig:

  Logical. On Linux, whether to send `SIGKILL` to the child process if
  the parent R process dies. Has no effect on other platforms. Defaults
  to `FALSE`.

- activate:

  Logical. Whether to resolve and apply `env_name`'s real
  `micromamba run` activation (via
  `get_micromamba_activation_envvars()`, including any package
  `activate.d` hook scripts) as an environment overlay before running
  `cmd`. Defaults to `TRUE`. Silently skipped (`cmd` still runs,
  unactivated) when `env_name` does not exist, so
  `error = "continue"`-style fallback to a binary outside any managed
  environment keeps working. Set to `FALSE` to restore the original,
  activation-free `run_bin()` behavior — `cmd` still resolves against
  `env_name`'s `bin/` directory (falling back to `PATH`), but the child
  process otherwise inherits the caller's environment unmodified. This
  is the mechanism that makes `run_bin(activate = TRUE)` behave like
  [`run()`](https://luciorq.github.io/condathis/reference/run.md), minus
  the different binary-resolution strategy:
  [`run()`](https://luciorq.github.io/condathis/reference/run.md)
  resolves `cmd` via the activated `PATH` inside a `micromamba run`
  wrapper, while `run_bin()` always resolves `cmd` itself beforehand.

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

## Examples

``` r
if (FALSE) { # \dontrun{
condathis::with_sandbox_dir({
  # Create an environment with 'python' and 'ripgrep'. `coreutils`
  # (and other GNU tools like `grep`) aren't available for Windows on
  # conda-forge, so `ripgrep` is used here instead of e.g. `ls`/`grep` —
  # a single package name that installs and runs the same way on every
  # platform `condathis` supports.
  condathis::create_env(
    c("conda-forge::python", "conda-forge::ripgrep"),
    env_name = "my-env"
  )

  # Run 'python' with a script in 'my-env' environment
  condathis::run_bin(
    "python", "-c", "import sys; print(sys.version)",
    env_name = "my-env"
  )

  # Run the 'rg' (ripgrep) binary with additional arguments
  condathis::run_bin("rg", "--version", env_name = "my-env")
})
} # }
```
