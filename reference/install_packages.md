# Install Packages in a Existing Conda Environment

Install Packages in a Existing Conda Environment

## Usage

``` r
install_packages(
  packages,
  env_name = "condathis-env",
  channels = c("conda-forge"),
  channel_priority = c("disabled", "strict", "flexible"),
  additional_channels = NULL,
  verbose = c("output", "silent", "cmd", "spinner", "full")
)
```

## Arguments

- packages:

  Character vector with the names of the packages and version strings if
  necessary.

- env_name:

  Name of the Conda environment where the packages are going to be
  installed. Defaults to 'condathis-env'.

- channels:

  Character vector. Names of the channels to be included. By default
  'c("conda-forge", "bioconda")' are used for solving dependencies.

- channel_priority:

  Character. Set the channel priority. Can be `"disabled"`, `"strict"`,
  or `"flexible"`. Defaults to `"disabled"`.

  Note: This is different from the default Conda behavior. Where
  `"flexible"` is the default.

  - **"disabled"**: The package dependency solver will search for
    packages across all channels without prioritizing any channel.

  - **"strict"**: Packages and dependencies for those packages will be
    installed from the highest priority channel that contains them and
    fail if dependencies cannot be satisfied from that channel.

  - **"flexible"**: The solver will prefer packages from higher priority
    channels but will fall back to lower priority channels if necessary.

- additional_channels:

  Character. Additional Channels to be added to the default ones.

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
    packages = "bioconda::fastqc",
    env_name = "fastqc-env"
  )
  # Install the package `python` in the `fastqc-env` environment.
  # NOTE: It is not recommended to install multiple packages in the same
  # environment, as it defeats the purpose of isolation provided by
  # separate environments.
  condathis::install_packages(packages = "python", env_name = "fastqc-env")
})
} # }
```
