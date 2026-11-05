# Install packages in a Conda environment

Installs packages into an existing `condathis` environment. If the
target environment does not exist, it is created first.

## Usage

``` r
install_packages(
  packages,
  env_name = "condathis-env",
  method = "auto",
  channels = c("conda-forge", "bioconda"),
  channel_priority = c("disabled", "strict", "flexible"),
  additional_channels = NULL,
  verbose = c("output", "silent", "cmd", "spinner", "full")
)
```

## Arguments

- packages:

  Character vector of package MatchSpec strings to install. Required;
  must not be `NULL` (use
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
  to create an empty environment instead).

- env_name:

  Character string with the target environment name. Defaults to
  `"condathis-env"`.

- method:

  Character string naming the backend to use. Defaults to `"auto"`
  (resolve automatically: the environment's own owning backend if it
  already exists). `"micromamba"` is the only backend registered today.
  `"native"` is a deprecated alias for `"micromamba"` (warns once per
  session).

- channels:

  Character vector with channel names used for dependency resolution.
  Defaults to `c("conda-forge", "bioconda")`.

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

A `condathis_result` S3 object (a classed list, still usable as a plain
list) with `status`, `stdout`, `stderr`, `timeout`, `pid`, `cmd`, and
`env_name`.

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
