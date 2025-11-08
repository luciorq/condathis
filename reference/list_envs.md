# List Installed Conda Environments

This function retrieves a list of Conda environments installed in the
`{condathis}` environment directory. The returned value excludes any
environments unrelated to `{condathis}`, such as the base Conda
environment itself.

## Usage

``` r
list_envs(verbose = "silent")
```

## Arguments

- verbose:

  A character string indicating the verbosity level for the command.
  Defaults to `"silent"`. See
  [`run()`](https://luciorq.github.io/condathis/reference/run.md) for
  details.

## Value

A character vector containing the names of installed Conda environments.
If the command fails, the function returns the process exit status as a
numeric value.

## Examples

``` r
if (FALSE) { # \dontrun{
condathis::with_sandbox_dir({
  # Create environments
  condathis::create_env(
    packages = "fastqc",
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
