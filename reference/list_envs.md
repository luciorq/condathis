# List Conda environments managed by condathis

Returns environment names located under the `condathis` installation
root. Environments not managed by `condathis` are excluded.

## Usage

``` r
list_envs(verbose = "silent")
```

## Arguments

- verbose:

  Character string controlling console output. Defaults to `"silent"`.

## Value

A character vector of environment names. If the command fails, returns
the process exit status as a numeric value.

## Examples

``` r
if (FALSE) { # \dontrun{
condathis::with_sandbox_dir({
  # Create environments
  condathis::create_env(
    packages = "bioconda::fastqc",
    env_name = "fastqc-env"
  )
  condathis::create_env(
    packages = "python",
    env_name = "python-env"
  )

  # List environments
  condathis::list_envs()
  #> [1] "fastqc-env" "python-env"
})
} # }
```
