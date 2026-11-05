# List Conda environments managed by condathis

Returns environment names located under each registered backend's own
installation root. Environments not managed by `condathis` are excluded.

## Usage

``` r
list_envs(method = "auto", verbose = "silent")
```

## Arguments

- method:

  Character string naming which backend(s) to list. Defaults to
  `"auto"`: every currently *registered and available* backend.
  `"micromamba"` is the only backend registered today. `"native"` is a
  deprecated alias for `"micromamba"` (warns once per session).

- verbose:

  Character string controlling console output. Defaults to `"silent"`.

## Value

A tibble-classed data frame with one row per environment, columns
`backend` (chr), `env_name` (chr), and `path` (chr) - one row per
environment across every backend covered by `method`. With a single
registered backend (today's default), this is always the same shape,
just one `backend` value throughout.

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
  condathis::list_envs()$env_name
  #> [1] "fastqc-env" "python-env"
})
} # }
```
