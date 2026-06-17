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
to `micromamba` under `bin`.

## Examples

``` r
condathis::with_sandbox_dir({
  # Retrieve the path used by condathis for micromamba
  micromamba_path <- condathis::micromamba_bin_path()
  print(micromamba_path)
})
#> /tmp/RtmplRm4hZ/tmp-data1aa540e80f85/R/condathis/micromamba/bin/micromamba
```
