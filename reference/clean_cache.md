# Clean Conda cache

Removes cached packages and archives from the `condathis` Conda root.
Also removes files from the package cache directory returned by
`tools::R_user_dir(package = "condathis", which = "cache")`.

## Usage

``` r
clean_cache(verbose = c("output", "silent", "cmd", "spinner", "full"))
```

## Arguments

- verbose:

  Character string controlling console output. Supported values are
  `"output"`, `"silent"`, `"cmd"`, `"spinner"`, and `"full"`. Defaults
  to `"output"`.

## Value

A `condathis_result` S3 object (a classed list, still usable as a plain
list) with `status`, `stdout`, `stderr`, `timeout`, `pid`, `cmd`, and
`env_name`. `env_name` is always `NA` since cache cleanup is not tied to
a specific environment.

## Details

Package files still referenced by existing environments may not be
removed. To maximize cleanup, remove environments first with
[`list_envs()`](https://luciorq.github.io/condathis/reference/list_envs.md)
and
[`remove_env()`](https://luciorq.github.io/condathis/reference/remove_env.md).

## Examples

``` r
if (FALSE) { # \dontrun{
condathis::with_sandbox_dir({
  clean_cache(verbose = "output")
})
} # }
```
