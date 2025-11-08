# Retrieve and Create the `condathis` Data Directory

Retrieves the installation directory for the `condathis` package,
creating it if it does not exist. This function ensures that the package
data directory complies with the [freedesktop's XDG Base Directory
Specification](https://specifications.freedesktop.org/basedir/latest/).
The base path can be controlled by the `XDG_DATA_HOME` environment
variable. Additionally, on Windows, `%LOCALAPPDATA%` is also accepted as
the base installation directory.

## Usage

``` r
get_install_dir()
```

## Value

A character string representing the normalized, real path to the
`condathis` data directory.

## Details

If the directory does not exist, it will be created. On macOS, special
handling is applied to avoid spaces in the path, as `micromamba run`
fails if there are spaces in the path (e.g., in
`~/Library/Application Support/condathis`). Therefore, Unix-style paths
are used on macOS.

## Examples

``` r
condathis::with_sandbox_dir({
  print(condathis::get_install_dir())
  #> /home/username/.local/share/condathis
})
#> /tmp/RtmpFsS4yt/tmp-data1d105a3db87d/R/condathis
```
