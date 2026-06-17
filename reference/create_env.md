# Create a Conda environment

Creates a Conda environment managed by `condathis` and installs
dependencies from package specs or from an environment file.

## Usage

``` r
create_env(
  packages = NULL,
  env_file = NULL,
  env_name = "condathis-env",
  channels = c("conda-forge", "bioconda"),
  method = c("native", "auto"),
  channel_priority = c("disabled", "strict", "flexible"),
  additional_channels = NULL,
  platform = NULL,
  verbose = c("output", "silent", "cmd", "spinner", "full"),
  overwrite = FALSE
)
```

## Arguments

- packages:

  Character vector of package MatchSpec strings. Examples:
  `"python=3.13"`, `"bioconda::fastqc==0.12.1"`. Defaults to `NULL`.

- env_file:

  Character string with the path to an environment YAML file. Defaults
  to `NULL`. When provided, it is passed to `micromamba create -f`.

- env_name:

  Character string with the target environment name. Defaults to
  `"condathis-env"`.

- channels:

  Character vector with channel names used for dependency resolution.
  Defaults to `c("conda-forge", "bioconda")`.

- method:

  Character string with the backend execution strategy. Supported values
  are `"native"` and `"auto"`. Defaults to `"native"`. This argument is
  soft-deprecated and currently does not change behavior.

- channel_priority:

  Character string with channel priority mode. Supported values are
  `"disabled"`, `"strict"`, and `"flexible"`. Defaults to `"disabled"`.

- additional_channels:

  Character vector of additional channels appended to `channels`.
  Defaults to `NULL`.

- platform:

  Character string with the platform used for dependency solving (for
  example, `"linux-64"`, `"osx-64"`, `"osx-arm64"`, `"win-64"`,
  `"noarch"`). Defaults to `NULL`. On Apple Silicon, `condathis` may
  fall back to `"osx-64"` when Rosetta 2 is available and packages are
  not available for `"osx-arm64"`.

- verbose:

  Character string controlling console output. Supported values are
  `"output"`, `"silent"`, `"cmd"`, `"spinner"`, and `"full"`. Defaults
  to `"output"`. Logical values are accepted for backward compatibility:
  `TRUE` maps to `"output"` and `FALSE` maps to `"silent"`.

- overwrite:

  Logical value that controls whether an existing environment should
  always be recreated. Defaults to `FALSE`.

## Value

A process result list (from
[`processx::run()`](http://processx.r-lib.org/reference/run.md)) with
command output, error output, exit status, and timeout information.

## Examples

``` r
if (FALSE) { # \dontrun{
condathis::with_sandbox_dir({
  # Create a Conda environment and install the CLI `fastqc` in it.
  # Explicitly using the channel `bioconda` and version `0.12.1`.
  condathis::create_env(
    packages = "bioconda::fastqc==0.12.1",
    env_name = "fastqc-env",
    verbose = "output"
  )
})
} # }
```
