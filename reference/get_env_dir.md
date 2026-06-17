# Get an environment directory path

Returns the absolute path where an environment is expected under the
`condathis` installation root. The path is returned even if the
environment has not been created yet.

## Usage

``` r
get_env_dir(env_name = "condathis-env")
```

## Arguments

- env_name:

  Character string with the environment name. Defaults to
  `"condathis-env"`.

## Value

A character string with the expected environment directory path.

## Examples

``` r
condathis::with_sandbox_dir({
  # Get the default environment directory
  condathis::get_env_dir()
  #> "/path/to/condathis/envs/condathis-env"

  # Get the directory for a specific environment
  condathis::get_env_dir("my-env")
  #> "/path/to/condathis/envs/my-env"
})
```
