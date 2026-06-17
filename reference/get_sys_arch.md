# Get operating system and CPU architecture

Returns the current operating system and CPU architecture as a single
string in the format `"<OS>-<Architecture>"`.

## Usage

``` r
get_sys_arch()
```

## Value

A character string such as `"Darwin-x86_64"` or `"Linux-aarch64"`.

## Examples

``` r
# Retrieve the system architecture
condathis::get_sys_arch()
#> [1] "Linux-x86_64"
#> [1] "Darwin-x86_64"
```
