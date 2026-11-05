# Unregister a condathis backend

Removes a backend added with
[`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md):
the registry entry and the S3 methods registered for its class. Call it
from the `.onUnload()` of a backend package (see *Registering from a
backend package* in
[`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md)).
Then an unloaded package leaves no registered backend whose functions
belong to a missing namespace.

## Usage

``` r
unregister_backend(name, call = rlang::caller_env())
```

## Arguments

- name:

  Character string with the backend name to unregister.

- call:

  The environment reported as the caller in errors, for calls from
  another package's `.onUnload()`, as in rlang.

## Value

Logical, invisibly: `TRUE` if a backend was unregistered, `FALSE` if no
backend by that name was registered. A malformed name aborts with class
`condathis_backend_invalid_name`, and a reserved one with
`condathis_backend_reserved_name` (also
`condathis_backend_invalid_name`).

## Details

Unregistering a name that is not registered does nothing and returns
`FALSE`, so an unload hook never fails on cleanup that has nothing left
to clean. `unregister_backend()` refuses the reserved names of
[`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md),
because the built-in `"micromamba"` backend is always registered.

Part of the **experimental** backend extension API. See the *Lifecycle*
section of
[`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md).

## See also

Other backends:
[`backend_root_dir()`](https://luciorq.github.io/condathis/reference/backend_root_dir.md),
[`list_registered_backend_names()`](https://luciorq.github.io/condathis/reference/list_registered_backend_names.md),
[`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md)

## Examples

``` r
# A minimal backend: the three required functions, which this example
# does not implement. It reports that it is unavailable, so
# `method = "auto"` never selects it. condathis supplies the other
# functions: they look for environments in
# `backend_root_dir("mybackend")/envs`. A backend package builds this
# object in its own constructor, for example `new_backend_mybackend()` in
# *Registering from a backend package* of `?register_backend`.
not_implemented <- function(...) {
  stop("Not implemented by this example backend.")
}
mybackend <- structure(
  list(
    backend_create_env = not_implemented,
    backend_install = not_implemented,
    backend_resolve_run = not_implemented,
    backend_available = function(backend) FALSE
  ),
  class = c("condathis_backend_mybackend", "condathis_backend")
)

condathis::register_backend("mybackend", mybackend)
condathis::list_registered_backend_names()
#> [1] "micromamba" "mybackend" 

condathis::unregister_backend("mybackend")
condathis::list_registered_backend_names()
#> [1] "micromamba"
```
