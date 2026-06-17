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
  stdin = NULL
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
  file path to use file contents as stdin.

## Value

A process result list (from
[`processx::run()`](http://processx.r-lib.org/reference/run.md)) with
command output, error output, exit status, and timeout information.

## Examples

``` r
if (FALSE) { # \dontrun{
condathis::with_sandbox_dir({
  # Example assumes that 'my-env' exists and contains 'python'
  # Run 'python' with a script in 'my-env' environment
  condathis::run_bin(
    "python", "-c", "import sys; print(sys.version)",
    env_name = "my-env"
  )

  # Run 'ls' command with additional arguments
  condathis::run_bin("ls", "-la", env_name = "my-env")
})
} # }
```
