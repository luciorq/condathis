# Clean Conda Cache

This function cleans the Conda cache by removing all packages and
tarballs from the local cache directory. It is useful for freeing up
disk space and ensuring that the cache does not contain outdated or
unnecessary files.

## Usage

``` r
clean_cache(verbose = c("output", "silent", "cmd", "spinner", "full"))
```

## Arguments

- verbose:

  A character string indicating the verbosity level of the output. It
  can be one of "silent", "cmd", "output", or "full". The default is
  "output".

## Value

Invisibly returns the result of the underlying command executed.

## Details

Packages that are still linked with existing environments are not be
removed. If you expect to clean the whole cache, consider removing all
existing environments first using
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
