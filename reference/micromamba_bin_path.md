# Get the managed `micromamba` binary path

Returns the expected path to the `micromamba` executable managed by
`condathis` for the current operating system.

## Usage

``` r
micromamba_bin_path()
```

## Value

A character string with the full executable path. On Windows this points
to `micromamba.exe` under `Library/bin`. On other platforms this points
to `micromamba` under `bin`. This is purely a computed, expected path —
it does not check whether a file actually exists there yet (unlike
[`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md),
which creates its directory before returning). Use
[`fs::file_exists()`](https://fs.r-lib.org/reference/file_access.html)
on the result, or
[`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md),
if you need the binary to actually be present.

## Examples

``` r
condathis::with_sandbox_dir({
  # Retrieve the path used by condathis for micromamba
  micromamba_path <- condathis::micromamba_bin_path()
  print(micromamba_path)
})
#> /tmp/RtmpwVEJJf/tmp-data1a134213e49c/R/condathis/micromamba/bin/micromamba
```
