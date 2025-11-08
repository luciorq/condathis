# Retrieve Path to the `micromamba` Executable

This function returns the file path to the `micromamba` executable
managed by the `condathis` package. The path is determined based on the
system's operating system and architecture.

## Usage

``` r
micromamba_bin_path()
```

## Value

A character string representing the full path to the `micromamba`
executable. The path differs depending on the operating system:

- Windows:

  `<install_dir>/micromamba/Library/bin/micromamba.exe`

- Other OS (e.g., Linux, macOS):

  `<install_dir>/micromamba/bin/micromamba`

## Examples

``` r
condathis::with_sandbox_dir({
  # Retrieve the path to where micromamba executable is searched
  micromamba_path <- condathis::micromamba_bin_path()
  print(micromamba_path)
})
#> /tmp/RtmpkiGgmo/tmp-data1d45726b5060/R/condathis/micromamba/bin/micromamba
```
