# List Packages Installed in a Conda Environment

This function retrieves a list of all packages installed in the
specified Conda environment. The result is returned as a tibble with
detailed information about each package, including its name, version,
and source details.

## Usage

``` r
list_packages(
  env_name = "condathis-env",
  verbose = c("output", "silent", "cmd", "spinner", "full")
)
```

## Arguments

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

## Value

A tibble containing all the packages installed in the specified
environment, with the following columns:

- base_url:

  The base URL of the package source.

- build_number:

  The build number of the package.

- build_string:

  The build string describing the package build details.

- channel:

  The channel from which the package was installed.

- dist_name:

  The distribution name of the package.

- name:

  The name of the package.

- platform:

  The platform for which the package is built.

- version:

  The version of the package.

## Examples

``` r
if (FALSE) { # \dontrun{
condathis::with_sandbox_dir({
  # Creates a Conda environment with the CLI `fastqc`
  condathis::create_env(
    packages = "fastqc",
    env_name = "fastqc-env"
  )
  # Lists the packages in env `fastqc-env`
  dat <- condathis::list_packages("fastqc-env")
  dim(dat)
  #> [1] 34  8
})
} # }
```
