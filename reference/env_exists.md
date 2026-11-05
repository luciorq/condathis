# Check whether a Conda environment exists

Checks whether an environment name is present in the environments
managed by `condathis`.

## Usage

``` r
env_exists(env_name, method = "auto", verbose = "silent")
```

## Arguments

- env_name:

  Character string with the environment name to check. Must be a single,
  non-missing character string.

- method:

  Character string naming which backend(s) to check. Defaults to
  `"auto"`: does the environment exist under *any* registered backend.
  An explicit backend name checks only that one. `"micromamba"` is the
  only backend registered today. `"native"` is a deprecated alias for
  `"micromamba"` (warns once per session).

- verbose:

  Character string controlling console output passed to the backend.
  Defaults to `"silent"`.

## Value

`TRUE` when the environment exists and `FALSE` otherwise.

## Examples

``` r
if (FALSE) { # \dontrun{
condathis::with_sandbox_dir({
  # Create the environment
  condathis::create_env(
    packages = "bioconda::fastqc",
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
