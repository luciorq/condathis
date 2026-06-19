# Get the `condathis` data directory

Returns the data directory used by `condathis`, creating it when needed.
The base path follows the platform-specific user data directory rules
used by [`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html).

## Usage

``` r
get_install_dir()
```

## Value

A character string with the normalized, real path to the `condathis`
data directory.

## Details

On macOS, `condathis` uses a path without spaces when possible because
`micromamba run` can fail on paths that contain spaces.

## Examples

``` r
condathis::with_sandbox_dir({
  print(condathis::get_install_dir())
  #> /home/username/.local/share/condathis
})
#> /tmp/Rtmpve5TVd/tmp-data1a354fd706ff/R/condathis
```
