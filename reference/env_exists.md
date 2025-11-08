# Check If Environment Already exists

This function checks whether a specified Conda environment already
exists in the available environments. It returns `TRUE` if the
environment exists and `FALSE` otherwise.

## Usage

``` r
env_exists(env_name, verbose = "silent")
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

Boolean. `TRUE` if the environment exists and `FALSE` otherwise.

## Examples

``` r
if (FALSE) { # \dontrun{
condathis::with_sandbox_dir({
  # Create the environment
  condathis::create_env(
    packages = "fastqc",
    env_name = "fastqc-env"
  )

  # Check if the environment exists
  condathis::env_exists("fastqc-env")
  #> [1] TRUE

  # Check for a non-existent environment
  condathis::env_exists("non-existent-env")
  #> [1] FALSE
})
} # }
```
