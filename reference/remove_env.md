# Remove a Conda environment

Removes an environment managed by `condathis`.

## Usage

``` r
remove_env(
  env_name = "condathis-env",
  verbose = c("silent", "cmd", "output", "spinner", "full")
)
```

## Arguments

- env_name:

  Character string with the environment name to remove. Defaults to
  `"condathis-env"`.

- verbose:

  Character string controlling console output. Supported values are
  `"silent"`, `"cmd"`, `"output"`, `"spinner"`, and `"full"`. Defaults
  to `"silent"`.

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
  condathis::remove_env(env_name = "fastqc-env")
})
} # }
```
