# Get operating system and CPU architecture

Returns the operating system and the CPU architecture that the running R
reports with [`base::Sys.info()`](https://rdrr.io/r/base/Sys.info.html),
as a single string, `"<OS>-<architecture>"`.
[`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md)
uses it to choose the micromamba build.

## Usage

``` r
get_sys_arch()
```

## Value

A character string such as `"Linux-x86_64"`, `"Linux-aarch64"`,
`"Darwin-x86_64"` or `"Darwin-arm64"`. On Windows it is
`"Windows-aarch64"` for a native ARM64 build of R. It is
`"Windows-x86-64"` for an x64 build, also when that build runs through
x64 emulation on an ARM64 PC.

## See also

Other setup:
[`clean_cache()`](https://luciorq.github.io/condathis/reference/clean_cache.md),
[`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md),
[`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md),
[`micromamba_bin_path()`](https://luciorq.github.io/condathis/reference/micromamba_bin_path.md),
[`with_sandbox_dir()`](https://luciorq.github.io/condathis/reference/with_sandbox_dir.md)

## Examples

``` r
condathis::get_sys_arch()
#> [1] "Linux-x86_64"
```
