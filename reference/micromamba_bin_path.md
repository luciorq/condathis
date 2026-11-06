# Get the path of the managed micromamba binary

Returns the path of the `micromamba` executable that
[`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md)
installs, in the condathis data directory (see
[`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md)).
It is the third candidate of *micromamba discovery* in
[condathis-options](https://luciorq.github.io/condathis/reference/condathis-options.md),
after the `condathis.micromamba_path` option and the
`CONDATHIS_MICROMAMBA_PATH` variable.

## Usage

``` r
micromamba_bin_path()
```

## Value

An `fs_path`, the full path of the executable:
`micromamba/bin/micromamba` in the condathis data directory, or
`micromamba/Library/bin/micromamba.exe` on Windows. It does not check
that a file exists there. Like
[`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md),
it creates the condathis data directory when it is missing. Use
[`fs::file_exists()`](https://fs.r-lib.org/reference/file_access.html)
on the result to check that the binary is present, or
[`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md)
to install it.

## See also

Other setup:
[`clean_cache()`](https://luciorq.github.io/condathis/reference/clean_cache.md),
[`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md),
[`get_sys_arch()`](https://luciorq.github.io/condathis/reference/get_sys_arch.md),
[`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md),
[`with_sandbox_dir()`](https://luciorq.github.io/condathis/reference/with_sandbox_dir.md)

## Examples

``` r
condathis::with_sandbox_dir({
  # The path where condathis installs micromamba
  print(condathis::micromamba_bin_path())
})
#> /tmp/Rtmpu60vo2/condathis-sandbox-2b1269dc3367/data/R/condathis/micromamba/bin/micromamba
```
