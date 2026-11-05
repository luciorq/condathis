# List every currently registered backend name

Returns the names of every backend currently registered with
[`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md),
whether or not each is currently available on this system. These are the
valid values for the `method` argument of `condathis`'s
environment-management functions, alongside `"auto"`. `"micromamba"`,
the built-in backend, is always present.

## Usage

``` r
list_registered_backend_names()
```

## Value

A sorted character vector of registered backend names.

## See also

[`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md),
[`unregister_backend()`](https://luciorq.github.io/condathis/reference/unregister_backend.md)

## Examples

``` r
condathis::list_registered_backend_names()
#> [1] "micromamba"
```
