# Create a Conda Environment

Create Conda Environment with specific packages installed to be used by
[`run()`](https://luciorq.github.io/condathis/reference/run.md).

## Usage

``` r
create_env(
  packages = NULL,
  env_file = NULL,
  env_name = "condathis-env",
  channels = c("bioconda", "conda-forge"),
  method = c("native", "auto"),
  additional_channels = NULL,
  platform = NULL,
  verbose = c("output", "silent", "cmd", "spinner", "full"),
  overwrite = FALSE
)
```

## Arguments

- packages:

  Character vector. Names of the packages, and version strings if
  necessary, e.g. 'python=3.13'. The use of the `packages` argument
  assumes that env_file is not used.

- env_file:

  Character. Path to the YAML file with Conda Environment description.
  If this argument is used, the `packages` argument should not be
  included in the command.

- env_name:

  Character. Name of the Conda environment where the packages are going
  to be installed. Defaults to 'condathis-env'.

- channels:

  Character vector. Names of the channels to be included. By default
  'c("bioconda", "conda-forge")' are used for solving dependencies.

- method:

  Character. Backend method to run `micromamba`, the default is "auto"
  running "native" with the `micromamba` binaries installed by
  `condathis`. This argument is **soft deprecated** as changing it don't
  really do anything.

- additional_channels:

  Character. Additional Channels to be added to the default ones.

- platform:

  Character. Platform to search for `packages`. Defaults to `NULL` which
  will use the current platform. E.g. "linux-64", "linux-32", "osx-64",
  "win-64", "win-32", "noarch". Note: on Apple Silicon MacOS will use
  "osx-64" instead of "osx-arm64" if Rosetta 2 is available and any of
  the `packages` is not available for "osx-arm64".

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

- overwrite:

  Logical. Should environment always be overwritten? Defaults to
  `FALSE`.

## Value

An object of class `list` representing the result of the command
execution. Contains information about the standard output, standard
error, and exit status of the command.

## Examples

``` r
if (FALSE) { # \dontrun{
condathis::with_sandbox_dir({
  # Create a Conda environment and install the CLI `fastqc` in it.
  condathis::create_env(
    packages = "fastqc==0.12.1",
    env_name = "fastqc-env",
    verbose = "output"
  )
  #> ! Environment fastqc-env succesfully created.
})
} # }
```
