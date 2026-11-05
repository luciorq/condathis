# Unregister a condathis backend

Removes a backend previously added with
[`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md):
the registry entry and the S3 methods that were registered for its
class. Intended for a backend package's `.onUnload()` (see the
registration section of
[`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md)),
so an unloaded package never leaves behind a registered backend whose
functions belong to a namespace that no longer exists.

## Usage

``` r
unregister_backend(name, call = rlang::caller_env())
```

## Arguments

- name:

  Character string with the backend name to unregister.

- call:

  Calling environment reported in error conditions. Defaults to the
  caller's environment.

## Value

Logical, invisibly: `TRUE` if a backend was unregistered, `FALSE` if no
backend by that name was registered.

## Details

Unregistering a name that isn't currently registered is a silent no-op
(returning `FALSE`), never an error - unload hooks shouldn't fail on
cleanup that has nothing left to clean.

Part of the **experimental** backend extension API - see the *Lifecycle*
section of
[`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md).

## See also

[`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md),
[`list_registered_backend_names()`](https://luciorq.github.io/condathis/reference/list_registered_backend_names.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Inside a backend package's .onUnload():
condathis::unregister_backend("mybackend")
} # }
```
