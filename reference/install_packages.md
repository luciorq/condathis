# Install packages in a Conda environment

Installs packages into an existing `condathis` environment. If the
target environment does not exist, it is created first.

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

  Character vector of package MatchSpec strings to install.

- env_name:

  Character string with the target environment name. Defaults to
  `"condathis-env"`.

- channels:

  Character vector with channel names used for dependency resolution.
  Defaults to `"conda-forge"`.

- channel_priority:

  Character string with channel priority mode. Supported values are
  `"disabled"`, `"strict"`, and `"flexible"`. Defaults to `"disabled"`.

- additional_channels:

  Character vector of additional channels appended to `channels`.
  Defaults to `NULL`.

- verbose:

  Character string controlling console output. Supported values are
  `"output"`, `"silent"`, `"cmd"`, `"spinner"`, and `"full"`. Defaults
  to `"output"`.

## Value

A process result list (from
[`processx::run()`](http://processx.r-lib.org/reference/run.md)) with
command output, error output, exit status, and timeout information.

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
