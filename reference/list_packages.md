# List packages in a Conda environment

Returns package metadata for a Conda environment as a tibble.

## Usage

``` r
list_packages(
  env_name = "condathis-env",
  verbose = c("output", "silent", "cmd", "spinner", "full")
)
```

## Arguments

- env_name:

  Character string with the target environment name. Defaults to
  `"condathis-env"`.

- verbose:

  Character string controlling console output. Supported values are
  `"output"`, `"silent"`, `"cmd"`, `"spinner"`, and `"full"`. Defaults
  to `"output"`.

## Value

A data frame (`tibble`) with installed packages and the columns:

- **base_url**: The base URL of the package source.

- **build_number**: The build number of the package.

- **build_string**: The build string describing the package build
  details.

- **channel**: The channel from which the package was installed.

- **dist_name**: The distribution name of the package.

- **name**: The name of the package.

- **platform**: The platform for which the package is built.

- **version**: The version of the package.

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
  #> [1] 34  8
})
} # }
```
