# List the registered backends

Returns the names of every backend registered with
[`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md),
available on this system or not. Each one is a valid `method` value of
every `condathis` function that takes `method`, besides `"auto"`. The
built-in `"micromamba"` backend is always registered.

## Usage

``` r
list_registered_backend_names()
```

## Value

A sorted character vector of registered backend names.

## Details

A backend whose package `condathis` knows, such as `"rattler"` of the
`rattlerthis` package, is also a valid `method` value when its package
is installed but not loaded yet. `condathis` loads the package on first
use (see *Registering from a backend package* in
[`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md)).
It is listed here once it is loaded. The error for an invalid `method`
value names these backends too.

## See also

Other backends:
[`backend_root_dir()`](https://luciorq.github.io/condathis/reference/backend_root_dir.md),
[`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md),
[`unregister_backend()`](https://luciorq.github.io/condathis/reference/unregister_backend.md)

## Examples

``` r
condathis::list_registered_backend_names()
#> [1] "micromamba"
```
