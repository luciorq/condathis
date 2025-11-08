# Run a Binary from a Conda Environment Without Environment Activation

Executes a binary command from a specified Conda environment without
activating the environment or using its environment variables. This
function temporarily clears Conda and Mamba-related environment
variables to prevent interference, ensuring that the command runs in a
clean environment. Usually this is not what the user wants as this mode
of execution does not load environment variables and scripts defined in
the environment `activate.d`, check
[`run()`](https://luciorq.github.io/condathis/reference/run.md) for the
stable function to use.

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

  Character. The main command to be executed in the Conda environment.

- ...:

  Additional arguments to be passed to the command. These arguments will
  be passed directly to the command executed in the Conda environment.
  File paths should not contain special characters or spaces.

- env_name:

  Character. The name of the Conda environment where the tool will be
  run. Defaults to `"condathis-env"`. If the specified environment does
  not exist, it will be created automatically using
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md).

- verbose:

  Character string specifying the verbosity level of the function's
  output. Acceptable values are:

  - **"output"**: Print the standard output and error from the
    command-line tool to the screen. Note that the order of the standard
    output and error lines may not be correct, as standard output is
    typically buffered.

  - **"silent"**: Suppress all output from internal command-line tools.
    Equivalent to `FALSE`.

  - **"cmd"**: Print the internal command(s) passed to the command-line
    tool. If the standard output and/or error is redirected to a file or
    they are ignored, they will not be echoed. Equivalent to `TRUE`.

  - **"full"**: Print both the internal command(s) (`"cmd"`) and their
    standard output and error (`"output"`).

  - Logical values `FALSE` and `TRUE` are also accepted for backward
    compatibility but are *soft-deprecated*. Please use `"silent"` or
    `"output"` instead.

- error:

  Character string. How to handle errors. Options are `"cancel"` or
  `"continue"`. Defaults to `"cancel"`.

- stdout:

  Default: "\|" keep stdout to the R object returned by
  [`run()`](https://luciorq.github.io/condathis/reference/run.md). A
  character string can be used to define a file path to be used as
  standard output. e.g: "output.txt".

- stderr:

  Default: "\|" keep stderr to the R object returned by
  [`run()`](https://luciorq.github.io/condathis/reference/run.md). A
  character string can be used to define a file path to be used as
  standard error. e.g: "error.txt".

- stdin:

  Default: `NULL` (no `stdin` stream). A character string can be used to
  define a file path to be used as standard input. e.g: "input.txt".

## Value

An object of class `list` representing the result of the command
execution. Contains information about the standard output, standard
error, and exit status of the command.

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
