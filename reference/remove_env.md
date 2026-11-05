# Remove a Conda environment

Removes an environment managed by `condathis`.

## Usage

``` r
remove_env(
  env_name = "condathis-env",
  method = "auto",
  verbose = c("silent", "cmd", "output", "spinner", "full")
)
```

## Arguments

- env_name:

  Character string with the environment name to remove. Defaults to
  `"condathis-env"`.

- method:

  Character string naming the backend to use. Defaults to `"auto"`
  (resolve automatically: the environment's own owning backend).
  `"micromamba"` is the only backend registered today. `"native"` is a
  deprecated alias for `"micromamba"` (warns once per session).

- verbose:

  Character string controlling console output. Supported values are
  `"silent"`, `"cmd"`, `"output"`, `"spinner"`, and `"full"`. Defaults
  to `"silent"`.

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
  condathis::remove_env(env_name = "fastqc-env")
})
} # }
```
