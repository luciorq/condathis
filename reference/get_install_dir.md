# Get the `condathis` data directory

Returns the data directory used by each backend, creating it when
needed. The base path follows the platform-specific user data directory
rules used by
[`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html) (each
backend resolves its own root independently - e.g. the `"micromamba"`
backend uses `condathis`'s own
`tools::R_user_dir("condathis", "data")`).

## Usage

``` r
get_install_dir(method = "auto")
```

## Arguments

- method:

  Character string naming which backend(s) to report. Defaults to
  `"auto"`: every currently *registered and available* backend.
  `"micromamba"` is the only backend registered today. `"native"` is a
  deprecated alias for `"micromamba"` (warns once per session).

## Value

A tibble-classed data frame with one row per backend covered by
`method`, columns `backend` (chr) and `path` (chr) - the normalized,
real path to that backend's own data directory. With a single registered
backend (today's default), this is always the same shape, just one row.

## Details

On macOS, `condathis` uses a path without spaces when possible because
`micromamba run` can fail on paths that contain spaces.

## Examples

``` r
condathis::with_sandbox_dir({
  print(condathis::get_install_dir())
  #> # A tibble: 1 x 2
  #>   backend    path
  #>   <chr>      <chr>
  #> 1 micromamba /home/username/.local/share/condathis
})
#> # A tibble: 1 × 2
#>   backend    path                                            
#> * <chr>      <chr>                                           
#> 1 micromamba /tmp/Rtmp7nn3rS/tmp-data1a23193b82ed/R/condathis
```
