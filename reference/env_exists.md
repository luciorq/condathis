# Check whether a Conda environment exists

Checks whether an environment name is present in the environments
managed by `condathis`.

## Usage

``` r
env_exists(env_name, verbose = "silent")
```

## Arguments

- env_name:

  Character string with the environment name to check.

- verbose:

  Character string controlling console output passed to
  [`list_envs()`](https://luciorq.github.io/condathis/reference/list_envs.md).
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
