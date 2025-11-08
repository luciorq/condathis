# Remove a Conda Environment

Remove a Conda environment previously created by
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md).

## Usage

``` r
remove_env(
  env_name = "condathis-env",
  verbose = c("silent", "cmd", "output", "spinner", "full")
)
```

## Arguments

- env_name:

  Character. Name of the Conda environment where the packages are going
  to be installed. Defaults to 'condathis-env'.

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

## Value

An object of class `list` representing the result of the command
execution. Contains information about the standard output, standard
error, and exit status of the command.

## Examples

``` r
if (FALSE) { # \dontrun{
condathis::with_sandbox_dir({
  condathis::create_env(
    packages = "fastqc",
    env_name = "fastqc-env"
  )
  condathis::remove_env(env_name = "fastqc-env")
})
} # }
```
