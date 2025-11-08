# Retrieve Operating System and CPU Architecture

This function retrieves the operating system (OS) name and the CPU
architecture of the current system. The output combines the OS and CPU
architecture into a single string in the format `"<OS>-<Architecture>"`.

## Usage

``` r
get_sys_arch()
```

## Value

A character string indicating the operating system and CPU architecture,
e.g., `"Darwin-x86_64"` or `"Linux-aarch64"`.

## Examples

``` r
# Retrieve the system architecture
condathis::get_sys_arch()
#> [1] "Linux-x86_64"
#> [1] "Darwin-x86_64"
```
