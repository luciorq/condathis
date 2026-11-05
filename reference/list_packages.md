# List packages in a Conda environment

Returns package metadata for a Conda environment as a tibble.

## Usage

``` r
list_packages(
  env_name = "condathis-env",
  method = "auto",
  verbose = c("output", "silent", "cmd", "spinner", "full")
)
```

## Arguments

- env_name:

  Character string with the target environment name. Defaults to
  `"condathis-env"`.

- method:

  Character string naming the backend to use. Defaults to `"auto"`
  (resolve automatically: the environment's own owning backend).
  `"micromamba"` is the only backend registered today. `"native"` is a
  deprecated alias for `"micromamba"` (warns once per session).

- verbose:

  Character string controlling console output. Supported values are
  `"output"`, `"silent"`, `"cmd"`, `"spinner"`, and `"full"`. Defaults
  to `"output"`.

## Value

A data frame (`tibble`) with installed packages. Only four columns are
guaranteed present regardless of backend: **name**, **version**,
**build_number**, and **channel**. Additional columns vary by backend
and shouldn't be relied on in cross-backend code - the `"micromamba"`
backend today also includes `base_url`, `build_string`, `dist_name`,
`platform`, `md5`, `sha256`, and `url`.

## Examples

``` r
if (FALSE) { # \dontrun{
condathis::with_sandbox_dir({
  # Creates a Conda environment with the CLI `fastqc`
  condathis::create_env(
    packages = "bioconda::fastqc",
    env_name = "fastqc-env"
  )
  # Lists the packages in env `fastqc-env`
  dat <- condathis::list_packages("fastqc-env")
  dim(dat)
  #> [1] 66 11
})
} # }
```
